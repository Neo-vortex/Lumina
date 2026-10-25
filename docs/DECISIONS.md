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
| `setProxy` might exist | 2.3.16 exposes only `addProxy / editProxy / enableProxy / disableProxy / removeProxy / getProxies / pingProxy / testProxy` | Phase 7 uses those |
| Communities | No `communit*` symbol in the generated TDLib 1.8.36 API | Omitted (D5) |
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
