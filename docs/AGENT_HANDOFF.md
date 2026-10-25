# Lumina: Agent Handoff Spec

This document is for an engineer or agent continuing the work. The main
[README](../README.md) is for users. Keep this document current: update
the status table and "Next steps" in the same commit as the work.

Companion docs:
- [ARCHITECTURE.md](ARCHITECTURE.md): layers, folder rules, TDLib threading
- [DECISIONS.md](DECISIONS.md): resolved decisions and spec corrections
- [UX_RESEARCH.md](UX_RESEARCH.md): UX requirements UX-01…UX-37 with sources

---

## 1. Product in one paragraph

Android-only Flutter Telegram client on TDLib (`handy_tdlib_next` 2.3.16 /
TDLib 1.8.36). It supports phone and bot-token login, VLC video with
streaming, offline Whisper speech-to-text with translate-to-English
(bundled model), a tiny on-device LLM that turns a message into a calendar
event, alarm, reminder or note, a local encrypted full-text message
search, Stories with a non-top-bar UI, and a "Glowing Relaxation" UI that
does not copy Telegram's look.

## 2. Requirements

### 2.1 Original spec v3.0 (condensed, still binding)

- **Bridge:** `handy_tdlib_next` pinned. No `td_send`/`td_receive`/JSON
  conversion on the UI isolate. Invoke vs update by `@extra`. One live
  client per process.
- **Auth:** phone FSM (code, password, email, registration) and bot token
  (only in `WaitPhoneNumber`). Error table:
  - `PHONE_NUMBER_INVALID`: inline error
  - `PHONE_CODE_INVALID`: inline error, stay on the code screen
  - `PHONE_CODE_EXPIRED`: back to phone entry
  - `PASSWORD_HASH_INVALID`: inline error
  - `FLOOD_WAIT`: countdown, submit disabled
  - Sessions persist under absolute dirs. Logout is complete.
- **Bots:** after `getMe`, gate secret chats, presence, starting private
  chats and full group management. Show the limitations right after login.
- **Proxy:** TDLib native `addProxy`/`enableProxy`/`pingProxy`/… with a list
  with toggles, an add/edit form, an active indicator and a test action.
  Secrets go in Keystore storage.
- **Feature parity:** spec §6 tables for private chats, groups and
  channels: formatting, media, voice, video notes,
  reply/forward/edit/delete (for me / everyone), pin, read receipts,
  typing, presence, in-chat search, drafts, reactions, view-once, secret
  chats (users only); groups: create, members, admin rights, slow mode,
  pinned banner, member list, invite links; channels: posts, admin post,
  edit/delete/pin, subscriber count, discussion link. Communities: omitted
  (not in TDLib 1.8.36).
- **Media:** VLC with gestures (double-tap ±10 s, horizontal scrub with
  timestamp, vertical brightness/volume, pinch zoom). Use TDLib transfers
  only (`updateFile`). Record 16 kHz mono WAV.
- **Whisper:** transcribe voice messages (collapsible transcript, "Translate
  to English"), and dictation (long-press the send orb, with opt-in
  auto-send). Chunk audio over 5 minutes into 30 s pieces. On OOM, suggest
  a smaller model.
- **UI "Glowing Relaxation":** charcoal base; incoming cyan/teal, outgoing
  amber/coral, active violet/magenta; soft glows. Bubbles with gradient,
  asymmetric radii, entrance fade+slide, send bloom and swipe glow. A send
  orb that fills with light and pulses when full, mic when empty. A
  timeline-ribbon chat list. A media cluster (up to 4 plus "+N"). Bottom
  bar with a center compose orb that opens a radial menu. Particle typing
  indicator, read receipt as an edge-glow shift, luminous pull-to-refresh.
- **Hardening:** lifecycle (resume the receive loop), process death, a
  battery-optimisation prompt, a 16 KB page-size check, "Clear cache" via
  `optimizeStorage`, and testing on a 4 GB device.

### 2.2 Additions from the product owner (chronological, all binding)

1. **State management: `flutter_bloc`**, not Riverpod.
2. **UX research before UI.** Done; the results are in `UX_RESEARCH.md`.
3. **Well-structured folders.** Feature-first layout, see ARCHITECTURE.md.
4. **Bundle the Whisper model** in the app (no runtime download):
   `assets/models/ggml-base-q5_1.bin` (60 MB, Git LFS).
5. **Streaming media:** play while downloading. Done through a loopback
   HTTP Range server over TDLib partial downloads (VLC and ExoPlayer).
