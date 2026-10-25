# Lumina

Android-only Telegram client on TDLib (`handy_tdlib_next` 2.3.16 / TDLib 1.8.36)
with a "Glowing Relaxation" UI. Built to spec v3.0.

**Status:** phases 1–2 are done: TDLib isolate bridge, phone and bot-token
login, session persistence, logout/reset, and bot capability gating.

## Run

```sh
flutter run \
  --dart-define=TG_API_ID=<id> \
  --dart-define=TG_API_HASH=<hash>   # from https://my.telegram.org
# optional: --dart-define=TG_TEST_DC=true
```

Or put the api_id and api_hash in `credential.txt` at the repository root
(git-ignored; the layout copied from my.telegram.org works) and use the
wrapper, which adds the two defines to `run`, `build`, `test` and `drive`:

```sh
tool/flutter.sh run
tool/flutter.sh build apk --release --split-per-abi
```

Requirements: Flutter ≥ 3.47 (Dart 3.13), Android SDK, an arm64 device or an
x86_64 emulator. minSdk 24.

## Test

```sh
flutter analyze
flutter test
```

## Docs

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): folder structure, layers, threading
- [docs/DECISIONS.md](docs/DECISIONS.md): spec open decisions and corrections
- [docs/UX_RESEARCH.md](docs/UX_RESEARCH.md): UI/UX requirements (UX-01…33) with sources
- [docs/AGENT_HANDOFF.md](docs/AGENT_HANDOFF.md): full spec, status and next steps for contributors/agents
