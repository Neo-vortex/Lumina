# Chat Folders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Full Telegram chat-folder support (lens switcher, Archive, create/edit/delete/reorder, suggested folders, "Add to folder", Premium tags, shareable `t.me/addlist` invites) in Lumina's own style.

**Architecture:** The cache in `core/telegram` mirrors folder and unread-count updates. The `chats` feature shows a swipeable "lens" of chat lists and gets every folder-specific action through the `ChatListExtensions` hook. A new `features/folders` slice owns the TDLib calls, editor, invite links and join sheet. `lib/app` wires the two together and registers internal link handlers (`addlist`, proxy links) that `openLink` and Android `VIEW` intents go through.

**Tech Stack:** Flutter 3.50 / Dart 3, `flutter_bloc` 9, `lumina_tdlib` (TDLib 1.8.69, `import 'package:lumina_tdlib/api.dart' as td;`), `flutter_zxing` 3.1 (QR writer), Kotlin `MainActivity`.

**Spec:** `docs/superpowers/specs/2026-10-26-chat-folders-design.md`

## Global Constraints

- Work in `/home/neo/projects/personal/Lumina-tdlib` on branch `tdlib-own-bindings`. Never edit `/home/neo/projects/personal/Lumina` (main).
- **Stage explicit paths only.** The worktree holds the owner's uncommitted edits (`android/build.gradle.kts`, `android/gradle/wrapper/gradle-wrapper.properties`, `android/settings.gradle.kts`, `lib/core/media/ffmpeg_service.dart`, `lib/features/transcription/data/whisper_service.dart`, `pubspec.lock`) and this session's earlier uncommitted work (channel bar, proxy button/scanner, video progress). Never `git add -A`/`git add .`; never stage those owner files. Earlier-session files may be staged only by the task that modifies them, and then whole.
- Dependencies point `app → features → core`. `features/chats` must not import `features/folders` or vice versa; they meet only in `lib/app`.
- Layer rules (docs/ARCHITECTURE.md): `bloc/` must not import Flutter widgets (`package:flutter/foundation.dart` is fine); `presentation/` must not call `TdClient` directly.
- Format with the repo setting (`formatter: page_width: 110` in analysis_options.yaml): run `dart format <files>` on touched files only, never on whole directories.
- Commit messages end with a blank line and `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Colours only from `GlowColors` (`lib/core/theme/glow_colors.dart`); folder palette = cyan, teal, violet, magenta, amber, coral, plus "none". Archive glow = `Color(0xFF7C86C9)`.
- Folder name max 12 characters (Telegram's limit). Chat folder colours are synced only for Premium; non-Premium choices are stored locally.
- Bots: no lens, no folder UI, title "Chats".
- Reduced motion (`Motion.ambientEnabled(context) == false`): fades only.
- **No `AlertDialog` / `showDialog`** (owner: "this app is supposed to offer the best UX"). Confirmations use `showGlowConfirm`, choices and small inputs use `showGlowSheet` (Task 1b), anything larger is a full screen.
- Verification commands (run from the worktree): `flutter analyze` must show no issues other than the existing `deprecated_member_use` infos; `flutter test` must pass.

## Review Focus

1. **Folder deleted while it is the current lens** (deleted on another device): the lens must fall back to All chats, not crash or show an empty page forever. Pinned by Task 5 test `falls back to All chats when the current folder disappears`.
2. **All chats moved** (`mainChatListPosition` > 0, Premium): lens order must place All chats at that index and reorder must send the right position back. Pinned by Task 5 test `places All chats at main_chat_list_position` and Task 9 test `reorder keeps All chats where it was dropped`.
3. **Non-Premium colour choice:** saving must not send `colorId` (TDLib rejects it) and the colour must still show from local storage. Pinned by Task 4 test `non-Premium colour is stored locally and not sent`.
4. **Links with trailing punctuation or in surrounding text** (`…join t.me/addlist/AbC.`): slug must not include the dot. Pinned by Task 3 test `finds addlist links in text and trims punctuation`.
5. **Unticking a chat that a folder includes by type rule** (Add to folder sheet): it must end up in `excludedChatIds` so it actually leaves. Pinned by Task 4 test `removing a chat that a rule includes excludes it`.

## File Map

Create:
- `lib/core/telegram/internal_links.dart`: registry of in-app link handlers.
- `lib/features/chats/domain/lens_entry.dart`: one lens (All chats, a folder, Archive).
- `lib/features/chats/bloc/lens_cubit.dart`: builds the ordered lens from the cache.
- `lib/features/chats/presentation/widgets/lens_title.dart`: header title button.
- `lib/features/chats/presentation/widgets/lens_picker.dart`: drop-down lens panel.
- `lib/features/chats/presentation/widgets/chat_list_page.dart`: one page of the pager (list, refresh, empty state).
- `lib/features/folders/domain/folder_draft.dart`: editable folder form state.
- `lib/features/folders/domain/addlist_link.dart`: addlist link parsing.
- `lib/features/folders/domain/folder_errors.dart`: TDLib error → text.
- `lib/features/folders/data/folders_repository.dart`: all folder TDLib calls, local colours, new-chats checks.
- `lib/features/folders/bloc/folder_manager_cubit.dart`, `folder_editor_cubit.dart`, `folder_links_cubit.dart`, `join_folder_cubit.dart`.
- `lib/features/folders/presentation/folder_palette.dart`: colour ids ↔ glow colours, icons.
- `lib/features/folders/presentation/screens/folder_manager_screen.dart`, `folder_editor_screen.dart`, `chat_picker_screen.dart`, `folder_qr_screen.dart`.
- `lib/features/folders/presentation/widgets/add_to_folder_sheet.dart`, `folder_share_sheet.dart`, `join_folder_sheet.dart`, `folder_settings.dart`.
- `lib/features/proxy/presentation/widgets/proxy_link_dialog.dart`: confirm adding a proxy opened from a link.
- `lib/app/app_chat_list_extensions.dart`: folders + proxy wired into the chat list.
- Tests under `test/core/telegram/`, `test/features/chats/`, `test/features/folders/`.

Modify:
- `lib/core/telegram/telegram_cache.dart`: folders, unread counts, events.
- `lib/core/telegram/link_opener.dart`: ask `InternalLinks` first.
- `lib/core/storage/app_preferences.dart`: `folderColorsJson`.
- `lib/features/chats/presentation/widgets/chat_list_extensions.dart`: new hooks.
- `lib/features/chats/presentation/screens/chats_screen.dart`: lens header + pager.
- `lib/features/chats/presentation/widgets/timeline_chat_row.dart`: `tint`, folder tags.
- `lib/features/chats/presentation/widgets/chat_actions_sheet.dart`: list-aware pin, hook actions.
- `lib/features/home/presentation/screens/home_shell.dart`: provide `LensCubit` instead of one `ChatListCubit`.
- `lib/features/proxy/presentation/screens/proxy_scan_screen.dart`: also accept addlist links.
- `lib/features/notifications/data/notification_center.dart`: `link` events.
- `android/app/src/main/kotlin/dev/lumina/lumina/MainActivity.kt`, `android/app/src/main/kotlin/dev/lumina/background/MessageNotifications.kt`, `android/app/src/main/AndroidManifest.xml`: `VIEW` intents for `tg://` and t.me links.
- `lib/app/feature_wiring.dart`: providers, settings entry, link handlers.
- `docs/AGENT_HANDOFF.md`: status row.

---

### Task 0: Commit the earlier uncommitted work

The worktree holds work from earlier in this session (ported from main, analyzer clean, 206 tests passing) that later tasks build on. Commit it first, in three commits, so folder commits stay readable.

**Files:** only the paths listed below. Never the owner's files from Global Constraints (except the single `flutter_zxing` hunk of `pubspec.lock`).

- [ ] **Step 1: Verify the baseline**

Run: `flutter analyze` then `flutter test`
Expected: no issues besides `deprecated_member_use` infos; all tests pass.

- [ ] **Step 2: Channels bar and mute state**

```bash
git add lib/features/conversation/presentation/screens/conversation_screen.dart lib/features/conversation/bloc/conversation_cubit.dart lib/features/chat_info/presentation/screens/chat_info_screen.dart lib/features/chats/presentation/widgets/chat_actions_sheet.dart lib/core/telegram/telegram_cache.dart test/core/telegram/telegram_cache_test.dart
git commit -m "Channels: Subscribe / Mute bar; mute state follows chat-type defaults

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 3: Proxy**

```bash
git add pubspec.yaml lib/features/proxy lib/features/chats/presentation/widgets/chat_list_extensions.dart lib/core/storage/app_preferences.dart lib/features/chats/bloc/chat_list_cubit.dart lib/features/chats/presentation/screens/chats_screen.dart lib/features/chats/presentation/widgets/timeline_chat_row.dart lib/features/home/presentation/screens/home_shell.dart lib/app/feature_wiring.dart test/features/proxy test/features/proxy_config_test.dart test/features/chats/chat_list_cubit_test.dart
git add -p pubspec.lock   # stage only the hunks adding flutter_zxing (and its own new transitive packages); answer "n" to everything else
git commit -m "Proxy: header button, QR scanner, multi-link paste, hide and tag the sponsor channel

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

If `git diff --cached pubspec.yaml` shows more than the `flutter_zxing` line, unstage it and use `git add -p pubspec.yaml`.

- [ ] **Step 4: Video progress**

```bash
git add lib/features/media/presentation/widgets/video_player_view.dart lib/features/media/presentation/screens/media_viewer_screen.dart lib/features/conversation/presentation/screens/instant_view_screen.dart test/features/media/stream_download_test.dart
git commit -m "Video: downloaded range on the seek bar, download and buffering percentages

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5: Check nothing of the owner's got in**

Run: `git show --stat HEAD~2 HEAD~1 HEAD`
Expected: none of `android/build.gradle.kts`, `android/gradle/wrapper/gradle-wrapper.properties`, `android/settings.gradle.kts`, `lib/core/media/ffmpeg_service.dart`, `lib/features/transcription/data/whisper_service.dart`. `git status --short` still lists those as modified.

---

### Task 1: Cache mirrors folders and unread counts

**Files:**
- Modify: `lib/core/telegram/telegram_cache.dart`
- Test: `test/core/telegram/telegram_cache_test.dart`

**Interfaces:**
- Produces:
  - `final class FoldersChanged extends CacheEvent { const FoldersChanged(); }`
  - `final class UnreadCountChanged extends CacheEvent { const UnreadCountChanged(this.list); final td.ChatList list; }`
  - `typedef UnreadCount = ({int chats, int unmuted});`
  - `TelegramCache.chatFolders` (`List<td.ChatFolderInfo>`, TDLib order), `mainListPosition` (`int`), `folderTagsEnabled` (`bool`)
  - `UnreadCount unreadIn(td.ChatList list)` (zeros when unknown)
  - `List<int> foldersOf(td.Chat chat)` (folder ids the chat is listed in)
  - `static String listKey(td.ChatList list)` → `'main'`, `'archive'`, `'folder:<id>'`

- [ ] **Step 1: Write the failing tests**

Append inside `main()` of `test/core/telegram/telegram_cache_test.dart`:

```dart
  td.ChatFolderInfo folderInfo(int id, String name) => td.ChatFolderInfo(
    id: id,
    name: td.ChatFolderName(text: td.FormattedText(text: name, entities: const []), animateCustomEmoji: false),
    icon: const td.ChatFolderIcon(name: 'Custom'),
    colorId: -1,
    isShareable: false,
    hasMyInviteLinks: false,
  );

  test('mirrors chat folders and emits FoldersChanged', () {
    final events = <CacheEvent>[];
    cache.events.listen(events.add);
    cache.apply(
      td.UpdateChatFolders(
        chatFolders: [folderInfo(3, 'Work'), folderInfo(5, 'Home')],
        mainChatListPosition: 1,
        areTagsEnabled: true,
      ),
    );
    expect(cache.chatFolders.map((f) => f.id), [3, 5]);
    expect(cache.mainListPosition, 1);
    expect(cache.folderTagsEnabled, isTrue);
    expect(events.whereType<FoldersChanged>(), hasLength(1));
  });

  test('unread counts are kept per chat list', () {
    final events = <CacheEvent>[];
    cache.events.listen(events.add);
    cache.apply(
      const td.UpdateUnreadChatCount(
        chatList: td.ChatListFolder(chatFolderId: 3),
        totalCount: 10,
        unreadCount: 4,
        unreadUnmutedCount: 2,
        markedAsUnreadCount: 0,
        markedAsUnreadUnmutedCount: 0,
      ),
    );
    expect(cache.unreadIn(const td.ChatListFolder(chatFolderId: 3)), (chats: 4, unmuted: 2));
    expect(cache.unreadIn(const td.ChatListMain()), (chats: 0, unmuted: 0));
    expect(events.whereType<UnreadCountChanged>().single.list, isA<td.ChatListFolder>());
  });

  test('foldersOf lists the folders a chat is positioned in', () {
    cache.apply(
      td.UpdateNewChat(
        chat: fakeChat(1).copyWith(
          positions: const [
            td.ChatPosition(list: td.ChatListMain(), order: 9, isPinned: false),
            td.ChatPosition(list: td.ChatListFolder(chatFolderId: 3), order: 9, isPinned: false),
            td.ChatPosition(list: td.ChatListFolder(chatFolderId: 5), order: 9, isPinned: true),
          ],
        ),
      ),
    );
    expect(cache.foldersOf(cache.chats[1]!), [3, 5]);
  });

  test('clear forgets folders and counts', () {
    cache.apply(
      td.UpdateChatFolders(chatFolders: [folderInfo(3, 'Work')], mainChatListPosition: 0, areTagsEnabled: false),
    );
    cache.clear();
    expect(cache.chatFolders, isEmpty);
  });
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `flutter test test/core/telegram/telegram_cache_test.dart`
Expected: compile errors: `FoldersChanged`, `chatFolders`, `unreadIn`, `foldersOf` undefined.

- [ ] **Step 3: Implement**

In `lib/core/telegram/telegram_cache.dart`:

Add after `final class ConnectionChanged … {}`:

```dart
/// The folder list, its order or the tags switch changed.
final class FoldersChanged extends CacheEvent {
  const FoldersChanged();
}

/// TDLib's unread counters for [list] changed.
final class UnreadCountChanged extends CacheEvent {
  const UnreadCountChanged(this.list);
  final td.ChatList list;
}

/// Unread chats in a list, and how many of them are not muted.
typedef UnreadCount = ({int chats, int unmuted});
```

Add fields after `final secretChats = …;`:

```dart
  /// Chat folders in the user's order (`updateChatFolders`).
  List<td.ChatFolderInfo> chatFolders = const [];

  /// Where "All chats" sits among [chatFolders] (Premium can move it).
  int mainListPosition = 0;

  /// Premium "folder tags" on chat rows.
  bool folderTagsEnabled = false;

  final _unread = <String, UnreadCount>{};
```

Add cases in `apply` before `default:`:

```dart
      case td.UpdateChatFolders(:final chatFolders, :final mainChatListPosition, :final areTagsEnabled):
        this.chatFolders = chatFolders;
        mainListPosition = mainChatListPosition;
        folderTagsEnabled = areTagsEnabled;
        _emit(const FoldersChanged());
      case td.UpdateUnreadChatCount(:final chatList, :final unreadCount, :final unreadUnmutedCount):
        _unread[listKey(chatList)] = (chats: unreadCount, unmuted: unreadUnmutedCount);
        _emit(UnreadCountChanged(chatList));
```

Add queries after `positionIn`:

```dart
  UnreadCount unreadIn(td.ChatList list) => _unread[listKey(list)] ?? (chats: 0, unmuted: 0);

  /// Folder ids [chat] is listed in.
  List<int> foldersOf(td.Chat chat) => [
    for (final p in chat.positions)
      if (p.list case td.ChatListFolder(:final chatFolderId) when p.order != 0) chatFolderId,
  ];

  static String listKey(td.ChatList list) => switch (list) {
    td.ChatListMain() => 'main',
    td.ChatListArchive() => 'archive',
    td.ChatListFolder(:final chatFolderId) => 'folder:$chatFolderId',
  };
```

In `clear()` add after `_scopeMuteFor.clear();`:

```dart
    chatFolders = const [];
    mainListPosition = 0;
    folderTagsEnabled = false;
    _unread.clear();
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/core/telegram/telegram_cache_test.dart`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
dart format lib/core/telegram/telegram_cache.dart test/core/telegram/telegram_cache_test.dart
git add lib/core/telegram/telegram_cache.dart test/core/telegram/telegram_cache_test.dart
git commit -m "Cache: chat folders and per-list unread counts

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```


---

### Task 1b: Glow sheets (shared confirm and choice sheets)

**Files:**
- Create: `lib/core/widgets/glow_sheet.dart`
- Test: `test/core/widgets/glow_sheet_test.dart`

**Interfaces:**
- Produces:
  - `Future<T?> showGlowSheet<T>(BuildContext context, {required WidgetBuilder builder, Color accent = GlowColors.violet, String? title})`: a rounded `surfaceHigh` sheet with a glowing top edge in [accent], drag handle, optional title, keyboard-safe padding, scrollable content.
  - `Future<bool> showGlowConfirm(BuildContext context, {required String title, String? message, required String confirmLabel, IconData icon = Icons.help_outline_rounded, Color accent = GlowColors.violet, bool destructive = false, WidgetBuilder? body})`: a glowing sigil, title, message, optional [body] (e.g. checkboxes), a full-width `GlowButton` (`GlowButton.warm` when [destructive]) and "Cancel". True only when confirmed.

- [ ] **Step 1: Write the failing test**

`test/core/widgets/glow_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/widgets/glow_sheet.dart';

