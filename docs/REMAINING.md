# Remaining work (as of 2026-10-27)

Read `docs/AGENT_HANDOFF.md` first for the rules (single `main` branch,
stage explicit paths only, never commit the owner's local edits or
"DIAGNOSTIC" lines, TDD, glow sheets instead of stock dialogs, designs
agreed with the owner before new features, `dart format` only touched
files, analyzer clean). Nothing is pushed yet: `main` is ahead of
`origin/main`; ask before pushing.

## Build and install

- Release: `tool/flutter.sh build apk --release --target-platform android-arm64`,
  then `python3 -I tool/check_16kb.py build/app/outputs/flutter-apk/app-release.apk`.
- `libtdjson.so` (arm64) is committed in LFS under
  `android/app/src/main/jniLibs/arm64-v8a/`; the `checkTdlib` Gradle task
  fails the build if it is missing or not the pinned TDLib. Rebuild it with
  `ANDROID_HOME=~/Android/Sdk tool/build_tdlib.sh arm64-v8a` after a pin
  change (about 1 h). Always confirm `lib/arm64-v8a/libtdjson.so` is in the
  APK before installing.
- The owner's phone is reached with `adb` (`adb install -r …` keeps data;
  screenshots with `adb exec-out screencap -p`). Release builds print Dart
  `print()` to logcat (tag `flutter`), handy for temporary diagnostics —
  never commit them.
- `pubspec.lock` holds owner edits: stage only your package entries
  (build the staged file from `git show HEAD:pubspec.lock` plus your blocks,
  `git hash-object -w` + `git update-index --cacheinfo`). The pub mirror is
  flaky; `PUB_HOSTED_URL=https://pub.myket.ir` works, but rewrite the lock
  URLs back to `https://pub.flutter-io.cn` and restore the owner's lock.
- In widget tests: never `await` a sheet/route result directly (hangs when
  a tap misses); never `close()` a cubit inside `runAsync` in teardown; use
  a 1080x2400 @3x view for sheets; `GlowButton` shimmers, so don't use
  `pumpAndSettle`; run tests with `--timeout`.

## Next (agreed with the owner)

2. **Full bot support with Lumina's own UI** (spec `docs/superpowers/specs/2026-10-27-bot-support-design.md`; 1/5 done: welcome card, start links, profile section; next: command palette) — needs a design first:
   reply keyboards (`ReplyMarkupShowKeyboard`) above the composer, the
   commands menu (`/` button, `GetCommands`/`botInfo.commands`), the bot's
   menu button and web apps (embedded vs browser), inline mode
   (`@bot query` results panel), /start for new bots, bot info in the
   profile.
4. **Sticker suggestions while typing an emoji** — needs a design (owner
   wants something more inventive than Telegram's strip). TDLib:
   `getStickers(stickerType, query: emoji)`.
9. **VLC smoothness, second try**: the SurfaceProducer rendering showed
   black/garbage on the owner's phone and was reverted to the platform
   view. Retry carefully (e.g. hybrid composition, or SurfaceProducer with
   explicit pixel format), verify on the phone before committing.
10. **Perf batches 4–6** (`docs/PERFORMANCE_AUDIT.md`): pause the hidden
    chat list, throttle the message-index backfill, polish; finding 4
    (`findChildIndexCallback` with `super_sliver_list`) deferred — it
    produced wrong element reuse in a test.
11. **Remaining stock dialogs** to replace with glow sheets/screens
    (`showDialog`/`AlertDialog`): compose_flows (New group / New channel,
    design first), call_settings, settings_screen, saved_story_viewer,
    background_settings (sync), call_screen, decoration_sheets,
    scheduled_messages_screen.
12. **Telegram gap plan**: turn `docs/TELEGRAM_GAP_ANALYSIS.md` into
    categorised milestones for the owner to pick from (don't build).
13. Pattern backgrounds draw only their fill (pattern art not rendered).

## Known problems (from reviews, not fixed yet)

Download manager:
- Search and filters only cover finished downloads already loaded (TDLib's
  `searchFileDownloads(query:)` isn't used).
- The speed figure can linger after the last download stops or pauses.
- A "Downloaded" notification can carry an empty path when TDLib's final
  `updateFile` arrives after the completion update; tapping then only opens
  Lumina.
- Completion notification ids (`4200 + fileId % 1000`) can collide.
- Pause all from the notification is dropped if Android killed the process
  (the receiver doesn't queue like `openDownload` does).
- `screenHidden` can push the visibility counter below zero.
- If a filter hides every loaded finished row, the next page never loads.
- Full-size photos opened in the media viewer aren't listed (no Save action).

Bots (piece 1):
- A non-TDLib error leaves the welcome card's Start busy for good.
- The welcome card needs the bot user cached; for a bot opened from a fresh
  link it can appear only after the next rebuild.
- The welcome card comes back after "Clear history" for a bot already
  started.
- The bot start-link handler sits first among link handlers (safe today).

Folder gesture picker:
- If folders change mid-gesture, the picker keeps the list it opened with.
- The preview doesn't update with messages arriving mid-gesture.
- TalkBack announces the picker, not the highlighted folder.
- The blurred backdrop re-composites every frame while names move; check
  cost on a low-end phone.
- The list always sits on the left (the title is left-aligned); pick the
  side from the first sideways movement if the owner prefers.

## Done recently, not yet confirmed on the phone

Download manager (header ring while downloading, Settings → Data & storage →
Downloads; pause/resume, pause all, drag to reorder = priority, filters, search,
Wi-Fi only, progress + "Downloaded" notifications), Bot welcome card with Start (and t.me/bot?start= links), bot section in the profile, Folder gesture picker (hold the folder title, slide along the edge list,
release; Settings → Chats → Swipe folder picker, on by default), SmolLM2 on the GPU (Vulkan) with CPU fallback and a "Run AI on the CPU"
setting showing where it runs, auto-download (downloads follow it: photos, GIFs, videos with optional
start preload, files, voice, video messages, music; settings screen synced with
TDLib (per network, presets, grid, size sliders, network type channel)), models extracted in the background 15 s after launch (AI action model,
then Whisper), TDLib log level set before the client exists (quiet startup), quick
repeat reactions toggle from local state (no double add), inline keyboards under bot messages (glass pills; url/login/web app open
the link, callbacks ask the bot with a spinner and answer as toast, glow
sheet or link, copy text, open user, switch inline fills the composer;
game/buy/password callbacks say "not supported yet"), chat backgrounds (Telegram, per chat, default with blur/dim; no black
flash, pre-blurred), media viewer captions (dark scrim, video tap swaps
caption ↔ controls), proxy link sheet with status, emoji-only messages
(still until tapped, double tap effect), inline GIFs (tap pauses) and GIF
panel (plays, pauses while scrolling), voice recording waveform/halo,
profile photos full screen (pull down, zoom, save), message Details,
AI reaction suggestion, focus menu above the keyboard and blurred chat,
violet sent bubbles, map previews + "Open in", expired self-destruct
card, profile (personal photo first, tip, swipe), sent-message flicker
fix, video reverted to the platform view.
