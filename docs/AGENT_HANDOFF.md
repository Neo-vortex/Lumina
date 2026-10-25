# Lumina: Agent Handoff Spec

This document is for an engineer or agent continuing the work. The main
[README](../README.md) is for users. Keep this document current: update
the status table and "Next steps" in the same commit as the work.

Companion docs:
- [ARCHITECTURE.md](ARCHITECTURE.md): layers, folder rules, TDLib threading
- [DECISIONS.md](DECISIONS.md): resolved decisions and spec corrections
- [UX_RESEARCH.md](UX_RESEARCH.md): UX requirements UX-01…UX-33 with sources

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
| Hardening (cache/optimizeStorage, battery prompt, 16 KB check) | ✅ | `lib/features/maintenance/` (StorageRepository: usage by kind, clear, keep-media auto clean; Background settings + one-time battery prompt in `LifecycleWatcher`); memory pressure frees the LLM and Whisper; `tool/check_16kb.py <apk>` |

Tests: `flutter test`, 99 tests covering routing, auth FSM (bloc_test),
error mapping, cache ordering, row grouping, video presets, search, assistant,
chat info, stories and storage. Run
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
- ABI filter: arm64-v8a and x86_64.
- **Licensing:** ffmpeg is the LGPL `ffmpeg_kit_flutter_new_full` build.
  Do not switch to the GPL variant, which would make the app GPL. H.264 and
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
- Bots and `loadChats`: confirm the error code (currently 400, treated as
  silent).
- A TalkBack pass, and a 16 KB page-size emulator image (VLC, ffmpeg,
  sqlite3mc, llama.cpp).
