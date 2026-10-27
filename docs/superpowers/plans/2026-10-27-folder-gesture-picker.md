# Folder Gesture Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hold the folder title in the chat list to open a full-screen gesture picker (edge list of folders, fisheye toward the finger, live preview), release to switch; default style, Classic selectable.

**Architecture:** Pure layout maths in `FolderPickerLayout`; preview data from `TelegramCache.chatsIn`; an `OverlayEntry` widget driven by the long-press pointer of `LensTitle` (start / move / end), so one continuous touch opens, steers and picks. A pref chooses gesture vs classic.

**Tech Stack:** Flutter, flutter_bloc, TDLib objects via `lumina_tdlib`.

**Spec:** `docs/superpowers/specs/2026-10-27-folder-gesture-picker-design.md`

## Global Constraints

- Build/test only via `tool/flutter.sh` (`tool/flutter.sh test --timeout 60s <path>`).
- Colors only from `GlowColors`; durations/curves from `Motion`; ambient motion gated by `Motion.ambientEnabled(context)`.
- No stock dialogs. Semantics labels on custom interactive widgets.
- `dart format` only touched files (page width 110); analyzer clean for touched files.
- Stage explicit paths only; never commit the owner's local edits. Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Widget tests: 1080x2400 @3x view; no `pumpAndSettle` while `GlowButton`s are on screen.
- Long-press ~250 ms; slots 56 dp; edge auto-scroll zone 64 dp; cancel when the finger is > 40% of the screen width away from the list.

## Review Focus

- Only one folder (or none): the gesture must not open — `chats_screen` passes no hold callbacks when `!many`; Task 5 test "without hold callbacks the title is tap-only".
- Finger leaves the screen via a system cancel (call, notification shade): no switch — Task 4 test (`cancel()`).
- Folder list taller than the screen (many folders): auto-scroll reaches the last folder and the slot maths stays right after scrolling — Task 2 test.
- Folder with no loaded chats: preview shows "No unread chats" and an empty list, not a crash — Task 3 test.
- Picker opened, then the chat list rebuilds (lens update) mid-gesture: the overlay lives in the root `Overlay` and the screen keeps it in `_gesture`, so it keeps working; Task 5 Step 3b adds a test that rebuilds the host mid-gesture.

---

### Task 1: Folder picker style preference and setting

**Files:**
- Modify: `lib/core/storage/app_preferences.dart` (new enum + getter/setter, near "Swipe gestures")
- Modify: `lib/features/folders/presentation/widgets/folder_settings.dart`
- Test: `test/features/folders/folder_picker_setting_test.dart`

**Interfaces:**
- Produces: `enum FolderPickerStyle { gesture, classic }` (in `app_preferences.dart`), `FolderPickerStyle AppPreferences.folderPicker` (default `gesture`), setter.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/features/folders/presentation/widgets/folder_settings.dart';

