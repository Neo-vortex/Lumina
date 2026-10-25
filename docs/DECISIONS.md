# Decision Record

Resolves the open decisions of spec v3.0 §12 and records where the spec
didn't match the packages as they actually are (checked against package
sources from pub.dev on 2026-10-25).

## Spec corrections

| Spec says | Actually | Consequence |
|---|---|---|
| minSdk 21 baseline | `whisper_edge` 0.2.0 builds with **minSdk 24** | App minSdk = 24 (D2) |
| `handy_tdlib_next` published 2026-10-03 | Published 2026-10-07 | none |
| `ffmpeg_kit_flutter` for conversion | **Discontinued** on pub.dev | Use `ffmpeg_kit_flutter_new` 4.6.7 (D7) |
| whisper can't decode m4a/mp3 | On Android it decodes **WAV only** (no NDK MediaCodec path yet). Telegram voice notes are **OGG/Opus** | Conversion is mandatory for every voice note (D7) |
| Whisper downloader "handles Range resume" | `WhisperModelDownloader` has no resume | Own resumable downloader in phase 6 |
| `setProxy` might exist | 2.3.16 exposed only `addProxy / editProxy / enableProxy / disableProxy / removeProxy / getProxies / pingProxy / testProxy`. Since 1.8.69 (D15): `addProxy(proxy, enable, comment) → addedProxy`, `getProxies → addedProxies`, `pingProxy(proxy)`, `testProxy(proxy, dc_id, timeout)`, share links via `getInternalLink(internalLinkTypeProxy)` | Phase 7 uses those |
| Communities | No `communit*` symbol in the generated TDLib 1.8.36 API (1.8.69 has communities; see D15) | Omitted (D5) |
| `LogOut → Close → destroy client` | `logOut` itself ends in `authorizationStateClosed`; a following `close` is redundant | `LogOut`, with `Close` only as a fallback if `LogOut` fails (D11) |
| "Client ID created exactly once per process" | TDLib can't reuse a closed client, so logout needs a new one | "Exactly one *live* client" (D9) |

## D1. Isolate topology: UI + receiver + sender
`td_receive` is a blocking FFI call (up to its timeout), so the isolate that
runs it can't process a command port at the same time. Sending therefore runs
in a second background isolate. JSON encoding, decoding and every FFI call
are off the UI isolate. See ARCHITECTURE.md.

## D2. VLC package: `flutter_vlc_player` 7.4.4 (minSdk 24 app)
The app floor is already 24 because of whisper. `vlc_player` 2.x would raise
it to 29 and drop Android 7–9. 16 KB page-size support is claimed since
Sep 2025, and will be checked on a 16 KB emulator image in phase 4.

## D3. State management: flutter_bloc 9
Chosen by the product owner. Sealed events, `context.select`, explicit
concurrency transformers. Replaced the initial Riverpod draft.

## D4. Local store: TDLib only
No message or chat duplication. Secrets go in `flutter_secure_storage`
(Keystore). Non-secret prefs get `shared_preferences` when the first one
appears (proxy list, phase 7).

## D5. Communities: omitted
Not present in TDLib 1.8.36 / `handy_tdlib_next` 2.3.16.

## D6. Whisper model: baseQ5_1 default
Per spec. Plan for phase 6: suggest tinyQ5_1 on devices under 4 GB RAM.

## D7. Compressed audio: `ffmpeg_kit_flutter_new`
OGG/Opus → 16 kHz mono WAV before `transcribeWavFile`. Watch APK size (use
an audio-only build variant) and verify 16 KB page alignment.

## D8. Bot token: not persisted
TDLib keeps the bot session in its encrypted database, so restart reaches
`authorizationStateReady` without the token. The token is needed again only
after logout, which is meant to forget everything.

## D9. Client lifecycle
One live client per process. A new id is created only after `Closed`, by
`TdClient.recreateAfterClose()`. Late traffic from a retired id is dropped.

## D10. Database encryption
A random 32-byte key in the Keystore, passed as `database_encryption_key`.
Backup and device transfer are disabled in the manifest, so a database
never arrives without its key. If the key is lost, TDLib refuses the
parameters and the app offers "Reset local data".

## D11. Logout / reset
- Logout: `LogOut` (fallback `Close`) → at `Closed`: wipe DB/files, discard
  the key, recreate the client.
- Reset local data: `Destroy` → same wipe, with no server logout.
- An unexpected `Closed` (session revoked elsewhere): no wipe (TDLib already
  did it), and a notice tells the user why.

