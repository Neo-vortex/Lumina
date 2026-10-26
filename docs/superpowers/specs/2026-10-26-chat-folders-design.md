# Chat Folders: Design

Date: 2026-10-26. Branch: `tdlib-own-bindings` (TDLib 1.8.69, `lumina_tdlib`).
Status: approved in conversation, section by section.

## Goal

Full Telegram chat-folder support in Lumina's "Glowing Relaxation" style,
not a copy of Telegram's tab strip: switching, unread counts, Archive,
create / edit / delete / reorder, suggested folders, "Add to folder", folder
tags (Premium) and shareable folder invite links (`t.me/addlist`).

Success: everything a Telegram user can do with folders works in Lumina,
folders stay in sync with other Telegram apps, and the chat list still knows
nothing about the `folders` feature (hooks only, see ARCHITECTURE.md).

Out of scope: custom-emoji rendering inside folder names (shown as text,
preserved on save); the custom-server login option (separate design).

## 1. The lens (chat list)

- **Header:** the title is the current lens ("All chats ▾", "Work ▾",
  "Archive ▾") with a soft glow in the lens colour. The connection status
  replaces it while connecting, as today. Proxy shield and search stay on the
  right.
- **Pages:** a horizontal `PageView`, one page per lens, in Telegram's order:
  All chats at `main_chat_list_position` among the folders, then Archive last.
  Each page has its own `ChatListCubit(list: …)`, created on first visit and
  kept, so scroll positions survive. Pull-to-refresh, search and long-press
  work on every page.
- **Ribbon colour:** the timeline ribbon's thread and nodes take the lens
  colour and cross-fade while swiping. Muted unread nodes stay dim. Archive
  uses a cool, dim slate-violet.
- **Lens picker** (tap the title): a glowing panel dropping from the header.
  One row per lens: icon, name, unread pill (teal when unmuted chats are
  unread, grey when only muted ones are), "+N new" pill for shared folders
  with new chats. The current lens is highlighted. Footer: "+ New folder" and
  "Edit folders". Long-press a folder row: Edit, Share, Mark all as read,
  Mute all / Unmute all, Delete (confirm). Reduced motion: fade instead of
  drop.
- **Folder tags** (Premium, when enabled): up to two small coloured tags on a
  chat row for the other folders the chat is in.
- **No folders:** the lens has All chats and Archive; the picker shows
  Telegram's suggested folders as one-tap chips above "+ New folder".
- **Bots:** no lens, title "Chats" (bots have no folders or archive list).
- **Empty folder page:** "No chats in <name> yet" with an "Edit folder"
  button.

### Colours

The palette chips are cyan, teal, violet, magenta, amber, coral and "none".
A folder's glow is Telegram's `colorId` when set (mapped to the nearest
palette colour), otherwise a locally stored choice, otherwise a palette
colour picked by the folder's position. Telegram only syncs folder colours for
Premium accounts; for others the choice is stored on this device
(`AppPreferences`, keyed by folder id). For Premium accounts a choice is also
written to `colorId`.

## 2. Managing folders