6. **Most-wanted user features (small ones):** forward without sender (and
   without captions), audio speed up to 4×, hide Stories, read without
   receipts, hide typing, appear offline, scheduled / silent /
   send-when-online, multi-select bulk delete and forward, search filters,
   select text (respecting protected content). Not doing: anti-revoke
   (overrides the sender's deletion); Shadowsocks proxies (not in TDLib).
7. **Stories:** view and post, with an intuitive UI that is **not a top bar**
   like Telegram or Instagram. See §5.4 for the agreed concept.
8. **Local full-text search for message text only.** No file-name search
   (the owner corrected this). Make it "blazingly fast" with a dedicated
   local DB. See §5.2.
9. **Tiny on-device LLM** (model changed after measurement, see D13). An "AI" action on a message that detects a
   calendar event, alarm, reminder or note. The prompt includes the user's
   name/username and the current time. If the model finds an action it
   proposes it in a popup, then performs the system action. The model must
   be very small. Model: **SmolLM2-360M-Instruct Q4_0 GGUF** (230 MB, Git LFS,
   `assets/models/SmolLM2-360M-Instruct-Q4_0.gguf`), chosen over FunctionGemma
   by a held-out evaluation (DECISIONS D13). See §5.3.
10. **Push every step to https://github.com/Neo-vortex/Lumina**, including
    models (Git LFS).
11. **ffmpeg pre-send video conversion:**
    - Simple: two smaller variants, plus a "compatible" H.264 version when
      the source is HEVC, VP9, AV1 or 10-bit.
    - Advanced: codec, size, bitrate, fps and audio.
    - Done.
12. **Ghost mode** master toggle, and a **toggle to stop showing ads in
    channels**. Done. Premium uses the official
    `toggleHasSponsoredMessagesEnabled`. Others get a local hide with an
    explicit API-terms warning.
13. **This handoff document**, which must not be the main README.
14. **Stories, fully:** who viewed your stories, posting as a channel,
    stickers and tags. Done (§5.4).
15. **Story history:** save another user's story on this device; each
    person gets a dedicated tab listing every story saved from them, so it
    can be revisited weeks later. Done (§5.4), with per-person auto-save.
16. **Rich text:** bold, italic, code, quotes, articles (Instant View);
    render all of them and allow composing them. Done (see status table).
17. **Web previews toggle:** link previews when sending. Open pages in
    Chromium (a Custom Tab), not an embedded/internal WebView. Done.
18. **CI:** a GitHub Action that builds the APK on every push and creates a
    release package signed with the debug key. Done (§4), green run still
    to be confirmed.
19. **Scheduled messages**, as in Telegram, and **sending images/videos as
    files**. Partly done, see §2.3.
20. **Modern attachment picker:** the same features as Telegram (location,
    documents, video, images, files…) but more intuitive and modern.
    Research first. Partly done, see §2.3.
21. **Calls, full support:**
    - (2026-10-25) **Phone app integration, both modes:** self-managed
      Telecom calls by default (Bluetooth/car/watch, audio routing, hold,
      Phone-app call history), plus an opt-in managed calling account so
      Google Phone shows its own in-call UI and can dial Lumina calls,
      **also when Lumina isn't running** (the ConnectionService boots the
      engine headless).
    - Voice and video calls.
    - **"Use proxy for calls"** option, as in official Telegram.
    - Video: **front camera, back camera (switch while in the call), and
      screen sharing**.
    - **Custom renderer:** when the user shares their screen and also
      chooses to share the front camera, the outgoing video is the screen
      with a small **picture-in-picture camera bubble** composited on it.
    In progress (license decided: GPL-3.0-or-later), see §2.3 and §5.7.
22. **No Firebase: Lumina's own background worker for notifications**
    (2026-10-25). Default: a small keep-alive foreground service holding
    the headless engine so TDLib stays connected (messages and calls in
    real time). Battery saver: periodic WorkManager sync (messages only).
    Notifications from TDLib's notification API. Optional later:
    UnifiedPush. See §2.3 G.
- **Declined:** "keep disposable (view-once / self-destructing) pictures
  and mark them as kept." The sender chose for them to disappear, so this
  must not be built (§5.4).

### 2.3 Not done yet (complete list, start here)