## D12. SMS Retriever / Firebase auth settings: not used
TDLib documents them as official-apps-only. Codes are typed, or autofilled
from the keyboard suggestion (`AutofillHints.oneTimeCode`).

## To verify on device
- Bots and `loadChats`: assumed unavailable, so capability `browseChatList`
  is false. Confirm the exact TDLib error.
- Isolate behaviour with the real `libtdjson.so`: batching under a burst,
  respawn after a forced isolate kill, process-death restart straight to
  `Ready`.
- TalkBack pass over every auth screen.

## D13. AI-action model: SmolLM2-360M-Instruct (Q4_0, 230 MB), not FunctionGemma
The owner asked for the smallest model that can turn a message into a
calendar event, alarm, reminder or note. I measured the candidates on this
machine's CPU with `test/integration/llm_eval_test.dart`: grammar-constrained
JSON, few-shot label prompt, 14 dev messages plus **16 held-out messages**
written after tuning.

| Model | Size | Held-out, model | Held-out, + guardrails | Avg latency |
|---|---|---|---|---|
| SmolLM2-360M-Instruct | 230 MB | 10/16 | **12/16** | 0.67 s |
| SmolLM2-135M-Instruct (Q8) | 145 MB | 8/16 | 10/16 | 0.38 s |
| FunctionGemma 270M | 242 MB | 5/16 | 8/16 | 1.1 s |
| Gemma 3 270M-it / LFM2-350M-Extract | ~220–240 MB | 3/14, 2/14 (dev) | n/a | 3.6 s |

FunctionGemma in native function-calling mode mostly refused in prose
(3/7). Its Mobile-Actions fine-tune is gated on Hugging Face. Decision:
SmolLM2-360M labels the message (action and title only), deterministic
`ActionGuardrails` settle unambiguous phrasing, `DateResolver` computes
dates and times, and the user confirms in an editable sheet. Re-run the
eval before changing the model or the prompt:
`LUMINA_LLM_SET=heldout LUMINA_LLM_MODE=label LUMINA_LLM_MODELS=assets/models/SmolLM2-360M-Instruct-Q4_0.gguf flutter test test/integration/llm_eval_test.dart`.

## D14. License: GPL-3.0-or-later (calls engine from Telegram-Android)
The owner accepted GPL compatibility so calls can reuse Telegram-Android's
voice/video engine (2026-10-25). The version is forced by what Lumina
already ships:
- Telegram-Android's voip glue and build: GPL v2 **or later** (file
  headers; the repo LICENSE is the GPLv2 text).
- tgcalls: LGPL-3.0. ffmpeg-kit (`ffmpeg_kit_flutter_new_full`): LGPL-3.0.
- SmolLM2 model: Apache-2.0. WebRTC, libyuv, abseil: BSD/Apache.
  libVLC: LGPL-2.1+. TDLib: BSL-1.0. llama.cpp, whisper.cpp, sqlite3mc:
  MIT.

GPLv2-only can't combine with LGPLv3 or Apache-2.0, so Lumina is
**GPL-3.0-or-later** (`LICENSE`). Consequences: anyone who gets an APK may
ask for the complete corresponding source, so the repository stays public,
and each release must match a tagged commit. Third-party notices for the
native libraries must ship in the app (Settings → About → Licenses; to do
with calls phase 1). The earlier rule "keep ffmpeg LGPL, never the GPL
variant" no longer protects anything, but stay on the LGPL build anyway:
the GPL codecs (x264/x265) add nothing because encoding uses MediaCodec.

## D15. Own TDLib bindings: `packages/lumina_tdlib`, pinned to TDLib 1.8.69
`handy_tdlib_next` 2.3.16 shipped a 1.8.52 binary with Dart classes generated
from the 1.8.36 schema, and its generator isn't published. We now build
`libtdjson.so` in CI (`tdlib.yml`, `tool/build_tdlib.sh`) from the commit in
`packages/lumina_tdlib/schema/VERSION` and generate the Dart API from the
`td_api.tl` of the same commit (`dart run tool/generate.dart`). TDLib only tags
major versions, so the pin is the "Update version to 1.8.N." commit.
Upgrading = new `td_api.tl` + `VERSION`, regenerate, fix the analyzer, push.
The public shape matches handy's (class names, `TdPlugin`, `convertMapToObject`).
Differences: int64 is sent as a string, and `Messages.messages` is `List<Message?>`.
Communities are now in the API; D5 can be revisited.