- **Edit folders screen** (lens footer, or Settings → Folders):
  - Your folders as glowing cards (colour dot, icon, name, chat-count summary)
    with drag handles (`reorderChatFolders`, including All chats' position).
  - Delete via swipe or long-press, with a confirmation. Deleting a shared
    folder you joined also asks which of its chats to leave
    (`getChatFolderChatsToLeave`).
  - **Suggested:** `getRecommendedChatFolders`, with a description and "Add".
  - **Folder tags** switch (Premium only, `toggleChatFolderTags`).
  - "+ New folder".
- **Folder editor** (full-screen page, check in the app bar to save, asks
  before discarding changes):
  - **Name:** plain text, max 12 characters. Custom emoji in an existing name
    show as text and are kept unless the name is edited.
  - **Icon:** grid of Telegram's folder icon names; "Auto" uses
    `getChatFolderDefaultIconName`.
  - **Glow colour:** palette chips; a ribbon preview at the top lights up live.
  - **Include:** chips for Contacts, Non-contacts, Groups, Channels, Bots;
    "Add chats" (multi-select chat picker); the included list with remove.
  - **Exclude:** chips for Muted, Read, Archived; "Add chats"; the list.
  - **Invite links** section, only for shareable folders (section 3).
  - **Validation:** a name, and at least one chat or chat type. Telegram's
    limits (10 folders / 100 chats per folder without Premium) are reported
    from its errors, naming the limit; the editor stays open.
- **Chat long-press → "Add to folder…":** a sheet of folders with checkmarks
  (`getChatListsToAddChat` for which ones are possible). Ticking adds the chat
  to the folder's included list and removes it from its excluded list;
  unticking does the reverse. Both are `editChatFolder` calls.

## 3. Shareable folder invites

- **Creating links** (editor → Invite links, or lens long-press → Share):
  - Telegram only shares folders with no chat-type rules and no exclusions. If
    the folder doesn't qualify, Share explains why and offers "Convert to a
    chat list": include the current matching chats explicitly and drop the
    rules, after a confirmation.
  - The share sheet lists `getChatFolderInviteLinks`: name, URL, shared chats;
    actions copy, share (system sheet), QR, edit (name and chats,
    `editChatFolderInviteLink`), revoke (`deleteChatFolderInviteLink`,
    confirm).
  - "New link" (`createChatFolderInviteLink`) picks the chats to share,
    defaulting to every chat that can be shared
    (`getChatsForChatFolderInviteLink`); the others are greyed with the reason.
  - **QR card:** full screen, folder colour glow, QR from flutter_zxing's
    writer, folder name and link.
- **Opening links:** `t.me/addlist/<slug>`, `telegram.me/addlist/<slug>`,
  `tg://addlist?slug=<slug>`, from a message, a paste in search, another app,
  or the QR scanner.
  - `checkChatFolderInviteLink` opens a join sheet: folder name and icon, and
    its chats (avatar, title, member count) with checkboxes. Chats you are in
    are ticked and greyed.
  - New folder: "Add folder" (`addChatFolderByInviteLink` with the ticked
    chats). A folder you have: "Join N chats".
  - Errors (expired or invalid link, folder limit, too many chats) as one line
    in the sheet; Premium limits name the limit.
- **New chats in a joined shared folder:** TDLib has no flag for this
  (`ChatFolderInfo` only says `isShareable` / `hasMyInviteLinks`), so
  `FoldersRepository` asks `getChatFolderNewChats` for each folder that is
  shareable and has no links of ours (i.e. joined, not owned): at startup,
  when the lens picker opens, and at most once per 10 minutes per folder.
  Counts are published as a listenable and reach the chat list through the
  `newChats` hook, shown as a "+N new" pill on the lens row and the Edit
  folders card. Tapping opens the join sheet with the new chats; the answer
  goes to `processChatFolderNewChats`, so "Not now" dismisses them.
- The proxy QR scanner also recognises addlist links and routes them here.

## 4. Architecture

Follows ARCHITECTURE.md: `app → features → core`, features independent,
cross-feature UI through hooks wired in `lib/app`.

### core

- `core/telegram/telegram_cache.dart`:
  - `UpdateChatFolders` → `chatFolders` (`List<ChatFolderInfo>`),
    `mainListPosition`, `folderTagsEnabled`; emits `FoldersChanged`.
  - `UpdateUnreadChatCount` (per `ChatList`) → unread counts; emits
    `UnreadCountChanged(list)`.
  - `foldersOf(chat)`: folder ids from `chat.positions`.
- `core/telegram/internal_links.dart` (new): a registry of handlers
  (`bool canHandle(Uri)`, `Future<void> handle(BuildContext, Uri)`).
  `openLink` asks it first and only then launches a browser. Folders register
  addlist links; proxy links are registered too, so tapping a proxy link in a
  message adds the proxy instead of opening the browser.
- Android: an intent filter for `tg://` (addlist and proxy) on the main
  activity, routed through the same registry. `https://t.me/...` links from
  other apps reach Lumina only if the user enables them in Android's "Open by
  default" settings (we can't verify t.me); Settings → Folders says so.

### chats (stays unaware of folders)

- `LensCubit` (bloc): builds `List<LensEntry>` (All chats, folders, Archive)
  from the cache with unread counts; rebuilds on
  `FoldersChanged` / `UnreadCountChanged`; falls back to All chats if the
  current folder disappears; empty for bots.
- `ChatsScreen`: header lens title and picker, `PageView` of
  `ChatListCubit`s. The proxy-sponsor filter applies to the main list only.
- `TimelineChatRow`: ribbon colour from the lens; folder tags.
- `ChatListExtensions` (hook, extended): `headerActions`, `lensColor(entry)`,
  `lensActions(context, entry)`, `openFolderManager(context)`,
  `newFolder(context)`, `suggestions(context)`, `chatActions(context, chat)`
  (adds "Add to folder…" to the long-press sheet), `folderTag(chat)`,
  `newChats` (listenable map of folder id → new-chat count).

### folders (new feature)

- `data/folders_repository.dart`: all folder TDLib calls listed above, plus
  mark all read (`readChatList`) and mute all (notification settings per chat
  in the folder).
- `data/folder_colors.dart`: local colour choices and the colour resolution
  rule from section 1.
- `domain/`: `FolderDraft` (editable form state and its `ChatFolder`
  conversion, validation, "convert to chat list"), addlist link parsing, and
  error-to-message mapping.
- `bloc/`: `FolderManagerCubit`, `FolderEditorCubit`, `FolderLinksCubit`,
  `JoinFolderCubit`.
- `presentation/`: Edit folders screen, folder editor, chat picker,
  "Add to folder" sheet, share sheet and QR card, join sheet, Settings →
  Folders entry.
- `lib/app/`: an `AppChatListExtensions` wiring folders and proxy into the
  chat list, the internal-link handlers, the Settings entry.

### Errors

- TDLib errors become one-line messages where they happen. Limit errors
  (`CHATLISTS_TOO_MUCH`, `FILTER_INCLUDE_TOO_MUCH`, `FILTER_ID_INVALID`,
  `INVITE_SLUG_EXPIRED`, …) map to readable text naming the limit.
- A network failure while saving keeps the editor open with the changes.
- A folder deleted elsewhere while being edited: save fails with "This folder
  was deleted" and the editor closes.

## 5. Testing

- Cache: folder list, unread counts per list, folder membership from
  positions.
- `LensCubit`: ordering with All chats moved, fallback when the current folder
  is deleted, bots.
- `FolderDraft`: validation, `ChatFolder` building, convert to chat list.
- Addlist link parsing (`tg://`, `t.me`, `telegram.me`, in pasted text and the
  scanner); internal-link routing.
- Error mapping.
- Widget tests with `FakeTdClient`: lens picker, join sheet, editor
  validation.
- Finish with an APK build and `tool/check_16kb.py`.
