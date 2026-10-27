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

2. **Full bot support with Lumina's own UI** — needs a design first:
   reply keyboards (`ReplyMarkupShowKeyboard`) above the composer, the
   commands menu (`/` button, `GetCommands`/`botInfo.commands`), the bot's
   menu button and web apps (embedded vs browser), inline mode
   (`@bot query` results panel), /start for new bots, bot info in the
   profile.
3. **Auto-download** (design approved): Settings → Data & storage →
   Auto-download. Tabs Mobile / Wi-Fi / Roaming; grid of media (photos,
   videos, files, voice, video messages, GIFs, music) × chat type
   (contacts, private, groups, channels) with glowing toggles; log-scale
   size sliders for videos and files (100 KB → 4 GB, snapping);
   presets Off/Low/Medium/High/Custom; "preload larger videos". Sync with
   TDLib `setAutoDownloadSettings` per network type and make the app's own
   downloads follow it. Needs `ACCESS_NETWORK_STATE` (manifest is an owner
   file: stage only your hunk) and a native network-type channel.
4. **Sticker suggestions while typing an emoji** — needs a design (owner
   wants something more inventive than Telegram's strip). TDLib:
   `getStickers(stickerType, query: emoji)`.
5. **Model extraction in the background** shortly after first launch
   (option A agreed), so the first ✨/AI action doesn't wait.
6. **On-device GPU for SmolLM2** (`ComputeDevice.gpu`, CPU fallback,
   setting to force CPU) — optional now: CPU load is 0.9 s, generation
   0.5 s.
7. **TDLib startup logging**: verbosity is lowered only after auth starts;
   set it before the client is created so logcat stays quiet.
8. **Swipe-to-react race**: two quick swipes within ~0.5 s can add twice
   (interaction updates are coalesced); toggle from local state.
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

## Done recently, not yet confirmed on the phone

Inline keyboards under bot messages (glass pills; url/login/web app open
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
