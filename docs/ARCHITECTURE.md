# Architecture

## Folder structure

Feature-first. `core/` holds things that know nothing about any feature,
`features/<name>/` holds one vertical slice, and `app/` wires them together.
Dependencies point inward only: `app → features → core`. A feature never
imports another feature's `data/` or `bloc/` internals except the auth bloc's
public events (e.g. home dispatches `AuthLogOutRequested`).

```
lib/
├── main.dart                        resolves paths, creates the one TdClient, runApp
├── app/
│   ├── app.dart                     composition root: RepositoryProviders + BlocProviders + MaterialApp
│   ├── auth_gate.dart               AuthStep → screen switch
│   └── lifecycle_watcher.dart       resumes TDLib receive loop on foreground
├── core/
│   ├── config/app_config.dart       --dart-define values, TdSettings
│   ├── storage/secure_store.dart    Keystore-backed secrets (DB key)
│   ├── tdlib/
│   │   ├── td_client.dart           TdClient interface: the only TDLib API features see
│   │   ├── td_isolate_client.dart   implementation over two background isolates
│   │   ├── invoke_router.dart       @extra ↔ Completer correlation (pure, unit-tested)
│   │   ├── td_errors.dart           TdException (+ flood-wait parsing), TdTransportException
│   │   ├── td_paths.dart            absolute DB/files dirs under app support dir
│   │   └── isolates/
│   │       ├── td_isolates.dart     receiver + sender isolate entry points (all FFI/JSON lives here)
│   │       └── td_messages.dart     sendable messages between isolates
│   ├── theme/
│   │   ├── glow_colors.dart         palette + glow() (contrast-checked, see UX_RESEARCH §1)
│   │   ├── glow_theme.dart          ThemeData
│   │   └── motion.dart              durations/curves mapped to M3 tokens; reduced-motion switch
│   └── widgets/                     feature-agnostic building blocks
│       ├── glow_background.dart  glow_button.dart  glow_field.dart
│       └── glow_sigil.dart       flood_gate.dart
└── features/
    ├── auth/
    │   ├── data/auth_repository.dart        TDLib auth calls, params, wipe, recreate
    │   ├── domain/                          pure types: AuthStep, AccountCapabilities, error classification
    │   ├── bloc/                            AuthBloc (+ part files auth_event / auth_state)
    │   └── presentation/
    │       ├── screens/                     one file per screen
    │       └── widgets/                     auth-only widgets (scaffold, submit button, back scope…)
    └── home/
        └── presentation/{screens,widgets}/
test/                                        mirrors lib/; shared fakes in test/helpers/
docs/                                        ARCHITECTURE, DECISIONS, UX_RESEARCH
```

New features (chats, media, voice, whisper, proxy, groups) each get the
same `data / domain / bloc / presentation` slice. A layer a feature doesn't
need is left out, not created empty.

## Layers and rules

| Layer | May depend on | Must not |
|---|---|---|
| `presentation` | its `bloc`, `domain`, `core/theme`, `core/widgets` | call `TdClient` or repositories directly |
| `bloc` | its `data`, `domain`, `core/tdlib/td_errors` | import Flutter widgets |
| `data` | `core/*` | hold UI state |
| `domain` | `lumina_tdlib` models, `core/tdlib/td_errors` | do I/O |
| `core/tdlib/isolates` | FFI, `dart:convert` | run on the UI isolate |

## TDLib bindings

`packages/lumina_tdlib` holds the FFI client (`TdPlugin`, four `td_json_client`
functions) and the Dart API generated from the pinned `schema/td_api.tl` by
`tool/generate.dart`. The generated `lib/src/tdapi` is committed; CI fails if
it is stale. `libtdjson.so` comes from the `tdlib-<key>` release that
`tdlib.yml` builds from the same commit (DECISIONS D15).

## TDLib threading (spec §2.3)

```
UI isolate                     td-sender isolate             td-receiver isolate
──────────                     ─────────────────             ───────────────────
TdClient.invoke(fn) ──SendCommand(extra, fn)──▶ jsonEncode
                                                td_send ──▶ libtdjson ──▶ td_receive (blocking, 0.5 s)
                                                                          convertMapToObject
InvokeRouter ◀──────────── ReceivedBatch(objects ≤ 100) ──────────────────┘
  extra != null → Completer
  extra == null → updates stream
```

- `td_receive` blocks, so the receiving isolate can't also serve a command
  port. That's why there are two background isolates, not one.
- The client id is created in the sender, once. Batches that arrive before
  the UI learns the id are held, then replayed.
- Each isolate has its own exit port and is respawned if it dies. A dead
  sender fails in-flight invokes. A stalled receiver is detected by ping on
  app resume.
- Exactly one live client per process. A second id is created only after
  `authorizationStateClosed` (logout/reset), which TDLib requires.

## State management

`flutter_bloc`. One bloc per feature concern. Events are sealed classes and
state is immutable.

- Widgets read slices with `context.select` so TDLib update bursts rebuild
  only what changed. `AuthGate` selects only `visibleStep`.
- Event concurrency is explicit (`bloc_concurrency`): TDLib state changes run
  `sequential()` (order matters), form submissions run `droppable()` (no
  double sends), and logout/reset run `droppable()`.
- Repositories are injected with `RepositoryProvider`. Blocs get them through
  their constructors, so tests pass fakes without a widget tree.

## Testing

- `core/tdlib`: `InvokeRouter` routing, errors and timeouts (pure Dart).
- `features/auth/domain`: error → UI-behaviour mapping (spec §4.2 table).
- `features/auth/bloc`: the full state machine against a fake `TdClient`
  through the real `AuthRepository`.
- `features/auth/presentation`: flood countdown, OTP auto-submit/clear,
  system back, reduced motion.
- Isolates and FFI need a device, since `libtdjson.so` ships for Android only.
