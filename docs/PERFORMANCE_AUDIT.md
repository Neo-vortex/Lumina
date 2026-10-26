# Performance audit: idle CPU, 120 Hz smoothness, UI glitches

Date: 2026-10-26. Branch `tdlib-own-bindings`, working tree as found (uncommitted
edits included). Flutter 3.50.0-0.2.pre (beta), Dart 3.14, Impeller on Android
(no opt-out in `AndroidManifest.xml`). Line numbers refer to that working tree.

Symptom being explained: a channel page sitting idle on a 120 Hz phone used
~110 % CPU (all threads of the process), with the Flutter raster thread at
~23 %. Idle should mean no frames at all: UI and raster near 0 %.

Labels: **confirmed** = visible in the code, with a mechanism that follows
from Flutter or Dart semantics. **suspected** = plausible from the code, but
needs a trace to size it or to rule it out.

---

## 1. Summary: likely causes, ranked

| Rank | Cause | Share of the symptom | Confidence |
|---|---|---|---|
| 1 | **`GlowBackground` repaints the whole conversation body at the display rate, forever.** `conversation_screen.dart:340` wraps the body in `GlowBackground`, and its 40 s drift controller repeats with no end (`glow_background.dart:22-28`). It ticks on every vsync, so 120 frames/s. **Impeller has no raster cache** ([flutter#166184](https://github.com/flutter/flutter/issues/166184), [flutter#131206](https://github.com/flutter/flutter/issues/131206)), so the `RepaintBoundary` at `:46` only saves the UI thread's re-recording. Each of those frames the raster thread redraws *everything* on screen: three full-screen radial gradients, every bubble with its gradient, its border and `BoxShadow` blur, each blurred minithumbnail (`ImageFiltered`), and the clip layers. One animated pixel means a full re-raster per frame. | Most of the 23 % raster, plus a steady UI-thread and vsync cost. Indirectly a share of the rest, since each frame also wakes the platform and GPU driver threads. | **High** (confirmed in code; the size of the cost needs a trace) |
| 2 | **The conversation rebuilds in full on every unrelated user-status change.** `ConversationCubit._onCacheEvent` treats every `UserChanged` as relevant (`conversation_cubit.dart:485`) and bumps `revision` (`:500`). `TelegramCache` emits `UserChanged` for every `updateUserStatus` of any contact (`telegram_cache.dart:138-142`), and on a large account that is many per minute. `BlocConsumer` has no `buildWhen` (`conversation_screen.dart:277`), so each event re-runs `buildRows`, rebuilds every visible bubble, re-decodes base64 minithumbnails (finding 6) and resubscribes every `TdFileImage` stream (finding 7). Each rebuild also schedules a frame. | A UI-thread share, plus extra frames when the background is fixed. | **High** (confirmed) |
| 3 | **The background search-index backfill.** `MessageIndexer._backfillLoop` (`message_indexer.dart:161-183`) walks up to 300 chats × 5 pages × 100 messages, every 300 ms, for up to 50 passes, after login and on every app start until it is done. That costs TDLib network and DB work, a JSON parse of 100 full messages on the receiver isolate, a copy to the UI isolate, then a copy to the SQLite worker isolate. It runs no matter which screen is open. | Non-raster CPU: native TDLib threads plus three Dart isolates. Likely a large part of the ~87 % that isn't the raster thread. | **Medium** (confirmed that it runs; its share needs a trace) |
| 4 | **The chat list rebuilds while it is hidden.** `ChatListCubit` re-sorts every chat and emits on any `ChatChanged`, `UserChanged` or `TypingChanged`, at most every 80 ms (`chat_list_cubit.dart:61-84`), and `revision` forces a new state each time. The home route is offstage under the conversation, but offstage routes still *build* (only layout and paint are skipped), so `ChatsScreen`'s `BlocBuilder` (`chats_screen.dart:140`) still rebuilds the visible rows and schedules frames. | Up to 12.5 builds and frames per second. | **Medium** (confirmed) |
| 5 | **Other ambient loops that never stop:** `SendOrb._wave` repeats while the composer holds *any* text, e.g. a restored draft (`send_orb.dart:67`). `StoryHalo` spins a blurred sweep-gradient forever for each chat with unseen stories (`story_halo.dart:45`, `:103-114`). The live-location `_Pulse` (`rich_cards_content.dart:166,175`) ignores reduced motion. `TypingParticles` runs while someone types. `GlowButton` breathes forever. Each one forces a full-screen re-raster per frame on Impeller. | Situational: a draft in a chat you can post in, story halos on the chat list. | **High** (confirmed) |
| 6 | **Possible 60 Hz lock or refresh-rate thrash.** Flutter on Android never calls `Surface.setFrameRate` ([flutter#160952](https://github.com/flutter/flutter/issues/160952), open, P2). Some OEMs (Xiaomi, Poco, Redmi, Infinix in that report) lock Flutter apps to 60 Hz. This is separate from the idle cost: it decides whether *real* animations look smooth. | Smoothness, not idle CPU. | **Suspected**: check with "Show refresh rate" |

If 1, 2 and 5 are fixed, an idle channel should produce **zero frames**:
DevTools' frame chart stays empty, and `dumpsys gfxinfo` "Total frames
rendered" stops growing. Then the raster thread drops to ~0 %. Fixing 3
removes most of the remaining background CPU.

---

## 2. Findings table

| # | Area | File:line | Problem | Why it costs frames/CPU | Fix (concrete code-level change) | Impact | Effort |
|---|---|---|---|---|---|---|---|
| 1 | Ambient anim | `core/widgets/glow_background.dart:22-28,46,66-91`; used at `conversation/presentation/screens/conversation_screen.dart:340`, `chat_info_screen.dart:212`, `proxy_screen.dart:130`, `send_media_screen.dart:176`, `call_screen.dart:96`, auth screens | 40 s drift `repeat()` forever; three full-screen `RadialGradient` shaders and a `LinearGradient` are created in `paint` on every frame. **Confirmed.** | 120 frames/s for the whole screen's lifetime. On Impeller every frame re-rasters the entire scene, so RepaintBoundary does not help the raster thread. Allocates 4 `Paint`s and 4 shaders per frame on the UI thread. | (a) Draw the backdrop **once**: make `_OrbPainter` take a fixed `t` (or a `CustomPaint` with `isComplex: true, willChange: false`) and don't run the controller on content screens (conversation, chat info, proxy, send media). (b) To keep *some* motion: run the drift only on auth/pulse screens and stop it after one cycle, or step it with a `Timer.periodic(Duration(seconds: 2))` that calls `markNeedsPaint` (0.5 fps reads as still at a 40 s period). (c) Better still: render the backdrop to a `ui.Image` once per size (`PictureRecorder` → `toImageSync`) and draw that image. A cached image is cheap to composite but is still redrawn every frame on Impeller, so (a) comes first. | **H** | S |
| 2 | Bloc rebuilds | `conversation/bloc/conversation_cubit.dart:481-502` (esp. `:485 UserChanged() => true`, `:500 revision + 1`) | Any user's status change anywhere rebuilds the open conversation. `ChatChanged` for this chat (read inbox, last message, online count, draft) does too. **Confirmed.** | `buildRows` (O(n)), every visible `MessageBubble.build`, the semantics label (`DateFormat.Hm()` built per call), base64 decodes, stream resubscriptions; each also schedules a frame. | Filter `UserChanged` to ids the screen shows: the private peer (`cache.peerUser(chat)?.id`) plus sender ids in `state.messages` (keep a `Set<int>` updated when messages change). Don't bump `revision` for users: put the relevant `td.User`s into state or let the header listen on its own. Emit `chat` only if `!identical(cache.chats[chatId], state.chat)`. | **H** | S |
| 3 | Bloc rebuilds | `conversation/presentation/screens/conversation_screen.dart:277-438` | One `BlocConsumer` builds the whole `Scaffold`, header, list and composer for any state change. No `buildWhen`; `_rows = buildRows(...)` runs inside `build` (`:292`). **Confirmed.** | The `highlightId` timer, `selected`, `pinned`, `revision`, `loadingOlder` all rebuild everything. | Split into slices: header → `BlocSelector` on `(chat, typing revision)`; pinned banner → `select((c) => c.state.pinned)`; list → `BlocBuilder(buildWhen: (a,b) => !identical(a.messages,b.messages) \|\| a.highlightId != b.highlightId \|\| a.selected != b.selected \|\| a.hasOlder != b.hasOlder \|\| a.sponsored != b.sponsored)`; composer → its own `select`. Memoise `buildRows` on `identical(messages)` and `firstUnreadId`. | **H** | M |
| 4 | List keys | `conversation_screen.dart:364-394`, keys at `:447` | `SuperListView.builder` has **no `findChildIndexCallback`**. When a new message lands at index 0 every row shifts by one. The sliver reuses elements *by index*, the `ValueKey` no longer matches, and each visible bubble's `State` is thrown away and rebuilt. **Confirmed.** | New `State`s → `_entrance` replays fade and slide (glitch G1); `TdFileImage` and `_ReplyQuote` re-run (`messageById` invoke); images flash. A full subtree inflation for each visible row on each incoming message. | Pass `findChildIndexCallback: (key) { final id = (key as ValueKey<int>).value; final i = _rowIndexById[id]; return i == null ? null : i + _adsOffset; }` and keep `_rowIndexById` up to date in the memoised `buildRows`. Also key `DayHeaderRow` (`ValueKey('d$day')`) and `ServiceRow` (`ValueKey(message.id)`). | **H** | S |
| 5 | Image decode | `core/telegram/widgets/td_file_image.dart:85-92` | `Image.file` without `cacheWidth`/`cacheHeight` decodes the full resolution (`_displaySize` picks ≥ 640 px; the viewer and IV use the largest, up to 2560 px). **Confirmed.** | Decode time on the UI-adjacent IO thread, GPU upload, and `ImageCache` (100 MB default) churn, evicting avatars. A 1280×1280 photo is 6.5 MB decoded, for a 280 dp tile. | Wrap in `LayoutBuilder` and pass `cacheWidth: (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context)).round()` (and `cacheHeight` for `BoxFit.cover` when the height is the binding side). Keep full size only in `MediaViewerScreen` (`priority: 32` path). See [`ResizeImage`](https://api.flutter.dev/flutter/painting/ResizeImage-class.html). | **H** | S |
| 6 | Per-build alloc | `core/telegram/display.dart:51` called from `media_content.dart:160,163`, `chat_avatar.dart:76`, `document_content.dart:83`, `video_note_content.dart:86`, `link_preview_card.dart:87`… | `Display.minithumbnail` runs `base64Decode` **on every build**, and the new `Uint8List` gives `Image.memory`'s `MemoryImage` a new cache key (identity equality), so the JPEG is **decoded again** each rebuild and the `ImageCache` fills with duplicates. **Confirmed.** | With finding 2, every visible avatar and media tile re-decodes on each unrelated user-status event. | Memoise: `static final _mini = Expando<Uint8List>();` keyed on the `td.Minithumbnail` instance, or a small LRU `Map<String, Uint8List>` keyed by `m.data.hashCode`. Better: a `MinithumbProvider extends ImageProvider` whose key is the base64 string. | **H** | S |
| 7 | Streams | `td_file_image.dart:65-67`, `file_progress.dart:19-21` (`FileBuilder`) | `stream: _files.watch(id)` is called **in `build`**. `watch` is an `async*` generator, so each build creates a new stream; `StreamBuilder` unsubscribes, resubscribes and gets one more async rebuild from the initial `yield`. **Confirmed.** | Doubles rebuilds; allocates a subscription per rebuild. `FileStore._changes` is one broadcast stream with a `.where(id)` per watcher, so every `updateFile` (download progress, often 10+/s) runs every watcher's filter. That is O(watchers × updates). | Create the stream once in `initState`/`didUpdateWidget` (when `file.id` changes). In `FileStore`, swap the broadcast + `where` for `Map<int, ValueNotifier<td.File>>` (ref-counted) and use `ValueListenableBuilder`. | **M** | S |
| 8 | Blur | `td_file_image.dart:82,98` | Every not-yet-downloaded image (and every avatar until its small photo arrives) draws a 40 px minithumbnail through `ImageFiltered(blur σ6)`, which is a saveLayer plus a blur pass. **Confirmed.** | Per frame, per tile. With finding 1, that is 120 blur passes/s per visible placeholder. | Pre-blur once: decode the minithumb at its own size with `filterQuality: FilterQuality.medium` and let upscaling smooth it (Telegram's minithumbs are already blurry), or blur once into a `ui.Image` and cache it. Drop `ImageFiltered`. | M | S |
| 9 | Blur | `media_content.dart:181` | Spoiler/view-once cover: `ImageFiltered(ImageFilter.blur(σ22))` over the full-size image, rebuilt with a new filter object each build. **Confirmed.** | A large-σ blur on a ~280×340 dp layer every frame. | Use the minithumbnail (already low-res) as the cover instead of blurring the full image, or cache the filter as a `static final`. | M | S |
| 10 | BoxShadow blur | `message_bubble.dart:160-165`, `glow_colors.dart:64-73` | Read outgoing bubbles always get `glow(cyan)` = a `BoxShadow` with blur 14.5. The radius is **asymmetric** (`BorderRadius.only`, `:104-116`). **Suspected** cost: Impeller's analytic fast path for blurred rounded rects was built for uniform corner radii. Non-uniform shapes may take the general Gaussian path (offscreen pass). | Each read outgoing bubble × each frame. | Measure first (DevTools → enable "Raster stats" / a Perfetto trace for `GaussianBlur` passes). If it is costly: use a uniform radius for the shadow only (paint the shadow as a separate `DecoratedBox` with `BorderRadius.circular(20)` behind the bubble), or replace the shadow with a 1.4 px brighter border (UX-04 already encodes read state as shape + color). | M | S |
| 11 | Ambient anim | `send_orb.dart:58-69` (`:67`) | `_wave.repeat()` runs whenever `charge > 0`, i.e. whenever the field holds text, including a restored draft. `_pulse` also runs at full charge. The `AnimatedBuilder` rebuilds a `Transform`, `CustomPaint` and `AnimatedSwitcher` each frame; no `RepaintBoundary`. The painter builds an ~26-segment path, two shaders and a `MaskFilter.blur` per frame (`:176-218`). **Confirmed.** | A composer with a draft = 120 frames/s, full re-raster. | Run the wave only while the text is *changing*: start on `controller` change, stop 1.5 s after the last keystroke (`Timer`). Wrap the orb in `RepaintBoundary`. Hoist the gradient `Shader`s into fields that change only with `size` and `recording`. | **H** (when a draft exists) | S |
| 12 | Ambient anim | `stories/presentation/widgets/story_halo.dart:26,40-49,102-114`; `app/app_story_wiring.dart:224` | Each chat-list avatar with unseen stories spins forever (10 s period) with a `SweepGradient` shader and a blurred stroke created per frame. It reads reduced motion from `platformDispatcher` once, not from `MediaQuery`. **Confirmed.** | Chat list idle = 120 frames/s whenever any visible chat has unseen stories. | Spin 1–2 turns when the row first appears, then rest on a static gradient ring. Or turn it into a slow `Timer`-stepped rotation. Use `Motion.ambientEnabled(context)` in `didChangeDependencies`. Add a `RepaintBoundary` around the halo. | **H** (chat list) | S |
| 13 | Ambient anim | `rich_cards_content.dart:161-176` (`_Pulse`) | Live-location pulse repeats for the whole sharing period (up to 8 h, or "until stopped"), ignores reduced motion, and animates `BoxShadow` `spreadRadius` (layout-free, but a full repaint). **Confirmed.** | Continuous frames while a live location is visible. | Gate on `Motion.ambientEnabled`; pulse 3 times after each location update, then rest. | M | S |
| 14 | Hidden rebuilds | `chats/bloc/chat_list_cubit.dart:61-84`; `chats_screen.dart:140-184` | Re-sorts all chats (`chatsIn`, O(n log n) plus allocation) and emits a new `revision` on *any* user/chat/typing event, even while the conversation covers the list. `UserChanged` for users without a private chat in view still triggers it. **Confirmed.** | Up to 12.5 rebuilds/s of the offstage list (build only), plus frames. | (a) Pause while covered: have `HomeShell` listen for `RouteAware.didPushNext`/`didPopNext` (needs a `RouteObserver`) and call `cubit.pause()` / `resume()` (on resume, rebuild once). (b) For `UserChanged`, rebuild only if the user is the peer of a listed private chat. (c) Re-sort only on `orderChanged: true`; otherwise patch the one chat in place. | M | M |
| 15 | Background CPU | `features/search/data/message_indexer.dart:161-210` | History backfill runs continuously after login and app start: 300 chats × 5 pages × 100 messages, every 300 ms, up to 50 passes. **Confirmed** that it runs; its share is **suspected**. | TDLib network and DB, a JSON parse on the receiver isolate, two isolate copies (UI and worker), SQLite FTS inserts. | Run only when idle *and* charging/unmetered (ask Android via the system channel), or from WorkManager. Pause while a conversation is open or while scrolling. Back off to ≥ 2 s between pages. Add a Settings switch (exists: `searchBackfill`) and default it to "while charging". | **H** (battery) | M |
| 16 | List perf | `conversation_screen.dart:374` | `_cubit.sponsoredVisible(ad)` is a side effect inside `itemBuilder`. It also fires for cache-extent builds that are not on screen. **Confirmed.** | Small CPU, but wrong semantics (ad views counted off-screen). | Report from `_reportVisible()` using `visibleRange` (indices `< _adsOffset`). | L | S |
| 17 | Per-build alloc | `message_bubble.dart:317-325` | `Tween(...).animate(CurvedAnimation(parent: _entrance, ...))` is created in `build`. `CurvedAnimation` adds a status listener to `_entrance` and is never disposed. **Confirmed.** | Leaks one listener per rebuild per bubble. With finding 2, rebuilds are frequent. | Create `_slide = Tween(...).animate(CurvedAnimation(...))` once in `initState` and dispose the `CurvedAnimation` in `dispose`. Skip the `FadeTransition`/`SlideTransition` wrappers entirely when `!widget.animateIn`. | M | S |
| 18 | Per-build alloc | `message_bubble.dart:332,373` | `DateFormat.Hm()` is built 3 times per bubble per build (footer, overlay footer, semantics). `_Footer` is built twice but only one is used (`message_content_view.dart:49-70`). **Confirmed.** | `DateFormat` construction parses a pattern and looks up locale data. | `static final _hm = DateFormat.Hm();`; pass a footer *builder* (or a flag) instead of two prebuilt footers. | L | S |
| 19 | Audio | `audio_content.dart:45,156` + `core/media/audio_playback.dart:63` | Every voice/music bubble listens to the global `PlaybackState`; position ticks rebuild *all* audio bubbles, not only the one playing. **Confirmed.** | N bubbles × ~5–10 Hz while playing. | Use a selector: `ValueListenableBuilder` on a derived `ValueNotifier` per message id, or compare `state.messageId == myId` in a custom listenable that only notifies matching bubbles. | L | S |
| 20 | Streaming | `core/media/tdlib_stream_server.dart:83-110` | The loopback HTTP server runs on the **UI isolate**: each 256 KB chunk does a `getFileDownloadedPrefixSize` invoke (isolate round trip), file I/O and a socket write. **Confirmed.** | At 5–10 MB/s video bitrates that is 20–40 chunk loops/s on the UI isolate. Can jank frames while scrolling a chat with a playing video note, or in the viewer's controls. | Move `TdStreamServer` to its own isolate. It needs `FileStore` state: forward `updateFile` for watched ids, or have it call TDLib through the sender isolate's port directly. Also raise `_chunk` to 1 MB once the prefix is known to be large. | M | M |
| 21 | Platform views | `packages/flutter_vlc_player_platform_interface/lib/src/method_channel/method_channel_vlc_player.dart:67-77`; used in bubbles by `video_note_content.dart:74` | `virtualDisplay = true` → `AndroidView` (TLHC; falls back to Virtual Display if the native view is a `SurfaceView`). The `else` path is Hybrid Composition (`initSurfaceAndroidView`), which makes every frame synchronise with the platform thread. **Suspected:** which mode actually runs depends on VLC's native view type. | HC in a scrolling list is a known frame-time killer; TLHC is fine. | Keep `virtualDisplay: true` (never HC) for in-list players. Verify in Perfetto: look for `PlatformView` / `SurfaceTexture` slices. Long term: render video notes through a `Texture` (as calls already do in `call_screen.dart:536`). | M | L |
| 22 | Blur | `home/presentation/widgets/glow_nav_bar.dart:29-31` | `BackdropFilter(blur σ18)` over the chat list (`extendBody: true`). **Confirmed.** | A backdrop read-back and blur each frame the list moves or any halo animates. On Vulkan it splits the render pass. | Keep it, but remove the reasons it runs at idle (findings 12, 23). Optionally replace it with an opaque `surface` at 0.94 alpha while scrolling, or wrap it in a `BackdropGroup` (Flutter ≥ 3.29 shares one backdrop for several filters). | M | S |
| 23 | Spinners | `connection_status.dart:66`; `file_progress.dart:79` (`value: p` can be null → indeterminate); `conversation_screen.dart:379-389` | Indeterminate `CircularProgressIndicator`s tick forever: the title while TDLib reports "Updating"/"Connecting" (can last minutes behind a proxy); transfer rings whose `expectedSize == 0`; the "loading older" row that never resolves (see G5). **Confirmed.** | Each one = continuous frames and a full re-raster. | Show a static icon after 3 s of the same state. In `TransferRing`, fall back to a static icon when `p == null`. Fix G5. | M | S |
| 24 | Rebuild scope | `app/app_story_wiring.dart:27`; `timeline_chat_row.dart:276-281` | `listenable` getter returns a **new** `Listenable.merge` on each call, so each row's `ListenableBuilder` resubscribes on every build. It also listens to all of `AppPreferences.changes`, so any preference change rebuilds every row's avatar. **Confirmed.** | Small, but multiplies by visible rows on every chat-list rebuild. | Cache the merged listenable in a field; use a narrower notifier (stories + `hideStories` only). | L | S |
| 25 | Painter alloc | `timeline_chat_row.dart:370-376`; `luminous_refresh.dart:109-134`; `story_halo.dart:103-106`; `send_orb.dart:188-218` | Shaders and `Paint`s are created inside `paint()` each frame. **Confirmed.** | GC churn while animating; Impeller also re-uploads gradient textures. | Cache `Shader`s keyed on `size` in the painter (or static `Paint`s with fixed shaders); pass animation via `super(repaint:)` instead of rebuilding via `AnimatedBuilder` + new painter each tick (`timeline_chat_row.dart:148-160`, `story_halo.dart:68-75`). | L | S |
| 26 | Bloc emits | `conversation_cubit.dart:472-479` | `_replace` copies and **re-sorts** the whole message list for each `updateMessageInteractionInfo`. View and reaction counts on a busy channel arrive continuously while it is open. **Confirmed.** | O(n log n) plus a full rebuild per view-count tick. | Don't sort on in-place replacement (the id doesn't change; only `UpdateMessageSendSucceeded` changes ids, and only that path needs re-sorting). Coalesce interaction-info updates: collect in a map and emit at most every 500 ms. | M | S |
| 27 | Rebuild scope | `conversation_screen.dart:406-408` | `ListenableBuilder(extensions.composerListenable)` rebuilds the whole `Composer` (incl. `TextField` decoration and `SendOrb`) on extension changes such as recording ticks. **Suspected** (depends on what the listenable fires on: the voice recorder ticks every 200 ms at `voice_recorder.dart:85`). | 5 Hz composer rebuilds while recording. | Scope it to `recordingOverlay` and `orbMode` only. | L | S |
| 28 | Isolate traffic | `core/tdlib/isolates/td_isolates.dart:41-55`; `td_isolate_client.dart:145-151` | Good: JSON is parsed off the UI isolate. But each batch of ≤ 100 objects is copied into the UI isolate and fanned out to ~12 `updates` listeners through an async broadcast controller, so each `Update` costs a microtask per listener. **Confirmed**, low cost. | Visible only in update storms (login sync, large channels). | Drop update types nobody handles in the receiver isolate (e.g. `updateOption`, `updateAnimatedEmojiMessageClicked`), and route `updateFile` to `FileStore` only. | L | M |

---

## 3. UI glitches

**G1. Bubbles re-animate in when a new message arrives (and images flash).**
`conversation_screen.dart:364-394`, `:447-452`; `message_bubble.dart:70-78`.
Repro: open an active group and wait until two messages arrive. Every bubble
that arrived *after* the chat was opened fades and slides in again when the
next one lands. Photos in shifted rows may flash their placeholders.
Cause: no `findChildIndexCallback`, so the shifted rows lose their `State`
(finding 4). With a fresh `State`, `animateIn` is true again for ids not in
`_seenAtOpen`. Fix: finding 4, plus track "already animated" ids in a
screen-level `Set` (`_animated.add(row.id)` the first time) instead of
recomputing from `_seenAtOpen`.

**G2. The view jumps when a message arrives while you read older history.**
`conversation_screen.dart:364` (reverse list, new rows at index 0).
Repro: in a busy chat, scroll up a few screens (jump button visible), then
wait for an incoming message. **Suspected:** the visible content moves by the
new bubble's height, because the new extent is added *before* the viewport.
`super_sliver_list` corrects scroll offset for re-measured estimated extents
(`render_object.dart:328-357` in 0.4.1). Whether it corrects for an inserted
leading item needs testing. Fix if confirmed: while `_scroll.offset > 0`,
hold new messages in a pending count shown on the jump button (the cubit
already tracks `hasNewer`). Or, after the insert frame, `jumpTo(offset +
insertedExtent)` using `_list.getOffsetToReveal`.

**G3. The composer and banners resize the list without animation.**
`conversation_screen.dart:343-350` (`PinnedBanner` inserted at the top of the
`Column`), `composer.dart:190-217` (`AnimatedSize` on the reply and preview
strips), `:405-431` (composer ↔ `_ReadOnlyBar` swap after membership loads).
Repro: open a channel with a pinned message. The list first lays out, then
jumps down by the banner height when `_refreshPinned` completes (it is
fetched after the history). Fix: reserve the banner slot as soon as
`chat.hasPinned…` is known, or overlay the banner (`Stack` + top padding on
the list) so the list doesn't relayout. Fetch the pinned message in
parallel with the history (`Future.wait`).

**G4. Images pop in with no reserved height in stickers, link previews and IV.**
`sticker_content.dart:27`, `instant_view_screen.dart:501,559,724`. Visual
media in bubbles reserve size from `w/h` (`media_content.dart:92-96`, good).
Stickers and IV images without known dimensions lay out at the image's size
when it decodes, so text below shifts. Fix: always wrap them in `SizedBox`/
`AspectRatio` from the TDLib-provided width/height.

**G5. A chat sometimes opens with only the last message and a spinner that never ends.**
`conversation_cubit.dart:84-105`, `:143-160`; `conversation_screen.dart:357-394`.
Repro: open a chat TDLib hasn't cached recently (or right after login).
Only the newest message shows, with the "loading older" spinner above it.
Reopening the chat works. Cause: `getChatHistory` may return just one
message from the local DB (TDLib documents that it may return fewer than
`limit`). The single retry often returns the same. `hasOlder` stays true,
so the spinner row is shown, but `loadOlder()` is only called from a
`ScrollNotification`. A one-message list can't scroll, so no notification
ever arrives. Fix: after each page that changes `messages`, check in a
post-frame callback whether the viewport is filled
(`position.extentAfter < 800`), and if so call `loadOlder()`. Also keep
fetching older pages in `_loadLatest` until ~20 messages are loaded or
TDLib returns nothing new.

**G6. Animations that ignore reduced motion.** `story_halo.dart:43` (reads
`platformDispatcher` once; doesn't react to changes),
`rich_cards_content.dart:166,175` (`_Pulse` ignores it), `call_screen.dart:45`
(1 Hz timer fine), `message_bubble.dart:317-325` (entrance slide runs even
when `ambient` is false; only the bloom checks it), `timeline_chat_row.dart`
(pulse checks; good). Fix: gate with `Motion.ambientEnabled(context)` in
`didChangeDependencies`, and replace slide with an instant appearance when
disabled.

**G7. The day header "Today"/"Yesterday" goes stale.** `conversation_screen.dart:486`
uses `DateTime.now()` at build time. A chat left open past midnight keeps
the old label until something rebuilds it. (Today this happens to be
rebuilt often by finding 2. Fixing that makes the bug visible.) Fix: one
`Timer` to the next midnight that triggers a rebuild of the list.

**G8. Text overflow risks.** `conversation_screen.dart:535-539` (service
messages: no `maxLines`, fine); `_JumpButton` badge `99+` is fine;
`TimelineChatRow` title row: `Display.listTime` and the badges are not
`Flexible`, so on a narrow phone with a large font scale the title collapses
to "…". Fix: give the time text `maxLines: 1` and test at font scale 2.0
(`MediaQuery.textScaler`).

**G9. Shader warm-up.** Impeller precompiles its shaders at engine build
time ([docs](https://docs.flutter.dev/perf/impeller)), so classic first-run
shader jank should not appear. If first-open jank is seen, it is pipeline
creation for new blend/blur variants on Vulkan. Look for `PipelineVK`
creation slices in the first-run trace. No SkSL warm-up is needed (or
possible) under Impeller.

---

## 4. Best practices (condensed, mapped to Lumina)

| Practice | Source | Lumina mapping |
|---|---|---|
| Impeller has **no raster cache**: every frame redraws the whole scene. `RepaintBoundary` saves UI-thread re-recording, not GPU work. The only way to make idle cheap is to **not produce frames**. | [flutter#166184](https://github.com/flutter/flutter/issues/166184), [flutter#131206](https://github.com/flutter/flutter/issues/131206) | Findings 1, 11–13, 23: stop every endless controller on content screens. |
| `saveLayer` (Opacity, ShaderMask, ColorFilter, ImageFiltered, blur) allocates an offscreen target and may switch render targets; BackdropFilter forces an offscreen pass. Prefer color alpha over `Opacity`. | [Flutter performance best practices](https://docs.flutter.dev/perf/best-practices) | Findings 8, 9, 22; `formatted_text_view.dart:365` (ShaderMask fade on collapsed quotes: fine if static, but costly with finding 1). |
| Animate through `Listenable`s (`CustomPainter(repaint:)`, `AnimatedBuilder` with a prebuilt `child`), not `setState`; keep `shouldRepaint` honest; don't build shaders in `paint`. | [CustomPainter API](https://api.flutter.dev/flutter/rendering/CustomPainter-class.html) | Findings 11, 12, 25. |
| Tickers stop when `TickerMode` is disabled (routes covered by an opaque route; `Offstage`), but **not** for widgets in a list's cache extent, and not for anything simply off-screen. Ambient loops need an explicit end. | [TickerMode](https://api.flutter.dev/flutter/widgets/TickerMode-class.html) | Covered routes are fine (conversation uses `MaterialPageRoute`). Story halos, spinners and live-location pulses in list cache extents keep ticking. |
| Builders: rebuild the smallest subtree; use `buildWhen` / `BlocSelector` / `context.select`. Offstage routes still *build* on `setState`. | [flutter_bloc docs](https://bloclibrary.dev/flutter-bloc-concepts/) | Findings 2, 3, 14. ARCHITECTURE.md already says "widgets read slices with `context.select`"; the conversation screen doesn't. |
| Lists: lazy builders; `findChildIndexCallback` when items reorder or insert at the start; `itemExtent`/`prototypeItem` when fixed. `addRepaintBoundaries` defaults to true (keep it). | [SliverChildBuilderDelegate.findChildIndexCallback](https://api.flutter.dev/flutter/widgets/SliverChildBuilderDelegate/findChildIndexCallback.html) | Finding 4. Chat list rows are a fixed 76 dp: set `itemExtent: 76` on `chats_screen.dart:165`. |
| Decode images at display size (`cacheWidth`/`cacheHeight`/`ResizeImage`); size the `ImageCache` for the app. | [ResizeImage](https://api.flutter.dev/flutter/painting/ResizeImage-class.html), [Image.memory](https://api.flutter.dev/flutter/widgets/Image/Image.memory.html) | Findings 5, 6. Consider `PaintingBinding.instance.imageCache.maximumSizeBytes = 150 << 20` on 8 GB+ devices after fixing decode sizes. |
| Heavy JSON or CPU work off the UI isolate (`Isolate.run`/`compute`, or long-lived isolates for streams). | [Concurrency in Dart](https://dart.dev/language/concurrency) | Already done for TDLib (good). Move the stream server (finding 20). |
| Android high refresh: Flutter does not call `Surface.setFrameRate`; on some OEMs Flutter apps are locked to 60 Hz. Workarounds: `flutter_displaymode` (sets `preferredDisplayModeId`; not effective on LTPO panels) or a native `Surface.setFrameRate(120f, FRAME_RATE_COMPATIBILITY_DEFAULT)` / `Window.attributes.preferredRefreshRate`. | [flutter#160952](https://github.com/flutter/flutter/issues/160952), [flutter_displaymode](https://pub.dev/packages/flutter_displaymode) | Check first with Developer options → "Show refresh rate". If locked at 60, set `window.attributes.preferredDisplayModeId` in `MainActivity.onCreate` to the highest-refresh mode with the current resolution. **Only after the idle fixes**, or the ambient loops will cost twice as much. |
| Profile on a physical device in profile mode; use the DevTools Performance view, Perfetto and `dumpsys gfxinfo`. | [Flutter performance profiling](https://docs.flutter.dev/perf/ui-performance), [DevTools Performance](https://docs.flutter.dev/tools/devtools/performance) | Section 5. |

---

## 5. On-device profiling plan

All commands assume the phone is attached over USB and `adb devices` lists it.
The package id is the one in `android/app/build.gradle.kts` (`applicationId`);
below it is `$PKG`.

### 5.0 Build and attach

```fish
cd /home/neo/projects/personal/Lumina-tdlib
set PKG (grep -oP 'applicationId\s*=\s*"\K[^"]+' android/app/build.gradle.kts)
tool/flutter.sh run --profile            # credentials injected by the wrapper
# DevTools URL is printed; open it. Keep the terminal for 'P' (perf overlay).
```

Put the phone on Developer options → **Show refresh rate** to see the
actual Hz. Optional: **Profile HWUI rendering** "On screen as bars" doesn't
cover Flutter's frames. Use the commands below instead.

### 5.1 Baseline: is the idle page producing frames? (findings 1, 11–13, 23)

1. Open the channel, don't touch the screen for 10 s.
2. DevTools → Performance → watch the frame chart. **Before:** a steady
   stream of frames (≈120/s, or 60/s if locked). **After the fix:** no new
   bars at all while idle.
3. Count frames independent of DevTools:
   ```fish
   adb shell dumpsys gfxinfo $PKG reset
   sleep 10
   adb shell dumpsys gfxinfo $PKG | grep -E 'Total frames rendered|Janky frames'
   ```
   Flutter draws into its own surface, so gfxinfo may report few frames even
   when Flutter renders. If so, use SurfaceFlinger:
   ```fish
   adb shell dumpsys SurfaceFlinger --latency-clear
   sleep 10
   adb shell dumpsys SurfaceFlinger --list | grep -i $PKG   # find the SurfaceView/BLAST layer name
   adb shell dumpsys SurfaceFlinger --latency '<layer name>' | wc -l   # ≈ frames presented in the window
   ```
   **Before:** ≈1200 lines in 10 s at 120 Hz. **After:** ≈0–5.
4. CPU per thread:
   ```fish
   adb shell top -H -d 2 -n 5 -p (adb shell pidof $PKG) | head -40
   ```
   Thread names: `1.ui` (Dart UI), `1.raster`, `1.io`, `DartWorker`,
   `td-*`/native TDLib threads, `RenderThread`. **Before:** `1.raster` ≈ 20–25 %,
   `1.ui` ≈ 10–20 %. **After batch 1:** both < 1 % while idle.

### 5.2 Rebuild storms (findings 2, 3, 14, 26)

1. DevTools → Performance → enable **Track widget builds** (profile mode
   supports it) and record 30 s idle on a channel and on a private chat.
2. Look for `ConversationScreen`/`MessageBubble` builds without user input.
   **Before:** builds every time a contact's status changes (bursts of
   several per minute; more on big accounts). **After:** none unless the
   chat itself changes.
3. Count emits directly (temporary, debug only): `Bloc.observer` printing
   `onChange` counts per cubit per 10 s. Expect ConversationCubit ≈ 0 idle.

### 5.3 Raster cost per frame (findings 1, 8–10, 22)

1. Perfetto, system-wide plus app tracing:
   ```fish
   tool/flutter.sh run --profile --trace-systrace   # mirrors Dart/engine trace events into atrace
   adb shell perfetto -o /data/misc/perfetto-traces/lumina.pftrace -t 15s \
     sched freq idle am wm gfx view binder_driver hal dalvik input res memory
   adb pull /data/misc/perfetto-traces/lumina.pftrace /tmp/claude-perf/
   ```
   Open at https://ui.perfetto.dev. Check `1.raster` slices:
   `Rasterizer::Draw`, `EntityPass`/`RenderPass`, `GaussianBlurFilter`,
   `BackdropFilter`. Note the median raster time per frame and how many blur
   passes each frame has.
2. **Expected before:** raster slices every 8.3 ms, each a few ms, with N blur
   passes (N ≈ visible placeholders + read bubbles + orb). **After:** no
   raster slices idle. During scroll: fewer blur passes, raster p90 < 4 ms.
3. A/B renderer sanity check (diagnostic only):
   `tool/flutter.sh run --profile --no-enable-impeller`, then compare.
   Skia's raster cache hides finding 1 partly; that comparison confirms the
   "no raster cache" mechanism.

### 5.4 Background CPU (finding 15)

1. Settings → turn off search backfill (`searchBackfill`), restart, idle on
   the channel for 60 s, and compare the `top -H` totals against the same
   with backfill on. DevTools → CPU Profiler on the UI isolate: look for
   `MessageIndexer._backfillChat` and `SearchWorker` traffic.
2. `adb shell dumpsys batterystats --reset`, then idle for 10 min, then
   `adb shell dumpsys batterystats $PKG | grep -E 'Cpu|Wake|Mobile'`.
   **Expected:** a large drop in app CPU time with backfill paused.

### 5.5 Refresh rate (rank 6)

- Developer options → Show refresh rate, while scrolling the chat list.
  **If it shows 60 on a 120 Hz panel** during interaction, the app is
  locked. Apply the `preferredDisplayModeId` fix, then expect 120 during
  scroll. With batch 1 done, LTPO panels drop back to low Hz when idle,
  which is what you want.
- `adb shell dumpsys display | grep -E 'mActiveSfDisplayMode|renderFrameRate|mDisplayModeSpecs'`
  shows the active mode and the app's vote.

### 5.6 Images (findings 5–7)

- DevTools → Memory → take a snapshot after scrolling 100 media posts.
  **Before:** `ImageCache` near its 100 MB cap with many duplicate small
  entries. **After:** smaller decoded sizes, no duplicates.
- Debug-only check: `debugInvertOversizedImages = true` in `main.dart` marks
  oversized decodes in inverted colors.

---

## 6. Ordered fix plan (each batch ships and is measured on its own)

**Batch 1: zero frames at idle (findings 1, 11, 12, 13, 23, G5, G6).** Make
`GlowBackground` static on content screens. Make the send-orb wave
typing-only. Have story halos spin then rest. Gate the live-location pulse.
Make spinners time out. Fix the never-ending "loading older" spinner.
*Measure:* §5.1. Expect 0 frames idle, raster ≈ 0 %.
*Risk:* visual change (less ambient motion). Owner sign-off on the look.

**Batch 2: stop rebuild storms (findings 2, 3, 4, 17, 18, 26, G1).** Filter
`UserChanged`. Slice the conversation screen with `buildWhen`/selectors and
memoise `buildRows`. Add `findChildIndexCallback`. Build the entrance
animation once. Add a static `DateFormat`. Skip the sort in `_replace` and
coalesce interaction info.
*Measure:* §5.2. Expect no idle builds; incoming messages no longer
re-animate other bubbles.

**Batch 3: images (findings 5, 6, 7, 8, 9, G4).** `cacheWidth` decode,
memoised minithumbnails, streams created once and per-file notifiers,
pre-blurred placeholders, a spoiler cover from the minithumbnail, and
reserved sizes.
*Measure:* §5.6 and §5.3 (scroll raster p90).

**Batch 4: background CPU (findings 14, 15, 28).** Pause the chat list while
covered. Throttle or reschedule the backfill (charging/unmetered/idle).
Filter update types in the receiver isolate.
*Measure:* §5.4. Expect idle app CPU well under 10 % with only TDLib
networking left.

**Batch 5: smoothness polish (findings 10, 19, 20, 21, 22, 24, 25, 27, G2, G3, G7, G8).**
Shadow strategy for bubbles (only after measuring), scoped audio rebuilds,
the stream server isolate, a VLC view-mode check, nav-bar backdrop, painter
caching, pinned-banner layout, scroll anchoring for incoming messages,
`itemExtent: 76` on the chat list.
*Measure:* §5.3 during scroll and video playback.

**Batch 6: refresh rate (rank 6).** Only if §5.5 shows a 60 Hz lock: native
`preferredDisplayModeId` (highest refresh, same resolution) in
`MainActivity.onCreate`, or the `flutter_displaymode` package (not
effective on LTPO).
*Measure:* §5.5.