void main() {
  testWidgets('confirm returns true on the action and false on cancel', (tester) async {
    final results = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => results.add(
              await showGlowConfirm(context, title: 'Delete “Work”?', message: 'Chats stay.', confirmLabel: 'Delete', destructive: true),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Delete “Work”?'), findsOneWidget);
    expect(find.text('Chats stay.'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(results, [true, false]);
  });

  testWidgets('sheet returns what its content pops', (tester) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await showGlowSheet<String>(
              context,
              title: 'Icon',
              builder: (context) => TextButton(onPressed: () => Navigator.pop(context, 'Work'), child: const Text('Work')),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Icon'), findsOneWidget);
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    expect(picked, 'Work');
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `flutter test test/core/widgets/glow_sheet_test.dart`
Expected: compile error (file missing).

- [ ] **Step 3: Implement**

`lib/core/widgets/glow_sheet.dart`:

```dart
import 'package:flutter/material.dart';

import '../theme/glow_colors.dart';
import 'glow_button.dart';

/// Lumina's sheet for choices and small inputs (instead of stock dialogs):
/// rounded, lifted from the bottom, with a soft glowing top edge.
Future<T?> showGlowSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  Color accent = GlowColors.violet,
  String? title,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black54,
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      decoration: BoxDecoration(
        color: GlowColors.surfaceHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: accent.withValues(alpha: 0.6), width: 1.5)),
        boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.25), blurRadius: 32, offset: const Offset(0, -6))],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: GlowColors.outlineStrong, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: Semantics(
                  header: true,
                  child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ),
            Flexible(child: SingleChildScrollView(child: Builder(builder: builder))),
          ],
        ),
      ),
    ),
  ),
);

/// A confirmation as a glowing sheet: sigil, title, message, optional
/// extra content, one clear action. True only when confirmed.
Future<bool> showGlowConfirm(
  BuildContext context, {
  required String title,
  String? message,
  required String confirmLabel,
  IconData icon = Icons.help_outline_rounded,
  Color accent = GlowColors.violet,
  bool destructive = false,
  WidgetBuilder? body,
}) async {
  final color = destructive ? GlowColors.coral : accent;
  final ok = await showGlowSheet<bool>(
    context,
    accent: color,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.15),
              boxShadow: glow(color, intensity: 0.7),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: GlowColors.textMuted)),
          ],
          if (body != null) ...[const SizedBox(height: 12), body(context)],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: destructive
                ? GlowButton.warm(label: confirmLabel, onPressed: () => Navigator.pop(context, true))
                : GlowButton(label: confirmLabel, onPressed: () => Navigator.pop(context, true)),
          ),
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ],
      ),
    ),
  );
  return ok ?? false;
}
```

- [ ] **Step 4: Run the test**

Run: `flutter test test/core/widgets/glow_sheet_test.dart`
Expected: pass. If `GlowButton`'s breathing animation keeps `pumpAndSettle` from settling, wrap the test's `MaterialApp` in `MediaQuery(data: const MediaQueryData(disableAnimations: true), child: …)`; `GlowButton` must already stop breathing under reduced motion (check `glow_button.dart`; if it doesn't, make it skip `repeat()` when `Motion.ambientEnabled(context)` is false and add that to this task's commit).

- [ ] **Step 5: Commit**

```bash
dart format lib/core/widgets/glow_sheet.dart test/core/widgets/glow_sheet_test.dart
git add lib/core/widgets/glow_sheet.dart test/core/widgets/glow_sheet_test.dart
git commit -m "Core: glow sheets for confirmations and choices (instead of stock dialogs)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Internal links and Android VIEW intents

**Files:**
- Create: `lib/core/telegram/internal_links.dart`
- Modify: `lib/core/telegram/link_opener.dart`
- Create: `lib/features/proxy/presentation/widgets/proxy_link_dialog.dart`
- Modify: `lib/features/notifications/data/notification_center.dart`
- Modify: `android/app/src/main/kotlin/dev/lumina/lumina/MainActivity.kt`
- Modify: `android/app/src/main/kotlin/dev/lumina/background/MessageNotifications.kt`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `lib/app/feature_wiring.dart`
- Test: `test/core/telegram/internal_links_test.dart`

**Interfaces:**
- Produces:
  - `class InternalLinkHandler { const InternalLinkHandler({required this.matches, required this.open}); final bool Function(Uri uri) matches; final Future<void> Function(BuildContext context, Uri uri) open; }`
  - `class InternalLinks { InternalLinks([List<InternalLinkHandler> handlers]); static Uri? parse(String url); bool canOpen(String url); Future<bool> tryOpen(BuildContext context, String url); }`
  - `Future<void> confirmProxyLink(BuildContext context, ProxyConfig config)` in `proxy_link_dialog.dart`
  - Native event `{"type": "link", "url": String}` on `dev.lumina/notifications/events`; `NotificationCenter(openLink: void Function(String url)?)`.
- Consumes: `ProxyConfig.parseLink`, `ProxyRepository.addAll` (existing, uncommitted from this session).

- [ ] **Step 1: Write the failing test**

Create `test/core/telegram/internal_links_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/internal_links.dart';

Future<BuildContext> contextOf(WidgetTester tester) async {
  late BuildContext ctx;
  await tester.pumpWidget(
    Builder(
      builder: (c) {
        ctx = c;
        return const SizedBox();
      },
    ),
  );
  return ctx;
}

void main() {
  test('parse adds https to bare t.me links and keeps tg:// links', () {
    expect(InternalLinks.parse('t.me/addlist/AbC')!.toString(), 'https://t.me/addlist/AbC');
    expect(InternalLinks.parse('tg://addlist?slug=AbC')!.scheme, 'tg');
    expect(InternalLinks.parse('  '), isNull);
    final links = InternalLinks([InternalLinkHandler(matches: (u) => u.scheme == 'tg', open: (_, _) async {})]);
    expect(links.canOpen('tg://addlist?slug=a'), isTrue);
    expect(links.canOpen('https://example.com'), isFalse);
  });

  testWidgets('the first matching handler opens the link', (tester) async {
    final opened = <String>[];
    final links = InternalLinks([
      InternalLinkHandler(matches: (u) => u.path.startsWith('/addlist'), open: (_, u) async => opened.add('a $u')),
      InternalLinkHandler(matches: (u) => true, open: (_, u) async => opened.add('b $u')),
    ]);
    final ctx = await contextOf(tester);
    expect(await links.tryOpen(ctx, 'https://t.me/addlist/x'), isTrue);
    expect(opened, ['a https://t.me/addlist/x']);
  });

  testWidgets('no handler: not handled', (tester) async {
    final ctx = await contextOf(tester);
    expect(await InternalLinks().tryOpen(ctx, 'https://example.com'), isFalse);
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `flutter test test/core/telegram/internal_links_test.dart`
Expected: compile error, `internal_links.dart` not found.

- [ ] **Step 3: Implement the registry**

Create `lib/core/telegram/internal_links.dart`:

```dart
import 'package:flutter/widgets.dart';

/// One kind of link Lumina opens itself instead of a browser
/// (t.me/addlist, proxy links, …). Registered by the composition root.
class InternalLinkHandler {
  const InternalLinkHandler({required this.matches, required this.open});

  final bool Function(Uri uri) matches;
  final Future<void> Function(BuildContext context, Uri uri) open;
}

/// The in-app link handlers. [openLink] and links from other apps ask this
/// first; anything unhandled goes to the browser as before.
class InternalLinks {
  InternalLinks([this._handlers = const []]);

  final List<InternalLinkHandler> _handlers;

  /// `t.me/x` without a scheme becomes `https://t.me/x`.
  static Uri? parse(String url) {
    final s = url.trim();
    if (s.isEmpty) return null;
    return Uri.tryParse(s.contains('://') ? s : 'https://$s');
  }

  bool canOpen(String url) {
    final uri = parse(url);
    return uri != null && _handlers.any((h) => h.matches(uri));
  }

  Future<bool> tryOpen(BuildContext context, String url) async {
    final uri = parse(url);
    if (uri == null) return false;
    for (final h in _handlers) {
      if (h.matches(uri)) {
        await h.open(context, uri);
        return true;
      }
    }
    return false;
  }
}
```

- [ ] **Step 4: Run the test**

Run: `flutter test test/core/telegram/internal_links_test.dart`
Expected: pass.

- [ ] **Step 5: Route `openLink` through it**

In `lib/core/telegram/link_opener.dart`, add `import 'internal_links.dart';` and at the start of `openLink` after `if (uri == null) return false;`:

```dart
  try {
    if (await context.read<InternalLinks>().tryOpen(context, url)) return true;
  } on ProviderNotFoundException {
    // Tests and previews: no in-app handlers.
  }
  if (!context.mounted) return false;
```

- [ ] **Step 6: Proxy link confirmation**

Create `lib/features/proxy/presentation/widgets/proxy_link_dialog.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/glow_sheet.dart';
import '../../data/proxy_config.dart';
import '../../data/proxy_repository.dart';

/// A proxy link was tapped or opened from another app: ask, then add and
/// switch to it.
Future<void> confirmProxyLink(BuildContext context, ProxyConfig config) async {
  final kind = switch (config.kind) {
    ProxyKind.mtproto => 'MTProto',
    ProxyKind.socks5 => 'SOCKS5',
    ProxyKind.http => 'HTTP',
  };
  final ok = await showGlowConfirm(
    context,
    title: 'Connect through this proxy?',
    message: '$kind proxy ${config.server}:${config.port}',
    confirmLabel: 'Connect',
    icon: Icons.shield_rounded,
    accent: GlowColors.cyan,
  );
  if (!ok || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final added = await context.read<ProxyRepository>().addAll([config]);
    messenger.showSnackBar(SnackBar(content: Text(added == 0 ? 'That proxy is already saved' : 'Proxy added')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
}
```

- [ ] **Step 7: Native VIEW intents**

`AndroidManifest.xml`: inside the main `<activity>` (the one with the `MAIN`/`LAUNCHER` filter), after that `<intent-filter>`, add:

```xml
            <!-- Telegram links Lumina handles itself (folders, proxies). -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="tg" android:host="addlist"/>
                <data android:scheme="tg" android:host="proxy"/>
                <data android:scheme="tg" android:host="socks"/>
            </intent-filter>
            <!-- Off until the user enables it under "Open by default" (t.me can't be verified for us). -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="https" android:host="t.me" android:pathPrefix="/addlist"/>
                <data android:scheme="https" android:host="t.me" android:pathPrefix="/proxy"/>
                <data android:scheme="https" android:host="t.me" android:pathPrefix="/socks"/>
                <data android:scheme="https" android:host="telegram.me" android:pathPrefix="/addlist"/>
            </intent-filter>
```

`MessageNotifications.kt`: in `companion object`, next to `fun openChat`:

```kotlin
        /** A tg:// or t.me link opened from another app. */
        fun openLink(url: String) {
            val event = mapOf("type" to "link", "url" to url)
            val target = instance
            if (target != null) target.deliver(event) else synchronized(pending) { pending += event }
        }
```

`MainActivity.kt`: in `handleCallIntent`, before `val action = intent?.getStringExtra(...)`:

```kotlin
        if (intent?.action == Intent.ACTION_VIEW) {
            intent.data?.let { MessageNotifications.openLink(it.toString()) }
            intent.data = null
        }
```

- [ ] **Step 8: Dart side of the event**

`lib/features/notifications/data/notification_center.dart`: add constructor parameter `this._openLink,` after `this._openChat,`, the field `final void Function(String url)? _openLink;` after `_openChat`, and at the very start of `_onAction`:

```dart
    if (a['type'] == 'link') {
      final url = a['url'] as String?;
      if (url != null) _openLink?.call(url);
      return;
    }
```

- [ ] **Step 9: Wire it**

`lib/app/feature_wiring.dart`:
- imports: `import '../core/telegram/internal_links.dart';`, `import '../features/proxy/data/proxy_config.dart';`, `import '../features/proxy/presentation/widgets/proxy_link_dialog.dart';`
- add to `featureProviders()` (before `NotificationCenter`):

```dart
  RepositoryProvider<InternalLinks>(create: (_) => InternalLinks(appLinkHandlers())),
```

- in the `NotificationCenter(...)` constructor call add:

```dart
      openLink: (url) {
        final context = appNavigatorKey.currentContext;
        if (context != null) context.read<InternalLinks>().tryOpen(context, url).ignore();
      },
```

- add at the bottom of the file:

```dart
/// Links Lumina opens itself. Folder links are added in the folders task.
List<InternalLinkHandler> appLinkHandlers() => [
  InternalLinkHandler(
    matches: (uri) => ProxyConfig.parseLink(uri.toString()) != null,
    open: (context, uri) => confirmProxyLink(context, ProxyConfig.parseLink(uri.toString())!),
  ),
];
```

- [ ] **Step 10: Verify and commit**

Run: `flutter analyze` (no new issues) and `flutter test test/core/telegram test/features/proxy test/features/proxy_config_test.dart` (pass).

```bash
dart format lib/core/telegram/internal_links.dart lib/core/telegram/link_opener.dart lib/features/proxy/presentation/widgets/proxy_link_dialog.dart lib/features/notifications/data/notification_center.dart lib/app/feature_wiring.dart test/core/telegram/internal_links_test.dart
git add lib/core/telegram/internal_links.dart lib/core/telegram/link_opener.dart lib/features/proxy/presentation/widgets/proxy_link_dialog.dart lib/features/notifications/data/notification_center.dart lib/app/feature_wiring.dart android/app/src/main/AndroidManifest.xml android/app/src/main/kotlin/dev/lumina/lumina/MainActivity.kt android/app/src/main/kotlin/dev/lumina/background/MessageNotifications.kt test/core/telegram/internal_links_test.dart
git commit -m "In-app links: proxy links open in Lumina, tg:// intents

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Folders domain: draft, addlist links, error text

**Files:**
- Create: `lib/features/folders/domain/folder_draft.dart`
- Create: `lib/features/folders/domain/addlist_link.dart`
- Create: `lib/features/folders/domain/folder_errors.dart`
- Test: `test/features/folders/folder_draft_test.dart`, `test/features/folders/addlist_link_test.dart`, `test/features/folders/folder_errors_test.dart`

**Interfaces:**
- Produces:
  - `class FolderDraft` (immutable): fields `name`, `iconName` (`String?`), `colorId` (`int`, -1 = none), `pinned` (`List<int>`), `included` (`List<int>`), `excluded` (`List<int>`), `includeContacts`, `includeNonContacts`, `includeGroups`, `includeChannels`, `includeBots`, `excludeMuted`, `excludeRead`, `excludeArchived` (all `bool`), `isShareable` (`bool`, read-only from TDLib). Constructors `FolderDraft.empty()`, `FolderDraft.fromFolder(td.ChatFolder f)`. Members: `static const maxNameLength = 12`, `bool get hasRules`, `bool get canShare`, `String? validate()`, `td.ChatFolder toFolder({required bool sendColor})`, `FolderDraft asChatList(List<int> matchingChatIds)`, `FolderDraft withChat(int chatId, {required bool included})`, `FolderDraft copyWith({...})`.
  - `String? addlistSlug(String input)`, `List<String> findAddlistLinks(String text)` (canonical `https://t.me/addlist/<slug>`), `String addlistUrl(String slug)`.
  - `String folderErrorText(Object error)`.

- [ ] **Step 1: Write the failing tests**

`test/features/folders/folder_draft_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/folders/domain/folder_draft.dart';
import 'package:lumina_tdlib/api.dart' as td;

td.ChatFolder folder({
  String name = 'Work',
  List<td.TextEntity> entities = const [],
  bool groups = false,
  List<int> included = const [],
  List<int> excluded = const [],
}) => td.ChatFolder(
  name: td.ChatFolderName(text: td.FormattedText(text: name, entities: entities), animateCustomEmoji: true),
  icon: const td.ChatFolderIcon(name: 'Work'),
  colorId: 2,
  isShareable: false,
  pinnedChatIds: const [],
  includedChatIds: included,
  excludedChatIds: excluded,
  excludeMuted: false,
  excludeRead: false,
  excludeArchived: false,
  includeContacts: false,
  includeNonContacts: false,
  includeBots: false,
  includeGroups: groups,
  includeChannels: false,
);

void main() {
  test('round-trips a folder and keeps an unedited custom-emoji name as is', () {
    const emoji = td.TextEntity(offset: 0, length: 2, type: td.TextEntityTypeCustomEmoji(customEmojiId: 7));
    final f = folder(name: '🔥Work', entities: const [emoji], groups: true, included: const [1, 2]);
    final back = FolderDraft.fromFolder(f).toFolder(sendColor: true);
    expect(back.name.text.entities, [emoji]);
    expect(back.name.animateCustomEmoji, isTrue);
    expect(back.includeGroups, isTrue);
    expect(back.includedChatIds, [1, 2]);
    expect(back.colorId, 2);
  });

  test('an edited name becomes plain text', () {
    final d = FolderDraft.fromFolder(folder(name: '🔥Work')).copyWith(name: 'Job');
    expect(d.toFolder(sendColor: true).name.text.entities, isEmpty);
    expect(d.toFolder(sendColor: true).name.text.text, 'Job');
  });

  test('colour is only sent when allowed', () {
    final d = FolderDraft.empty().copyWith(name: 'A', includeGroups: true, colorId: 4);
    expect(d.toFolder(sendColor: false).colorId, -1);
    expect(d.toFolder(sendColor: true).colorId, 4);
  });

  test('validation', () {
    expect(FolderDraft.empty().validate(), 'Give the folder a name');
    expect(FolderDraft.empty().copyWith(name: 'Thirteen char').validate(), 'Names can be at most 12 characters');
    expect(FolderDraft.empty().copyWith(name: 'A').validate(), 'Add chats or chat types');
    expect(FolderDraft.empty().copyWith(name: 'A', included: const [1]).validate(), isNull);
    expect(FolderDraft.empty().copyWith(name: 'A', excludeRead: true, includeBots: true).validate(), isNull);
  });

  test('sharing needs a plain chat list', () {
    expect(FolderDraft.empty().copyWith(name: 'A', included: const [1]).canShare, isTrue);
    expect(FolderDraft.empty().copyWith(name: 'A', includeGroups: true).canShare, isFalse);
    expect(FolderDraft.empty().copyWith(name: 'A', included: const [1], excluded: const [2]).canShare, isFalse);
  });

  test('asChatList drops rules and lists the matching chats explicitly', () {
    final d = FolderDraft.fromFolder(folder(groups: true, included: const [1], excluded: const [9]));
    final list = d.asChatList(const [1, 5, 6]);
    expect(list.hasRules, isFalse);
    expect(list.included, [1, 5, 6]);
    expect(list.excluded, isEmpty);
  });

  test('withChat adds to included or moves to excluded', () {
    final d = FolderDraft.fromFolder(folder(groups: true, included: const [1]));
    expect(d.withChat(3, included: true).included, [1, 3]);
    final removed = d.withChat(1, included: false);
    expect(removed.included, isEmpty);
    expect(removed.excluded, [1]);
  });
}
```

`test/features/folders/addlist_link_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/folders/domain/addlist_link.dart';

void main() {
  test('reads the slug from every link form', () {
    for (final link in [
      'https://t.me/addlist/AbC_1-x',
      'http://telegram.me/addlist/AbC_1-x',
      't.me/addlist/AbC_1-x',
      'tg://addlist?slug=AbC_1-x',
      'tg:addlist?slug=AbC_1-x',
    ]) {
      expect(addlistSlug(link), 'AbC_1-x', reason: link);
    }
    expect(addlistSlug('https://t.me/proxy?server=a&port=1'), isNull);
    expect(addlistSlug('https://t.me/addlist/'), isNull);
  });

  test('finds addlist links in text and trims punctuation', () {
    expect(findAddlistLinks('Join t.me/addlist/AbC. Also tg://addlist?slug=XyZ, and t.me/addlist/AbC!'), [
      'https://t.me/addlist/AbC',
      'https://t.me/addlist/XyZ',
    ]);
    expect(findAddlistLinks('nothing'), isEmpty);
  });
}
```

`test/features/folders/folder_errors_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/tdlib/td_errors.dart';
import 'package:lumina/features/folders/domain/folder_errors.dart';

void main() {
  test('known TDLib errors read as sentences that name the limit', () {
    expect(folderErrorText(TdException(400, 'CHATLISTS_TOO_MUCH')), contains('folder limit'));
    expect(folderErrorText(TdException(400, 'FILTER_INCLUDE_TOO_MUCH')), contains('too many chats'));
    expect(folderErrorText(TdException(400, 'INVITE_SLUG_EXPIRED')), 'This folder link has expired');
    expect(folderErrorText(TdException(400, 'FILTER_ID_INVALID')), 'This folder was deleted');
  });

  test('unknown errors fall back to the message', () {
    expect(folderErrorText(TdException(500, 'Something odd')), 'Something odd');
    expect(folderErrorText(StateError('x')), 'Bad state: x');
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/folders`
Expected: compile errors (files missing).

- [ ] **Step 3: Implement `folder_draft.dart`**

```dart
import 'package:lumina_tdlib/api.dart' as td;

/// The folder editor's form state, and its conversion to TDLib's
/// `ChatFolder`. Pure; no TDLib calls.
class FolderDraft {
  const FolderDraft({
    required this.name,
    this.iconName,
    this.colorId = -1,
    this.pinned = const [],
    this.included = const [],
    this.excluded = const [],
    this.includeContacts = false,
    this.includeNonContacts = false,
    this.includeGroups = false,
    this.includeChannels = false,
    this.includeBots = false,
    this.excludeMuted = false,
    this.excludeRead = false,
    this.excludeArchived = false,
    this.isShareable = false,
    this.originalName,
  });

  const FolderDraft.empty() : this(name: '');

  factory FolderDraft.fromFolder(td.ChatFolder f) => FolderDraft(
    name: f.name.text.text,
    iconName: f.icon?.name,
    colorId: f.colorId,
    pinned: f.pinnedChatIds,
    included: f.includedChatIds,
    excluded: f.excludedChatIds,
    includeContacts: f.includeContacts,
    includeNonContacts: f.includeNonContacts,
    includeGroups: f.includeGroups,
    includeChannels: f.includeChannels,
    includeBots: f.includeBots,
    excludeMuted: f.excludeMuted,
    excludeRead: f.excludeRead,
    excludeArchived: f.excludeArchived,
    isShareable: f.isShareable,
    originalName: f.name,
  );

  /// Telegram's folder-name limit.
  static const maxNameLength = 12;

  final String name;
  final String? iconName;
  final int colorId;
  final List<int> pinned;
  final List<int> included;
  final List<int> excluded;
  final bool includeContacts;
  final bool includeNonContacts;
  final bool includeGroups;
  final bool includeChannels;
  final bool includeBots;
  final bool excludeMuted;
  final bool excludeRead;
  final bool excludeArchived;
  final bool isShareable;

  /// The name as TDLib sent it (may hold custom emoji), kept when [name]
  /// was not edited.
  final td.ChatFolderName? originalName;

  bool get hasRules =>
      includeContacts ||
      includeNonContacts ||
      includeGroups ||
      includeChannels ||
      includeBots ||
      excludeMuted ||
      excludeRead ||
      excludeArchived;

  /// Telegram shares only plain chat lists.
  bool get canShare => !hasRules && excluded.isEmpty;

  String? validate() {
    final n = name.trim();
    if (n.isEmpty) return 'Give the folder a name';
    if (n.runes.length > maxNameLength) return 'Names can be at most $maxNameLength characters';
    final anyType = includeContacts || includeNonContacts || includeGroups || includeChannels || includeBots;
    if (!anyType && included.isEmpty && pinned.isEmpty) return 'Add chats or chat types';
    return null;
  }

  td.ChatFolder toFolder({required bool sendColor}) {
    final original = originalName;
    final folderName = original != null && original.text.text == name
        ? original
        : td.ChatFolderName(
            text: td.FormattedText(text: name.trim(), entities: const []),
            animateCustomEmoji: false,
          );
    return td.ChatFolder(
      name: folderName,
      icon: iconName == null ? null : td.ChatFolderIcon(name: iconName!),
      colorId: sendColor ? colorId : -1,
      isShareable: isShareable,
      pinnedChatIds: pinned,
      includedChatIds: included,
      excludedChatIds: excluded,
      excludeMuted: excludeMuted,
      excludeRead: excludeRead,
      excludeArchived: excludeArchived,
      includeContacts: includeContacts,
      includeNonContacts: includeNonContacts,
      includeBots: includeBots,
      includeGroups: includeGroups,
      includeChannels: includeChannels,
    );
  }

  /// The same chats as an explicit list, so the folder can be shared.
  FolderDraft asChatList(List<int> matchingChatIds) => copyWith(
    included: [
      for (final id in {...pinned, ...included, ...matchingChatIds})
        if (!pinned.contains(id)) id,
    ],
    excluded: const [],
    includeContacts: false,
    includeNonContacts: false,
    includeGroups: false,
    includeChannels: false,
    includeBots: false,
    excludeMuted: false,
    excludeRead: false,
    excludeArchived: false,
  );

  /// Puts [chatId] in the folder, or takes it out. Taking it out also
  /// excludes it, so a type rule can't keep it in.
  FolderDraft withChat(int chatId, {required bool included}) => included
      ? copyWith(
          included: [...this.included.where((id) => id != chatId), chatId],
          excluded: excluded.where((id) => id != chatId).toList(),
        )
      : copyWith(
          included: this.included.where((id) => id != chatId).toList(),
          pinned: pinned.where((id) => id != chatId).toList(),
          excluded: [...excluded.where((id) => id != chatId), chatId],
        );

  FolderDraft copyWith({
    String? name,
    String? Function()? iconName,
    int? colorId,
    List<int>? pinned,
    List<int>? included,
    List<int>? excluded,
    bool? includeContacts,
    bool? includeNonContacts,
    bool? includeGroups,
    bool? includeChannels,
    bool? includeBots,
    bool? excludeMuted,
    bool? excludeRead,
    bool? excludeArchived,
  }) => FolderDraft(
    name: name ?? this.name,
    iconName: iconName != null ? iconName() : this.iconName,
    colorId: colorId ?? this.colorId,
    pinned: pinned ?? this.pinned,
    included: included ?? this.included,
    excluded: excluded ?? this.excluded,
    includeContacts: includeContacts ?? this.includeContacts,
    includeNonContacts: includeNonContacts ?? this.includeNonContacts,
    includeGroups: includeGroups ?? this.includeGroups,
    includeChannels: includeChannels ?? this.includeChannels,
    includeBots: includeBots ?? this.includeBots,
    excludeMuted: excludeMuted ?? this.excludeMuted,
    excludeRead: excludeRead ?? this.excludeRead,
    excludeArchived: excludeArchived ?? this.excludeArchived,
    isShareable: isShareable,
    originalName: originalName,
  );
}
```

Note: the `asChatList` test expects `[1, 5, 6]` for `included: [1]`, `pinned: []`, matching `[1, 5, 6]`; the set keeps first-seen order.

- [ ] **Step 4: Implement `addlist_link.dart`**

```dart
final _pattern = RegExp(
  r'(?:(?:https?://)?(?:www\.)?(?:t\.me|telegram\.me|telegram\.dog)/addlist/|tg:(?://)?addlist\?slug=)'
  r'([A-Za-z0-9_-]+)',
  caseSensitive: false,
);

/// The invite slug of a chat-folder link, or null.
String? addlistSlug(String input) {
  final m = _pattern.firstMatch(input.trim());
  return m == null ? null : m[1];
}

/// TDLib accepts the https form for every link variant.
String addlistUrl(String slug) => 'https://t.me/addlist/$slug';

/// Every folder link in [text], canonical and without duplicates. The slug
/// alphabet has no punctuation, so a trailing "." or "!" is never included.
List<String> findAddlistLinks(String text) => {
  for (final m in _pattern.allMatches(text)) addlistUrl(m[1]!),
}.toList();
```

- [ ] **Step 5: Implement `folder_errors.dart`**

```dart
import '../../../core/tdlib/td_errors.dart';

/// One line for a failed folder action. Limit errors name the limit.
String folderErrorText(Object error) {
  if (error is! TdException) return '$error';
  return switch (error.message) {
    'CHATLISTS_TOO_MUCH' || 'DIALOG_FILTERS_TOO_MUCH' || 'FILTERS_TOO_MUCH' =>
      'You have reached the folder limit (10 without Telegram Premium)',
    'FILTER_INCLUDE_TOO_MUCH' || 'CHATLIST_INCLUDE_TOO_MUCH' =>
      'This folder has too many chats (100 without Telegram Premium)',
    'FILTER_EXCLUDE_TOO_MUCH' => 'This folder excludes too many chats',
    'FILTER_TITLE_EMPTY' => 'Give the folder a name',
    'FILTER_ID_INVALID' || 'CHAT_FOLDER_NOT_FOUND' => 'This folder was deleted',
    'INVITE_SLUG_EXPIRED' => 'This folder link has expired',
    'INVITE_SLUG_EMPTY' || 'INVITE_SLUG_INVALID' => 'This folder link is not valid',
    'CHATLISTS_INVITES_TOO_MUCH' || 'INVITES_TOO_MUCH' => 'This folder has too many invite links',
    'USER_CHANNELS_TOO_MUCH' || 'CHANNELS_TOO_MUCH' => 'You are in too many groups and channels to join more',
    'PREMIUM_ACCOUNT_REQUIRED' => 'This needs Telegram Premium',
    final m => m,
  };
}
```

- [ ] **Step 6: Run the tests**

Run: `flutter test test/features/folders`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
dart format lib/features/folders/domain test/features/folders
git add lib/features/folders/domain test/features/folders
git commit -m "Folders: draft model, addlist link parsing, error text

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: FoldersRepository

**Files:**
- Create: `lib/features/folders/data/folders_repository.dart`
- Modify: `lib/core/storage/app_preferences.dart` (add `folderColorsJson`)
- Test: `test/features/folders/folders_repository_test.dart`

**Interfaces:**
- Consumes: `FolderDraft` (Task 3), `TelegramCache.chatFolders` / `chatsIn` (Task 1), `AppPreferences`.
- Produces `class FoldersRepository`:
  - `FoldersRepository({required TdClient client, required TelegramCache cache, required AppPreferences prefs, DateTime Function()? now})`
  - `bool get isPremium` (from TDLib option `is_premium`)
  - `Future<td.ChatFolder> folder(int id)`
  - `Future<td.ChatFolderInfo> create(FolderDraft draft)`, `Future<td.ChatFolderInfo> edit(int id, FolderDraft draft)`
  - `Future<void> delete(int id, {List<int> leaveChatIds = const []})`, `Future<List<int>> chatsToLeave(int id)`
  - `Future<void> reorder(List<int> folderIds, int mainPosition)`
  - `Future<List<td.RecommendedChatFolder>> recommended()`, `Future<void> addRecommended(td.ChatFolder folder)`
  - `Future<String> defaultIconName(FolderDraft draft)`
  - `Future<void> setTagsEnabled(bool on)`
  - `Future<List<int>> foldersToAddChat(int chatId)`, `Future<void> setChatInFolder(int chatId, int folderId, {required bool inFolder})`
  - `Future<void> readAll(td.ChatList list)`, `Future<void> setAllMuted(td.ChatList list, {required bool muted})`
  - `Future<List<td.ChatFolderInviteLink>> inviteLinks(int id)`, `Future<List<int>> shareableChats(int id)`, `Future<td.ChatFolderInviteLink> createLink(int id, {required String name, required List<int> chatIds})`, `Future<td.ChatFolderInviteLink> editLink(int id, String link, {required String name, required List<int> chatIds})`, `Future<void> deleteLink(int id, String link)`
  - `Future<td.ChatFolderInviteLinkInfo> checkLink(String url)`, `Future<void> join(String url, List<int> chatIds)`
  - `ValueListenable<Map<int, List<int>>> get newChats` (folder id → new chat ids), `Future<void> refreshNewChats()`, `Future<void> processNewChats(int id, List<int> added)`
  - `Future<List<int>> searchChats(String query)`
  - `int colorIdOf(td.ChatFolderInfo info)`, `int? localColor(int folderId)`
  - `Future<void> dispose()`

- [ ] **Step 1: Add the preference**

In `lib/core/storage/app_preferences.dart`, after `hideProxySponsor`:

```dart
  /// Folder glow colours chosen on this device (JSON: folder id → colour id),
  /// for accounts whose folder colours Telegram doesn't sync (non-Premium).
  String get folderColorsJson => _string('folders.colors') ?? '{}';
  set folderColorsJson(String v) => _set('folders.colors', v);
```

- [ ] **Step 2: Write the failing tests**

`test/features/folders/folders_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/folders/data/folders_repository.dart';
import 'package:lumina/features/folders/domain/folder_draft.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';
import 'folder_draft_test.dart' show folder;

td.ChatFolderInfo info(int id, {int colorId = -1, bool shareable = false, bool mine = false}) => td.ChatFolderInfo(
  id: id,
  name: td.ChatFolderName(text: td.FormattedText(text: 'F$id', entities: const []), animateCustomEmoji: false),
  icon: const td.ChatFolderIcon(name: 'Custom'),
  colorId: colorId,
  isShareable: shareable,
  hasMyInviteLinks: mine,
);

void main() {
  late FakeTdClient client;
  late TelegramCache cache;
  late AppPreferences prefs;
  late FoldersRepository repo;
  var now = DateTime(2026, 10, 26, 12);

  setUp(() {
    client = FakeTdClient();
    cache = TelegramCache.detached();
    prefs = AppPreferences.inMemory();
    now = DateTime(2026, 10, 26, 12);
    repo = FoldersRepository(client: client, cache: cache, prefs: prefs, now: () => now);
    client.respond = (f) => switch (f) {
      td.CreateChatFolder() || td.EditChatFolder() => info(7),
      td.GetChatFolder() => folder(groups: true, included: const [1]),
      td.GetChatFolderNewChats() => const td.Chats(totalCount: 2, chatIds: [11, 12]),
      _ => const td.Ok(),
    };
  });

  final draft = const FolderDraft.empty().copyWith(name: 'Work', includeGroups: true, colorId: 4);

  test('non-Premium colour is stored locally and not sent', () async {
    final created = await repo.create(draft);
    expect(client.sentOf<td.CreateChatFolder>().single.folder.colorId, -1);
    expect(repo.localColor(created.id), 4);
    expect(repo.colorIdOf(info(7)), 4);
  });

  test('Premium colour is sent to Telegram', () async {
    client.emitUpdate(const td.UpdateOption(name: 'is_premium', value: td.OptionValueBoolean(value: true)));
    await Future<void>.delayed(Duration.zero);
    await repo.create(draft);
    expect(client.sentOf<td.CreateChatFolder>().single.folder.colorId, 4);
    expect(repo.colorIdOf(info(7, colorId: 1)), 1);
  });

  test('adding a chat uses addChatToList', () async {
    await repo.setChatInFolder(5, 3, inFolder: true);
    final sent = client.sentOf<td.AddChatToList>().single;
    expect((sent.chatId, (sent.chatList as td.ChatListFolder).chatFolderId), (5, 3));
  });

  test('removing a chat that a rule includes excludes it', () async {
    await repo.setChatInFolder(1, 3, inFolder: false);
    final edit = client.sentOf<td.EditChatFolder>().single;
    expect(edit.chatFolderId, 3);
    expect(edit.folder.includedChatIds, isEmpty);
    expect(edit.folder.excludedChatIds, [1]);
  });

  test('new chats are checked only for joined shared folders, at most every 10 minutes', () async {
    cache.apply(
      td.UpdateChatFolders(
        chatFolders: [info(1), info(2, shareable: true), info(3, shareable: true, mine: true)],
        mainChatListPosition: 0,
        areTagsEnabled: false,
      ),
    );
    await repo.refreshNewChats();
    expect(client.sentOf<td.GetChatFolderNewChats>().map((f) => f.chatFolderId), [2]);
    expect(repo.newChats.value, {2: [11, 12]});

    await repo.refreshNewChats();
    expect(client.sentOf<td.GetChatFolderNewChats>(), hasLength(1));
    now = now.add(const Duration(minutes: 11));
    await repo.refreshNewChats();
    expect(client.sentOf<td.GetChatFolderNewChats>(), hasLength(2));
  });

  test('processing new chats clears the count', () async {
    cache.apply(
      td.UpdateChatFolders(chatFolders: [info(2, shareable: true)], mainChatListPosition: 0, areTagsEnabled: false),
    );
    await repo.refreshNewChats();
    await repo.processNewChats(2, const [11]);
    expect(client.sentOf<td.ProcessChatFolderNewChats>().single.addedChatIds, [11]);
    expect(repo.newChats.value, isEmpty);
  });

  test('reorder sends the folder order and where All chats goes', () async {
    await repo.reorder(const [5, 3], 1);
    final r = client.sentOf<td.ReorderChatFolders>().single;
    expect((r.chatFolderIds, r.mainChatListPosition), (const [5, 3], 1));
  });
}
```

Also add to `test/features/folders/folder_draft_test.dart` nothing; `folder()` is reused via `show folder` (it is a top-level function there).

- [ ] **Step 3: Run them to see them fail**

Run: `flutter test test/features/folders/folders_repository_test.dart`
Expected: compile error, `folders_repository.dart` missing.

- [ ] **Step 4: Implement**

`lib/features/folders/data/folders_repository.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/storage/app_preferences.dart';
import '../../../core/tdlib/td_client.dart';
import '../../../core/telegram/telegram_cache.dart';
import '../domain/folder_draft.dart';

/// TDLib's chat-folder API (spec: docs/superpowers/specs/2026-10-26-chat-folders-design.md),
/// local folder colours for non-Premium accounts, and the "new chats in a
/// shared folder" checks TDLib leaves to clients.
class FoldersRepository {
  FoldersRepository({
    required this._client,
    required this._cache,
    required this._prefs,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _sub = _client.updates.listen((u) {
      if (u case td.UpdateOption(name: 'is_premium', value: td.OptionValueBoolean(:final value))) {
        _premium = value;
      }
    });
  }

  final TdClient _client;
  final TelegramCache _cache;
  final AppPreferences _prefs;
  final DateTime Function() _now;
  late final StreamSubscription<td.Update> _sub;
  var _premium = false;

  /// TDLib allows checking a folder's new chats once per period; we use 10 min.
  static const newChatsPeriod = Duration(minutes: 10);
  final _lastChecked = <int, DateTime>{};
  final _newChats = ValueNotifier<Map<int, List<int>>>(const {});

  bool get isPremium => _premium;

  ValueListenable<Map<int, List<int>>> get newChats => _newChats;

  // ---- Folders --------------------------------------------------------------

  Future<td.ChatFolder> folder(int id) => _client.invoke<td.ChatFolder>(td.GetChatFolder(chatFolderId: id));

  Future<td.ChatFolderInfo> create(FolderDraft draft) async {
    final info = await _client.invoke<td.ChatFolderInfo>(
      td.CreateChatFolder(folder: draft.toFolder(sendColor: _premium)),
    );
    if (!_premium) _setLocalColor(info.id, draft.colorId);
    return info;
  }

  Future<td.ChatFolderInfo> edit(int id, FolderDraft draft) async {
    final info = await _client.invoke<td.ChatFolderInfo>(
      td.EditChatFolder(chatFolderId: id, folder: draft.toFolder(sendColor: _premium)),
    );
    if (!_premium) _setLocalColor(id, draft.colorId);
    return info;
  }

  Future<void> delete(int id, {List<int> leaveChatIds = const []}) async {
    await _client.invoke<td.Ok>(td.DeleteChatFolder(chatFolderId: id, leaveChatIds: leaveChatIds));
    _setLocalColor(id, -1);
  }

  /// Chats of a joined shared folder that Telegram suggests leaving with it.
  Future<List<int>> chatsToLeave(int id) async =>
      (await _client.invoke<td.Chats>(td.GetChatFolderChatsToLeave(chatFolderId: id))).chatIds;

  Future<void> reorder(List<int> folderIds, int mainPosition) => _client.invoke<td.Ok>(
    td.ReorderChatFolders(chatFolderIds: folderIds, mainChatListPosition: mainPosition),
  );

  Future<List<td.RecommendedChatFolder>> recommended() async =>
      (await _client.invoke<td.RecommendedChatFolders>(const td.GetRecommendedChatFolders())).chatFolders;

  Future<void> addRecommended(td.ChatFolder folder) =>
      _client.invoke<td.ChatFolderInfo>(td.CreateChatFolder(folder: folder));

  Future<String> defaultIconName(FolderDraft draft) async => (await _client.invoke<td.ChatFolderIcon>(
    td.GetChatFolderDefaultIconName(folder: draft.toFolder(sendColor: false)),
  )).name;

  Future<void> setTagsEnabled(bool on) => _client.invoke<td.Ok>(td.ToggleChatFolderTags(areTagsEnabled: on));

  // ---- Chats in folders -----------------------------------------------------

  /// Folder ids the chat could be added to (TDLib knows the limits).
  Future<List<int>> foldersToAddChat(int chatId) async {
    final lists = await _client.invoke<td.ChatLists>(td.GetChatListsToAddChat(chatId: chatId));
    return [
      for (final l in lists.chatLists)
        if (l case td.ChatListFolder(:final chatFolderId)) chatFolderId,
    ];
  }

  Future<void> setChatInFolder(int chatId, int folderId, {required bool inFolder}) async {
    if (inFolder) {
      await _client.invoke<td.Ok>(td.AddChatToList(chatId: chatId, chatList: td.ChatListFolder(chatFolderId: folderId)));
      return;
    }
    final f = await folder(folderId);
    final draft = FolderDraft.fromFolder(f).withChat(chatId, included: false);
    await _client.invoke<td.ChatFolderInfo>(
      td.EditChatFolder(chatFolderId: folderId, folder: draft.toFolder(sendColor: _premium)),
    );
  }

  Future<void> readAll(td.ChatList list) => _client.invoke<td.Ok>(td.ReadChatList(chatList: list));

  /// Mutes or unmutes every loaded chat of [list].
  Future<void> setAllMuted(td.ChatList list, {required bool muted}) async {
    for (final chat in _cache.chatsIn(list)) {
      await _client.invoke<td.Ok>(
        td.SetChatNotificationSettings(
          chatId: chat.id,
          notificationSettings: chat.notificationSettings.copyWith(
            useDefaultMuteFor: false,
            muteFor: muted ? 0x7fffffff : 0,
          ),
        ),
      );
    }
  }

  Future<List<int>> searchChats(String query) async {
    if (query.trim().isEmpty) return const [];
    return (await _client.invoke<td.Chats>(td.SearchChats(query: query, limit: 50))).chatIds;
  }

  // ---- Invite links ---------------------------------------------------------

  Future<List<td.ChatFolderInviteLink>> inviteLinks(int id) async =>
      (await _client.invoke<td.ChatFolderInviteLinks>(td.GetChatFolderInviteLinks(chatFolderId: id))).inviteLinks;

  Future<List<int>> shareableChats(int id) async =>
      (await _client.invoke<td.Chats>(td.GetChatsForChatFolderInviteLink(chatFolderId: id))).chatIds;

  Future<td.ChatFolderInviteLink> createLink(int id, {required String name, required List<int> chatIds}) =>
      _client.invoke<td.ChatFolderInviteLink>(
        td.CreateChatFolderInviteLink(chatFolderId: id, name: name, chatIds: chatIds),
      );

  Future<td.ChatFolderInviteLink> editLink(
    int id,
    String link, {
    required String name,
    required List<int> chatIds,
  }) => _client.invoke<td.ChatFolderInviteLink>(
    td.EditChatFolderInviteLink(chatFolderId: id, inviteLink: link, name: name, chatIds: chatIds),
  );

  Future<void> deleteLink(int id, String link) =>
      _client.invoke<td.Ok>(td.DeleteChatFolderInviteLink(chatFolderId: id, inviteLink: link));

  Future<td.ChatFolderInviteLinkInfo> checkLink(String url) =>
      _client.invoke<td.ChatFolderInviteLinkInfo>(td.CheckChatFolderInviteLink(inviteLink: url));

  Future<void> join(String url, List<int> chatIds) =>
      _client.invoke<td.Ok>(td.AddChatFolderByInviteLink(inviteLink: url, chatIds: chatIds));

  // ---- New chats in joined shared folders -----------------------------------

  /// Asks TDLib for new chats in every shared folder we joined (shareable,
  /// no links of our own), at most once per [newChatsPeriod] per folder.
  Future<void> refreshNewChats() async {
    final next = {..._newChats.value};
    for (final f in _cache.chatFolders) {
      if (!f.isShareable || f.hasMyInviteLinks) continue;
      final last = _lastChecked[f.id];
      if (last != null && _now().difference(last) < newChatsPeriod) continue;
      _lastChecked[f.id] = _now();
      try {
        final chats = await _client.invoke<td.Chats>(td.GetChatFolderNewChats(chatFolderId: f.id));
        if (chats.chatIds.isEmpty) {
          next.remove(f.id);
        } else {
          next[f.id] = chats.chatIds;
        }
      } on Exception {
        // Offline or rate-limited; the next refresh retries.
      }
    }
    _newChats.value = next;
  }

  Future<void> processNewChats(int id, List<int> added) async {
    await _client.invoke<td.Ok>(td.ProcessChatFolderNewChats(chatFolderId: id, addedChatIds: added));
    _newChats.value = {..._newChats.value}..remove(id);
  }

  // ---- Colours ---------------------------------------------------------------

  /// Telegram's colour when set, else this device's choice, else -1.
  int colorIdOf(td.ChatFolderInfo info) => info.colorId >= 0 ? info.colorId : localColor(info.id) ?? -1;

  int? localColor(int folderId) => (jsonDecode(_prefs.folderColorsJson) as Map<String, dynamic>)['$folderId'] as int?;

  void _setLocalColor(int folderId, int colorId) {
    final map = (jsonDecode(_prefs.folderColorsJson) as Map<String, dynamic>)..remove('$folderId');
    if (colorId >= 0) map['$folderId'] = colorId;
    _prefs.folderColorsJson = jsonEncode(map);
  }

  Future<void> dispose() async {
    await _sub.cancel();
    _newChats.dispose();
  }
}
```

- [ ] **Step 5: Run the tests**

Run: `flutter test test/features/folders`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
dart format lib/features/folders/data lib/core/storage/app_preferences.dart test/features/folders
git add lib/features/folders/data lib/core/storage/app_preferences.dart test/features/folders/folders_repository_test.dart
git commit -m "Folders: repository (folders, links, new chats, local colours)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Lens model and LensCubit

**Files:**
- Create: `lib/features/chats/domain/lens_entry.dart`
- Create: `lib/features/chats/bloc/lens_cubit.dart`
- Test: `test/features/chats/lens_cubit_test.dart`

**Interfaces:**
- Consumes: `TelegramCache.chatFolders`, `mainListPosition`, `unreadIn`, `listKey`, `FoldersChanged`, `UnreadCountChanged`, `UnreadCount` (Task 1).
- Produces:
  - `class LensEntry { const LensEntry({required td.ChatList list, required String title, td.ChatFolderInfo? folder, UnreadCount unread}); td.ChatList list; String title; td.ChatFolderInfo? folder; UnreadCount unread; int? get folderId; String get key; bool get isMain; bool get isArchive; }`
  - `class LensState { const LensState({List<LensEntry> entries, int index}); LensEntry? get current; }`
  - `class LensCubit extends Cubit<LensState> { LensCubit({required TelegramCache cache, required bool isBot}); void select(int index); void selectList(td.ChatList list); }`

- [ ] **Step 1: Write the failing tests**

`test/features/chats/lens_cubit_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/chats/bloc/lens_cubit.dart';
import 'package:lumina_tdlib/api.dart' as td;

td.ChatFolderInfo info(int id, String name) => td.ChatFolderInfo(
  id: id,
  name: td.ChatFolderName(text: td.FormattedText(text: name, entities: const []), animateCustomEmoji: false),
  icon: const td.ChatFolderIcon(name: 'Custom'),
  colorId: -1,
  isShareable: false,
  hasMyInviteLinks: false,
);

void main() {
  late TelegramCache cache;
  setUp(() => cache = TelegramCache.detached());

  void folders(List<td.ChatFolderInfo> f, {int main = 0}) =>
      cache.apply(td.UpdateChatFolders(chatFolders: f, mainChatListPosition: main, areTagsEnabled: false));

  List<String> titles(LensCubit c) => c.state.entries.map((e) => e.title).toList();

  test('All chats, then folders, then Archive', () async {
    folders([info(3, 'Work'), info(5, 'Home')]);
    final c = LensCubit(cache: cache, isBot: false);
    expect(titles(c), ['All chats', 'Work', 'Home', 'Archive']);
    expect(c.state.current!.isMain, isTrue);
    await c.close();
  });

  test('places All chats at main_chat_list_position', () async {
    folders([info(3, 'Work'), info(5, 'Home')], main: 1);
    final c = LensCubit(cache: cache, isBot: false);
    expect(titles(c), ['Work', 'All chats', 'Home', 'Archive']);
    expect(c.state.current!.isMain, isTrue, reason: 'opens on All chats wherever it is');
    await c.close();
  });

  test('follows folder updates and keeps the current lens', () async {
    final c = LensCubit(cache: cache, isBot: false);
    expect(titles(c), ['All chats', 'Archive']);
    folders([info(3, 'Work')]);
    c.selectList(const td.ChatListFolder(chatFolderId: 3));
    folders([info(9, 'New'), info(3, 'Work')]);
    expect(c.state.current!.folderId, 3);
    await c.close();
  });

  test('falls back to All chats when the current folder disappears', () async {
    folders([info(3, 'Work'), info(5, 'Home')], main: 1);
    final c = LensCubit(cache: cache, isBot: false);
    c.selectList(const td.ChatListFolder(chatFolderId: 5));
    folders([info(3, 'Work')], main: 1);
    expect(c.state.current!.isMain, isTrue);
    await c.close();
  });

  test('carries unread counts', () async {
    folders([info(3, 'Work')]);
    final c = LensCubit(cache: cache, isBot: false);
    cache.apply(
      const td.UpdateUnreadChatCount(
        chatList: td.ChatListFolder(chatFolderId: 3),
        totalCount: 5,
        unreadCount: 2,
        unreadUnmutedCount: 1,
        markedAsUnreadCount: 0,
        markedAsUnreadUnmutedCount: 0,
      ),
    );
    expect(c.state.entries[1].unread, (chats: 2, unmuted: 1));
    await c.close();
  });

  test('bots get only the main list', () async {
    folders([info(3, 'Work')]);
    final c = LensCubit(cache: cache, isBot: true);
    expect(titles(c), ['Chats']);
    await c.close();
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/chats/lens_cubit_test.dart`
Expected: compile error (files missing).

- [ ] **Step 3: Implement `lens_entry.dart`**

```dart
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/telegram/telegram_cache.dart';

/// One page of the chat list lens: All chats, a folder, or Archive.
class LensEntry {
  const LensEntry({
    required this.list,
    required this.title,
    this.folder,
    this.unread = (chats: 0, unmuted: 0),
  });

  final td.ChatList list;
  final String title;
  final td.ChatFolderInfo? folder;
  final UnreadCount unread;

  int? get folderId => folder?.id;
  String get key => TelegramCache.listKey(list);
  bool get isMain => list is td.ChatListMain;
  bool get isArchive => list is td.ChatListArchive;
}
```

- [ ] **Step 4: Implement `lens_cubit.dart`**

```dart
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/telegram/telegram_cache.dart';
import '../domain/lens_entry.dart';

class LensState {
  const LensState({this.entries = const [], this.index = 0});

  final List<LensEntry> entries;
  final int index;

  LensEntry? get current => index < entries.length ? entries[index] : null;
}

/// The chat lists the lens pages through, in Telegram's order: folders
/// with All chats at `main_chat_list_position`, then Archive.
class LensCubit extends Cubit<LensState> {
  LensCubit({required this._cache, required this._isBot}) : super(const LensState()) {
    _sub = _cache.events.listen((e) {
      if (e is FoldersChanged || e is UnreadCountChanged) _rebuild();
    });
    _rebuild();
  }

  final TelegramCache _cache;
  final bool _isBot;
  late final StreamSubscription<CacheEvent> _sub;

  void select(int index) {
    if (index == state.index || index < 0 || index >= state.entries.length) return;
    emit(LensState(entries: state.entries, index: index));
  }

  void selectList(td.ChatList list) {
    final key = TelegramCache.listKey(list);
    final i = state.entries.indexWhere((e) => e.key == key);
    if (i >= 0) select(i);
  }

  void _rebuild() {
    if (isClosed) return;
    final entries = _build();
    final currentKey = state.current?.key ?? 'main';
    var index = entries.indexWhere((e) => e.key == currentKey);
    if (index < 0) index = entries.indexWhere((e) => e.isMain);
    emit(LensState(entries: entries, index: index));
  }

  List<LensEntry> _build() {
    LensEntry entry(td.ChatList list, String title, [td.ChatFolderInfo? folder]) =>
        LensEntry(list: list, title: title, folder: folder, unread: _cache.unreadIn(list));
    if (_isBot) return [entry(const td.ChatListMain(), 'Chats')];
    final folders = [
      for (final f in _cache.chatFolders) entry(td.ChatListFolder(chatFolderId: f.id), f.name.text.text, f),
    ];
    final at = _cache.mainListPosition.clamp(0, folders.length);
    return [
      ...folders.take(at),
      entry(const td.ChatListMain(), 'All chats'),
      ...folders.skip(at),
      entry(const td.ChatListArchive(), 'Archive'),
    ];
  }

  @override
  Future<void> close() async {
    await _sub.cancel();
    return super.close();
  }
}
```

- [ ] **Step 5: Run the tests**

Run: `flutter test test/features/chats/lens_cubit_test.dart`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
dart format lib/features/chats/domain lib/features/chats/bloc/lens_cubit.dart test/features/chats/lens_cubit_test.dart
git add lib/features/chats/domain lib/features/chats/bloc/lens_cubit.dart test/features/chats/lens_cubit_test.dart
git commit -m "Chats: lens model and cubit (All chats, folders, Archive)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Chat list hooks, ribbon tint, folder tags, list-aware actions

**Files:**
- Modify: `lib/core/theme/glow_colors.dart` (add `archive`)
- Modify: `lib/features/chats/presentation/widgets/chat_list_extensions.dart`
- Modify: `lib/features/chats/presentation/widgets/timeline_chat_row.dart`
- Modify: `lib/features/chats/presentation/widgets/chat_actions_sheet.dart`
- Test: `test/features/chats/chat_actions_sheet_test.dart`

**Interfaces:**
- Consumes: `LensEntry` (Task 5).
- Produces (in `chat_list_extensions.dart`):

```dart
class LensAction {
  const LensAction({required this.label, required this.icon, required this.onSelected, this.destructive = false});
  final String label;
  final IconData icon;
  final void Function(BuildContext context) onSelected;
  final bool destructive;
}

class LensSuggestion {
  const LensSuggestion({required this.title, required this.description, required this.onAdd});
  final String title;
  final String description;
  final Future<void> Function() onAdd;
}

class ChatAction {
  const ChatAction({required this.label, required this.icon, required this.run});
  final String label;
  final IconData icon;
  /// Runs after the actions sheet closed, with the chat list's context.
  final Future<void> Function(BuildContext context) run;
}
```

and on `ChatListExtensions`: `Listenable? get lensListenable`, `Color lensColor(LensEntry entry)`, `IconData lensIcon(LensEntry entry)`, `int newChatsIn(LensEntry entry)`, `void openNewChats(BuildContext context, LensEntry entry)`, `List<LensAction> lensActions(BuildContext context, LensEntry entry)`, `VoidCallback? newFolder(BuildContext context)`, `VoidCallback? manageFolders(BuildContext context)`, `VoidCallback? editFolder(BuildContext context, LensEntry entry)`, `Future<List<LensSuggestion>> suggestions()`, `void onLensOpened()`, `List<ChatAction> chatActions(td.Chat chat)`, `List<Widget> folderTags(BuildContext context, td.Chat chat)`.
- `TimelineChatRow({..., Color? tint})`.
- `showChatActions(BuildContext context, td.Chat chat, {td.ChatList list = const td.ChatListMain()})`.

- [ ] **Step 1: Write the failing test**

`test/features/chats/chat_actions_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/chats/data/chats_repository.dart';
import 'package:lumina/features/chats/presentation/widgets/chat_actions_sheet.dart';
import 'package:lumina/features/chats/presentation/widgets/chat_list_extensions.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';

class _Ext extends ChatListExtensions {
  _Ext(this.ran);
  final List<int> ran;

  @override
  List<ChatAction> chatActions(td.Chat chat) => [
    ChatAction(label: 'Add to folder…', icon: Icons.folder_rounded, run: (_) async => ran.add(chat.id)),
  ];
}

void main() {
  testWidgets('pins within the shown list and offers hook actions', (tester) async {
    final client = FakeTdClient();
    final cache = TelegramCache.detached()..apply(td.UpdateNewChat(chat: fakeChat(1, order: 5)));
    final ran = <int>[];
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: cache),
          RepositoryProvider.value(value: ChatsRepository(client: client, cache: cache)),
          RepositoryProvider<ChatListExtensions>.value(value: _Ext(ran)),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showChatActions(context, cache.chats[1]!, list: const td.ChatListFolder(chatFolderId: 3)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin'));
    await tester.pumpAndSettle();
    final pin = client.sentOf<td.ToggleChatIsPinned>().single;
    expect((pin.chatList as td.ChatListFolder).chatFolderId, 3);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to folder…'));
    await tester.pumpAndSettle();
    expect(ran, [1]);
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `flutter test test/features/chats/chat_actions_sheet_test.dart`
Expected: compile errors (`ChatAction`, `list:` undefined).

- [ ] **Step 3: Archive colour**

In `lib/core/theme/glow_colors.dart`, inside `GlowColors` after `magentaDeep`:

```dart
  /// Archive lens: cool and dimmer than the folder palette.
  static const archive = Color(0xFF7C86C9);
```

- [ ] **Step 4: Extend the hook**

Replace `lib/features/chats/presentation/widgets/chat_list_extensions.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:lumina_tdlib/api.dart' as td;
import 'package:provider/provider.dart';

import '../../../../core/theme/glow_colors.dart';
import '../../domain/lens_entry.dart';

/// An action on a lens (folder) from the picker's long-press menu.
class LensAction {
  const LensAction({required this.label, required this.icon, required this.onSelected, this.destructive = false});

  final String label;
  final IconData icon;
  final void Function(BuildContext context) onSelected;
  final bool destructive;
}

/// A folder Telegram suggests, offered when the user has none.
class LensSuggestion {
  const LensSuggestion({required this.title, required this.description, required this.onAdd});

  final String title;
  final String description;
  final Future<void> Function() onAdd;
}

/// An extra entry in a chat row's long-press sheet.
class ChatAction {
  const ChatAction({required this.label, required this.icon, required this.run});

  final String label;
  final IconData icon;

  /// Runs after the actions sheet closed, with the chat list's context.
  final Future<void> Function(BuildContext context) run;
}

/// Lets other features add to the chat list (the proxy button, folders)
/// without the chat list depending on them. Provided by the composition
/// root; the defaults are a plain list with no folders.
class ChatListExtensions {
  const ChatListExtensions();

  static ChatListExtensions of(BuildContext context) {
    try {
      return context.read<ChatListExtensions>();
    } on ProviderNotFoundException {
      return const ChatListExtensions();
    }
  }

  /// Shown before the search button.
  List<Widget> headerActions(BuildContext context) => const [];

  /// Rebuilds the lens when it fires (new chats in shared folders).
  Listenable? get lensListenable => null;

  Color lensColor(LensEntry entry) => entry.isArchive ? GlowColors.archive : GlowColors.violet;

  IconData lensIcon(LensEntry entry) => entry.isArchive
      ? Icons.inventory_2_rounded
      : entry.isMain
      ? Icons.forum_rounded
      : Icons.folder_rounded;

  /// Chats the owner of a joined shared folder added since we last looked.
  int newChatsIn(LensEntry entry) => 0;

  void openNewChats(BuildContext context, LensEntry entry) {}

  List<LensAction> lensActions(BuildContext context, LensEntry entry) => const [];

  VoidCallback? newFolder(BuildContext context) => null;

  VoidCallback? manageFolders(BuildContext context) => null;

  VoidCallback? editFolder(BuildContext context, LensEntry entry) => null;

  Future<List<LensSuggestion>> suggestions() async => const [];

  /// The lens picker opened (time to look for new shared-folder chats).
  void onLensOpened() {}

  List<ChatAction> chatActions(td.Chat chat) => const [];

  /// Small tags after a chat's title (Premium folder tags).
  List<Widget> folderTags(BuildContext context, td.Chat chat) => const [];
}
```

The existing `_ChatListExtensions` in `lib/app/feature_wiring.dart` keeps compiling (it only overrides `headerActions`); Task 13 replaces it.

- [ ] **Step 5: Ribbon tint and folder tags in `timeline_chat_row.dart`**

1. Constructor: add `this.tint,` after `this.showPresence = true,` and the field:

```dart
  /// The lens colour; null keeps the default violet/teal ribbon.
  final Color? tint;
```

2. Replace `final accent = unread > 0 && !muted ? GlowColors.cyan : GlowColors.violet;` with:

```dart
    final tint = widget.tint;
    final accent = unread > 0 && !muted ? (tint ?? GlowColors.cyan) : (tint ?? GlowColors.violet);
```

3. Pass the tint to the painter: in `_RibbonPainter(` add `tint: tint,`. In `_RibbonPainter` add `required this.tint,` to the constructor, `final Color? tint;`, `old.tint != tint ||` to `shouldRepaint`, and replace the thread gradient colours with:

```dart
        colors: tint == null
            ? [GlowColors.violet.withValues(alpha: 0.35), GlowColors.teal.withValues(alpha: 0.35)]
            : [tint!.withValues(alpha: 0.45), tint!.withValues(alpha: 0.2)],
```

4. Folder tags: in the title `Row`, right after `if (sponsored) const _SponsorTag(),` add:

```dart
                        ...ChatListExtensions.of(context).folderTags(context, chat),
```

and `import 'chat_list_extensions.dart';`.

- [ ] **Step 6: List-aware pin and hook actions in `chat_actions_sheet.dart`**

1. Signature: `Future<void> showChatActions(BuildContext context, td.Chat chat, {td.ChatList list = const td.ChatListMain()}) async {`
2. `final pinned = cache.positionIn(chat, list)?.isPinned ?? false;`
3. Pin tile: `onTap: () => run(() => repo.setPinned(chat.id, !pinned, list: list)),`
4. Before the Leave/Delete tile, add:

```dart
          for (final a in ChatListExtensions.of(context).chatActions(chat))
            ListTile(
              leading: Icon(a.icon),
              title: Text(a.label),
              onTap: () {
                Navigator.of(context).pop();
                a.run(outer).ignore();
              },
            ),
```

5. At the top of the function, after `final messenger = ScaffoldMessenger.of(context);`, add `final outer = context;` and `import 'chat_list_extensions.dart';`. (Inside the sheet builder the `context` parameter shadows it; `outer` is the list's context.)

- [ ] **Step 7: Run the test and analyzer**

Run: `flutter test test/features/chats` then `flutter analyze`
Expected: pass; no new issues.

- [ ] **Step 8: Commit**

```bash
dart format lib/core/theme/glow_colors.dart lib/features/chats/presentation/widgets test/features/chats/chat_actions_sheet_test.dart
git add lib/core/theme/glow_colors.dart lib/features/chats/presentation/widgets/chat_list_extensions.dart lib/features/chats/presentation/widgets/timeline_chat_row.dart lib/features/chats/presentation/widgets/chat_actions_sheet.dart test/features/chats/chat_actions_sheet_test.dart
git commit -m "Chats: lens hooks, ribbon tint, folder tags, list-aware chat actions

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: The lens UI: title, picker, swipeable pages

**Files:**
- Modify: `lib/core/telegram/widgets/connection_status.dart` (`ConnectionAwareTitle.glow`)
- Create: `lib/features/chats/presentation/widgets/lens_title.dart`
- Create: `lib/features/chats/presentation/widgets/lens_picker.dart`
- Create: `lib/features/chats/presentation/widgets/chat_list_page.dart`
- Modify: `lib/features/chats/presentation/screens/chats_screen.dart`
- Modify: `lib/features/home/presentation/screens/home_shell.dart`
- Test: `test/features/chats/lens_picker_test.dart`

**Interfaces:**
- Consumes: `LensCubit`, `LensState`, `LensEntry` (Task 5); `ChatListExtensions` hooks (Task 6); `ChatListCubit({required ChatsRepository repository, AppPreferences? prefs, td.ChatList list})` (existing); `InternalLinks.canOpen/tryOpen` (Task 2).
- Produces:
  - `ConnectionAwareTitle({required String title, Color? glow})`
  - `LensTitle({required LensEntry entry, required Color color, VoidCallback? onTap})`
  - `Future<int?> showLensPicker(BuildContext context, {required List<LensEntry> entries, required int current})`
  - `ChatListPage({required LensEntry entry, required bool isBot, required Color? tint, required void Function(td.Chat) onOpen})`

- [ ] **Step 1: Write the failing test**

`test/features/chats/lens_picker_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/chats/domain/lens_entry.dart';
import 'package:lumina/features/chats/presentation/widgets/lens_picker.dart';
import 'package:lumina_tdlib/api.dart' as td;

void main() {
  testWidgets('lists every lens with unread pills and returns the picked one', (tester) async {
    const entries = [
      LensEntry(list: td.ChatListMain(), title: 'All chats', unread: (chats: 3, unmuted: 1)),
      LensEntry(list: td.ChatListFolder(chatFolderId: 4), title: 'Work', unread: (chats: 2, unmuted: 0)),
      LensEntry(list: td.ChatListArchive(), title: 'Archive'),
    ];
    int? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await showLensPicker(context, entries: entries, current: 0),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    expect(picked, 1);
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `flutter test test/features/chats/lens_picker_test.dart`
Expected: compile error (`lens_picker.dart` missing).

- [ ] **Step 3: Title glow**

In `lib/core/telegram/widgets/connection_status.dart`: constructor `const ConnectionAwareTitle({super.key, required this.title, this.glow});`, field `final Color? glow;`, and the title `Text` becomes:

```dart
            ? Text(
                widget.title,
                key: const ValueKey('title'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  shadows: widget.glow == null
                      ? null
                      : [Shadow(color: widget.glow!.withValues(alpha: 0.7), blurRadius: 14)],
                ),
              )
```

- [ ] **Step 4: `lens_title.dart`**

```dart
import 'package:flutter/material.dart';

import '../../../../core/telegram/widgets/connection_status.dart';
import '../../domain/lens_entry.dart';

/// "Work ▾": the current lens, glowing in its colour. Tap opens the picker.
class LensTitle extends StatelessWidget {
  const LensTitle({super.key, required this.entry, required this.color, this.onTap});

  final LensEntry entry;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final title = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: ConnectionAwareTitle(title: entry.title, glow: onTap == null ? null : color)),
        if (onTap != null) Icon(Icons.expand_more_rounded, color: color),
      ],
    );
    if (onTap == null) return Align(alignment: Alignment.centerLeft, child: title);
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        label: 'Chat folder: ${entry.title}. Double tap to switch',
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4), child: title),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: `lens_picker.dart`**

```dart
import 'package:flutter/material.dart';

import '../../../../core/theme/glow_colors.dart';
import '../../../../core/theme/motion.dart';
import '../../../../core/widgets/glow_sheet.dart';
import '../../domain/lens_entry.dart';
import 'chat_list_extensions.dart';

/// The lens panel that drops from the header: every lens with its unread
/// glow, "+N new" for shared folders, suggestions, New / Edit folders.
/// Returns the picked index, or null.
Future<int?> showLensPicker(BuildContext context, {required List<LensEntry> entries, required int current}) {
  final ext = ChatListExtensions.of(context);
  final animate = Motion.ambientEnabled(context);
  return showGeneralDialog<int>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close folders',
    barrierColor: Colors.black54,
    transitionDuration: Motion.standard,
    transitionBuilder: (context, a, _, child) {
      final curved = CurvedAnimation(parent: a, curve: Motion.enter, reverseCurve: Motion.exit);
      final faded = FadeTransition(opacity: curved, child: child);
      if (!animate) return faded;
      return SlideTransition(
        position: Tween(begin: const Offset(0, -0.08), end: Offset.zero).animate(curved),
        child: faded,
      );
    },
    pageBuilder: (dialogContext, _, _) => SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 56, 12, 12),
          child: _Panel(entries: entries, current: current, ext: ext, outer: context),
        ),
      ),
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.entries, required this.current, required this.ext, required this.outer});

  final List<LensEntry> entries;
  final int current;
  final ChatListExtensions ext;
  final BuildContext outer;

  @override
  Widget build(BuildContext context) {
    final hasFolders = entries.any((e) => e.folderId != null);
    final newFolder = ext.newFolder(outer);
    final manage = ext.manageFolders(outer);
    final listenable = ext.lensListenable;
    Widget rows() => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < entries.length; i++)
          _LensRow(entry: entries[i], selected: i == current, ext: ext, outer: outer, index: i),
      ],
    );
    return Material(
      color: GlowColors.surfaceHigh,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 420, maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (listenable == null) rows() else ListenableBuilder(listenable: listenable, builder: (_, _) => rows()),
              if (!hasFolders) _Suggestions(ext: ext),
              if (newFolder != null || manage != null) const Divider(height: 16, color: GlowColors.outline),
              if (newFolder != null)
                ListTile(
                  leading: const Icon(Icons.add_rounded, color: GlowColors.cyan),
                  title: const Text('New folder'),
                  onTap: () {
                    Navigator.of(context).pop();
                    newFolder();
                  },
                ),
              if (manage != null)
                ListTile(
                  leading: const Icon(Icons.tune_rounded),
                  title: const Text('Edit folders'),
                  onTap: () {
                    Navigator.of(context).pop();
                    manage();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LensRow extends StatelessWidget {
  const _LensRow({
    required this.entry,
    required this.selected,
    required this.ext,
    required this.outer,
    required this.index,
  });

  final LensEntry entry;
  final bool selected;
  final ChatListExtensions ext;
  final BuildContext outer;
  final int index;

  Future<void> _actions(BuildContext context) async {
    final actions = ext.lensActions(outer, entry);
    if (actions.isEmpty) return;
    final picked = await showGlowSheet<LensAction>(
      context,
      title: entry.title,
      accent: ext.lensColor(entry),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final a in actions)
              ListTile(
                leading: Icon(a.icon, color: a.destructive ? GlowColors.coral : null),
                title: Text(a.label, style: a.destructive ? const TextStyle(color: GlowColors.coral) : null),
                onTap: () => Navigator.of(context).pop(a),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    Navigator.of(context).pop();
    picked.onSelected(outer);
  }

  @override
  Widget build(BuildContext context) {
    final color = ext.lensColor(entry);
    final fresh = ext.newChatsIn(entry);
    final unread = entry.unread;
    return Material(
      color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(index),
        onLongPress: () => _actions(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.18),
                  boxShadow: selected ? glow(color, intensity: 0.6) : null,
                ),
                child: Icon(ext.lensIcon(entry), size: 18, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
                ),
              ),
              if (fresh > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: ActionChip(
                    label: Text('+$fresh new'),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(color: color),
                    onPressed: () {
                      Navigator.of(context).pop();
                      ext.openNewChats(outer, entry);
                    },
                  ),
                ),
              if (unread.chats > 0)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  constraints: const BoxConstraints(minWidth: 22),
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: unread.unmuted > 0 ? GlowColors.teal : GlowColors.surface,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    unread.chats > 999 ? '999+' : '${unread.chats}',
                    style: TextStyle(
                      color: unread.unmuted > 0 ? GlowColors.onAccent : GlowColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Telegram's suggested folders as one-tap chips (only when there are no
/// folders yet).
class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.ext});

  final ChatListExtensions ext;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LensSuggestion>>(
      future: ext.suggestions(),
      builder: (context, snap) {
        final items = snap.data ?? const [];
        if (items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in items)
                Tooltip(
                  message: s.description,
                  child: ActionChip(
                    avatar: const Icon(Icons.add_rounded, size: 16),
                    label: Text(s.title),
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await s.onAdd();
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 6: `chat_list_page.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/storage/app_preferences.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/luminous_refresh.dart';
import '../../bloc/chat_list_cubit.dart';
import '../../data/chats_repository.dart';
import '../../domain/lens_entry.dart';
import 'chat_actions_sheet.dart';
import 'chat_list_extensions.dart';
import 'timeline_chat_row.dart';

/// One lens page: its own chat list, kept alive while swiping so each page
/// keeps its scroll position.
class ChatListPage extends StatefulWidget {
  const ChatListPage({
    super.key,
    required this.entry,
    required this.isBot,
    required this.tint,
    required this.onOpen,
  });

  final LensEntry entry;
  final bool isBot;
  final Color? tint;
  final void Function(td.Chat chat) onOpen;

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> with AutomaticKeepAliveClientMixin {
  late final ChatListCubit _cubit = ChatListCubit(
    repository: context.read<ChatsRepository>(),
    prefs: context.read<AppPreferences>(),
    list: widget.entry.list,
  )..start();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  Widget _empty(BuildContext context) {
    final e = widget.entry;
    final edit = e.folderId == null ? null : ChatListExtensions.of(context).editFolder(context, e);
    final text = widget.isBot
        ? 'No chats yet. Chats appear here when someone messages your bot.'
        : e.isArchive
        ? 'No archived chats'
        : e.isMain
        ? 'No chats yet. Tap the orb to start one.'
        : 'No chats in ${e.title} yet';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: GlowColors.textMuted)),
            if (edit != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(onPressed: edit, icon: const Icon(Icons.edit_rounded), label: const Text('Edit folder')),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return BlocProvider.value(
      value: _cubit,
      child: BlocBuilder<ChatListCubit, ChatListState>(
        builder: (context, state) {
          if (state.chats.isEmpty) {
            return state.loading
                ? const Center(child: CircularProgressIndicator(color: GlowColors.violet))
                : _empty(context);
          }
          return LuminousRefresh(
            onRefresh: _cubit.refresh,
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.extentAfter < 600) _cubit.loadMore();
                return false;
              },
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 120),
                itemCount: state.chats.length,
                itemBuilder: (context, i) {
                  final chat = state.chats[i];
                  return TimelineChatRow(
                    key: ValueKey(chat.id),
                    chat: chat,
                    isFirst: i == 0,
                    isLast: i == state.chats.length - 1,
                    showPresence: !widget.isBot,
                    tint: widget.tint,
                    onTap: () => widget.onOpen(chat),
                    onLongPress: () => showChatActions(context, chat, list: widget.entry.list),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 7: `chats_screen.dart`**

1. Imports: add `../../../../core/telegram/internal_links.dart`, `../../bloc/lens_cubit.dart`, `../../domain/lens_entry.dart`, `../widgets/chat_list_page.dart`, `../widgets/lens_picker.dart`, `../widgets/lens_title.dart`. Remove now-unused imports (`chat_list_cubit.dart`, `luminous_refresh.dart`, `timeline_chat_row.dart`, `chat_actions_sheet.dart`) if the analyzer flags them.

2. In `_ChatsScreenState` add:

```dart
  late final PageController _pages = PageController(initialPage: context.read<LensCubit>().state.index);
```

and `_pages.dispose();` in `dispose()`.

3. Add methods:

```dart
  Future<void> _pickLens(LensState lens) async {
    ChatListExtensions.of(context).onLensOpened();
    final picked = await showLensPicker(context, entries: lens.entries, current: lens.index);
    if (picked != null && mounted) context.read<LensCubit>().select(picked);
  }

  Future<void> _submitSearch(String q) async {
    try {
      final links = context.read<InternalLinks>();
      if (links.canOpen(q)) {
        setState(() {
          _searching = false;
          _search.clear();
          _results = null;
        });
        await links.tryOpen(context, q);
      }
    } on ProviderNotFoundException {
      // No in-app link handlers in this build.
    }
  }
```

4. Replace the whole `return Scaffold(...)` in `build` with:

```dart
    final ext = ChatListExtensions.of(context);
    return BlocConsumer<LensCubit, LensState>(
      listenWhen: (a, b) => a.index != b.index,
      listener: (context, lens) {
        if (_pages.hasClients && (_pages.page ?? -1).round() != lens.index) _pages.jumpToPage(lens.index);
      },
      builder: (context, lens) {
        final current = lens.current;
        final many = lens.entries.length > 1;
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: _searching
                            ? TextField(
                                controller: _search,
                                autofocus: true,
                                onChanged: _onQuery,
                                onSubmitted: _submitSearch,
                                decoration: const InputDecoration(
                                  hintText: 'Search chats and people',
                                  border: InputBorder.none,
                                ),
                              )
                            : current == null
                            ? const SizedBox.shrink()
                            : LensTitle(
                                entry: current,
                                color: ext.lensColor(current),
                                onTap: many ? () => _pickLens(lens) : null,
                              ),
                      ),
                      if (!_searching) ...ext.headerActions(context),
                      IconButton(
                        tooltip: _searching ? 'Close search' : 'Search',
                        icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
                        onPressed: () => setState(() {
                          _searching = !_searching;
                          _search.clear();
                          _results = null;
                        }),
                      ),
                    ],
                  ),
                ),
                if (isBot && !_botNoticeDismissed)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Dismissible(
                      key: const ValueKey('bot-limits'),
                      onDismissed: (_) => setState(() => _botNoticeDismissed = true),
                      child: BotLimitationsCard(caps!.limitations),
                    ),
                  ),
                Expanded(
                  child: _results != null
                      ? _ResultsList(
                          results: _results!,
                          messageHits: _messageHits,
                          query: _search.text.trim(),
                          onOpen: _open,
                          onOpenMessage: (hit) => Navigator.of(
                            context,
                          ).push(ConversationScreen.route(hit.chatId, focusMessageId: hit.messageId)),
                        )
                      : PageView.custom(
                          controller: _pages,
                          onPageChanged: context.read<LensCubit>().select,
                          childrenDelegate: SliverChildBuilderDelegate(
                            (context, i) {
                              final e = lens.entries[i];
                              return ChatListPage(
                                key: ValueKey(e.key),
                                entry: e,
                                isBot: isBot,
                                tint: many ? ext.lensColor(e) : null,
                                onOpen: _open,
                              );
                            },
                            childCount: lens.entries.length,
                            findChildIndexCallback: (key) {
                              final k = (key as ValueKey<String>).value;
                              final i = lens.entries.indexWhere((e) => e.key == k);
                              return i < 0 ? null : i;
                            },
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
```

- [ ] **Step 8: `home_shell.dart` provides the lens**

Replace the `BlocProvider(create: (context) => ChatListCubit(...)..start(), …)` with:

```dart
    return BlocProvider(
      create: (context) => LensCubit(
        cache: context.read<TelegramCache>(),
        isBot: switch (context.read<AuthBloc>().state.step) {
          AuthReady(:final capabilities) => capabilities.isBot,
          _ => false,
        },
      ),
```

Imports: replace `../../../chats/bloc/chat_list_cubit.dart`, `../../../chats/data/chats_repository.dart`, `../../../../core/storage/app_preferences.dart` (if now unused) with `../../../chats/bloc/lens_cubit.dart`, `../../../../core/telegram/telegram_cache.dart`, `../../../auth/bloc/auth_bloc.dart`, `../../../auth/domain/auth_step.dart`.

- [ ] **Step 9: Run tests and analyzer**

Run: `flutter test test/features/chats` then `flutter analyze` then `flutter test`
Expected: all pass; no new analyzer issues.

- [ ] **Step 10: Commit**

```bash
dart format lib/core/telegram/widgets/connection_status.dart lib/features/chats/presentation lib/features/home/presentation/screens/home_shell.dart test/features/chats/lens_picker_test.dart
git add lib/core/telegram/widgets/connection_status.dart lib/features/chats/presentation/widgets/lens_title.dart lib/features/chats/presentation/widgets/lens_picker.dart lib/features/chats/presentation/widgets/chat_list_page.dart lib/features/chats/presentation/screens/chats_screen.dart lib/features/home/presentation/screens/home_shell.dart test/features/chats/lens_picker_test.dart
git commit -m "Chats: the lens: glowing folder title, picker, swipeable pages

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Palette, Edit folders screen and FolderManagerCubit

**Files:**
- Create: `lib/features/folders/presentation/folder_palette.dart`
- Create: `lib/features/folders/bloc/folder_manager_cubit.dart`
- Create: `lib/features/folders/presentation/screens/folder_manager_screen.dart`
- Test: `test/features/folders/folder_palette_test.dart`, `test/features/folders/folder_manager_cubit_test.dart`

**Interfaces:**
- Consumes: `FoldersRepository` (Task 4), `TelegramCache.chatFolders/mainListPosition/folderTagsEnabled`, `FoldersChanged` (Task 1), `folderErrorText` (Task 3).
- Produces:
  - `abstract final class FolderPalette { static const choices; static Color colorOf(int colorId, {required int position}); static IconData iconOf(String? name); static const iconNames; }` where `choices` is `List<({int colorId, Color color, String label})>`.
  - `class ManagerRow { const ManagerRow(this.folder); final td.ChatFolderInfo? folder; bool get isMain; }`
  - `class FolderManagerState { rows, tagsEnabled, recommended, error }`
  - `class FolderManagerCubit { FolderManagerCubit({required FoldersRepository repository, required TelegramCache cache}); Future<void> load(); Future<void> reorder(int oldIndex, int newIndex); Future<void> delete(int id, {List<int> leave}); Future<void> addRecommended(td.RecommendedChatFolder r); Future<void> setTags(bool on); }`
  - `class FolderManagerScreen { static Route<void> route(); }`

- [ ] **Step 1: Write the failing tests**

`test/features/folders/folder_palette_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/theme/glow_colors.dart';
import 'package:lumina/features/folders/presentation/folder_palette.dart';

void main() {
  test('Telegram colour ids map to glow colours; blue folds into cyan', () {
    expect(FolderPalette.colorOf(0, position: 0), GlowColors.coral);
    expect(FolderPalette.colorOf(1, position: 0), GlowColors.amber);
    expect(FolderPalette.colorOf(2, position: 0), GlowColors.violet);
    expect(FolderPalette.colorOf(3, position: 0), GlowColors.teal);
    expect(FolderPalette.colorOf(4, position: 0), GlowColors.cyan);
    expect(FolderPalette.colorOf(5, position: 0), GlowColors.cyan);
    expect(FolderPalette.colorOf(6, position: 0), GlowColors.magenta);
  });

  test('no colour: picked by position, cycling the palette', () {
    final n = FolderPalette.choices.length;
    expect(FolderPalette.colorOf(-1, position: 0), FolderPalette.choices[0].color);
    expect(FolderPalette.colorOf(-1, position: n + 1), FolderPalette.choices[1].color);
  });

  test('icons: known names map, unknown falls back to a folder', () {
    expect(FolderPalette.iconOf('Work'), Icons.work_rounded);
    expect(FolderPalette.iconOf('Nope'), Icons.folder_rounded);
    expect(FolderPalette.iconOf(null), Icons.folder_rounded);
  });
}
```

`test/features/folders/folder_manager_cubit_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/folders/bloc/folder_manager_cubit.dart';
import 'package:lumina/features/folders/data/folders_repository.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';
import 'folders_repository_test.dart' show info;

void main() {
  late FakeTdClient client;
  late TelegramCache cache;
  late FoldersRepository repo;

  setUp(() {
    client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.GetRecommendedChatFolders() => const td.RecommendedChatFolders(chatFolders: []),
        _ => const td.Ok(),
      };
    cache = TelegramCache.detached()
      ..apply(td.UpdateChatFolders(chatFolders: [info(3), info(5)], mainChatListPosition: 0, areTagsEnabled: false));
    repo = FoldersRepository(client: client, cache: cache, prefs: AppPreferences.inMemory());
  });

  Future<void> premium() async {
    client.emitUpdate(const td.UpdateOption(name: 'is_premium', value: td.OptionValueBoolean(value: true)));
    await Future<void>.delayed(Duration.zero);
  }

  test('rows put All chats at its position', () async {
    final c = FolderManagerCubit(repository: repo, cache: cache);
    await c.load();
    expect(c.state.rows.map((r) => r.folder?.id), [null, 3, 5]);
    await c.close();
  });

  test('reorder keeps All chats where it was dropped', () async {
    await premium();
    final c = FolderManagerCubit(repository: repo, cache: cache);
    await c.load();
    await c.reorder(0, 2); // ReorderableListView: drop All chats after "3"
    final r = client.sentOf<td.ReorderChatFolders>().single;
    expect((r.chatFolderIds, r.mainChatListPosition), (const [3, 5], 1));
    expect(c.state.rows.map((r) => r.folder?.id), [3, null, 5]);
    await c.close();
  });

  test('without Premium All chats stays first', () async {
    final c = FolderManagerCubit(repository: repo, cache: cache);
    await c.load();
    await c.reorder(0, 2);
    expect(client.sentOf<td.ReorderChatFolders>(), isEmpty);
    expect(c.state.error, 'Moving All chats needs Telegram Premium');
    expect(c.state.rows.map((r) => r.folder?.id), [null, 3, 5]);
    await c.close();
  });

  test('folders reorder without Premium', () async {
    final c = FolderManagerCubit(repository: repo, cache: cache);
    await c.load();
    await c.reorder(2, 1);
    final r = client.sentOf<td.ReorderChatFolders>().single;
    expect((r.chatFolderIds, r.mainChatListPosition), (const [5, 3], 0));
    await c.close();
  });

  test('delete passes the chats to leave', () async {
    final c = FolderManagerCubit(repository: repo, cache: cache);
    await c.delete(5, leave: const [9]);
    final d = client.sentOf<td.DeleteChatFolder>().single;
    expect((d.chatFolderId, d.leaveChatIds), (5, const [9]));
    await c.close();
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/folders/folder_palette_test.dart test/features/folders/folder_manager_cubit_test.dart`
Expected: compile errors (files missing).

- [ ] **Step 3: `folder_palette.dart`**

```dart
import 'package:flutter/material.dart';

import '../../../core/theme/glow_colors.dart';

/// Folder glow colours and icons. Telegram colour ids: 0 red, 1 orange,
/// 2 violet, 3 green, 4 cyan, 5 blue, 6 pink; -1 none.
abstract final class FolderPalette {
  static const choices = <({int colorId, Color color, String label})>[
    (colorId: 4, color: GlowColors.cyan, label: 'Cyan'),
    (colorId: 3, color: GlowColors.teal, label: 'Teal'),
    (colorId: 2, color: GlowColors.violet, label: 'Violet'),
    (colorId: 6, color: GlowColors.magenta, label: 'Magenta'),
    (colorId: 1, color: GlowColors.amber, label: 'Amber'),
    (colorId: 0, color: GlowColors.coral, label: 'Coral'),
  ];

  /// [colorId] when set, else a palette colour picked by [position].
  static Color colorOf(int colorId, {required int position}) => switch (colorId) {
    0 => GlowColors.coral,
    1 => GlowColors.amber,
    2 => GlowColors.violet,
    3 => GlowColors.teal,
    4 || 5 => GlowColors.cyan,
    6 => GlowColors.magenta,
    _ => choices[position % choices.length].color,
  };

  /// Telegram's folder icon names (what other apps show and sync).
  static const iconNames = <String, IconData>{
    'All': Icons.forum_rounded,
    'Unread': Icons.mark_chat_unread_rounded,
    'Unmuted': Icons.notifications_active_rounded,
    'Bots': Icons.smart_toy_rounded,
    'Channels': Icons.campaign_rounded,
    'Groups': Icons.groups_rounded,
    'Private': Icons.person_rounded,
    'Custom': Icons.folder_rounded,
    'Setup': Icons.tune_rounded,
    'Cat': Icons.pets_rounded,
    'Crown': Icons.workspace_premium_rounded,
    'Favorite': Icons.star_rounded,
    'Flower': Icons.local_florist_rounded,
    'Game': Icons.sports_esports_rounded,
    'Home': Icons.home_rounded,
    'Love': Icons.favorite_rounded,
    'Mask': Icons.theater_comedy_rounded,
    'Party': Icons.celebration_rounded,
    'Sport': Icons.sports_soccer_rounded,
    'Study': Icons.school_rounded,
    'Trade': Icons.trending_up_rounded,
    'Travel': Icons.luggage_rounded,
    'Work': Icons.work_rounded,
    'Airplane': Icons.flight_rounded,
    'Book': Icons.menu_book_rounded,
    'Light': Icons.lightbulb_rounded,
    'Like': Icons.thumb_up_rounded,
    'Money': Icons.payments_rounded,
    'Note': Icons.sticky_note_2_rounded,
    'Palette': Icons.palette_rounded,
  };

  static IconData iconOf(String? name) => iconNames[name] ?? Icons.folder_rounded;
}
```

- [ ] **Step 4: `folder_manager_cubit.dart`**

```dart
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/telegram/telegram_cache.dart';
import '../data/folders_repository.dart';
import '../domain/folder_errors.dart';

/// A row on the Edit folders screen; a null [folder] is All chats.
class ManagerRow {
  const ManagerRow(this.folder);
  final td.ChatFolderInfo? folder;
  bool get isMain => folder == null;
}

class FolderManagerState {
  const FolderManagerState({
    this.rows = const [],
    this.tagsEnabled = false,
    this.recommended = const [],
    this.error,
  });

  final List<ManagerRow> rows;
  final bool tagsEnabled;
  final List<td.RecommendedChatFolder> recommended;
  final String? error;

  FolderManagerState copyWith({
    List<ManagerRow>? rows,
    bool? tagsEnabled,
    List<td.RecommendedChatFolder>? recommended,
    String? Function()? error,
  }) => FolderManagerState(
    rows: rows ?? this.rows,
    tagsEnabled: tagsEnabled ?? this.tagsEnabled,
    recommended: recommended ?? this.recommended,
    error: error != null ? error() : this.error,
  );
}

class FolderManagerCubit extends Cubit<FolderManagerState> {
  FolderManagerCubit({required this._repository, required this._cache}) : super(const FolderManagerState()) {
    _sub = _cache.events.where((e) => e is FoldersChanged).listen((_) => _fromCache());
    _fromCache();
  }

  final FoldersRepository _repository;
  final TelegramCache _cache;
  late final StreamSubscription<CacheEvent> _sub;

  bool get isPremium => _repository.isPremium;

  void _fromCache() {
    if (isClosed) return;
    final folders = [for (final f in _cache.chatFolders) ManagerRow(f)];
    final at = _cache.mainListPosition.clamp(0, folders.length);
    emit(
      state.copyWith(
        rows: [...folders.take(at), const ManagerRow(null), ...folders.skip(at)],
        tagsEnabled: _cache.folderTagsEnabled,
      ),
    );
  }

  Future<void> load() async {
    _fromCache();
    try {
      final r = await _repository.recommended();
      if (!isClosed) emit(state.copyWith(recommended: r));
    } on Exception {
      // Suggestions are optional.
    }
  }

  /// [newIndex] as ReorderableListView reports it (before removal).
  Future<void> reorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex == oldIndex) return;
    final before = state.rows;
    final rows = [...before];
    rows.insert(newIndex, rows.removeAt(oldIndex));
    final mainAt = rows.indexWhere((r) => r.isMain);
    if (mainAt != 0 && !_repository.isPremium) {
      emit(state.copyWith(error: () => 'Moving All chats needs Telegram Premium'));
      return;
    }
    emit(state.copyWith(rows: rows, error: () => null));
    try {
      await _repository.reorder([for (final r in rows) if (r.folder != null) r.folder!.id], mainAt);
    } catch (e) {
      if (!isClosed) emit(state.copyWith(rows: before, error: () => folderErrorText(e)));
    }
  }

  Future<void> delete(int id, {List<int> leave = const []}) => _guard(() => _repository.delete(id, leaveChatIds: leave));

  Future<List<int>> chatsToLeave(int id) => _repository.chatsToLeave(id);

  Future<void> addRecommended(td.RecommendedChatFolder r) => _guard(() async {
    await _repository.addRecommended(r.folder);
    if (!isClosed) emit(state.copyWith(recommended: [...state.recommended]..remove(r)));
  });

  Future<void> setTags(bool on) => _guard(() => _repository.setTagsEnabled(on));

  Future<void> _guard(Future<void> Function() action) async {
    try {
      emit(state.copyWith(error: () => null));
      await action();
    } catch (e) {
      if (!isClosed) emit(state.copyWith(error: () => folderErrorText(e)));
    }
  }

  @override
  Future<void> close() async {
    await _sub.cancel();
    return super.close();
  }
}
```

- [ ] **Step 5: `folder_manager_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/glow_background.dart';
import '../../../../core/widgets/glow_sheet.dart';
import '../../bloc/folder_manager_cubit.dart';
import '../../data/folders_repository.dart';
import '../folder_palette.dart';
import 'folder_editor_screen.dart';

/// Edit folders: reorder (All chats included), delete, suggestions, tags.
class FolderManagerScreen extends StatelessWidget {
  const FolderManagerScreen({super.key});

  static Route<void> route() => MaterialPageRoute(
    builder: (context) => BlocProvider(
      create: (context) =>
          FolderManagerCubit(repository: context.read<FoldersRepository>(), cache: context.read<TelegramCache>())
            ..load(),
      child: const FolderManagerScreen(),
    ),
  );

  Future<void> _delete(BuildContext context, td.ChatFolderInfo f) async {
    final cubit = context.read<FolderManagerCubit>();
    final joined = f.isShareable && !f.hasMyInviteLinks;
    var leave = <int>{};
    var candidates = const <int>[];
    if (joined) {
      try {
        candidates = await cubit.chatsToLeave(f.id);
        leave = {...candidates};
      } on Exception {
        candidates = const [];
      }
    }
    if (!context.mounted) return;
    final cache = context.read<TelegramCache>();
    final ok = await showGlowConfirm(
      context,
      title: 'Delete “${f.name.text.text}”?',
      message: candidates.isEmpty ? 'Its chats stay in All chats.' : 'Also leave these chats?',
      confirmLabel: 'Delete folder',
      icon: Icons.folder_delete_rounded,
      destructive: true,
      body: candidates.isEmpty
          ? null
          : (context) => StatefulBuilder(
              builder: (context, setState) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final id in candidates)
                    CheckboxListTile(
                      dense: true,
                      value: leave.contains(id),
                      title: Text(cache.chats[id]?.title ?? 'Chat'),
                      onChanged: (v) => setState(() => v! ? leave.add(id) : leave.remove(id)),
                    ),
                ],
              ),
            ),
    );
    if (ok) await cubit.delete(f.id, leave: leave.toList());
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<FoldersRepository>();
    return BlocConsumer<FolderManagerCubit, FolderManagerState>(
      listenWhen: (a, b) => b.error != null && a.error != b.error,
      listener: (context, s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.error!))),
      builder: (context, s) {
        final cubit = context.read<FolderManagerCubit>();
        final cache = context.read<TelegramCache>();
        return Scaffold(
          appBar: AppBar(backgroundColor: GlowColors.background, title: const Text('Folders')),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: GlowColors.violetDeep,
            onPressed: () => Navigator.of(context).push(FolderEditorScreen.route()),
            icon: const Icon(Icons.add_rounded),
            label: const Text('New folder'),
          ),
          body: GlowBackground(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  sliver: SliverReorderableList(
                    itemCount: s.rows.length,
                    onReorder: cubit.reorder,
                    itemBuilder: (context, i) {
                      final row = s.rows[i];
                      final f = row.folder;
                      final color = f == null
                          ? GlowColors.violet
                          : FolderPalette.colorOf(
                              repo.colorIdOf(f),
                              position: cache.chatFolders.indexWhere((x) => x.id == f.id),
                            );
                      return Card(
                        key: ValueKey(f?.id ?? 'main'),
                        color: GlowColors.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: BorderSide(color: color.withValues(alpha: 0.5)),
                        ),
                        child: ListTile(
                          leading: Icon(f == null ? Icons.forum_rounded : FolderPalette.iconOf(f.icon.name), color: color),
                          title: Text(f == null ? 'All chats' : f.name.text.text),
                          subtitle: f == null
                              ? null
                              : Text(f.isShareable ? (f.hasMyInviteLinks ? 'Shared by you' : 'Shared folder') : 'Folder'),
                          onTap: f == null
                              ? null
                              : () => Navigator.of(context).push(FolderEditorScreen.route(folderId: f.id)),
                          onLongPress: f == null ? null : () => _delete(context, f),
                          trailing: ReorderableDragStartListener(
                            index: i,
                            child: const Icon(Icons.drag_handle_rounded, color: GlowColors.textMuted),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(24, 8, 24, 0),
                    child: Text(
                      'Drag to reorder. Long-press a folder to delete it.',
                      style: TextStyle(color: GlowColors.textMuted, fontSize: 12),
                    ),
                  ),
                ),
                if (s.recommended.isNotEmpty)
                  SliverList.list(
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(24, 24, 24, 8),
                        child: Text('SUGGESTED', style: TextStyle(color: GlowColors.violet, fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                      for (final r in s.recommended)
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                          leading: Icon(FolderPalette.iconOf(r.folder.icon?.name), color: GlowColors.cyan),
                          title: Text(r.folder.name.text.text),
                          subtitle: Text(r.description),
                          trailing: TextButton(onPressed: () => cubit.addRecommended(r), child: const Text('Add')),
                        ),
                    ],
                  ),
                if (cubit.isPremium)
                  SliverToBoxAdapter(
                    child: SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                      value: s.tagsEnabled,
                      onChanged: cubit.setTags,
                      title: const Text('Folder tags'),
                      subtitle: const Text('Show which folders a chat is in, next to its name'),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
        );
      },
    );
  }
}
```

(`FolderEditorScreen` is created in Task 9. To keep this task compiling, create a stub `lib/features/folders/presentation/screens/folder_editor_screen.dart` now:

```dart
import 'package:flutter/material.dart';

class FolderEditorScreen extends StatelessWidget {
  const FolderEditorScreen({super.key});

  static Route<void> route({int? folderId}) => MaterialPageRoute(builder: (_) => const FolderEditorScreen());

  @override
  Widget build(BuildContext context) => const Scaffold();
}
```

Task 9 replaces it completely.)

- [ ] **Step 6: Run tests and analyzer**

Run: `flutter test test/features/folders` then `flutter analyze`
Expected: pass; no new issues.

- [ ] **Step 7: Commit**

```bash
dart format lib/features/folders test/features/folders
git add lib/features/folders/presentation/folder_palette.dart lib/features/folders/bloc/folder_manager_cubit.dart lib/features/folders/presentation/screens/folder_manager_screen.dart lib/features/folders/presentation/screens/folder_editor_screen.dart test/features/folders/folder_palette_test.dart test/features/folders/folder_manager_cubit_test.dart
git commit -m "Folders: palette, Edit folders screen (reorder, delete, suggestions, tags)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Folder editor and chat picker

**Files:**
- Create: `lib/features/folders/bloc/folder_editor_cubit.dart`
- Replace: `lib/features/folders/presentation/screens/folder_editor_screen.dart` (the Task 8 stub)
- Create: `lib/features/folders/presentation/screens/chat_picker_screen.dart`
- Test: `test/features/folders/folder_editor_cubit_test.dart`

**Interfaces:**
- Consumes: `FolderDraft` (Task 3), `FoldersRepository.folder/create/edit/localColor/defaultIconName/searchChats` (Task 4), `FolderPalette` (Task 8), `TelegramCache.chatsIn`.
- Produces:
  - `class FolderEditorState { FolderDraft draft; bool loading; bool saving; bool changed; bool done; bool deleted; String? error; }`
  - `class FolderEditorCubit { FolderEditorCubit({required FoldersRepository repository, required TelegramCache cache, int? folderId, FolderDraft? initial}); final int? folderId; Future<void> load(); void update(FolderDraft Function(FolderDraft) change); Future<bool> save(); void convertToChatList(); }`
  - `FolderEditorScreen.route({int? folderId, FolderDraft? initial})`
  - `ChatPickerScreen.pick(BuildContext context, {required List<int> initial, String title}) → Future<List<int>?>`

- [ ] **Step 1: Write the failing tests**

`test/features/folders/folder_editor_cubit_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/folders/bloc/folder_editor_cubit.dart';
import 'package:lumina/features/folders/data/folders_repository.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';
import 'folder_draft_test.dart' show folder;
import 'folders_repository_test.dart' show info;

void main() {
  late FakeTdClient client;
  late TelegramCache cache;
  late AppPreferences prefs;
  late FoldersRepository repo;

  setUp(() {
    client = FakeTdClient();
    cache = TelegramCache.detached();
    prefs = AppPreferences.inMemory()..folderColorsJson = '{"3": 6}';
    repo = FoldersRepository(client: client, cache: cache, prefs: prefs);
    client.respond = (f) => switch (f) {
      td.GetChatFolder() => folder(groups: true, included: const [1]).copyWith(colorId: -1),
      td.CreateChatFolder() || td.EditChatFolder() => info(3),
      _ => const td.Ok(),
    };
  });

  test('a new folder is validated before anything is sent', () async {
    final c = FolderEditorCubit(repository: repo, cache: cache);
    await c.load();
    expect(await c.save(), isFalse);
    expect(c.state.error, 'Give the folder a name');
    expect(client.sentOf<td.CreateChatFolder>(), isEmpty);

    c.update((d) => d.copyWith(name: 'Work', includeGroups: true));
    expect(c.state.changed, isTrue);
    expect(await c.save(), isTrue);
    expect(c.state.done, isTrue);
    expect(client.sentOf<td.CreateChatFolder>().single.folder.name.text.text, 'Work');
    await c.close();
  });

  test('editing loads the folder with its local colour and saves by id', () async {
    final c = FolderEditorCubit(repository: repo, cache: cache, folderId: 3);
    await c.load();
    expect(c.state.draft.name, 'Work');
    expect(c.state.draft.colorId, 6);
    c.update((d) => d.copyWith(name: 'Job'));
    await c.save();
    final e = client.sentOf<td.EditChatFolder>().single;
    expect((e.chatFolderId, e.folder.name.text.text), (3, 'Job'));
    await c.close();
  });

  test('a folder deleted elsewhere closes the editor', () async {
    final c = FolderEditorCubit(repository: repo, cache: cache, folderId: 3);
    await c.load();
    client.respond = (f) => const td.TdError(code: 400, message: 'FILTER_ID_INVALID');
    c.update((d) => d.copyWith(name: 'Job'));
    expect(await c.save(), isFalse);
    expect(c.state.deleted, isTrue);
    expect(c.state.error, 'This folder was deleted');
    await c.close();
  });

  test('convert to a chat list keeps the matching chats', () async {
    cache.apply(
      td.UpdateNewChat(
        chat: fakeChat(8).copyWith(
          positions: const [td.ChatPosition(list: td.ChatListFolder(chatFolderId: 3), order: 5, isPinned: false)],
        ),
      ),
    );
    final c = FolderEditorCubit(repository: repo, cache: cache, folderId: 3);
    await c.load();
    c.convertToChatList();
    expect(c.state.draft.hasRules, isFalse);
    expect(c.state.draft.included, [1, 8]);
    await c.close();
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/folders/folder_editor_cubit_test.dart`
Expected: compile error (`folder_editor_cubit.dart` missing).

- [ ] **Step 3: `folder_editor_cubit.dart`**

```dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/telegram/telegram_cache.dart';
import '../data/folders_repository.dart';
import '../domain/folder_draft.dart';
import '../domain/folder_errors.dart';

class FolderEditorState {
  const FolderEditorState({
    this.draft = const FolderDraft.empty(),
    this.loading = true,
    this.saving = false,
    this.changed = false,
    this.done = false,
    this.deleted = false,
    this.error,
  });

  final FolderDraft draft;
  final bool loading;
  final bool saving;
  final bool changed;
  final bool done;
  final bool deleted;
  final String? error;

  FolderEditorState copyWith({
    FolderDraft? draft,
    bool? loading,
    bool? saving,
    bool? changed,
    bool? done,
    bool? deleted,
    String? Function()? error,
  }) => FolderEditorState(
    draft: draft ?? this.draft,
    loading: loading ?? this.loading,
    saving: saving ?? this.saving,
    changed: changed ?? this.changed,
    done: done ?? this.done,
    deleted: deleted ?? this.deleted,
    error: error != null ? error() : this.error,
  );
}

class FolderEditorCubit extends Cubit<FolderEditorState> {
  FolderEditorCubit({required this._repository, required this._cache, this.folderId, FolderDraft? initial})
    : _initial = initial,
      super(const FolderEditorState());

  final FoldersRepository _repository;
  final TelegramCache _cache;
  final FolderDraft? _initial;

  /// Null for a new folder.
  final int? folderId;

  static const _deletedText = 'This folder was deleted';

  Future<void> load() async {
    final id = folderId;
    if (id == null) {
      emit(state.copyWith(draft: _initial ?? const FolderDraft.empty(), loading: false));
      return;
    }
    try {
      var draft = FolderDraft.fromFolder(await _repository.folder(id));
      if (draft.colorId < 0) draft = draft.copyWith(colorId: _repository.localColor(id) ?? -1);
      emit(state.copyWith(draft: draft, loading: false));
    } catch (e) {
      final text = folderErrorText(e);
      emit(state.copyWith(loading: false, error: () => text, deleted: text == _deletedText));
    }
  }

  void update(FolderDraft Function(FolderDraft draft) change) =>
      emit(state.copyWith(draft: change(state.draft), changed: true, error: () => null));

  Future<bool> save() async {
    final invalid = state.draft.validate();
    if (invalid != null) {
      emit(state.copyWith(error: () => invalid));
      return false;
    }
    emit(state.copyWith(saving: true, error: () => null));
    try {
      final id = folderId;
      if (id == null) {
        await _repository.create(state.draft);
      } else {
        await _repository.edit(id, state.draft);
      }
      emit(state.copyWith(saving: false, done: true));
      return true;
    } catch (e) {
      final text = folderErrorText(e);
      emit(state.copyWith(saving: false, error: () => text, deleted: text == _deletedText));
      return false;
    }
  }

  /// Rules → explicit chats, so the folder can be shared.
  void convertToChatList() {
    final id = folderId;
    final matching = id == null
        ? const <int>[]
        : [for (final c in _cache.chatsIn(td.ChatListFolder(chatFolderId: id))) c.id];
    update((d) => d.asChatList(matching));
  }
}
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/features/folders/folder_editor_cubit_test.dart`
Expected: pass.

- [ ] **Step 5: `chat_picker_screen.dart`**

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/chat_avatar.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../data/folders_repository.dart';

/// Multi-select chats (folder include/exclude lists).
class ChatPickerScreen extends StatefulWidget {
  const ChatPickerScreen({super.key, required this.initial, required this.title});

  final List<int> initial;
  final String title;

  static Future<List<int>?> pick(BuildContext context, {required List<int> initial, String title = 'Choose chats'}) =>
      Navigator.of(context).push<List<int>>(
        MaterialPageRoute(builder: (_) => ChatPickerScreen(initial: initial, title: title)),
      );

  @override
  State<ChatPickerScreen> createState() => _ChatPickerScreenState();
}

class _ChatPickerScreenState extends State<ChatPickerScreen> {
  late final Set<int> _selected = {...widget.initial};
  List<int>? _results;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _search(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final ids = q.trim().isEmpty ? null : await context.read<FoldersRepository>().searchChats(q);
      if (mounted) setState(() => _results = ids);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    final ids =
        _results ??
        [
          ...widget.initial,
          for (final c in cache.chatsIn(const td.ChatListMain()))
            if (!widget.initial.contains(c.id)) c.id,
        ];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: GlowColors.background,
        title: Text('${widget.title} (${_selected.length})'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(_selected.toList()), child: const Text('Done')),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              onChanged: _search,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search'),
            ),
          ),
        ),
      ),
      body: ListView.builder(
        itemCount: ids.length,
        itemBuilder: (context, i) {
          final chat = cache.chats[ids[i]];
          if (chat == null) return const SizedBox.shrink();
          return CheckboxListTile(
            value: _selected.contains(chat.id),
            onChanged: (v) => setState(() => v! ? _selected.add(chat.id) : _selected.remove(chat.id)),
            secondary: ChatAvatar.chat(chat, size: 40),
            title: Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 6: `folder_editor_screen.dart` (replaces the stub)**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/chat_avatar.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/glow_background.dart';
import '../../../../core/widgets/glow_sheet.dart';
import '../../bloc/folder_editor_cubit.dart';
import '../../data/folders_repository.dart';
import '../../domain/folder_draft.dart';
import '../folder_palette.dart';
import 'chat_picker_screen.dart';

/// Create or edit a folder: name, icon, glow colour, rules, chats.
class FolderEditorScreen extends StatefulWidget {
  const FolderEditorScreen({super.key});

  static Route<void> route({int? folderId, FolderDraft? initial}) => MaterialPageRoute(
    builder: (context) => BlocProvider(
      create: (context) => FolderEditorCubit(
        repository: context.read<FoldersRepository>(),
        cache: context.read<TelegramCache>(),
        folderId: folderId,
        initial: initial,
      )..load(),
      child: const FolderEditorScreen(),
    ),
  );

  @override
  State<FolderEditorScreen> createState() => _FolderEditorScreenState();
}

class _FolderEditorScreenState extends State<FolderEditorScreen> {
  final _name = TextEditingController();

  /// Set once the user confirmed discarding changes, so the pop goes through.
  var _leaving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickIcon(FolderEditorCubit cubit) async {
    final picked = await showGlowSheet<String>(
      context,
      title: 'Icon',
      accent: FolderPalette.colorOf(cubit.state.draft.colorId, position: 0),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            IconButton.filledTonal(
              tooltip: 'Automatic',
              onPressed: () => Navigator.pop(context, ''),
              icon: const Icon(Icons.auto_awesome_rounded),
            ),
            for (final e in FolderPalette.iconNames.entries)
              IconButton(
                tooltip: e.key,
                isSelected: cubit.state.draft.iconName == e.key,
                onPressed: () => Navigator.pop(context, e.key),
                icon: Icon(e.value),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    cubit.update((d) => d.copyWith(iconName: () => picked.isEmpty ? null : picked));
  }

  Future<void> _pickChats(FolderEditorCubit cubit, {required bool included}) async {
    final d = cubit.state.draft;
    final result = await ChatPickerScreen.pick(
      context,
      initial: included ? d.included : d.excluded,
      title: included ? 'Include chats' : 'Exclude chats',
    );
    if (result == null) return;
    cubit.update((d) => included ? d.copyWith(included: result) : d.copyWith(excluded: result));
  }

  Future<bool> _confirmDiscard() => showGlowConfirm(
    context,
    title: 'Discard your changes?',
    message: 'The folder stays as it was.',
    confirmLabel: 'Discard',
    icon: Icons.undo_rounded,
    destructive: true,
  );

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    return BlocConsumer<FolderEditorCubit, FolderEditorState>(
      listener: (context, s) {
        if (!s.loading && _name.text.isEmpty && s.draft.name.isNotEmpty) _name.text = s.draft.name;
        if (s.done || (s.deleted && s.error != null)) {
          if (s.deleted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.error!)));
          Navigator.of(context).pop();
        }
      },
      builder: (context, s) {
        final cubit = context.read<FolderEditorCubit>();
        final d = s.draft;
        final color = FolderPalette.colorOf(d.colorId, position: 0);
        Widget chatTile(int id, {required bool included}) {
          final chat = cache.chats[id];
          return ListTile(
            leading: chat == null ? const Icon(Icons.chat_rounded) : ChatAvatar.chat(chat, size: 36),
            title: Text(chat?.title ?? 'Chat', maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => cubit.update(
                (d) => included
                    ? d.copyWith(included: d.included.where((x) => x != id).toList())
                    : d.copyWith(excluded: d.excluded.where((x) => x != id).toList()),
              ),
            ),
          );
        }

        FilterChip chip(String label, bool value, FolderDraft Function(FolderDraft, bool) set) =>
            FilterChip(label: Text(label), selected: value, onSelected: (v) => cubit.update((d) => set(d, v)));

        return PopScope(
          canPop: !s.changed || s.done || _leaving,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            if (await _confirmDiscard() && context.mounted) {
              // PopScope reads canPop on rebuild, so pop after the frame.
              setState(() => _leaving = true);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) Navigator.of(context).pop();
              });
            }
          },
          child: Scaffold(
            appBar: AppBar(
              backgroundColor: GlowColors.background,
              title: Text(cubit.folderId == null ? 'New folder' : 'Edit folder'),
              actions: [
                IconButton(
                  tooltip: 'Save',
                  onPressed: s.saving || s.loading ? null : cubit.save,
                  icon: s.saving
                      ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check_rounded),
                ),
              ],
            ),
            body: GlowBackground(
              child: s.loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
                      children: [
                        // Ribbon preview in the chosen colour.
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          height: 6,
                          margin: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.2)]),
                            boxShadow: glow(color, intensity: 0.6),
                          ),
                        ),
                        TextField(
                          controller: _name,
                          maxLength: FolderDraft.maxNameLength,
                          decoration: const InputDecoration(labelText: 'Folder name'),
                          onChanged: (v) => cubit.update((d) => d.copyWith(name: v)),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Icon'),
                          trailing: Icon(FolderPalette.iconOf(d.iconName), color: color),
                          onTap: () => _pickIcon(cubit),
                        ),
                        const SizedBox(height: 8),
                        const Text('Glow', style: TextStyle(color: GlowColors.textMuted)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('None'),
                              selected: d.colorId < 0,
                              onSelected: (_) => cubit.update((d) => d.copyWith(colorId: -1)),
                            ),
                            for (final c in FolderPalette.choices)
                              ChoiceChip(
                                avatar: CircleAvatar(backgroundColor: c.color, radius: 6),
                                label: Text(c.label),
                                selected: d.colorId == c.colorId,
                                onSelected: (_) => cubit.update((d) => d.copyWith(colorId: c.colorId)),
                              ),
                          ],
                        ),
                        if (!context.read<FoldersRepository>().isPremium)
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Text(
                              'Saved on this device. Telegram Premium syncs folder colours.',
                              style: TextStyle(color: GlowColors.textMuted, fontSize: 12),
                            ),
                          ),
                        const _Header('Included chats'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            chip('Contacts', d.includeContacts, (d, v) => d.copyWith(includeContacts: v)),
                            chip('Non-contacts', d.includeNonContacts, (d, v) => d.copyWith(includeNonContacts: v)),
                            chip('Groups', d.includeGroups, (d, v) => d.copyWith(includeGroups: v)),
                            chip('Channels', d.includeChannels, (d, v) => d.copyWith(includeChannels: v)),
                            chip('Bots', d.includeBots, (d, v) => d.copyWith(includeBots: v)),
                          ],
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.add_rounded, color: GlowColors.cyan),
                          title: const Text('Add chats'),
                          onTap: () => _pickChats(cubit, included: true),
                        ),
                        for (final id in d.included) chatTile(id, included: true),
                        const _Header('Excluded chats'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            chip('Muted', d.excludeMuted, (d, v) => d.copyWith(excludeMuted: v)),
                            chip('Read', d.excludeRead, (d, v) => d.copyWith(excludeRead: v)),
                            chip('Archived', d.excludeArchived, (d, v) => d.copyWith(excludeArchived: v)),
                          ],
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.remove_rounded, color: GlowColors.coral),
                          title: const Text('Exclude chats'),
                          onTap: () => _pickChats(cubit, included: false),
                        ),
                        for (final id in d.excluded) chatTile(id, included: false),
                        if (s.error != null && !s.deleted)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(s.error!, style: const TextStyle(color: GlowColors.error)),
                          ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Semantics(
      header: true,
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(color: GlowColors.violet, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.1),
      ),
    ),
  );
}
```

- [ ] **Step 7: Run tests and analyzer**

Run: `flutter test test/features/folders` then `flutter analyze`
Expected: pass; no new issues.

- [ ] **Step 8: Commit**

```bash
dart format lib/features/folders test/features/folders
git add lib/features/folders/bloc/folder_editor_cubit.dart lib/features/folders/presentation/screens/folder_editor_screen.dart lib/features/folders/presentation/screens/chat_picker_screen.dart test/features/folders/folder_editor_cubit_test.dart
git commit -m "Folders: editor (name, icon, glow, rules, chats) and chat picker

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: "Add to folder…" sheet

**Files:**
- Create: `lib/features/folders/presentation/widgets/add_to_folder_sheet.dart`
- Test: `test/features/folders/add_to_folder_sheet_test.dart`

**Interfaces:**
- Consumes: `FoldersRepository.foldersToAddChat/setChatInFolder/colorIdOf` (Task 4), `TelegramCache.chatFolders/foldersOf`, `showGlowSheet` (Task 1b), `FolderPalette`, `FolderEditorScreen.route(initial:)`, `FolderDraft`, `folderErrorText`.
- Produces: `Future<void> showAddToFolderSheet(BuildContext context, td.Chat chat)`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/folders/data/folders_repository.dart';
import 'package:lumina/features/folders/presentation/widgets/add_to_folder_sheet.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';
import 'folder_draft_test.dart' show folder;
import 'folders_repository_test.dart' show info;

void main() {
  testWidgets('ticks add with addChatToList, unticks edit the folder', (tester) async {
    final client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.GetChatListsToAddChat() => const td.ChatLists(chatLists: [td.ChatListFolder(chatFolderId: 3)]),
        td.GetChatFolder() => folder(included: const [1]),
        td.EditChatFolder() => info(5),
        _ => const td.Ok(),
      };
    final cache = TelegramCache.detached()
      ..apply(td.UpdateChatFolders(chatFolders: [info(3), info(5)], mainChatListPosition: 0, areTagsEnabled: false))
      ..apply(
        td.UpdateNewChat(
          chat: fakeChat(1).copyWith(
            positions: const [td.ChatPosition(list: td.ChatListFolder(chatFolderId: 5), order: 3, isPinned: false)],
          ),
        ),
      );
    final repo = FoldersRepository(client: client, cache: cache, prefs: AppPreferences.inMemory());
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [RepositoryProvider.value(value: cache), RepositoryProvider.value(value: repo)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAddToFolderSheet(context, cache.chats[1]!),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('F3'));
    await tester.pumpAndSettle();
    expect(client.sentOf<td.AddChatToList>().single.chatId, 1);
    await tester.tap(find.text('F5'));
    await tester.pumpAndSettle();
    expect(client.sentOf<td.EditChatFolder>().single.folder.excludedChatIds, [1]);
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `flutter test test/features/folders/add_to_folder_sheet_test.dart`
Expected: compile error (file missing).

- [ ] **Step 3: Implement `add_to_folder_sheet.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/glow_sheet.dart';
import '../../data/folders_repository.dart';
import '../../domain/folder_draft.dart';
import '../../domain/folder_errors.dart';
import '../folder_palette.dart';
import '../screens/folder_editor_screen.dart';

/// Chat long-press → "Add to folder…": tick folders in or out.
Future<void> showAddToFolderSheet(BuildContext context, td.Chat chat) => showGlowSheet<void>(
  context,
  title: 'Folders for ${chat.title}',
  builder: (_) => _AddToFolder(chat: chat, outer: context),
);

class _AddToFolder extends StatefulWidget {
  const _AddToFolder({required this.chat, required this.outer});

  final td.Chat chat;
  final BuildContext outer;

  @override
  State<_AddToFolder> createState() => _AddToFolderState();
}

class _AddToFolderState extends State<_AddToFolder> {
  late final FoldersRepository _repo = context.read<FoldersRepository>();
  late final TelegramCache _cache = context.read<TelegramCache>();
  late final Set<int> _in = {..._cache.foldersOf(widget.chat)};
  Set<int>? _addable;
  final _busy = <int>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    _repo.foldersToAddChat(widget.chat.id).then((ids) {
      if (mounted) setState(() => _addable = {...ids});
    }, onError: (_) {
      if (mounted) setState(() => _addable = const {});
    });
  }

  Future<void> _toggle(int folderId, bool add) async {
    setState(() {
      _busy.add(folderId);
      _error = null;
      add ? _in.add(folderId) : _in.remove(folderId);
    });
    try {
      await _repo.setChatInFolder(widget.chat.id, folderId, inFolder: add);
    } catch (e) {
      if (mounted) {
        setState(() {
          add ? _in.remove(folderId) : _in.add(folderId);
          _error = folderErrorText(e);
        });
      }
    } finally {
      if (mounted) setState(() => _busy.remove(folderId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final folders = _cache.chatFolders;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_addable == null) const LinearProgressIndicator(minHeight: 2),
        for (var i = 0; i < folders.length; i++)
          Builder(
            builder: (context) {
              final f = folders[i];
              final inside = _in.contains(f.id);
              final enabled = !_busy.contains(f.id) && (inside || (_addable?.contains(f.id) ?? false));
              final color = FolderPalette.colorOf(_repo.colorIdOf(f), position: i);
              return CheckboxListTile(
                value: inside,
                activeColor: color,
                onChanged: enabled ? (v) => _toggle(f.id, v!) : null,
                secondary: Icon(FolderPalette.iconOf(f.icon.name), color: color),
                title: Text(f.name.text.text),
              );
            },
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text(_error!, style: const TextStyle(color: GlowColors.error)),
          ),
        ListTile(
          leading: const Icon(Icons.create_new_folder_rounded, color: GlowColors.cyan),
          title: const Text('New folder with this chat'),
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(widget.outer).push(
              FolderEditorScreen.route(initial: const FolderDraft.empty().copyWith(included: [widget.chat.id])),
            );
          },
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run the test**

Run: `flutter test test/features/folders/add_to_folder_sheet_test.dart`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
dart format lib/features/folders/presentation/widgets/add_to_folder_sheet.dart test/features/folders/add_to_folder_sheet_test.dart
git add lib/features/folders/presentation/widgets/add_to_folder_sheet.dart test/features/folders/add_to_folder_sheet_test.dart
git commit -m "Folders: Add to folder sheet

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Invite links: cubit, share sheet, QR card

**Files:**
- Create: `lib/features/folders/bloc/folder_links_cubit.dart`
- Create: `lib/features/folders/presentation/widgets/folder_share_sheet.dart`
- Create: `lib/features/folders/presentation/screens/folder_qr_screen.dart`
- Modify: `lib/features/folders/presentation/screens/folder_editor_screen.dart` (Invite links tile)
- Modify: `lib/core/platform/system_channel.dart`, `android/app/src/main/kotlin/dev/lumina/lumina/MainActivity.kt` (`shareText`)
- Test: `test/features/folders/folder_links_cubit_test.dart`

**Interfaces:**
- Consumes: `FoldersRepository.folder/edit/inviteLinks/shareableChats/createLink/editLink/deleteLink` (Task 4), `FolderDraft.canShare/asChatList` (Task 3), `TelegramCache.chatsIn`, glow sheets (Task 1b), `flutter_zxing` (`zx.encodeBarcode`, `EncodeParams`, `Format.qrCode`, `EccLevel`, `pngFromBytes`).
- Produces:
  - `class FolderLinksState { List<td.ChatFolderInviteLink> links; List<int> shareable; bool loading; bool needsConversion; String? error; }`
  - `class FolderLinksCubit { FolderLinksCubit({required FoldersRepository repository, required TelegramCache cache, required int folderId}); Future<void> load(); Future<void> convert(); Future<td.ChatFolderInviteLink?> create(String name, List<int> chatIds); Future<void> edit(td.ChatFolderInviteLink link, String name, List<int> chatIds); Future<void> delete(td.ChatFolderInviteLink link); }`
  - `Future<void> showFolderShareSheet(BuildContext context, {required int folderId, required String title, required Color color})`
  - `FolderQrScreen.route({required String url, required String title, required Color color})`
  - `SystemChannel.shareText(String text) → Future<bool>`

- [ ] **Step 1: Write the failing test**

`test/features/folders/folder_links_cubit_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/folders/bloc/folder_links_cubit.dart';
import 'package:lumina/features/folders/data/folders_repository.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';
import 'folder_draft_test.dart' show folder;
import 'folders_repository_test.dart' show info;

const link = td.ChatFolderInviteLink(inviteLink: 'https://t.me/addlist/abc', name: 'Team', chatIds: [1, 2]);

void main() {
  late FakeTdClient client;
  late FoldersRepository repo;
  late TelegramCache cache;
  var withRules = false;

  setUp(() {
    withRules = false;
    client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.GetChatFolder() => withRules ? folder(groups: true, included: const [1]) : folder(included: const [1, 2]),
        td.GetChatFolderInviteLinks() => const td.ChatFolderInviteLinks(inviteLinks: [link]),
        td.GetChatsForChatFolderInviteLink() => const td.Chats(totalCount: 2, chatIds: [1, 2]),
        td.CreateChatFolderInviteLink() => link,
        td.EditChatFolder() => info(3),
        _ => const td.Ok(),
      };
    cache = TelegramCache.detached();
    repo = FoldersRepository(client: client, cache: cache, prefs: AppPreferences.inMemory());
  });

  test('a shareable folder loads its links and shareable chats', () async {
    final c = FolderLinksCubit(repository: repo, cache: cache, folderId: 3);
    await c.load();
    expect(c.state.needsConversion, isFalse);
    expect(c.state.links.single.name, 'Team');
    expect(c.state.shareable, [1, 2]);
    await c.close();
  });

  test('a folder with rules asks to convert first, then converts', () async {
    withRules = true;
    final c = FolderLinksCubit(repository: repo, cache: cache, folderId: 3);
    await c.load();
    expect(c.state.needsConversion, isTrue);
    expect(client.sentOf<td.GetChatFolderInviteLinks>(), isEmpty);
    withRules = false;
    await c.convert();
    final edited = client.sentOf<td.EditChatFolder>().single.folder;
    expect(edited.includeGroups, isFalse);
    expect(c.state.needsConversion, isFalse);
    await c.close();
  });

  test('create and delete', () async {
    final c = FolderLinksCubit(repository: repo, cache: cache, folderId: 3);
    await c.load();
    await c.create('Team', const [1, 2]);
    expect(client.sentOf<td.CreateChatFolderInviteLink>().single.chatIds, [1, 2]);
    await c.delete(link);
    expect(client.sentOf<td.DeleteChatFolderInviteLink>().single.inviteLink, link.inviteLink);
    await c.close();
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `flutter test test/features/folders/folder_links_cubit_test.dart`
Expected: compile error.

- [ ] **Step 3: `folder_links_cubit.dart`**

```dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/telegram/telegram_cache.dart';
import '../data/folders_repository.dart';
import '../domain/folder_draft.dart';
import '../domain/folder_errors.dart';

class FolderLinksState {
  const FolderLinksState({
    this.links = const [],
    this.shareable = const [],
    this.loading = true,
    this.needsConversion = false,
    this.error,
  });

  final List<td.ChatFolderInviteLink> links;
  final List<int> shareable;
  final bool loading;

  /// The folder has rules or exclusions; Telegram shares only chat lists.
  final bool needsConversion;
  final String? error;

  FolderLinksState copyWith({
    List<td.ChatFolderInviteLink>? links,
    List<int>? shareable,
    bool? loading,
    bool? needsConversion,
    String? Function()? error,
  }) => FolderLinksState(
    links: links ?? this.links,
    shareable: shareable ?? this.shareable,
    loading: loading ?? this.loading,
    needsConversion: needsConversion ?? this.needsConversion,
    error: error != null ? error() : this.error,
  );
}

class FolderLinksCubit extends Cubit<FolderLinksState> {
  FolderLinksCubit({required this._repository, required this._cache, required this.folderId})
    : super(const FolderLinksState());

  final FoldersRepository _repository;
  final TelegramCache _cache;
  final int folderId;

  Future<void> load() => _guard(() async {
    final draft = FolderDraft.fromFolder(await _repository.folder(folderId));
    if (!draft.canShare) {
      emit(state.copyWith(loading: false, needsConversion: true));
      return;
    }
    final links = await _repository.inviteLinks(folderId);
    final shareable = await _repository.shareableChats(folderId);
    emit(state.copyWith(loading: false, needsConversion: false, links: links, shareable: shareable));
  });

  /// Rules → explicit chats, then load the links.
  Future<void> convert() => _guard(() async {
    final draft = FolderDraft.fromFolder(await _repository.folder(folderId));
    final matching = [for (final c in _cache.chatsIn(td.ChatListFolder(chatFolderId: folderId))) c.id];
    await _repository.edit(folderId, draft.asChatList(matching));
    await load();
  });

  Future<td.ChatFolderInviteLink?> create(String name, List<int> chatIds) async {
    td.ChatFolderInviteLink? created;
    await _guard(() async {
      created = await _repository.createLink(folderId, name: name, chatIds: chatIds);
      emit(state.copyWith(links: [...state.links, created!]));
    });
    return created;
  }

  Future<void> edit(td.ChatFolderInviteLink link, String name, List<int> chatIds) => _guard(() async {
    final updated = await _repository.editLink(folderId, link.inviteLink, name: name, chatIds: chatIds);
    emit(state.copyWith(links: [for (final l in state.links) l.inviteLink == link.inviteLink ? updated : l]));
  });

  Future<void> delete(td.ChatFolderInviteLink link) => _guard(() async {
    await _repository.deleteLink(folderId, link.inviteLink);
    emit(state.copyWith(links: state.links.where((l) => l.inviteLink != link.inviteLink).toList()));
  });

  Future<void> _guard(Future<void> Function() action) async {
    try {
      emit(state.copyWith(error: () => null));
      await action();
    } catch (e) {
      if (!isClosed) emit(state.copyWith(loading: false, error: () => folderErrorText(e)));
    }
  }
}
```

- [ ] **Step 4: Run the test**

Run: `flutter test test/features/folders/folder_links_cubit_test.dart`
Expected: pass.

- [ ] **Step 5: `shareText` on the system channel**

`MainActivity.kt` `handle`: before `"sdkInt" ->` add:

```kotlin
            "shareText" -> {
                val share = Intent(Intent.ACTION_SEND)
                    .setType("text/plain")
                    .putExtra(Intent.EXTRA_TEXT, call.argument<String>("text") ?: "")
                result.success(start(Intent.createChooser(share, null)))
            }
```

`system_channel.dart`:

```dart
  /// The system share sheet for plain text.
  Future<bool> shareText(String text) async => (await _ch.invokeMethod<bool>('shareText', {'text': text})) ?? false;
```

- [ ] **Step 6: `folder_qr_screen.dart`**

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

import '../../../../core/theme/glow_colors.dart';

/// A folder invite as a glowing QR card.
class FolderQrScreen extends StatelessWidget {
  const FolderQrScreen({super.key, required this.url, required this.title, required this.color});

  final String url;
  final String title;
  final Color color;

  static Route<void> route({required String url, required String title, required Color color}) =>
      MaterialPageRoute(builder: (_) => FolderQrScreen(url: url, title: title, color: color));

  Uint8List? _png() {
    final r = zx.encodeBarcode(
      contents: url,
      params: EncodeParams(format: Format.qrCode, width: 640, height: 640, margin: 2, eccLevel: EccLevel.medium),
    );
    if (!r.isValid || r.data == null) return null;
    return pngFromBytes(r.data!, r.width ?? 640, r.height ?? 640);
  }

  @override
  Widget build(BuildContext context) {
    final png = _png();
    return Scaffold(
      backgroundColor: GlowColors.backgroundDeep,
      appBar: AppBar(backgroundColor: Colors.transparent, title: Text(title)),
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: glow(color, intensity: 1.2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (png == null)
                const Padding(padding: EdgeInsets.all(48), child: Text('Could not draw the QR code'))
              else
                Semantics(
                  label: 'QR code for $url',
                  child: Image.memory(png, width: 260, height: 260, filterQuality: FilterQuality.none),
                ),
              const SizedBox(height: 12),
              Text(title, style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(url, style: const TextStyle(color: Colors.black54, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: `folder_share_sheet.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/platform/system_channel.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/chat_avatar.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/glow_button.dart';
import '../../../../core/widgets/glow_sheet.dart';
import '../../bloc/folder_links_cubit.dart';
import '../../data/folders_repository.dart';
import '../screens/folder_qr_screen.dart';

/// Share a folder: its invite links (copy, share, QR, edit, revoke) and
/// "New link". Converts a rule-based folder to a chat list first.
Future<void> showFolderShareSheet(
  BuildContext context, {
  required int folderId,
  required String title,
  required Color color,
}) => showGlowSheet<void>(
  context,
  title: 'Share “$title”',
  accent: color,
  builder: (_) => BlocProvider(
    create: (_) => FolderLinksCubit(
      repository: context.read<FoldersRepository>(),
      cache: context.read<TelegramCache>(),
      folderId: folderId,
    )..load(),
    child: _ShareBody(title: title, color: color, outer: context),
  ),
);

class _ShareBody extends StatelessWidget {
  const _ShareBody({required this.title, required this.color, required this.outer});

  final String title;
  final Color color;
  final BuildContext outer;

  Future<void> _editLink(BuildContext context, {td.ChatFolderInviteLink? link}) async {
    final cubit = context.read<FolderLinksCubit>();
    final cache = context.read<TelegramCache>();
    final name = TextEditingController(text: link?.name ?? '');
    final chosen = {...(link?.chatIds ?? cubit.state.shareable)};
    final ok = await showGlowSheet<bool>(
      context,
      title: link == null ? 'New invite link' : 'Edit invite link',
      accent: color,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                maxLength: 32,
                decoration: const InputDecoration(labelText: 'Link name (optional)'),
              ),
              for (final id in cubit.state.shareable)
                CheckboxListTile(
                  value: chosen.contains(id),
                  onChanged: (v) => setState(() => v! ? chosen.add(id) : chosen.remove(id)),
                  secondary: cache.chats[id] == null ? null : ChatAvatar.chat(cache.chats[id]!, size: 32),
                  title: Text(cache.chats[id]?.title ?? 'Chat'),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: GlowButton(
                  label: link == null ? 'Create link' : 'Save',
                  onPressed: chosen.isEmpty ? null : () => Navigator.pop(context, true),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;
    if (link == null) {
      await cubit.create(name.text.trim(), chosen.toList());
    } else {
      await cubit.edit(link, name.text.trim(), chosen.toList());
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FolderLinksCubit, FolderLinksState>(
      builder: (context, s) {
        final cubit = context.read<FolderLinksCubit>();
        if (s.loading) return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
        if (s.needsConversion) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Telegram shares folders that are a plain list of chats. This one picks chats by type or '
                  'excludes some. Convert it to the list of chats it shows right now?',
                  style: TextStyle(color: GlowColors.textMuted),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: GlowButton(label: 'Convert to a chat list', onPressed: cubit.convert),
                ),
                if (s.error != null) Text(s.error!, style: const TextStyle(color: GlowColors.error)),
              ],
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final l in s.links)
              ListTile(
                leading: Icon(Icons.link_rounded, color: color),
                title: Text(l.name.isEmpty ? l.inviteLink : l.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${l.chatIds.length} chats · ${l.inviteLink}', maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => _editLink(context, link: l),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Copy',
                      icon: const Icon(Icons.copy_rounded),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: l.inviteLink));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied')));
                        }
                      },
                    ),
                    IconButton(
                      tooltip: 'Share',
                      icon: const Icon(Icons.share_rounded),
                      onPressed: () => const SystemChannel().shareText(l.inviteLink),
                    ),
                    IconButton(
                      tooltip: 'QR code',
                      icon: const Icon(Icons.qr_code_2_rounded),
                      onPressed: () => Navigator.of(outer).push(
                        FolderQrScreen.route(url: l.inviteLink, title: title, color: color),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Revoke',
                      icon: const Icon(Icons.link_off_rounded, color: GlowColors.coral),
                      onPressed: () async {
                        final ok = await showGlowConfirm(
                          context,
                          title: 'Revoke this link?',
                          message: 'People who already joined keep the folder.',
                          confirmLabel: 'Revoke',
                          icon: Icons.link_off_rounded,
                          destructive: true,
                        );
                        if (ok) await cubit.delete(l);
                      },
                    ),
                  ],
                ),
              ),
            ListTile(
              leading: const Icon(Icons.add_link_rounded, color: GlowColors.cyan),
              title: const Text('New link'),
              onTap: s.shareable.isEmpty ? null : () => _editLink(context),
              subtitle: s.shareable.isEmpty ? const Text('None of these chats can be shared') : null,
            ),
            if (s.error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(s.error!, style: const TextStyle(color: GlowColors.error)),
              ),
          ],
        );
      },
    );
  }
}
```

- [ ] **Step 8: Invite links tile in the editor**

In `folder_editor_screen.dart`, after the excluded chat tiles (`for (final id in d.excluded) chatTile(id, included: false),`) add:

```dart
                        if (cubit.folderId != null) ...[
                          const _Header('Invite links'),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.share_rounded, color: color),
                            title: const Text('Share this folder'),
                            subtitle: const Text('Others can add it and join its chats with one link'),
                            onTap: () => showFolderShareSheet(
                              context,
                              folderId: cubit.folderId!,
                              title: d.name,
                              color: color,
                            ),
                          ),
                        ],
```

and `import '../widgets/folder_share_sheet.dart';`.

- [ ] **Step 9: Verify and commit**

Run: `flutter test test/features/folders` and `flutter analyze`.

```bash
dart format lib/features/folders lib/core/platform/system_channel.dart test/features/folders
git add lib/features/folders/bloc/folder_links_cubit.dart lib/features/folders/presentation/widgets/folder_share_sheet.dart lib/features/folders/presentation/screens/folder_qr_screen.dart lib/features/folders/presentation/screens/folder_editor_screen.dart lib/core/platform/system_channel.dart android/app/src/main/kotlin/dev/lumina/lumina/MainActivity.kt test/features/folders/folder_links_cubit_test.dart
git commit -m "Folders: invite links (create, edit, revoke, share, QR)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Join sheet (links and new chats)

**Files:**
- Create: `lib/features/folders/bloc/join_folder_cubit.dart`
- Create: `lib/features/folders/presentation/widgets/join_folder_sheet.dart`
- Test: `test/features/folders/join_folder_cubit_test.dart`

**Interfaces:**
- Consumes: `FoldersRepository.checkLink/join/processNewChats` (Task 4), `folderErrorText`, glow sheets, `TelegramCache.chats/supergroupOf/chatFolders`.
- Produces:
  - `class JoinFolderState { String title; List<int> chatIds; Set<int> alreadyIn; Set<int> selected; bool existing; bool loading; bool joining; bool done; String? error; }`
  - `class JoinFolderCubit { JoinFolderCubit.link({required FoldersRepository repository, required String url}); JoinFolderCubit.newChats({required FoldersRepository repository, required TelegramCache cache, required int folderId, required List<int> chatIds}); Future<void> load(); void toggle(int chatId); Future<void> join(); Future<void> notNow(); }`
  - `Future<void> showJoinFolderSheet(BuildContext context, {String? url, int? folderId, List<int>? chatIds})`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/folders/bloc/join_folder_cubit.dart';
import 'package:lumina/features/folders/data/folders_repository.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';
import 'folders_repository_test.dart' show info;

void main() {
  late FakeTdClient client;
  late TelegramCache cache;
  late FoldersRepository repo;

  setUp(() {
    client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.CheckChatFolderInviteLink() => td.ChatFolderInviteLinkInfo(
          chatFolderInfo: info(0),
          missingChatIds: const [1, 2],
          addedChatIds: const [3],
        ),
        _ => const td.Ok(),
      };
    cache = TelegramCache.detached()
      ..apply(td.UpdateChatFolders(chatFolders: [info(7)], mainChatListPosition: 0, areTagsEnabled: false));
    repo = FoldersRepository(client: client, cache: cache, prefs: AppPreferences.inMemory());
  });

  test('a link preselects the chats to join and adds the folder', () async {
    final c = JoinFolderCubit.link(repository: repo, url: 'https://t.me/addlist/abc');
    await c.load();
    expect(c.state.title, 'F0');
    expect(c.state.existing, isFalse);
    expect(c.state.chatIds, [1, 2, 3]);
    expect(c.state.alreadyIn, {3});
    expect(c.state.selected, {1, 2});
    c.toggle(2);
    c.toggle(3); // already in: ignored
    await c.join();
    final j = client.sentOf<td.AddChatFolderByInviteLink>().single;
    expect((j.inviteLink, j.chatIds), ('https://t.me/addlist/abc', const [1]));
    expect(c.state.done, isTrue);
  });

  test('an expired link shows why', () async {
    client.respond = (_) => const td.TdError(code: 400, message: 'INVITE_SLUG_EXPIRED');
    final c = JoinFolderCubit.link(repository: repo, url: 'https://t.me/addlist/old');
    await c.load();
    expect(c.state.error, 'This folder link has expired');
  });

  test('new chats: join the ticked ones, or dismiss them all', () async {
    final c = JoinFolderCubit.newChats(repository: repo, cache: cache, folderId: 7, chatIds: const [11, 12]);
    await c.load();
    expect(c.state.title, 'F7');
    c.toggle(12);
    await c.join();
    expect(client.sentOf<td.ProcessChatFolderNewChats>().single.addedChatIds, [11]);

    final d = JoinFolderCubit.newChats(repository: repo, cache: cache, folderId: 7, chatIds: const [11]);
    await d.load();
    await d.notNow();
    expect(client.sentOf<td.ProcessChatFolderNewChats>().last.addedChatIds, isEmpty);
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `flutter test test/features/folders/join_folder_cubit_test.dart`
Expected: compile error.

- [ ] **Step 3: `join_folder_cubit.dart`**

```dart
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/telegram/telegram_cache.dart';
import '../data/folders_repository.dart';
import '../domain/folder_errors.dart';

class JoinFolderState {
  const JoinFolderState({
    this.title = '',
    this.chatIds = const [],
    this.alreadyIn = const {},
    this.selected = const {},
    this.existing = false,
    this.loading = true,
    this.joining = false,
    this.done = false,
    this.error,
  });

  final String title;
  final List<int> chatIds;
  final Set<int> alreadyIn;
  final Set<int> selected;

  /// We already have this folder (joining more of its chats).
  final bool existing;
  final bool loading;
  final bool joining;
  final bool done;
  final String? error;

  JoinFolderState copyWith({
    String? title,
    List<int>? chatIds,
    Set<int>? alreadyIn,
    Set<int>? selected,
    bool? existing,
    bool? loading,
    bool? joining,
    bool? done,
    String? Function()? error,
  }) => JoinFolderState(
    title: title ?? this.title,
    chatIds: chatIds ?? this.chatIds,
    alreadyIn: alreadyIn ?? this.alreadyIn,
    selected: selected ?? this.selected,
    existing: existing ?? this.existing,
    loading: loading ?? this.loading,
    joining: joining ?? this.joining,
    done: done ?? this.done,
    error: error != null ? error() : this.error,
  );
}

/// Joining a folder from a `t.me/addlist` link, or adding the chats the
/// owner of a joined shared folder added since.
class JoinFolderCubit extends Cubit<JoinFolderState> {
  JoinFolderCubit.link({required this._repository, required String url})
    : _url = url,
      _cache = null,
      _folderId = null,
      _newChatIds = const [],
      super(const JoinFolderState());

  JoinFolderCubit.newChats({
    required this._repository,
    required TelegramCache cache,
    required int folderId,
    required List<int> chatIds,
  }) : _url = null,
       _cache = cache,
       _folderId = folderId,
       _newChatIds = chatIds,
       super(const JoinFolderState());

  final FoldersRepository _repository;
  final String? _url;
  final TelegramCache? _cache;
  final int? _folderId;
  final List<int> _newChatIds;

  Future<void> load() async {
    final url = _url;
    if (url == null) {
      final folder = _cache!.chatFolders.where((f) => f.id == _folderId).firstOrNull;
      emit(
        state.copyWith(
          title: folder?.name.text.text ?? 'Folder',
          chatIds: _newChatIds,
          selected: {..._newChatIds},
          existing: true,
          loading: false,
        ),
      );
      return;
    }
    try {
      final info = await _repository.checkLink(url);
      emit(
        state.copyWith(
          title: info.chatFolderInfo.name.text.text,
          chatIds: [...info.missingChatIds, ...info.addedChatIds],
          alreadyIn: {...info.addedChatIds},
          selected: {...info.missingChatIds},
          existing: info.chatFolderInfo.id != 0,
          loading: false,
        ),
      );
    } catch (e) {
      emit(state.copyWith(loading: false, error: () => folderErrorText(e)));
    }
  }

  void toggle(int chatId) {
    if (state.alreadyIn.contains(chatId)) return;
    final next = {...state.selected};
    next.contains(chatId) ? next.remove(chatId) : next.add(chatId);
    emit(state.copyWith(selected: next));
  }

  Future<void> join() => _send(state.selected.toList());

  /// New chats only: dismiss them.
  Future<void> notNow() => _send(const []);

  Future<void> _send(List<int> chatIds) async {
    emit(state.copyWith(joining: true, error: () => null));
    try {
      final url = _url;
      if (url != null) {
        await _repository.join(url, chatIds);
      } else {
        await _repository.processNewChats(_folderId!, chatIds);
      }
      emit(state.copyWith(joining: false, done: true));
    } catch (e) {
      emit(state.copyWith(joining: false, error: () => folderErrorText(e)));
    }
  }
}
```

- [ ] **Step 4: Run the test**

Run: `flutter test test/features/folders/join_folder_cubit_test.dart`
Expected: pass.

- [ ] **Step 5: `join_folder_sheet.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/chat_avatar.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/glow_button.dart';
import '../../../../core/widgets/glow_sheet.dart';
import '../../bloc/join_folder_cubit.dart';
import '../../data/folders_repository.dart';

/// Opened by a `t.me/addlist` link ([url]), or by "+N new" on a joined
/// shared folder ([folderId] and [chatIds]).
Future<void> showJoinFolderSheet(BuildContext context, {String? url, int? folderId, List<int>? chatIds}) {
  final repo = context.read<FoldersRepository>();
  final cache = context.read<TelegramCache>();
  return showGlowSheet<void>(
    context,
    accent: GlowColors.cyan,
    builder: (_) => BlocProvider(
      create: (_) => (url != null
          ? JoinFolderCubit.link(repository: repo, url: url)
          : JoinFolderCubit.newChats(repository: repo, cache: cache, folderId: folderId!, chatIds: chatIds!))
        ..load(),
      child: _JoinBody(isLink: url != null),
    ),
  );
}

class _JoinBody extends StatelessWidget {
  const _JoinBody({required this.isLink});

  final bool isLink;

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    return BlocConsumer<JoinFolderCubit, JoinFolderState>(
      listenWhen: (a, b) => b.done && !a.done,
      listener: (context, s) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.existing ? 'Joined ${s.selected.length} chats' : 'Folder “${s.title}” added')),
        );
      },
      builder: (context, s) {
        final cubit = context.read<JoinFolderCubit>();
        if (s.loading) return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
        if (s.chatIds.isEmpty && s.error != null) {
          return Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.link_off_rounded, color: GlowColors.coral, size: 40),
                const SizedBox(height: 12),
                Text(s.error!, textAlign: TextAlign.center),
              ],
            ),
          );
        }
        final action = !isLink || s.existing
            ? 'Join ${s.selected.length} chat${s.selected.length == 1 ? '' : 's'}'
            : 'Add folder';
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: GlowColors.cyan.withValues(alpha: 0.15),
                  boxShadow: glow(GlowColors.cyan, intensity: 0.7),
                ),
                child: const Icon(Icons.folder_shared_rounded, color: GlowColors.cyan, size: 28),
              ),
              const SizedBox(height: 12),
              Text(s.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              Text(
                isLink ? '${s.chatIds.length} chats' : '${s.chatIds.length} new chats in this folder',
                style: const TextStyle(color: GlowColors.textMuted),
              ),
              const SizedBox(height: 8),
              for (final id in s.chatIds)
                Builder(
                  builder: (context) {
                    final chat = cache.chats[id];
                    final members = chat == null ? null : cache.supergroupOf(chat)?.memberCount;
                    final already = s.alreadyIn.contains(id);
                    return CheckboxListTile(
                      value: already || s.selected.contains(id),
                      onChanged: already ? null : (_) => cubit.toggle(id),
                      secondary: chat == null ? const Icon(Icons.chat_rounded) : ChatAvatar.chat(chat, size: 36),
                      title: Text(chat?.title ?? 'Chat', maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        already ? 'Already joined' : (members == null || members == 0 ? '' : '$members members'),
                      ),
                    );
                  },
                ),
              if (s.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(s.error!, style: const TextStyle(color: GlowColors.error)),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: GlowButton(
                  label: action,
                  busy: s.joining,
                  onPressed: s.joining || (s.existing && s.selected.isEmpty) ? null : cubit.join,
                ),
              ),
              if (!isLink) TextButton(onPressed: s.joining ? null : cubit.notNow, child: const Text('Not now')),
            ],
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 6: Verify and commit**

Run: `flutter test test/features/folders` and `flutter analyze`.

```bash
dart format lib/features/folders test/features/folders
git add lib/features/folders/bloc/join_folder_cubit.dart lib/features/folders/presentation/widgets/join_folder_sheet.dart test/features/folders/join_folder_cubit_test.dart
git commit -m "Folders: join sheet for addlist links and new shared-folder chats

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: Wire folders into the app

**Files:**
- Create: `lib/app/app_chat_list_extensions.dart`
- Create: `lib/features/folders/presentation/widgets/folder_settings.dart`
- Modify: `lib/features/folders/data/folders_repository.dart` (`watchFolders`)
- Modify: `lib/app/feature_wiring.dart` (provider, extensions, link handler, settings entry)
- Modify: `lib/features/proxy/presentation/screens/proxy_scan_screen.dart` (route other in-app links)
- Modify: `lib/core/platform/system_channel.dart`, `MainActivity.kt` (`openLinkSettings`)
- Test: `test/app/app_chat_list_extensions_test.dart`

**Interfaces:**
- Consumes: everything above.
- Produces: `class AppChatListExtensions extends ChatListExtensions { AppChatListExtensions({required FoldersRepository folders, required TelegramCache cache}); }`, `FolderSettings` widget, `FoldersRepository.watchFolders()`, `SystemChannel.openLinkSettings()`.

- [ ] **Step 1: Write the failing test**

`test/app/app_chat_list_extensions_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/app/app_chat_list_extensions.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/core/theme/glow_colors.dart';
import 'package:lumina/features/chats/domain/lens_entry.dart';
import 'package:lumina/features/folders/data/folders_repository.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../features/folders/folders_repository_test.dart' show info;
import '../helpers/fakes.dart';

void main() {
  test('lens colours: Telegram colour, local colour, position, archive', () {
    final cache = TelegramCache.detached()
      ..apply(
        td.UpdateChatFolders(
          chatFolders: [info(1, colorId: 0), info(2), info(3)],
          mainChatListPosition: 0,
          areTagsEnabled: false,
        ),
      );
    final prefs = AppPreferences.inMemory()..folderColorsJson = '{"2": 1}';
    final ext = AppChatListExtensions(
      folders: FoldersRepository(client: FakeTdClient(), cache: cache, prefs: prefs),
      cache: cache,
    );
    LensEntry folder(int i) =>
        LensEntry(list: td.ChatListFolder(chatFolderId: cache.chatFolders[i].id), title: '', folder: cache.chatFolders[i]);
    expect(ext.lensColor(folder(0)), GlowColors.coral);
    expect(ext.lensColor(folder(1)), GlowColors.amber);
    expect(ext.lensColor(folder(2)), GlowColors.violet); // position 2 → third palette colour
    expect(ext.lensColor(const LensEntry(list: td.ChatListArchive(), title: '')), GlowColors.archive);
  });
}
```

(`FolderPalette.choices[2]` is violet, so position 2 → violet.)

- [ ] **Step 2: Run it to see it fail**

Run: `flutter test test/app/app_chat_list_extensions_test.dart`
Expected: compile error.

- [ ] **Step 3: `watchFolders` in `FoldersRepository`**

Add a field `StreamSubscription<CacheEvent>? _foldersSub;`, the method:

```dart
  /// Checks for new shared-folder chats whenever the folder list arrives or
  /// changes (startup included); [refreshNewChats] throttles per folder.
  void watchFolders() => _foldersSub ??= _cache.events
      .where((e) => e is FoldersChanged)
      .listen((_) => refreshNewChats().ignore());
```

and `await _foldersSub?.cancel();` at the start of `dispose()`.

- [ ] **Step 4: `openLinkSettings` on the system channel**

`MainActivity.kt` `handle`, next to `"shareText"`:

```kotlin
            "openLinkSettings" -> {
                val uri = Uri.parse("package:$packageName")
                val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                    Intent(Settings.ACTION_APP_OPEN_BY_DEFAULT_SETTINGS, uri)
                else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, uri)
                result.success(start(intent))
            }
```

`system_channel.dart`:

```dart
  /// Android's "Open by default" page for Lumina (t.me links).
  Future<bool> openLinkSettings() async => (await _ch.invokeMethod<bool>('openLinkSettings')) ?? false;
```

- [ ] **Step 5: `folder_settings.dart`**

```dart
import 'package:flutter/material.dart';

import '../../../../core/platform/system_channel.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../settings/presentation/widgets/settings_section.dart';
import '../screens/folder_manager_screen.dart';

/// Settings → Chats → Folders.
class FolderSettings extends StatelessWidget {
  const FolderSettings({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: 'Folders',
      children: [
        ListTile(
          leading: const Icon(Icons.folder_copy_rounded, color: GlowColors.cyan),
          title: const Text('Chat folders'),
          subtitle: const Text('Create, reorder and share folders'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push(FolderManagerScreen.route()),
        ),
        ListTile(
          leading: const Icon(Icons.open_in_new_rounded),
          title: const Text('Open Telegram links in Lumina'),
          subtitle: const Text(
            'tg:// links already open here. For t.me folder and proxy links from other apps, '
            'turn on Lumina under "Open by default".',
          ),
          onTap: () => const SystemChannel().openLinkSettings(),
        ),
      ],
    );
  }
}
```

(Check that `folders` importing `settings/presentation/widgets/settings_section.dart` matches what other features do; `proxy/presentation/widgets/connection_settings.dart` already imports it, so it is the established pattern.)

- [ ] **Step 6: `app_chat_list_extensions.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../core/telegram/telegram_cache.dart';
import '../core/theme/glow_colors.dart';
import '../core/widgets/glow_sheet.dart';
import '../features/chats/domain/lens_entry.dart';
import '../features/chats/presentation/widgets/chat_list_extensions.dart';
import '../features/folders/data/folders_repository.dart';
import '../features/folders/presentation/folder_palette.dart';
import '../features/folders/presentation/screens/folder_editor_screen.dart';
import '../features/folders/presentation/screens/folder_manager_screen.dart';
import '../features/folders/presentation/widgets/add_to_folder_sheet.dart';
import '../features/folders/presentation/widgets/folder_share_sheet.dart';
import '../features/folders/presentation/widgets/join_folder_sheet.dart';
import '../features/proxy/presentation/widgets/proxy_button.dart';

/// Folders and the proxy button, plugged into the chat list.
class AppChatListExtensions extends ChatListExtensions {
  AppChatListExtensions({required this.folders, required this.cache});

  final FoldersRepository folders;
  final TelegramCache cache;

  @override
  List<Widget> headerActions(BuildContext context) => const [ProxyButton()];

  @override
  Listenable? get lensListenable => folders.newChats;

  int _position(int folderId) => cache.chatFolders.indexWhere((f) => f.id == folderId);

  Color _folderColor(td.ChatFolderInfo f) => FolderPalette.colorOf(folders.colorIdOf(f), position: _position(f.id));

  @override
  Color lensColor(LensEntry entry) {
    final f = entry.folder;
    if (f != null) return _folderColor(f);
    return entry.isArchive ? GlowColors.archive : GlowColors.violet;
  }

  @override
  IconData lensIcon(LensEntry entry) {
    final f = entry.folder;
    return f == null ? super.lensIcon(entry) : FolderPalette.iconOf(f.icon.name);
  }

  @override
  int newChatsIn(LensEntry entry) => folders.newChats.value[entry.folderId]?.length ?? 0;

  @override
  void openNewChats(BuildContext context, LensEntry entry) {
    final ids = folders.newChats.value[entry.folderId];
    if (ids != null) showJoinFolderSheet(context, folderId: entry.folderId, chatIds: ids);
  }

  @override
  List<LensAction> lensActions(BuildContext context, LensEntry entry) {
    final readAll = LensAction(
      label: 'Mark all as read',
      icon: Icons.mark_chat_read_rounded,
      onSelected: (context) => folders.readAll(entry.list).ignore(),
    );
    final f = entry.folder;
    if (f == null) return [readAll];
    final anyUnmuted = cache.chatsIn(entry.list).any((c) => !cache.isMuted(c));
    return [
      LensAction(
        label: 'Edit',
        icon: Icons.edit_rounded,
        onSelected: (context) => Navigator.of(context).push(FolderEditorScreen.route(folderId: f.id)),
      ),
      LensAction(
        label: 'Share',
        icon: Icons.share_rounded,
        onSelected: (context) =>
            showFolderShareSheet(context, folderId: f.id, title: f.name.text.text, color: _folderColor(f)),
      ),
      readAll,
      LensAction(
        label: anyUnmuted ? 'Mute all' : 'Unmute all',
        icon: anyUnmuted ? Icons.notifications_off_rounded : Icons.notifications_rounded,
        onSelected: (context) => folders.setAllMuted(entry.list, muted: anyUnmuted).ignore(),
      ),
      LensAction(
        label: 'Delete',
        icon: Icons.delete_outline_rounded,
        destructive: true,
        onSelected: (context) async {
          final ok = await showGlowConfirm(
            context,
            title: 'Delete “${f.name.text.text}”?',
            message: 'Its chats stay in All chats.',
            confirmLabel: 'Delete folder',
            icon: Icons.folder_delete_rounded,
            destructive: true,
          );
          if (ok) await folders.delete(f.id);
        },
      ),
    ];
  }

  @override
  VoidCallback? newFolder(BuildContext context) =>
      () => Navigator.of(context).push(FolderEditorScreen.route());

  @override
  VoidCallback? manageFolders(BuildContext context) =>
      () => Navigator.of(context).push(FolderManagerScreen.route());

  @override
  VoidCallback? editFolder(BuildContext context, LensEntry entry) {
    final id = entry.folderId;
    return id == null ? null : () => Navigator.of(context).push(FolderEditorScreen.route(folderId: id));
  }

  @override
  Future<List<LensSuggestion>> suggestions() async {
    try {
      return [
        for (final r in await folders.recommended())
          LensSuggestion(
            title: r.folder.name.text.text,
            description: r.description,
            onAdd: () => folders.addRecommended(r.folder),
          ),
      ];
    } on Exception {
      return const [];
    }
  }

  @override
  void onLensOpened() => folders.refreshNewChats().ignore();

  @override
  List<ChatAction> chatActions(td.Chat chat) => [
    ChatAction(
      label: 'Add to folder…',
      icon: Icons.create_new_folder_rounded,
      run: (context) => showAddToFolderSheet(context, chat),
    ),
  ];

  @override
  List<Widget> folderTags(BuildContext context, td.Chat chat) {
    if (!cache.folderTagsEnabled) return const [];
    return [
      for (final id in cache.foldersOf(chat).take(2))
        if (cache.chatFolders.where((f) => f.id == id).firstOrNull case final f?)
          Container(
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: _folderColor(f).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              f.name.text.text,
              style: TextStyle(color: _folderColor(f), fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ),
    ];
  }
}
```

- [ ] **Step 7: `feature_wiring.dart`**

1. Imports: `app_chat_list_extensions.dart`, `../features/folders/data/folders_repository.dart`, `../features/folders/domain/addlist_link.dart`, `../features/folders/presentation/widgets/folder_settings.dart`, `../features/folders/presentation/widgets/join_folder_sheet.dart`. Remove the `proxy_button.dart` import if now unused.
2. Before the `ChatListExtensions` provider:

```dart
  RepositoryProvider<FoldersRepository>(
    lazy: false,
    create: (c) => FoldersRepository(
      client: c.read<TdClient>(),
      cache: c.read<TelegramCache>(),
      prefs: c.read<AppPreferences>(),
    )..watchFolders(),
    dispose: (r) => r.dispose(),
  ),
```

3. Replace `RepositoryProvider<ChatListExtensions>(create: (_) => const _ChatListExtensions()),` with:

```dart
  RepositoryProvider<ChatListExtensions>(
    create: (c) => AppChatListExtensions(folders: c.read<FoldersRepository>(), cache: c.read<TelegramCache>()),
  ),
```

and delete the `_ChatListExtensions` class at the bottom.
4. In `SettingsEntries`, add `SettingsEntry(SettingsCategory.chats, (_) => const FolderSettings(), forBots: false),`.
5. In `appLinkHandlers()` add first:

```dart
  InternalLinkHandler(
    matches: (uri) => addlistSlug(uri.toString()) != null,
    open: (context, uri) => showJoinFolderSheet(context, url: addlistUrl(addlistSlug(uri.toString())!)),
  ),
```

- [ ] **Step 8: The scanner opens folder links too**

In `proxy_scan_screen.dart`, in `_onScan`, replace the "no proxy" branch (`// The camera keeps seeing the same code; say so once.` block) with:

```dart
    InternalLinks? links;
    try {
      links = context.read<InternalLinks>();
    } on ProviderNotFoundException {
      links = null;
    }
    if (links != null && links.canOpen(text)) {
      _done = true;
      final nav = Navigator.of(context);
      nav.pop();
      links.tryOpen(nav.context, text).ignore();
      return;
    }
    // The camera keeps seeing the same code; say so once.
    if (text != _lastRejected) {
      _lastRejected = text;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('That QR code has no proxy or folder link')));
    }
```

Imports: `package:flutter_bloc/flutter_bloc.dart`, `../../../../core/telegram/internal_links.dart`. Title: `'Scan a proxy or folder QR code'`.

- [ ] **Step 9: Verify and commit**

Run: `flutter test` and `flutter analyze`
Expected: all pass, no new issues.

```bash
dart format lib/app lib/features/folders lib/features/proxy/presentation/screens/proxy_scan_screen.dart lib/core/platform/system_channel.dart test/app
git add lib/app/app_chat_list_extensions.dart lib/app/feature_wiring.dart lib/features/folders/data/folders_repository.dart lib/features/folders/presentation/widgets/folder_settings.dart lib/features/proxy/presentation/screens/proxy_scan_screen.dart lib/core/platform/system_channel.dart android/app/src/main/kotlin/dev/lumina/lumina/MainActivity.kt test/app/app_chat_list_extensions_test.dart
git commit -m "Folders: wired into the chat list, settings, links and the QR scanner

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 14: Final verification and docs

**Files:**
- Modify: `docs/AGENT_HANDOFF.md`

- [ ] **Step 1: Full checks**

Run: `flutter analyze` (only the existing `deprecated_member_use` infos), `flutter test` (all pass).

- [ ] **Step 2: Release build and 16 KB check**

Run (from the worktree): `tool/flutter.sh build apk --release --target-platform android-arm64` then `python3 -I tool/check_16kb.py build/app/outputs/flutter-apk/app-release.apk | grep -v '^OK'`
Expected: build succeeds; only the existing 32-bit ffmpeg `warn` lines. (Do not touch the corrupted debug engine jar in `~/.gradle`.)

- [ ] **Step 3: Handoff doc**

In `docs/AGENT_HANDOFF.md` §3 status table add a row:

```markdown
| Chat folders (lens, editor, Add to folder, tags, addlist invites, join sheet) | ✅ | `lib/features/folders/`, `lib/features/chats/presentation/widgets/lens_*`, spec `docs/superpowers/specs/2026-10-26-chat-folders-design.md` |
```

and in §8 "Must verify on a real device" add: lens swipe and picker at 120 Hz; t.me/addlist from another app after enabling "Open by default"; non-Premium folder colours persisting across restarts; joining a shared folder and the "+N new" pill.

- [ ] **Step 4: Commit**

```bash
git add docs/AGENT_HANDOFF.md docs/superpowers/plans/2026-10-26-chat-folders.md
git commit -m "Docs: chat folders status and device checks

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