void main() {
  test('gesture is the default folder picker', () {
    expect(AppPreferences.inMemory().folderPicker, FolderPickerStyle.gesture);
  });

  testWidgets('the setting switches to classic', (tester) async {
    final prefs = AppPreferences.inMemory();
    await tester.pumpWidget(
      RepositoryProvider.value(
        value: prefs,
        child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: FolderSettings()))),
      ),
    );
    expect(find.text('Hold the title to swipe through folders'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('folder-picker-style')));
    await tester.pump();
    expect(prefs.folderPicker, FolderPickerStyle.classic);
    expect(find.text('Tap the title for a list'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `tool/flutter.sh test --timeout 60s test/features/folders/folder_picker_setting_test.dart`
Expected: compile error, `folderPicker` / `FolderPickerStyle` undefined.

- [ ] **Step 3: Implement**

In `app_preferences.dart`, above the class:

```dart
/// How the chat-list title switches folders.
enum FolderPickerStyle { gesture, classic }
```

Inside the class, after the swipe section:

```dart
  // ---- Folder picker --------------------------------------------------------

  /// Hold-and-swipe picker (default) or the classic drop-down list.
  FolderPickerStyle get folderPicker => _enum(FolderPickerStyle.values, 'chats.folderPicker') ?? FolderPickerStyle.gesture;
  set folderPicker(FolderPickerStyle v) => _set('chats.folderPicker', v.name);
```

In `folder_settings.dart`: make `build` read `AppPreferences` and wrap in `ListenableBuilder(listenable: prefs.changes, ...)`; add after the "Chat folders" tile:

```dart
          SwitchListTile(
            key: const ValueKey('folder-picker-style'),
            secondary: const Icon(Icons.swipe_vertical_rounded, color: GlowColors.violet),
            activeThumbColor: GlowColors.cyan,
            title: const Text('Swipe folder picker'),
            subtitle: Text(
              prefs.folderPicker == FolderPickerStyle.gesture
                  ? 'Hold the title to swipe through folders'
                  : 'Tap the title for a list',
            ),
            value: prefs.folderPicker == FolderPickerStyle.gesture,
            onChanged: (on) => prefs.folderPicker = on ? FolderPickerStyle.gesture : FolderPickerStyle.classic,
          ),
```

(imports: `flutter_bloc`, `core/storage/app_preferences.dart`.)

- [ ] **Step 4: Run the test, expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add lib/core/storage/app_preferences.dart lib/features/folders/presentation/widgets/folder_settings.dart test/features/folders/folder_picker_setting_test.dart
git commit -m "Folders: setting for the folder picker style (swipe by default)"
```

---

### Task 2: FolderPickerLayout (pure maths)

**Files:**
- Create: `lib/features/chats/presentation/widgets/folder_picker_layout.dart`
- Test: `test/features/chats/folder_picker_layout_test.dart`

**Interfaces:**
- Produces:
  - `class FolderPickerLayout { FolderPickerLayout({required Size screen, required EdgeInsets padding, required int count, required bool rightEdge, double scroll = 0}); static const slot = 56.0, edgeZone = 64.0, cancelFraction = 0.4, maxScrollSpeed = 900.0; static bool rightEdgeFor(double pressX, double width); double get listX; double get top; double get maxScroll; double centerOf(int i); int indexAt(double y); bool isCancel(Offset finger); double focus(int i, Offset finger); double scrollVelocity(double y); FolderPickerLayout withScroll(double scroll); }`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/chats/presentation/widgets/folder_picker_layout.dart';

void main() {
  const screen = Size(400, 800);
  FolderPickerLayout layout(int n, {double scroll = 0}) =>
      FolderPickerLayout(screen: screen, padding: EdgeInsets.zero, count: n, rightEdge: true, scroll: scroll);

  test('the list goes on the thumb side', () {
    expect(FolderPickerLayout.rightEdgeFor(300, 400), isTrue);
    expect(FolderPickerLayout.rightEdgeFor(100, 400), isFalse);
  });

  test('a short list is centred and the slot under the finger is picked', () {
    final l = layout(4); // 224 tall, top = (800 - 224) / 2 = 288
    expect(l.top, 288);
    expect(l.indexAt(290), 0);
    expect(l.indexAt(288 + 56 * 2 + 1), 2);
    expect(l.indexAt(0), 0, reason: 'clamped');
    expect(l.indexAt(800), 3, reason: 'clamped');
    expect(l.maxScroll, 0);
  });

  test('pulling far from the list cancels', () {
    final l = layout(4);
    expect(l.isCancel(Offset(l.listX - 100, 300)), isFalse);
    expect(l.isCancel(Offset(l.listX - 0.41 * 400, 300)), isTrue);
  });

  test('focus is strongest at the finger and falls off with distance', () {
    final l = layout(6);
    final finger = Offset(l.listX, l.centerOf(2));
    expect(l.focus(2, finger), closeTo(1, 0.01));
    expect(l.focus(3, finger), lessThan(l.focus(2, finger)));
    expect(l.focus(5, finger), lessThan(l.focus(3, finger)));
    final farSideways = Offset(l.listX - 0.3 * 400, l.centerOf(2));
    expect(l.focus(2, farSideways), lessThan(l.focus(2, finger)));
  });

  test('a long list scrolls near the edges and the slot maths follows', () {
    final l = layout(20); // 1120 tall on an 800 screen
    expect(l.maxScroll, 320);
    expect(l.top, 0);
    expect(l.scrollVelocity(400), 0);
    expect(l.scrollVelocity(799), greaterThan(0));
    expect(l.scrollVelocity(1), lessThan(0));
    expect(l.scrollVelocity(799), lessThanOrEqualTo(FolderPickerLayout.maxScrollSpeed));
    final end = l.withScroll(9999);
    expect(end.top, -320, reason: 'scroll clamps to maxScroll');
    expect(end.indexAt(799), 19);
    expect(l.withScroll(-50).top, 0);
  });
}
```

- [ ] **Step 2: Run, expect FAIL (file missing).**

Run: `tool/flutter.sh test --timeout 60s test/features/chats/folder_picker_layout_test.dart`

- [ ] **Step 3: Implement**

```dart
import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Geometry of the folder gesture picker: a column of [count] slots on one
/// screen edge, the slot under the finger, how strongly each name reacts to
/// the finger (fisheye), the cancel zone and edge auto-scroll.
class FolderPickerLayout {
  FolderPickerLayout({
    required this.screen,
    required this.padding,
    required this.count,
    required this.rightEdge,
    double scroll = 0,
  }) : scroll = scroll.clamp(0, _maxScroll(screen, padding, count));

  static const slot = 56.0;
  static const edgeZone = 64.0;
  static const cancelFraction = 0.4;
  static const maxScrollSpeed = 900.0;
  static const _inset = 28.0;

  final Size screen;
  final EdgeInsets padding;
  final int count;
  final bool rightEdge;
  final double scroll;

  static bool rightEdgeFor(double pressX, double width) => pressX > width / 2;

  static double _visible(Size s, EdgeInsets p) => s.height - p.vertical;
  static double _maxScroll(Size s, EdgeInsets p, int n) => math.max(0, n * slot - _visible(s, p));

  double get maxScroll => _maxScroll(screen, padding, count);

  /// The x the names line up on.
  double get listX => rightEdge ? screen.width - _inset : _inset;

  double get top {
    final visible = _visible(screen, padding);
    final height = count * slot;
    return padding.top + (height < visible ? (visible - height) / 2 : 0) - scroll;
  }

  double centerOf(int i) => top + slot * i + slot / 2;

  int indexAt(double y) => ((y - top) / slot).floor().clamp(0, math.max(0, count - 1));

  bool isCancel(Offset finger) => (finger.dx - listX).abs() > cancelFraction * screen.width;

  /// 0…1: how much slot [i] lights up, lean and scale, for [finger].
  double focus(int i, Offset finger) {
    final dy = (centerOf(i) - finger.dy) / (slot * 1.5);
    final vertical = math.exp(-dy * dy);
    final sideways = 1 - ((finger.dx - listX).abs() / (cancelFraction * screen.width)).clamp(0.0, 1.0);
    return vertical * (0.35 + 0.65 * sideways);
  }

  /// Pixels per second to scroll (negative = up) while the finger rests
  /// near the top or bottom of a list taller than the screen.
  double scrollVelocity(double y) {
    if (maxScroll == 0) return 0;
    final fromTop = y - padding.top;
    final fromBottom = screen.height - padding.bottom - y;
    if (fromBottom < edgeZone) return maxScrollSpeed * (1 - fromBottom.clamp(0, edgeZone) / edgeZone);
    if (fromTop < edgeZone) return -maxScrollSpeed * (1 - fromTop.clamp(0, edgeZone) / edgeZone);
    return 0;
  }

  FolderPickerLayout withScroll(double scroll) =>
      FolderPickerLayout(screen: screen, padding: padding, count: count, rightEdge: rightEdge, scroll: scroll);
}
```

Note: `focus(2, finger at listX)` must be ≈1: vertical = 1, sideways = 1 → 0.35 + 0.65 = 1.

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add lib/features/chats/presentation/widgets/folder_picker_layout.dart test/features/chats/folder_picker_layout_test.dart
git commit -m "Chats: geometry for the folder gesture picker"
```

---

### Task 3: Folder preview data

**Files:**
- Create: `lib/features/chats/presentation/widgets/folder_preview.dart`
- Test: `test/features/chats/folder_preview_test.dart`

**Interfaces:**
- Consumes: `TelegramCache.chatsIn(td.ChatList)`, `td.Chat.unreadCount`.
- Produces: `class FolderPreview { final int unreadMessages; final int unreadChats; final List<td.Chat> chats; static FolderPreview of(TelegramCache cache, td.ChatList list, {int limit = 6}); String get headline; }` — `chats` = unread chats first (TDLib order kept within each group), at most `limit`. `headline`: `"$unreadMessages unread in $unreadChats chats"` (singular "chat" when 1), or `"No unread chats"`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/chats/presentation/widgets/folder_preview.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';

void main() {
  test('unread chats come first, then the rest, capped', () {
    final cache = TelegramCache.detached();
    for (var i = 1; i <= 8; i++) {
      cache.apply(td.UpdateNewChat(chat: fakeChat(i, order: 100 - i, unread: i.isEven ? i : 0)));
    }
    final p = FolderPreview.of(cache, const td.ChatListMain());
    expect(p.chats.map((c) => c.id), [2, 4, 6, 8, 1, 3]);
    expect(p.unreadChats, 4);
    expect(p.unreadMessages, 2 + 4 + 6 + 8);
    expect(p.headline, '20 unread in 4 chats');
  });

  test('an empty or fully read folder says so', () {
    final cache = TelegramCache.detached()..apply(td.UpdateNewChat(chat: fakeChat(1, order: 5)));
    expect(FolderPreview.of(cache, const td.ChatListMain()).headline, 'No unread chats');
    expect(FolderPreview.of(cache, const td.ChatListArchive()).chats, isEmpty);
  });

  test('one unread chat is singular', () {
    final cache = TelegramCache.detached()..apply(td.UpdateNewChat(chat: fakeChat(1, order: 5, unread: 3)));
    expect(FolderPreview.of(cache, const td.ChatListMain()).headline, '3 unread in 1 chat');
  });
}
```

Before Step 2, check `fakeChat` in `test/helpers/fakes.dart`: it must put the chat in `ChatListMain` at `order` (it takes `order` and `unread`). If `order: 0` hides a chat, keep orders > 0 as above.

- [ ] **Step 2: Run, expect FAIL.**

Run: `tool/flutter.sh test --timeout 60s test/features/chats/folder_preview_test.dart`

- [ ] **Step 3: Implement**

```dart
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/telegram/telegram_cache.dart';

/// What the folder gesture picker shows for a highlighted folder.
class FolderPreview {
  const FolderPreview({required this.unreadMessages, required this.unreadChats, required this.chats});

  final int unreadMessages;
  final int unreadChats;
  final List<td.Chat> chats;

  static FolderPreview of(TelegramCache cache, td.ChatList list, {int limit = 6}) {
    final all = cache.chatsIn(list);
    final unread = all.where((c) => c.unreadCount > 0).toList();
    final read = all.where((c) => c.unreadCount == 0);
    return FolderPreview(
      unreadMessages: unread.fold(0, (s, c) => s + c.unreadCount),
      unreadChats: unread.length,
      chats: [...unread, ...read].take(limit).toList(),
    );
  }

  String get headline => unreadChats == 0
      ? 'No unread chats'
      : '$unreadMessages unread in $unreadChats ${unreadChats == 1 ? 'chat' : 'chats'}';
}
```

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add lib/features/chats/presentation/widgets/folder_preview.dart test/features/chats/folder_preview_test.dart
git commit -m "Chats: folder preview (unread first) for the gesture picker"
```

---

### Task 4: The gesture picker overlay

**Files:**
- Create: `lib/features/chats/presentation/widgets/folder_gesture_picker.dart`
- Test: `test/features/chats/folder_gesture_picker_test.dart`

**Interfaces:**
- Consumes: `FolderPickerLayout` (Task 2), `FolderPreview` (Task 3), `LensEntry`, `TelegramCache`, `ChatAvatar`, `Display.preview`.
- Produces:
  - `class FolderGesturePicker { static FolderGesturePicker open(BuildContext context, {required List<LensEntry> entries, required int current, required Color Function(LensEntry) colorOf, required Offset start, required ValueChanged<int> onPicked}); void move(Offset globalPosition); void end(); void cancel(); bool get isOpen; }`
  - `end()` calls `onPicked(index)` only when not in the cancel zone and the index differs from `current`; both `end()` and `cancel()` remove the overlay.

**Widget structure** (inside an `OverlayEntry`):
- `_PickerView` (StatefulWidget) owns a `ValueNotifier<Offset> finger`, the `FolderPickerLayout`, a `Ticker` for auto-scroll, and `int? highlighted`.
- Backdrop: `BackdropFilter(ImageFilter.blur(sigmaX: 14, sigmaY: 14))` over a `DecoratedBox` with a `RadialGradient` from `GlowColors.background.withValues(alpha: 0.35)` at the centre to `GlowColors.backgroundDeep.withValues(alpha: 0.92)` at the edges. Built once (it does not listen to `finger`), wrapped in `RepaintBoundary`.
- Names: `ValueListenableBuilder<Offset>(finger)` → `Stack` of `Positioned` names. For slot `i`: `f = layout.focus(i, finger)` (0 when cancelled); `Transform.translate(Offset(lean, 0))` where `lean = f * 22 * (rightEdge ? -1 : 1)`; `Transform.scale(scale: 1 + 0.35 * f, alignment: rightEdge ? Alignment.centerRight : Alignment.centerLeft)`; text colour `Color.lerp(GlowColors.textMuted, GlowColors.text, f)`; highlighted slot gets `glow(colorOf(entry), intensity: 0.8)` shadows on a pill and its unread badge. Text aligned to the edge. With `!Motion.ambientEnabled(context)`, use `f = i == highlighted ? 1 : 0` (no falloff).
- Preview: glass card (`GlowColors.surface.withValues(alpha: 0.85)`, radius 22, border `outline`) on the opposite side, width 58% of the screen, vertically centred on the highlighted slot (clamped to the screen). `AnimatedSwitcher(duration: Motion.standard)` keyed by the highlighted index: headline (`FolderPreview.headline`, colour of the lens), then up to 6 rows `ChatAvatar(id: c.id, title: c.title, photo: c.photo?.small, size: 36)`, title, `Display.preview(cache, c.lastMessage)` one line, unread badge. Cache previews per index in a `Map<int, FolderPreview>` (computed on first highlight).
- Cancel zone: everything at 40% opacity, preview hidden, a centred "Release to cancel" label.
- Haptics: `HapticFeedback.selectionClick()` on highlight change; `HapticFeedback.mediumImpact()` when `end()` switches.
- Semantics: the overlay root `Semantics(label: 'Folder picker. Slide to a folder and release', liveRegion: true)`.
- Auto-scroll: on each tick, `v = layout.scrollVelocity(finger.dy)`; if `v != 0`, `layout = layout.withScroll(layout.scroll + v * dt)` and recompute the highlight.

- [ ] **Step 1: Write the failing widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/core/theme/glow_colors.dart';
import 'package:lumina/features/chats/domain/lens_entry.dart';
import 'package:lumina/features/chats/presentation/widgets/folder_gesture_picker.dart';
import 'package:lumina/features/chats/presentation/widgets/folder_picker_layout.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';

void main() {
  const entries = [
    LensEntry(list: td.ChatListMain(), title: 'All chats'),
    LensEntry(list: td.ChatListFolder(chatFolderId: 1), title: 'Work'),
    LensEntry(list: td.ChatListFolder(chatFolderId: 2), title: 'Family'),
    LensEntry(list: td.ChatListArchive(), title: 'Archive'),
  ];
  late BuildContext ctx;
  int? picked;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    picked = null;
    final cache = TelegramCache.detached()
      ..apply(td.UpdateNewChat(chat: fakeChat(5, title: 'Ada', order: 9, unread: 2)))
      ..apply(td.UpdateNewChat(chat: fakeChat(6, title: 'Bob', order: 8)));
    await tester.pumpWidget(
      RepositoryProvider.value(
        value: cache,
        child: MaterialApp(home: Builder(builder: (c) => ctx = c)),
      ),
    );
  }

  FolderGesturePicker open(Offset start) => FolderGesturePicker.open(
    ctx,
    entries: entries,
    current: 0,
    colorOf: (_) => GlowColors.violet,
    start: start,
    onPicked: (i) => picked = i,
  );

  // Screen is 360x800 logical; press on the right half → list on the right.
  FolderPickerLayout layoutFor(WidgetTester tester) => FolderPickerLayout(
    screen: const Size(360, 800),
    padding: MediaQuery.of(ctx).padding,
    count: entries.length,
    rightEdge: true,
  );

  testWidgets('sliding to a folder and releasing switches to it', (tester) async {
    await pump(tester);
    final picker = open(const Offset(300, 100));
    await tester.pump();
    expect(find.text('Family'), findsOneWidget);
    final l = layoutFor(tester);
    picker.move(Offset(l.listX, l.centerOf(2)));
    await tester.pump(const Duration(milliseconds: 300));
    picker.end();
    await tester.pump(const Duration(milliseconds: 300));
    expect(picked, 2);
    expect(picker.isOpen, isFalse);
    expect(find.text('Family'), findsNothing);
  });

  testWidgets('the preview shows unread first for the highlighted folder', (tester) async {
    await pump(tester);
    final picker = open(const Offset(300, 100));
    final l = layoutFor(tester);
    picker.move(Offset(l.listX, l.centerOf(0)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('2 unread in 1 chat'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Ada')).dy, lessThan(tester.getTopLeft(find.text('Bob')).dy));
    picker.cancel();
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('releasing far from the list cancels', (tester) async {
    await pump(tester);
    final picker = open(const Offset(300, 100));
    final l = layoutFor(tester);
    picker.move(Offset(l.listX - 0.45 * 360, l.centerOf(2)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Release to cancel'), findsOneWidget);
    picker.end();
    await tester.pump(const Duration(milliseconds: 300));
    expect(picked, isNull);
  });

  testWidgets('a system cancel switches nothing', (tester) async {
    await pump(tester);
    final picker = open(const Offset(300, 100));
    final l = layoutFor(tester);
    picker.move(Offset(l.listX, l.centerOf(3)));
    await tester.pump(const Duration(milliseconds: 300));
    picker.cancel();
    await tester.pump(const Duration(milliseconds: 300));
    expect(picked, isNull);
    expect(picker.isOpen, isFalse);
  });

  testWidgets('releasing on the current folder does not switch', (tester) async {
    await pump(tester);
    final picker = open(const Offset(300, 100));
    final l = layoutFor(tester);
    picker.move(Offset(l.listX, l.centerOf(0)));
    await tester.pump(const Duration(milliseconds: 300));
    picker.end();
    await tester.pump(const Duration(milliseconds: 300));
    expect(picked, isNull);
  });
}
```

Before running: check `fakeChat` accepts `title:` (it does: `fakeChat(int id, {String title = 'Chat', int order = 0, int unread = 0, ...})`).

- [ ] **Step 2: Run, expect FAIL (file missing).**

Run: `tool/flutter.sh test --timeout 60s test/features/chats/folder_gesture_picker_test.dart`

- [ ] **Step 3: Implement `folder_gesture_picker.dart`** following the widget structure above. Skeleton:

```dart
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/telegram/display.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/chat_avatar.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/theme/motion.dart';
import '../../domain/lens_entry.dart';
import 'folder_picker_layout.dart';
import 'folder_preview.dart';

/// Hold-and-swipe folder switcher: an overlay driven by the long-press
/// pointer that opened it ([move], [end], [cancel]).
class FolderGesturePicker {
  FolderGesturePicker._(this._entry, this._view);

  final OverlayEntry _entry;
  final GlobalKey<_PickerViewState> _view;
  var _open = true;

  bool get isOpen => _open;

  static FolderGesturePicker open(
    BuildContext context, {
    required List<LensEntry> entries,
    required int current,
    required Color Function(LensEntry) colorOf,
    required Offset start,
    required ValueChanged<int> onPicked,
  }) {
    final key = GlobalKey<_PickerViewState>();
    final cache = context.read<TelegramCache>();
    late final FolderGesturePicker picker;
    final entry = OverlayEntry(
      builder: (_) => _PickerView(
        key: key,
        entries: entries,
        current: current,
        colorOf: colorOf,
        start: start,
        cache: cache,
        onDone: (index) {
          picker._close();
          if (index != null && index != current) onPicked(index);
        },
      ),
    );
    picker = FolderGesturePicker._(entry, key);
    Overlay.of(context, rootOverlay: true).insert(entry);
    HapticFeedback.lightImpact();
    return picker;
  }

  void move(Offset globalPosition) => _view.currentState?.move(globalPosition);

  void end() => _view.currentState?.finish(cancelled: false) ?? _close();

  void cancel() => _view.currentState?.finish(cancelled: true) ?? _close();

  void _close() {
    if (!_open) return;
    _open = false;
    _entry.remove();
  }
}
```

`_PickerViewState`:
- `late FolderPickerLayout _layout` built in `didChangeDependencies` from `MediaQuery.sizeOf(context)`, `MediaQuery.paddingOf(context)`, `entries.length`, `FolderPickerLayout.rightEdgeFor(start.dx, width)`.
- `final _finger = ValueNotifier<Offset>(start)`; `int? _highlight` (initial `current`); `bool get _cancelled => _layout.isCancel(_finger.value)`.
- `late final Ticker _ticker = createTicker(_tick)..start()` (use `SingleTickerProviderStateMixin`); `_tick(elapsed)` applies `scrollVelocity` with `dt` from the previous elapsed and calls `_rehighlight()`.
- `move(p)`: `_finger.value = p; _rehighlight();`
- `_rehighlight()`: `final i = _cancelled ? null : _layout.indexAt(_finger.value.dy); if (i != _highlight) { _highlight = i; HapticFeedback.selectionClick(); setState(() {}); }` (setState only on highlight change — the names repaint via the notifier).
- `finish({required bool cancelled})`: `_ticker.stop(); final pick = cancelled || _cancelled ? null : _highlight; if (pick != null && pick != widget.current) HapticFeedback.mediumImpact(); widget.onDone(pick);`
- `build`: `Stack(children: [backdrop, names (ValueListenableBuilder), preview (AnimatedSwitcher keyed by _highlight), if cancelled: centred 'Release to cancel'])` per the structure above. Wrap in `Material(type: MaterialType.transparency)`.
- `dispose`: `_ticker.dispose(); _finger.dispose();`.

- [ ] **Step 4: Run, expect PASS.** If a test finds two 'Family' texts, the preview headline must not repeat folder titles (it doesn't: headline is the unread line).

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format lib/features/chats/presentation/widgets/folder_gesture_picker.dart test/features/chats/folder_gesture_picker_test.dart
tool/flutter.sh analyze lib/features/chats test/features/chats
git add lib/features/chats/presentation/widgets/folder_gesture_picker.dart test/features/chats/folder_gesture_picker_test.dart
git commit -m "Chats: hold-and-swipe folder picker overlay"
```

---

### Task 5: Wire it into the chat list title

**Files:**
- Modify: `lib/features/chats/presentation/widgets/lens_title.dart` (add long-press callbacks)
- Modify: `lib/features/chats/presentation/screens/chats_screen.dart:71-75,139-143`
- Modify: `docs/REMAINING.md` (Done list)
- Test: `test/features/chats/lens_title_gesture_test.dart`

**Interfaces:**
- Consumes: `FolderGesturePicker.open/move/end/cancel` (Task 4), `AppPreferences.folderPicker` (Task 1).
- Produces: `LensTitle({..., VoidCallback? onTap, GestureLongPressStartCallback? onHoldStart, GestureLongPressMoveUpdateCallback? onHoldMove, GestureLongPressEndCallback? onHoldEnd, VoidCallback? onHoldCancel})`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/chats/domain/lens_entry.dart';
import 'package:lumina/features/chats/presentation/widgets/lens_title.dart';
import 'package:lumina_tdlib/api.dart' as td;

void main() {
  const entry = LensEntry(list: td.ChatListMain(), title: 'All chats');

  testWidgets('holding the title streams the gesture; a tap still taps', (tester) async {
    final events = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LensTitle(
            entry: entry,
            color: Colors.purple,
            onTap: () => events.add('tap'),
            onHoldStart: (_) => events.add('start'),
            onHoldMove: (_) => events.add('move'),
            onHoldEnd: (_) => events.add('end'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('All chats'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(events, ['tap']);

    final g = await tester.startGesture(tester.getCenter(find.text('All chats')));
    await tester.pump(const Duration(milliseconds: 300));
    await g.moveBy(const Offset(0, 120));
    await tester.pump();
    await g.up();
    await tester.pump();
    expect(events, ['tap', 'start', 'move', 'end']);
  });

  testWidgets('without hold callbacks the title is tap-only', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: LensTitle(entry: entry, color: Colors.purple, onTap: () => taps++))),
    );
    final g = await tester.startGesture(tester.getCenter(find.text('All chats')));
    await tester.pump(const Duration(milliseconds: 600));
    await g.up();
    expect(taps, 0, reason: 'a long press is not a tap');
  });
}
```

Note: the long-press delay is set to 250 ms via `RawGestureDetector` with `LongPressGestureRecognizer(duration: const Duration(milliseconds: 250))` — the 300 ms pump above passes it.

- [ ] **Step 2: Run, expect FAIL** (`onHoldStart` undefined).

Run: `tool/flutter.sh test --timeout 60s test/features/chats/lens_title_gesture_test.dart`

- [ ] **Step 3: Implement**

`LensTitle`: add the four optional fields. In the tappable branch, wrap the `InkWell` in a `RawGestureDetector` only when `onHoldStart != null`:

```dart
    Widget tappable = InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4), child: title),
    );
    if (onHoldStart != null) {
      tappable = RawGestureDetector(
        gestures: {
          LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => LongPressGestureRecognizer(duration: const Duration(milliseconds: 250)),
            (r) => r
              ..onLongPressStart = onHoldStart
              ..onLongPressMoveUpdate = onHoldMove
              ..onLongPressEnd = onHoldEnd
              ..onLongPressCancel = onHoldCancel,
          ),
        },
        child: tappable,
      );
    }
```

Update the semantics label: `'Chat folder: ${entry.title}. Double tap to switch, or hold and slide'` when hold is on.

`chats_screen.dart`: add `FolderGesturePicker? _gesture;` to the state; in the `LensTitle(...)` call:

```dart
                            : LensTitle(
                                entry: current,
                                color: ext.lensColor(current),
                                onTap: many ? () => _pickLens(lens) : null,
                                onHoldStart: many && context.read<AppPreferences>().folderPicker == FolderPickerStyle.gesture
                                    ? (d) => _gesture = FolderGesturePicker.open(
                                        context,
                                        entries: lens.entries,
                                        current: lens.index,
                                        colorOf: ext.lensColor,
                                        start: d.globalPosition,
                                        onPicked: (i) {
                                          ext.onLensOpened();
                                          context.read<LensCubit>().select(i);
                                        },
                                      )
                                    : null,
                                onHoldMove: (d) => _gesture?.move(d.globalPosition),
                                onHoldEnd: (_) => _gesture?.end(),
                                onHoldCancel: () => _gesture?.cancel(),
                              ),
```

Also in `dispose()` of the screen state: `_gesture?.cancel();`. Import `folder_gesture_picker.dart` and `core/storage/app_preferences.dart` if missing. Wrap the header in `ListenableBuilder(listenable: prefs.changes)` only if the style should apply without a restart — it should: read the pref inside `build`; the settings screen is a separate route, so returning to the chat list rebuilds it. If it doesn't, add the listener.

- [ ] **Step 3b: Rebuild-mid-gesture test** — append to `test/features/chats/folder_gesture_picker_test.dart`:

```dart
  testWidgets('a rebuild of the host mid-gesture keeps the picker working', (tester) async {
    await pump(tester);
    final picker = open(const Offset(300, 100));
    final l = layoutFor(tester);
    picker.move(Offset(l.listX, l.centerOf(1)));
    await tester.pump(const Duration(milliseconds: 100));
    // Same tree, new widget instance: forces a rebuild of the host.
    await tester.pumpWidget(
      RepositoryProvider.value(
        value: TelegramCache.detached(),
        child: MaterialApp(home: Builder(builder: (c) => ctx = c)),
      ),
    );
    picker.end();
    await tester.pump(const Duration(milliseconds: 300));
    expect(picked, 1);
  });
```

Run it; expected PASS (the overlay entry is independent of the host's rebuild).

- [ ] **Step 4: Run the new test and the existing chats tests**

Run: `tool/flutter.sh test --timeout 60s test/features/chats`
Expected: all PASS.

- [ ] **Step 5: Full suite, analyze, docs, commit**

```bash
tool/flutter.sh test --timeout 60s
dart format lib/features/chats/presentation/widgets/lens_title.dart lib/features/chats/presentation/screens/chats_screen.dart test/features/chats/lens_title_gesture_test.dart
tool/flutter.sh analyze lib test
```

Add to `docs/REMAINING.md` "Done recently, not yet confirmed on the phone": "folder gesture picker (hold the title, slide, release; Settings → Chats → Swipe folder picker)".

```bash
git add lib/features/chats/presentation/widgets/lens_title.dart lib/features/chats/presentation/screens/chats_screen.dart test/features/chats/lens_title_gesture_test.dart docs/REMAINING.md
git commit -m "Chats: hold the folder title to swipe between folders"
```