**A. Attachment picker and sending (owner items 19 and 20)**
- Done and pushed:
  - New hub `media/presentation/widgets/attach_sheet.dart`. It has Gallery
    (system Photo Picker) and Camera hero cards (tap for photo, hold for
    video), adaptive tiles ordered by usage (File, Location, Contact, Poll,
    Music, Round video), and an "Original quality" switch.
  - `location_sheet.dart`, `poll_composer.dart`.
  - Bubbles for location / live location / venue, contact and poll (with
    voting, quiz, retract and stop) in
    `conversation/.../content/rich_cards_content.dart`.
  - Contact sharing is wired in `app_conversation_extensions.dart`.
  - `MediaPick.asFiles` / `.music` reach `SendMediaScreen.open`: "Send as
    file" starts on for the File tile and "Original quality", and Music
    sends `InputMessageAudio` (duration, and title/performer from container
    tags via `FfmpegService.audioTags`, clipped to 64 characters, plus the
    embedded cover art as `albumCoverThumbnail`). Audio
    picked through File stays a document.
  - Long-pressing send on `SendMediaScreen` offers silent / schedule /
    when-online (`core/widgets/send_options_sheet.dart`, shared with the
    composer). `MediaSendRequest.options` is passed to `sendAlbum` /
    `sendContent`, with a "Scheduled · View" snackbar.
  - `SendOptions` and `pickScheduleTime` moved to `core/` (the media
    feature can't import conversation); `messages_repository.dart`
    re-exports `SendOptions`.
  - Poll building is `buildPoll` (pure). It fixed a quiz bug: the correct
    answer was a row index, but TDLib wants the index among non-empty
    options, and removing a row above it didn't shift it.
  - Picker research recorded as UX-34…37.
  - Live locations stay updated: `media/data/live_location_service.dart`
    (`LiveLocationService`, provided non-lazily in `feature_wiring.dart`).
    - `prepare()` asks for precise location + notifications and starts the
      native `LiveLocationService.kt` foreground service (type `location`);
      `track()` gets the pending message from
      `ConversationCubit.sendContent(onSent:)`.
    - The temporary id is swapped on `updateMessageSendSucceeded`; failed
      sends are dropped. Every 60 s a fix from
      `SystemChannel.currentPosition()` (GPS when precise, never prompts)
      goes out via `editMessageLiveLocation` if it moved ≥ 20 m or 5 min
      passed.
    - Stops at expiry, on `expiresIn == 0` (the bubble's "Stop sharing" or
      another device), on deletion and on logout. Shares are saved in prefs
      (`live.shares`) and resume, without prompting, the next time the app
      starts after the process was killed.
    - Swiping the task away stops the service (`onTaskRemoved`): the Flutter
      engine is gone, so nothing could send updates anyway.
  - Tests: tile order, `buildPoll`, music kind/tags/audio content, send
    options, schedule presets and `LiveLocationService`.
- Nothing left in A. `ScheduledMessagesScreen` has widget tests (order,
  send now, delete, empty state). Scheduled updates no longer leak into
  the timeline.

**B. Calls (owner item 21), in progress, see §5.7 for the phases**
- License decided: GPL-3.0-or-later (DECISIONS D14, `LICENSE`).
- Phase 1 (engine build) is done:
  - `tool/fetch_calls_engine.sh` (pin `TG_COMMIT`), `tool/build_calls_engine.sh`
    (NDK 27, SDK CMake 3.22, `c++_static`), `tool/calls_engine_key.sh`.
  - `android/calls-engine/`: our top-level `CMakeLists.txt` (reuses
    Telegram's `voip/CMakeLists.txt`, drops their JNI glue),
    `src/lumina_calls_jni.cpp` (1:1 calls only), `src/tgnet/FileLog.h`
    stand-in, `java/` (vendored `org.webrtc` + `VideoCapturerDevice`,
    committed, regenerated by the fetch) and `java-shims/` (FileLog,
    AndroidUtilities, ApplicationLoader, SharedConfig, VoIPService events,
    Instance constants).
  - Kotlin binding `android/app/src/main/kotlin/dev/lumina/calls/NativeCall.kt`
    (`NativeCall.load()` returns false when the .so isn't bundled).
  - Built locally for arm64-v8a: 16 MB stripped, 16 KB aligned, exports
    our 20 JNI functions + WebRTC's, system libs only. A clean build is
    ~1,750 objects (about 10 min with 6 jobs here).
  - CI: `.github/workflows/calls-engine.yml` builds both ABIs only when the
    key changes and publishes pre-release `calls-engine-<key>`;
    `android.yml` downloads it into `jniLibs` (APK still builds without).
  - Licenses: `assets/licenses/calls_engine.txt` (generated by the fetch),
    registered in `main.dart`; Settings → "About & licenses".
- Not verified yet: the engine on a device (`NativeCall.load`, versions),
  the x86_64 build (first CI run), R8 keep rules (`calls-rules.pro`).
- Phases 2–3 (engine channel + signaling) are written, without UI:
  - Kotlin `dev/lumina/calls/CallChannel.kt` ("dev.lumina/calls" +
    "/events"): available, capabilities (versions, max layer, device
    AEC/NS), start (from `EngineParams.toMap`), receiveSignaling, setMuted,
    stop. Holds communication audio mode and focus during a call; video
    frames are dropped until phase 5.
  - Dart `features/calls/`: `domain/engine_params.dart` (`callProtocol`,
    `engineParamsFor`: reflector ids 1…n by id, `reflector` + hex peer tag
    credentials, server-config AEC/NS, proxy turns P2P off),
    `data/call_engine.dart` (`CallEngine`, `ChannelCallEngine`, event
    decoding), `data/calls_repository.dart` (TDLib requests, timeouts from
    `call_connect_timeout_ms` / `call_packet_timeout_ms`),
    `bloc/call_cubit.dart` (app-wide, non-lazy in `app.dart`; buffers
    signaling until the engine runs, declines a second incoming call,
    sends debug info when TDLib asks, rating).
  - Incoming calls only ring while the app process runs (Lumina has no
    push notifications).
- Phase 4 system side (written, not yet device-tested):
  - `LuminaEngine.kt`: the process-wide cached FlutterEngine (Dart + TDLib)
    that `MainActivity` attaches to (`provideFlutterEngine`,
    `shouldDestroyEngineWithHost = false`). Anything can boot it headless.
  - `CallTelecom.kt`: self-managed PhoneAccount (always; logs to the Phone
    app's history on Android 11+) and the opt-in managed calling account
    (`SelfManagedCallService`, `CallProviderService`). `LuminaConnection`
    maps answer / reject / disconnect / hold / audio route to Dart. A
    `tel:` number dialed in the Phone app with Lumina's account boots the
    engine if needed (`pendingDialerNumber` → `takeDialerCall`), then
    `CallsRepository.userIdByPhone` (waits for TDLib login) →
    `startCall(fromDialer: true)`.
  - `CallService.kt`: in-call foreground service (microphone|camera) with
    Hang up; incoming notification (full-screen intent, Answer/Decline),
    ringtone + vibration by ringer mode, all in `CallChannel`.
  - `CallSystem` (Dart, implemented by `ChannelCallEngine`): `CallCubit`
    reports calls to Telecom, rings itself only when Telecom asks
    (`onShowIncomingCallUi`) or refuses, maps end reasons to
    `DisconnectCause`, handles hold, speaker, permissions.
  - Pref `calls.callingAccount` (`AppPreferences.callsUseCallingAccount`).
- Call UI (Dart, `features/calls/presentation/`): `CallButtons` in the
  conversation header (`ConversationExtensions.headerActions`; private
  chats with regular users, never for bots or yourself), `CallScreen`
  (pulsing halo, status/duration, key emojis with explanation, signal
  bars, mute/speaker/end, answer/decline, rating), `CallHost` in
  `MaterialApp.builder` (opens the screen when a call starts unless the
  Phone app shows it, "return to call" pill), Settings → Calls.
  Video button waits for phase 5.
- Next: verify on a device (audio call end to end, Telecom both modes,
  dialing from the Phone app with Lumina closed); then phase 5 (video).

**G. Background notifications without Firebase (owner item 22), written, device test pending**
- Native `android/app/src/main/kotlin/dev/lumina/background/`:
  - `Background.kt`: modes `connected` (default) / `saver` / `off`, kept
    in native prefs so boot can act before Dart. `KeepAliveService`
    (foreground type `specialUse`, min-importance notification, boots
    `LuminaEngine`, START_STICKY), `SyncWorker` (WorkManager, 15 min,
    boots the engine and waits 60 s), `BootReceiver` (boot / app update).
    `MainActivity` resumes the stored mode on start.
  - `MessageNotifications.kt` ("dev.lumina/notifications"): MessagingStyle
    per TDLib group with Reply (RemoteInput) and Mark as read;
    `ActionReceiver` boots the engine and queues actions until Dart
    listens; taps open the chat (`EXTRA_OPEN_CHAT`).
- Dart `features/notifications/`: `NotificationCenter` (non-lazy) turns on
  TDLib's notification groups (`notification_group_count_max` 25, size 10),
  mirrors `updateActiveNotifications` / `updateNotificationGroup` /
  `updateNotification`, posts nothing while in the foreground, skips call
  groups, replies with `sendMessage` + `viewMessages(forceRead)`.
  Settings → Notifications picks the mode.
- Verify on a device: headless start really builds the providers (the
  warm-up frame) and TDLib connects; the keep-alive service survives Doze
  with battery optimisation off; boot start on Android 14/15.
- Later: UnifiedPush (TDLib `registerDevice` with a web-push token) as a
  no-persistent-notification option.

**C. CI / release**
- Confirm a green run of `.github/workflows/android.yml`:
  - The first run failed on `abiFilters` vs `--split-per-abi`; that is
    fixed in `android/app/build.gradle.kts`.
  - A running build on `main` is never cancelled, but GitHub replaces a
    *pending* run with the newest push (one pending run per group), so
    quick consecutive pushes build only the latest commit.
  - Green: run 40187963183 (commit 62a325f), all steps through release.
- Owner action: add the repository secrets `TG_API_ID`, `TG_API_HASH` and
  (recommended) `DEBUG_KEYSTORE_B64` (§4).
- The local release build in the dev container failed only for lack of
  disk space. CI has ~20 GB after the cleanup step.

**D. Rich text leftovers**
- Animated custom emoji (TGS/WebM) show their static thumbnail. TGS needs
  a Lottie renderer.
- Done: reply quotes. "Select text" has a Quote button
  (`quoteFromSelection` in `message_menu.dart` keeps only the entity types
  TDLib allows, clipped). `ConversationState.replyQuote` goes out with
  sends, albums and drafts, and drafts bring back their reply and quote
  (`restoreDraftReply`). The composer strip shows the passage, and
  received replies show a manual quote instead of the message preview.
  The quote is located by the first match of the selected text, so a
  repeated phrase may get the wrong `position` (TDLib treats it as
  approximate).
- Instant View: `PageBlockEmbedded` HTML is not executed (it shows the
  poster and links out). Collages are a simple PageView.

**E. Stories leftovers**
- The weather area is rendered but can't be created (no weather source).
- Done: the story *message* area (`StoryAreaTypeMessage`, a reposted
  post) is tappable and opens the chat at that message through the
  injected `StoryMessageOpener` (wired in `feature_wiring.dart`); the
  story pauses while the chat is open.
- Saved-story history is a JSON index in app-private storage, not
  encrypted.

**F. Older open items**
- Everything in §8 ("Must verify on a real device").
- Battery prompt, 16 KB check and storage are done, but none of them has
  been checked on a device yet.

## 3. Status

| Area | Status | Where |
|---|---|---|
| TDLib bridge (2 isolates, routing, respawn) | ✅ | `lib/core/tdlib/` |
| Auth (phone, bot, errors, logout/reset) | ✅ | `lib/features/auth/` |
| Theme, motion, shared widgets | ✅ | `lib/core/theme/`, `lib/core/widgets/` |
| Telegram cache + file store | ✅ | `lib/core/telegram/` |
| Stream server (Range over TDLib) | ✅ (untested on device) | `lib/core/media/tdlib_stream_server.dart` |
| Chat list (timeline ribbon, search, actions) | ✅ | `lib/features/chats/` |
| Conversation (bubbles, reply/edit/forward/pin/react/select, search, drafts, typing, schedule) | ✅ | `lib/features/conversation/` |
| Ghost mode, ads toggle, sponsored messages | ✅ | prefs + settings + conversation |
| Home shell (nav bar, compose orb radial menu) | ✅ (new message/group/channel/secret chat, Glimpses, post story) | `lib/features/home/` |
| Settings (privacy, stories, media, channels, connection, storage, search, speech, background) | ✅ | `lib/features/settings/` |
| Media: photos, videos, GIFs, albums (cluster), documents, stickers, viewer, VLC player, attach + review, converter | ✅ (APK builds; verify on device) | `lib/features/media/`, `conversation/.../content/` |
| Voice notes (record, Opus, waveform, playback 0.5–4×), video notes (play + record), music | ✅ | `lib/features/voice/`, `core/media/audio_playback.dart` |
| Whisper (bundled model, transcribe, translate, dictation, chunking) | ✅ | `lib/features/transcription/`, `core/models/` |
| Local FTS search (encrypted sqlite3mc, trigram + unicode61, worker isolate, live + backfill, global + in-chat, settings, wipe on close) | ✅ (tested on real SQLite) | `lib/features/search/` |
| Tiny LLM actions (SmolLM2-360M bundled, llama.cpp on CPU, label + guardrails + date resolver, editable sheet, system intents) | ✅ (75% held-out; measured) | `lib/features/assistant/`, DECISIONS D13 |
| Proxy (list, toggle, add/edit, paste link, test, share, login-screen access, encrypted restore after wipe) | ✅ | `lib/features/proxy/` |
| Groups/channels admin, chat info, secret chats, contacts, new chat/group/channel | ✅ | `lib/features/chat_info/` (repository, ChatInfoScreen, contact picker, permissions sheet, `ComposeFlows`); wired in `app/feature_wiring.dart` |
| Stories | ✅ | `lib/features/stories/` (StoriesRepository, halos via `ChatRowExtensions`, viewer with bottom-left ring, Glimpses grid, post with ffmpeg 1080×1920 / 720×1280 prep); wired in `app/app_story_wiring.dart` |
| Rich text (code blocks, quotes, custom emoji, card numbers, media timestamps), composer formatting menu, link previews (receive + compose with size/position/remove), Instant View reader, Custom Tab links | ✅ | `core/telegram/entity_edit.dart`, `formatted_text_view.dart`, `conversation/.../formatting_controller.dart`, `link_preview_card.dart`, `instant_view_screen.dart` |
| Hardening (cache/optimizeStorage, battery prompt, 16 KB check) | ✅ | `lib/features/maintenance/` (StorageRepository: usage by kind, clear, keep-media auto clean; Background settings + one-time battery prompt in `LifecycleWatcher`); memory pressure frees the LLM and Whisper; `tool/check_16kb.py <apk>` |

Tests: `flutter test`, 179 tests covering routing, auth FSM (bloc_test),
error mapping, cache ordering, row grouping, video presets, search, assistant,
chat info, stories, storage, the attach hub, polls, music, send options, live locations, the scheduled list, reply quotes, calls and notifications. Run
`flutter analyze` too; it must stay at zero issues.

## 4. Environment & build

### CI (`.github/workflows/android.yml`)
- Every push and PR: LFS checkout (LFS objects are cached, since GitHub's
  free LFS bandwidth is 1 GB/month and the models are ~290 MB), `flutter
  analyze`, `flutter test`, then `flutter build apk --release
  --split-per-abi` for arm64-v8a and x86_64, the 16 KB check, and an
  artifact upload.
- Push to `main` replaces the **`latest-build`** pre-release; a `v*` tag
  creates a normal release. Both attach `lumina-<abi>-release.apk` and
  `SHA256SUMS.txt`.
- Release builds are **signed with a debug key** (`buildTypes.release`
  uses `signingConfigs.debug`). Not for the Play Store.
- Repository secrets:
  - `TG_API_ID`, `TG_API_HASH`: Telegram API credentials (my.telegram.org).
    Without them the APK builds but cannot sign in.
  - `DEBUG_KEYSTORE_B64` (recommended): a stable debug keystore, so each
    build installs over the previous one. Create it once:
    `keytool -genkeypair -v -keystore debug.keystore -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"`
    then `gh secret set DEBUG_KEYSTORE_B64 --body "$(base64 -w0 debug.keystore)"`.

### Local

- **Build machine note:** Maven Central rate-limited this environment
  (HTTP 429). `~/.gradle/init.d/maven-central-mirror.gradle` redirects to
  Google's official mirror (`maven-central.storage-download.googleapis.com`).
  It's an environment tweak, not committed. Recreate it if builds fail with 429.
- Native libraries: libVLC and ffmpeg-kit both ship `libc++_shared.so`;
  `packaging.jniLibs.pickFirsts` keeps one copy.
- The debug APK is about 870 MB (every ABI, Vulkan validation layers, 300 MB
  of models). Release builds should use `--split-per-abi` / an AAB.

- Flutter 3.47.8 stable (Dart 3.13.7), Android SDK with the NDK fetched by
  Gradle, Java 21, minSdk 24.
- `git lfs install` before cloning (the models are LFS).
- Run: `flutter run --dart-define=TG_API_ID=… --dart-define=TG_API_HASH=…`
  (get them at my.telegram.org). Optionally add `--dart-define=TG_TEST_DC=true`.
- **Local builds use `tool/flutter.sh`** (owner's choice): it reads the
  api_id (digits) and api_hash (32 hex) from the git-ignored
  `credential.txt` at the repo root and appends both defines to `run`,
  `build`, `test`, `drive` and `attach` (other commands pass through).
  `LUMINA_CREDENTIALS=<path>` points it at another file. Never commit or
  print the file's contents.
- ABI filter: arm64-v8a and x86_64.
- **Licensing:** Lumina is GPL-3.0-or-later (DECISIONS D14). ffmpeg stays
  the LGPL `ffmpeg_kit_flutter_new_full` build (the GPL codecs add nothing). H.264 and
  H.265 encoding use the hardware encoders `h264_mediacodec` /
  `hevc_mediacodec`, with an `mpeg4` fallback.
- **APK size:** models ≈ 300 MB. For Play distribution, move the models to
  Play Asset Delivery install-time packs (base module limit ≈ 200 MB).

## 5. Agreed designs for the remaining work

### 5.1 Voice (phase 5)
- Orb gestures, decided: on an **empty orb, tap = start/stop voice
  recording** (a persistent recorder, Google Messages style), and
  **long-press = dictation**. With text, long-press opens the send options.
  This resolves the conflict between spec §8.2 (long-press = dictation) and
  hold-to-record.
- Record with `record` as 16 kHz mono WAV. On send, `FfmpegService.toVoiceNote`
  converts to OGG/Opus. The waveform is 100 five-bit samples packed as TDLib
  expects (`InputMessageVoiceNote.waveform`), from PCM peaks.
- While recording, `ConversationExtensions.recordingOverlay` shows a live
  waveform and timer, and `orbMode` returns `stop`. After stopping: preview,
  play, discard, send.
- Playback uses `just_audio` with streaming from the loopback URL. The speed
  comes from `AppPreferences.playbackSpeed` (0.5–4×).
- Video notes: circular VLC playback, muted autoplay is optional.
  Recording uses the `camera` package (front camera, square, ≤ 60 s).

### 5.2 Local full-text search (task #10)
- `sqlite3` 3.x with `hooks.user_defines.sqlite3.source: sqlite3mc` in
  pubspec (SQLite3MultipleCiphers, encrypted; the key comes from
  `SecureStore`, the same pattern as the TDLib DB key).
- Tables:
  - `msg_tri`: FTS5 `tokenize='trigram'`, for substring search in any
    script, CJK included.
  - `msg_words`: FTS5 `unicode61 remove_diacritics 2`, with prefix search
    for queries of 1–2 characters.
  - Columns: chat_id, message_id, date, sender_id, text. Index text and
    captions only.
- The worker isolate owns the DB. The UI isolate sends small records from
  `updateNewMessage` / `updateMessageContent` / `updateDeleteMessages`, and
  a throttled backfill walks `getChatHistory` per chat (with the progress
  stored).
- Implement `core/search/message_search.dart` `MessageSearch`; the in-chat
  search already uses it when provided. Add a global search tab in the
  chats screen. The snippet uses `[[`/`]]` markers, which the UI
  highlights. Wipe on logout. Settings: on/off, progress, clear.

### 5.3 Tiny LLM actions (task #11)
- Runtime: `llamadart` 0.16.x (llama.cpp over FFI; native libs come from
  its build hook). Load the GGUF from assets, copying it to app support
  once.
- Use **grammar-constrained** generation (`GenerationParams.grammar`) to
  force this JSON:
  `{"action":"none|calendar|alarm|reminder|note","title":str,"date":"YYYY-MM-DD"|null,"time":"HH:MM"|null,"duration_min":int|null,"notes":str|null}`.
- Prompt: the user's display name and username, the current local
  date/time/weekday and timezone, then the message text and sender.
- Resolve relative dates in Dart ("tomorrow", weekday names, "in 2
  hours"). Treat the model's date as a hint and validate it.
- UX: an "AI action" entry in the message long-press menu
  (`ExtraMenuEntry` with `MessageAction.aiAction`). It shows a thinking
  shimmer, then an **editable confirmation sheet**. Nothing executes
  without confirmation.
- Intents (the manifest `<queries>` are already added):
  - Calendar: `ACTION_INSERT` on `CalendarContract.Events`.
  - Alarm: `AlarmClock.ACTION_SET_ALARM` (hour, minutes, message).
  - Reminder: a calendar event with an alert, or `ACTION_SET_TIMER` for
    relative reminders under 24 h.
  - Note: `com.google.android.gms.actions.CREATE_NOTE`, falling back to
    `ACTION_SEND` text.
  - Use `android_intent_plus` or a small MethodChannel.

### 5.4 Stories (task #9). The UI must not be a top bar
- Concept: **"Halos on the timeline."** Chats whose users have active
  stories get an animated halo around the avatar in the timeline ribbon;
  unseen stories pulse. Tapping the avatar opens the stories, and tapping
  the row opens the chat.
- An entry in the compose-orb radial menu: "Glimpses" (a vertical story
  stream) and "Post story".
- Viewer: full screen. Progress is a ring around the poster's avatar at the
  **bottom left**, not segmented bars at the top. Tap right/left to go
  next/previous; swipe down closes; swipe up replies (a message to the
  poster); long-press pauses; quick reactions.
- Honour `prefs.hideStories` (hide everything) and `prefs.hideStoryViews`
  (do not call `openStory`, so nothing is marked viewed).
- APIs: `loadActiveStories`, `getChatActiveStories`,
  `updateChatActiveStories`, `openStory`/`closeStory`, `setStoryReaction`,
  and `sendStory` (photo/video plus privacy: everyone, contacts, close
  friends).
- **Done.** The chat list knows nothing about stories: `ChatRowExtensions`
  (chats feature) decorates avatars and `AppChatRowExtensions` adds the
  halo. Swipe sideways in the viewer to move between people. Posting uses
  `canSendStory` first; videos are cut to 60 s and letterboxed
  (`StoryMedia`, tested), with an mpeg4 fallback. Active period is fixed
  at 24 h (other periods need Premium).
- **Viewers:** own stories show a views button → `showStoryViewers`
  (`getStoryInteractions`, search, reactions first, contacts only; channel
  stories use `getChatStoryInteractions`).
- **Post as:** `getChatsToSendStories` fills a "Post as" picker; channel
  stories are always public.
- **Stickers & tags** (`domain/story_decoration.dart`): emoji and text
  stickers, link and location pills are *burned in* (one transparent PNG
  overlay rendered by `DecorationPainter`, composited by ffmpeg); link,
  location and suggested-reaction tags are also sent as story *areas*.
  Reaction bubbles and weather are drawn by the viewer
  (`StoryAreasLayer`); links/places open after a confirmation. Location
  uses `SystemChannel.currentLocation` (coarse permission, asked on use).
- **Story history** (owner request): `SavedStoriesStore` keeps copies of
  other people's stories in app-private storage (`saved_stories/`, JSON
  index), with per-person auto-save that never calls `openStory`. Stories
  with `canBeForwarded == false` are never saved (TDLib: saving must be
  forbidden). Wiped on logout. UI: bookmark in the viewer, chat info tab
  "Story history" (`ChatInfoExtensions`), Glimpses → history list.
- **Declined:** keeping view-once / self-destructing media. The sender
  chose for it to disappear; don't add this.

### 5.5 Proxy (phase 7)
- `lib/features/proxy/`: a list from `getProxies` with enable switches, an
  add/edit form for socks5 (user/pass), http (user/pass, httpOnly) and
  mtproto (secret), and a test via `pingProxy` showing the latency. The
  active proxy is shown in `ConnectionAwareTitle`.
- It must be reachable from the **login screen** too, for censored regions.
- Persist non-secrets in shared_preferences and secrets in `SecureStore`.
  Re-add them after logout (the DB wipe drops TDLib's copy).

### 5.6 Groups, channels, chat info (phase 8)
- Chat info: avatar, title, description, member/subscriber count, invite
  link (create/copy/revoke), members list (`getSupergroupMembers` /
  basic group full info), admin rights editor (`setChatMemberStatus`),
  permissions and slow mode (`setChatPermissions`, `setChatSlowModeDelay`),
  discussion link (`linkedChatId`), and leave.
- Compose radial menu actions: new message (contacts search,
  `createPrivateChat`), new group, new channel, new secret chat (users
  only, `createNewSecretChat`), post story. Register them through
  `ComposeActions` in `app/feature_wiring.dart`.
- `ConversationExtensions.openChatInfo` opens chat info.
- **Done.** `ComposeFlows` (chat_info feature) gets an injected `OpenChat`
  callback so the feature does not import the conversation feature. The
  "Post story" orb entry is still to be added with Stories (§5.4).

### 5.7 Calls (owner item 21), design and phases

**What TDLib gives and what it doesn't**
- TDLib does **signaling only**:
  - `createCall(userId, protocol, isVideo)`, `acceptCall`, `discardCall`.
  - `updateCall` with `CallStatePending / ExchangingKeys / Ready /
    HangingUp / Discarded / Error`, plus `sendCallSignalingData` and
    `updateNewCallSignalingData`.
  - `sendCallRating`, `sendCallDebugInformation`.
- `CallStateReady` carries `servers` (WebRTC STUN/TURN and Telegram
  reflectors), `config` JSON, `encryptionKey`, `emojis`
  (verification), `allowP2p` and `customParameters`.
- The **media layer is not in TDLib**. Official apps use **tgcalls**
  (github.com/TelegramMessenger/tgcalls), a C++ library on top of WebRTC.
  Lumina must build it for arm64-v8a and x86_64, wrap it in JNI/FFI, and
  feed it TDLib's signaling. This is the bulk of the work.
- Decided (D14): reuse Telegram-Android's engine. Their
  `TMessagesProj/jni` builds WebRTC (vendored, ~1,700 files in
  `voip/CMakeLists.txt`) and tgcalls (submodule) with plain CMake, and
  links prebuilt static libs committed per ABI in `jni/prebuild/lib/<abi>`
  (crypto, ssl, opus, libvpx, openh264, iwasm, dav1d, ffmpeg). Headers come
  from submodules: tgcalls, absl, libyuv, boringssl, xiph/opus, ffmpeg,
  libvpx, dav1d, wamr. Java side: their `org.webrtc` package (173 files;
  the native code expects these exact class names).

**Phases**
1. **Engine build.** `tool/fetch_calls_engine.sh` sparse-checks out
   DrKLO/Telegram at a pinned commit (with only the submodules above,
   shallow). A Lumina-owned top-level CMake reuses their
   `voip/CMakeLists.txt` but replaces `org_telegram_messenger_voip_Instance.cpp`
   (tied to Telegram's tgnet and Java classes) with our JNI glue, and
   builds `liblumina_calls.so` for arm64-v8a and x86_64. A separate CI
   workflow builds it once per pin and publishes it as a release asset;
   the app workflow downloads it, so app builds stay fast. Ship license
   notices.
2. **JNI + Kotlin engine.** `dev.lumina.calls.CallEngine` (adapted from
   Telegram's `NativeInstance`): start with TDLib's `CallStateReady`
   (servers, encryption key, config, allowP2p, custom parameters), feed
   signaling both ways, mute, audio route, network type, stats, stop
   (returns debug log for `sendCallDebugInformation`). A
   `MethodChannel`/`EventChannel` exposes it to Dart.
3. **Dart signaling.** `features/calls/`: `CallsRepository` (`createCall`
   with `CallProtocol` listing the bundled `libraryVersions`,
   `acceptCall`, `discardCall`, `sendCallSignalingData`, `updateCall`,
   `updateNewCallSignalingData`, rating), `CallCubit` state machine.
   Tests with `FakeTdClient`.
4. **Audio-call UI.** In-call screen, header/chat-info call buttons,
   incoming call full-screen notification, foreground service
   (`phoneCall|microphone`), self-managed `ConnectionService`, proximity
   wake lock, audio routing.
5. **Video.** Camera capture (front default, switch), remote renderer as a
   Flutter `Texture`, local self-view PiP.
6. **Screen share + camera PiP compositor** (MediaProjection service,
   GL compositor feeding one `VideoSource`).
7. **Proxy for calls** (SOCKS5 into tgcalls' proxy config, see below).

- `CallProtocol`: `udpP2p`, `udpReflector`, `minLayer 65`, `maxLayer 92`,
  and `libraryVersions` must list the tgcalls versions actually bundled
  (for example "4.0.0", "5.0.0", "7.0.0", "8.0.0", "9.0.0", "11.0.0").

**Proxy for calls**
- Settings → Connection → "Use proxy for calls" (pref
  `calls.useProxy`, default off, as in official Telegram).
- When on and the active proxy is **SOCKS5**, pass its host, port, user
  and password into tgcalls' proxy config. tgcalls tunnels the reflector
  connection through SOCKS5 UDP ASSOCIATE.
- With MTProto or HTTP proxies, calls can't be proxied. Show a note, and
  keep `allowP2p` off when the toggle is on.
- `ProxyRepository` already knows the active proxy (secrets are in
  `SecureStore`).

**Video sources and the custom renderer**
- Camera: Camera2 via WebRTC's `Camera2Capturer`.
  - Front by default.
  - "Switch camera" button: `CameraVideoCapturer.switchCamera`.
- Screen share:
  - `MediaProjection` permission plus a foreground service of type
    `mediaProjection`, required on Android 14+.
  - WebRTC's `ScreenCapturerAndroid`.
- **Screen + camera PiP:** a custom `VideoSource` fed by a compositor.
  - Take the latest screen frame and draw the front-camera frame on top
    as a rounded square, about 22% of the width, in a corner; the user
    can drag it to a different corner.
  - Use an OpenGL ES shader on a `SurfaceTextureHelper` and output a
    single `VideoFrame` stream, so the peer receives one composited
    track (tgcalls sends one video track for 1:1 calls).
  - The PiP corner and size are settings in the call UI.
  - The camera inside the PiP can also be switched front/back.
- Remote video renders through WebRTC's `SurfaceViewRenderer`.
  - Expose it to Flutter as a `PlatformView` or `Texture` widget, with a
    local self-view PiP in the Flutter UI.

**UI (Glowing Relaxation)**
- Incoming call: a full-screen notification (`USE_FULL_SCREEN_INTENT`,
  `ConnectionService` / self-managed calls) plus an in-app ringing screen.
- In call:
  - Avatar halo pulses with audio level.
  - Encryption emojis, shown to compare.
  - Mute, speaker, video, switch camera, share screen (with "Include
    camera" toggle), hang up.
  - Duration and network quality.
- Call buttons in the conversation header and chat info for private
  chats. Call history comes from `MessageCall` messages, which already
  arrive as messages.

## 6. Conventions (keep them)

- Feature-first. Presentation never calls `TdClient` directly.
  Cross-feature hooks go only through `app/feature_wiring.dart` and
  `ConversationExtensions`, `ComposeActions` and `SettingsEntries`.
- No static mutable hooks. Provide interfaces via `RepositoryProvider`.
- Colors from `GlowColors` only. White text only on the `*Deep` gradients;
  bright accents carry near-black text (`onAccent`). Glow is decoration.
- Durations and curves come from `Motion` (M3 tokens). Ambient animation
  checks `Motion.ambientEnabled(context)`.
- Interactive custom widgets get semantics labels and touch targets of at
  least 48 dp.
- Every step ends with `flutter analyze` at zero issues and `flutter test`
  green, then commit and push to `main`. Commit messages end with the
  attribution lines the session provides. No model identifiers in commits
  or docs.

## 7. Verified API facts and gotchas

- The TDLib error class is `td.TdError` (code, message). `convertMapToObject`
  returns null for unknown types; a parse failure with `@extra` must fail
  the waiting invoke (it already does).
- `td_receive` blocks (0.5 s timeout here) and must never run on two
  threads. Restart the receiver only after the old isolate's exit
  (`onExit`).
- Bot tokens work only in `authorizationStateWaitPhoneNumber`.
  `setAuthenticationPhoneNumber` also works in the code, password, email
  and registration states (used for "back to phone entry").
- The generated `copyWith` cannot set a field to null; see
  `TelegramCache._rebuild`.
- `getChatHistory` often returns only the local cache first; call it again.
- `whisper_edge` on Android decodes WAV only. Telegram voice notes are
  OGG/Opus, so always run `FfmpegService.toWhisperWav` first.
  `whisper_edge` has minSdk 24 and its downloader can't resume (we bundle
  the model anyway).
- `file_picker` 13 may return `content://` URIs; copy them through `XFile`.
- `RadioListTile.groupValue` is deprecated; use `RadioGroup`.
- `provider` rejects a `ChangeNotifier` through a plain `RepositoryProvider`.
  `main.dart` and `test/flutter_test_config.dart` set
  `Provider.debugCheckInvalidValueType = null`, because services
  (VoiceRecorder, TranscriptionCenter, MessageIndexer) are listened to
  explicitly with `ListenableBuilder`, never through `context.watch`.
- Sponsored messages: report impressions with `viewMessages` (always, even
  in ghost mode) and clicks with `clickChatSponsoredMessage`.

## 8. Must verify on a real device

- The real `libtdjson.so`: batching, isolate respawn, and process death
  going straight to `Ready`.
- Streaming: VLC and ExoPlayer seeking through the loopback server, and
  two concurrent range requests on one file.
- `h264_mediacodec` encoding on several SoCs (the fallback is `mpeg4`).
- Live location in the background on Android 14+ (foreground service type
  `location` with while-in-use permission), on Android 7–10
  (`requestSingleUpdate` path), and the notification on Android 13+.
- Bots and `loadChats`: confirm the error code (currently 400, treated as
  silent).
- A TalkBack pass, and a 16 KB page-size emulator image (VLC, ffmpeg,
  sqlite3mc, llama.cpp).
