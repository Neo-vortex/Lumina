# Lumina × NeoMtProto × Telegram: three-way gap analysis

Date: 2026-11-09. Read-only review; nothing in either repo was changed.

- **Lumina**: `/home/neo/projects/personal/Lumina`, branch `main` at `49b6863`, TDLib 1.8.69
  (layer 232) through `packages/lumina_tdlib`. Custom-server support (`lib/core/custom_server/`,
  `tool/tdlib-patches/custom-server.patch`, the login "Server:" sheet, session backup and the
  contacts feature) is **uncommitted** work in the tree. Another agent is editing contacts and the
  chat-list background right now. Those rows describe the tree as it stood when I read it.
- **Custom server**: `/home/neo/projects/personal/NeoMtProto`. It's a C#/.NET 10 MTProto server that
  Lumina points at (`62.60.191.87:443`). Its commits cover milestone 1 (transport, key exchange,
  login). Everything after that (messaging, chats, files, calls, stories, folders and so on) is
  **uncommitted** (`git status`: `Rpc/*Handlers.cs`, `Storage/*Store.cs` and `Calls/` are untracked).
- **Real Telegram**: the layer-232 API (`NeoMtProto/schema/telegram_api.tl`, vendored from TDLib)
  and the official apps as of late 2026.

Companion docs: [TELEGRAM_GAP_ANALYSIS.md](TELEGRAM_GAP_ANALYSIS.md) compares Lumina with official
Telegram (2026-10-26). This document refreshes the Lumina column where it has moved since then
(folders, profile editing, contacts, the sticker/GIF panel, bots, downloads, wallpapers,
auto-download). It also adds the server dimension.

## How this was checked

1. **Server**: every RPC handler is a `Handle(Api.X req, RpcContext)` method in a `[RpcHandlers]` class
   (`NeoMtProto/Rpc/*.cs`). A Roslyn generator turns these into a `switch` in `RpcDispatcher`
   (`NeoMtProto.Tl.Generator/Generator.cs:95-145`). A method without a handler gets
   **`rpc_error 400 METHOD_NOT_IMPLEMENTED`** (`NeoMtProto/Mtproto/MtConnection.cs:283-288`). I listed
   all handlers and read their bodies, separating real ones from stubs that return empty or `true`
   and do nothing.
2. **Lumina**: I listed every `td.<Function>(` call in `lib/` (184 distinct TDLib functions) and
   mapped each one to the MTProto method TDLib sends. Uncertain mappings were checked in the TDLib
   source at `Lumina/build/tdlib/td/td/telegram/*.cpp`, for example
   `DialogParticipantManager.cpp:846` (`messages.editChatParticipantRank`),
   `StoryManager.cpp:369` (`stories.getStoryReactionsList`), `StickersManager.cpp:244`
   (`messages.getEmojiKeywords`) and `SavedMessagesManager.cpp:101` (`messages.getSavedDialogs`).
3. Nothing was run. No device or E2E test was done for this review. The server's own tests
   (`tests/NeoMtProto.E2E.Chat/Program.cs`, `tests/NeoMtProto.Tests/IntegrationTests.cs`) show what
   its author verified: text chat, reply, edit, read, archive, Saved Messages, delete, background,
   pin, typing, a 1:1 call through the relay and session backup.

### Path prefixes in the Evidence column

- `L:` = `/home/neo/projects/personal/Lumina/lib/`
- `S:` = `/home/neo/projects/personal/NeoMtProto/NeoMtProto/`
- `TD:` = `/home/neo/projects/personal/Lumina/build/tdlib/td/td/telegram/`

### Status words

- **Lumina**: Yes / Partial / No (the UI or code path exists or doesn't).
- **Custom server**: Yes (real implementation) / Partial / **Stub** (answers success or empty but
  does nothing) / **No** (no handler, so `METHOD_NOT_IMPLEMENTED`) / **Rejects** (a handler exists
  but refuses this input, e.g. `MEDIA_INVALID`).
- **Notes** start with one of these verdicts:
  - **WORKS**: Lumina has it and the server supports it.
  - **BROKEN-ON-SERVER**: Lumina has it, but the server doesn't support it.
  - **SILENT**: a BROKEN-ON-SERVER case where no error ever reaches the user. The server
    answers OK and drops or ignores the data.
  - **NO-UI**: the server supports it, but Lumina has no UI.
  - **NEITHER**: only real Telegram has it.

### How failures show up in Lumina

`L:core/tdlib/unsupported_api.dart` (uncommitted) turns `METHOD_NOT_IMPLEMENTED` on a **direct**
TDLib request into a "Not supported by this server" toast. It's wired in
`L:core/tdlib/td_isolate_client.dart:193-197`. Sends are different. TDLib returns the pending
message at once and reports failure later as `updateMessageSendFailed`, so a failed forward, poll
or location shows up as a failed bubble with no toast. `MEDIA_INVALID` isn't on the toast's
marker list either. Anything the server *accepts and ignores* gives no signal at all.

### Server coverage in numbers

The server has handlers for 211 of the 848 methods in layer 232. About 35 of those are empty
stubs (`S:Rpc/SettingsHandlers.cs:196-228`, `S:Rpc/HelpHandlers.cs:56-62`,
`S:Rpc/MessagingHandlers.cs:663-672`).

| Namespace | Handled / in schema | Namespace | Handled / in schema |
|---|---|---|---|
| auth | 7 / 30 | stories | 29 / 33 |
| account | 33 / 128 (many stubs) | phone | 10 / 43 (1:1 calls only) |
| contacts | 10 / 30 | help | 9 / 25 |
| messages | 75 / 261 | updates | 3 / 3 |
| channels | 19 / 58 | photos | 4 / 5 |
| upload | 3 / 8 | folders | 1 / 1 |
| bots, payments, stickers, stats, chatlists, premium | **0** | langpack | 5 / 5 (empty) |

---

## Executive summary: top 10 gaps by user impact

Ranked by how often an everyday user hits the gap and how bad the failure is. Silent failures
rank higher.

1. **Forwarding is broken (also "save to Saved Messages" and sharing a message).** There is no
   `messages.forwardMessages` handler. Lumina's forward sheet (`L:features/conversation/data/messages_repository.dart:224`)
   produces failed bubbles with no explanation. Server work, M.
2. **Scheduled and "send when online" messages go out immediately.** This one is silent.
   `messages.sendMessage`/`sendMedia` never read `schedule_date` (`S:Rpc/MessagingHandlers.cs:189,199`),
   so the recipient gets the message at once. `messages.getScheduledHistory` is missing, so
   Lumina's Scheduled screen (`L:.../messages_repository.dart:282,288`) can't list or edit anything.
   How TDLib reconciles the sender's pending scheduled copy is unverified. Server, M.
3. **Polls, location, live location, contact sharing, venue and dice all fail.** `ToMediaAsync`
   accepts only uploaded or stored photos and documents. Everything else gets `MEDIA_INVALID`
   (`S:Rpc/FileHandlers.cs:151-152`). Lumina has full UI for these (`poll_composer.dart:36`,
   `location_sheet.dart:31-32`, `app_conversation_extensions.dart:383`). `messages.sendVote` is
   missing too. Server, M.
4. **Channel and supergroup messages that arrive while you're offline are probably missed.**
   `updates.getDifference` reads only the per-user box (`S:Rpc/MessagingHandlers.cs:693-717`) and
   never emits `updateChannelTooLong`. Nothing tells TDLib to call `getChannelDifference` for
   channels with new posts. The chat list and background notifications stay stale until the chat
   is opened. I inferred this from the code; it hasn't been checked on a device. Lumina's
   WorkManager "saver" sync is hit hardest. Server, S.
5. **Mute and notification settings, the manual unread mark and contact names don't sync.** All
   silent. Per-chat mutes are saved (`S:Rpc/SettingsHandlers.cs:100`), but every dialog and full
   chat returns an empty `PeerNotifySettings` (`S:Rpc/MessagingHandlers.cs:580`,
   `S:Rpc/UserHandlers.cs:31`, `S:Rpc/ChatHandlers.cs:107,317`), so a new login or device shows
   every chat unmuted. `messages.markDialogUnread` returns `true` and stores nothing
   (`S:Rpc/MessagingHandlers.cs:663`). Contact first and last names are stored but never read
   (`S:Storage/Repos.cs:200`, `S:Rpc/Mapping.cs:63`). Server, S.
6. **Account security is weak.**
   - One login code can be shared by every phone number. `NEO_LOGIN_CODE`/`Auth:LoginCode`
     (`S:ServerOptions.cs:45`, `S:Rpc/LoginCodes.cs:16-21`) means anyone who knows it can sign in
     as any phone number.
   - Without it, the code is only written to the server log.
   - There is no 2FA: `account.getPassword` always says "no password" (`S:Rpc/UserHandlers.cs:62`)
     and there is no `account.updatePasswordSettings`.
   - There is no session list or remote logout (`account.getAuthorizations`/`resetAuthorization`
     are missing).
   - Privacy settings are missing (`account.getPrivacy`/`setPrivacy`). Last seen goes to every
     contact and chat partner (`S:Rpc/Presence.cs:9-13`).

   Server, M. Lumina also lacks the UI for sessions, 2FA management and privacy.
7. **Secret chats fail.** `messages.requestEncryption`, `acceptEncryption` and
   `sendEncrypted*` are missing (only `getDhConfig` exists, for calls, `S:Rpc/CallHandlers.cs:26`).
   `qts` is always 0. Lumina offers "New secret chat" (`L:features/chat_info/data/chat_info_repository.dart:229`).
   Server, L.
8. **Bots don't exist on the server, so all of Lumina's bot work is dead there.** There is no
   `auth.importBotAuthorization` (so bot-token login, `L:features/auth/data/auth_repository.dart:67`,
   fails), no `messages.startBot`, `getBotCallbackAnswer` or `getInlineBotResults`, and no `bots.*`.
   So the welcome card and Start button, inline keyboards (`L:.../inline_keyboard.dart:68`) and
   **GIF search through `@gif`** (`L:features/media_panel/data/media_panel_repository.dart:40`) all
   fail. Server, L. GIF search alone is S if the server gets its own GIF search or a built-in
   `@gif`.
9. **Stickers, GIF panel, custom emoji and emoji search are empty.** All sticker lists are empty
   stubs. `messages.getStickerSet` throws `STICKERSET_INVALID` (`S:Rpc/SettingsHandlers.cs:206-214`).
   There is no `stickers.*` to create packs, no `messages.saveGif`, `getCustomEmojiDocuments`,
   `getEmojiKeywords` or `getEmojiGroups`. Lumina's new media panel
   (`L:features/media_panel/data/media_panel_repository.dart:15-34`) opens onto nothing but local
   emoji. Server, M–L, and it needs sticker content.
10. **Common everyday actions fail one by one.** Each of these Lumina features calls a method the
    server lacks:
    - delete or clear chat history (`messages.deleteHistory`; `L:features/chats/data/chats_repository.dart:106`)
    - cloud drafts (`messages.saveDraft`; `L:.../messages_repository.dart:327`)
    - link previews and Instant View (`messages.getWebPagePreview`/`getWebPage`; `:81`)
    - block user (`contacts.block`; `L:features/profile/data/user_profile_repository.dart:81`)
    - slow mode (`channels.toggleSlowMode`; `L:.../chat_info_repository.dart:161`)
    - admin title (`messages.editChatParticipantRank`; `:152`)
    - read time (`messages.getOutboxReadDate`; `L:.../messages_repository.dart:356`)
    - view-once and "voice listened" (`messages.readMessageContents`; `:495`)
    - channel view counts (`messages.getMessagesViews`)
    - folder share links (all of `chatlists.*`; `L:features/folders/data/folders_repository.dart:150-205`)
    - removing a caption (`editMessage` rejects empty text, `S:Rpc/MessagingHandlers.cs:498`)

    Each is S on the server.

Honourable mentions:
- Photos are stored in one size only (`S:Rpc/Mapping.cs:31-33`), so avatars and previews download
  the full original.
- Story replies and quote replies lose their reference silently (`S:Rpc/MessagingHandlers.cs:245`).
- MTProto proxies most likely route to real Telegram instead of the custom server (unverified).

**Where the server is ahead of Lumina** (the server supports it, Lumina has no UI):
- invite-link management and join requests
- joining by `t.me/+` link
- group and channel photo, public username and allowed reactions
- deleting a channel and upgrading a group
- editing, archiving, pinning and album-sorting stories; stealth mode
- editing close friends and hiding a person's stories
- global server message search, and Saved Messages history by source chat

The server-side work is done for all of these. The app-side work is mostly S each.

---

## 1. Auth and account

| Feature | Lumina | Custom server | Real Telegram | Evidence | Notes |
|---|---|---|---|---|---|
| Phone + code login, sign-up | Yes | Yes | Yes | L:features/auth/data/auth_repository.dart:62,69,77; S:Rpc/AuthHandlers.cs:66,77,89 | **WORKS.** The server always answers `sentCodeTypeApp`. The code is fixed (`NEO_LOGIN_CODE`, S:ServerOptions.cs:45) or only logged (S:Rpc/LoginCodes.cs:16-21); there's no SMS. A shared fixed code lets anyone sign in to any number |
| Resend code / other delivery types | Yes | No | Yes | L:auth_repository.dart:71; no `auth.resendCode`/`cancelCode` handler | **BROKEN-ON-SERVER** (toast). There's no `next_type`, so TDLib may not offer resend (unverified) |
| Country list and number detection | Yes | Stub (empty list) | Yes | L:features/auth/presentation/widgets/country_phone_field.dart:51-70; S:Rpc/HelpHandlers.cs:56 | **SILENT**, handled gracefully: the field works without a picker and without flags |
| 2FA password at login | Yes | No (always "no password") | Yes | L:auth_repository.dart:74; S:Rpc/UserHandlers.cs:62 | **BROKEN-ON-SERVER**, though the step is never reached. No `auth.checkPassword` |
| Manage 2FA, recovery email | No | No | Yes | no `SetPassword` in L:; no `account.updatePasswordSettings` | **NEITHER** |
| Login email setup / email code | Yes | No | Yes | L:auth_repository.dart:81,84; no `account.sendVerifyEmailCode` | Not reached on this server |
| QR login (show QR / scan to approve) | No | No | Yes | `RequestQrCodeAuthentication` unused; no `auth.exportLoginToken`/`acceptLoginToken` | **NEITHER** |
| Bot-token login | Yes | No | Yes | L:auth_repository.dart:67; no `auth.importBotAuthorization` | **BROKEN-ON-SERVER** (toast). No bot accounts can exist |
| Log out | Yes | Yes | Yes | L:auth_repository.dart:94; S:Rpc/AuthHandlers.cs:103 | **WORKS** |
| Multi-DC file auth (`exportAuthorization`) | n/a (TDLib) | Yes | Yes | S:Rpc/AuthHandlers.cs:45-64 | All five DCs point to one server (S:Rpc/HelpHandlers.cs:15-16) |
| PFS temp keys | n/a (TDLib) | Yes | Yes | S:Rpc/AuthHandlers.cs:17-40 | |
| Active sessions, terminate others | No | No | Yes | no `account.getAuthorizations`/`resetAuthorization` | **NEITHER**. Security-relevant given the shared code |
| Delete account, account TTL, change phone | No | No | Yes | no `account.deleteAccount`/`setAccountTTL`/`changePhone` | **NEITHER** |
| Session backup/restore over HTTP | Yes (uncommitted) | Yes | No | L:features/session_backup/; S:Http/BackupApi.cs | Custom-server-only extra. **WORKS** (server integration tests at tests/NeoMtProto.Tests/IntegrationTests.cs:302,330) |
| Custom server selection, RSA from `/.well-known` | Yes (uncommitted) | Yes | n/a | L:core/custom_server/custom_server.dart; S:Transport/MtConnectionHandler.cs:10-43 | **WORKS** |

## 2. Contacts and people

| Feature | Lumina | Custom server | Real Telegram | Evidence | Notes |
|---|---|---|---|---|---|
| Contact list | Yes (uncommitted screen) | Yes | Yes | L:features/contacts/data/contacts_repository.dart:62; S:Rpc/ContactsHandlers.cs:50 | **WORKS**. `mutual` is computed |
| Import phone book | Yes | Yes | Yes | L:contacts_repository.dart:130; S:Rpc/ContactsHandlers.cs:62 | **WORKS**. Unregistered numbers are skipped (no `retry_contacts`, no invite suggestions) |
| Add / edit contact (custom name) | Yes | Partial | Yes | L:contacts_repository.dart:114; S:Rpc/ContactsHandlers.cs:86; names stored at S:Storage/Repos.cs:200 but `ToApi` uses the user's own name (S:Rpc/Mapping.cs:63) | **SILENT**: a renamed contact keeps their own name. `add_phone_privacy_exception` is ignored |
| Delete contact | Yes | Yes | Yes | L:contacts_repository.dart:141; S:Rpc/ContactsHandlers.cs:95 | **WORKS** |
| Search contacts / people | Yes | Yes | Yes | L:contacts_repository.dart:86, L:features/chats/data/chats_repository.dart:38; S:Rpc/ContactsHandlers.cs:14 | **WORKS**. Searches users and public channels |
| Find by @username / phone | Yes | Yes | Yes | L:app/app_profiles.dart:85, L:features/calls/data/calls_repository.dart:95; S:Rpc/ContactsHandlers.cs:33,43 | **WORKS** |
| Share a contact in chat | Yes | Rejects | Yes | L:app/app_conversation_extensions.dart:383; S:Rpc/FileHandlers.cs:151 | **BROKEN-ON-SERVER**: `inputMediaContact` gets `MEDIA_INVALID`, a failed bubble with no toast |
| Block / unblock, blocked list | Partial (block in profile) | No | Yes | L:features/profile/data/user_profile_repository.dart:81; no `contacts.block`/`unblock`/`getBlocked` | **BROKEN-ON-SERVER**. Blocking isn't enforced anywhere on the server either |
| Contact online statuses refresh | n/a (TDLib) | No | Yes | TD:UserManager.cpp:194 `contacts.getStatuses` | Log noise only; presence still arrives through pushes (S:Rpc/Presence.cs) |
| Close friends list | No | Yes | Yes | S:Rpc/StoryHandlers.cs:579 | **NO-UI** |
| Top peers, birthdays | No | Stub | Yes | S:Rpc/SettingsHandlers.cs:204-205 | NEITHER, really |
| Groups in common | Yes | Yes | Yes | L:features/profile/data/user_profile_repository.dart:77; S:Rpc/SocialHandlers.cs:610 | **WORKS** |

## 3. Private chats, groups, channels, supergroups

| Feature | Lumina | Custom server | Real Telegram | Evidence | Notes |
|---|---|---|---|---|---|
| Chat list, paging, pins, archive | Yes | Yes | Yes | L:chats_repository.dart:20,60,94; S:Rpc/MessagingHandlers.cs:604-660 | **WORKS** (archive is in the E2E test) |
| Mark as unread | Yes | Stub | Yes | L:chats_repository.dart:63; S:Rpc/MessagingHandlers.cs:663-672 | **SILENT**: not stored, not synced, lost after re-login |
| Delete chat / clear history | Yes | No | Yes | L:chats_repository.dart:106; no `messages.deleteHistory`/`channels.deleteHistory` | **BROKEN-ON-SERVER** (toast). Deleted locally only; it probably comes back from the server later (unverified) |
| Leave group / channel | Yes | Yes | Yes | L:chats_repository.dart:109; S:Rpc/ChatHandlers.cs:134,446 | **WORKS** |
| Create basic group / supergroup / channel | Yes | Yes | Yes | L:features/chat_info/data/chat_info_repository.dart:211,217; S:Rpc/ChatHandlers.cs:75,270 | **WORKS** |
| Create forum | No | No | Yes | no `channels.toggleForum`, no `*ForumTopic*` | **NEITHER** |
| Members: list, add, remove | Yes | Yes | Yes | L:chat_info_repository.dart:95,123,126,131; S:Rpc/ChatHandlers.cs:119,134,352,398,517 | **WORKS** |
| Admin rights, promote / demote | Yes | Yes | Yes | L:chat_info_repository.dart:142; S:Rpc/ChatHandlers.cs:165,494 | **WORKS** |
| Admin custom title ("member tag") | Yes | No | Yes | L:chat_info_repository.dart:152 → `messages.editChatParticipantRank` (TD:DialogParticipantManager.cpp:846) | **BROKEN-ON-SERVER**. `channels.editAdmin` takes a rank (S:Rpc/ChatHandlers.cs:510), but TDLib 1.8.69 uses the new method |
| Default permissions | Yes | Yes | Yes | L:chat_info_repository.dart:157; S:Rpc/SocialHandlers.cs:209 | **WORKS** |
| Slow mode | Yes | No | Yes | L:chat_info_repository.dart:161; no `channels.toggleSlowMode` | **BROKEN-ON-SERVER** (toast) |
| Title / description | Yes | Yes | Yes | L:chat_info_repository.dart:164,167; S:Rpc/ChatHandlers.cs:154,230,472 | **WORKS** |
| Group / channel photo | No | Yes | Yes | `SetChatPhoto` unused; S:Rpc/ChatHandlers.cs:180,486 | **NO-UI** |
| Public username for groups / channels | No | Yes | Yes | `SetSupergroupUsername` unused; S:Rpc/ChatHandlers.cs:544,552 | **NO-UI** |
| Primary invite link | Yes | Yes | Yes | L:chat_info_repository.dart:175,185; S:Rpc/SocialHandlers.cs:246 | **WORKS** |
| Extra invite links (expiry, limit, approval), revoke, joined list | No | Yes | Yes | S:Rpc/SocialHandlers.cs:263-336,408 | **NO-UI** |
| Join requests: approve / decline | No | Yes | Yes | S:Rpc/SocialHandlers.cs:427,439 | **NO-UI** |
| Join by `t.me/+…` link with preview | No | Yes | Yes | L:core/telegram/internal_links.dart (no invite handler); S:Rpc/SocialHandlers.cs:351,368 | **NO-UI** |
| Join a public channel | Yes | Yes | Yes | L:chat_info_repository.dart:187; S:Rpc/ChatHandlers.cs:428 | **WORKS** |
| Upgrade group to supergroup | Implicit | Yes | Yes | S:Rpc/ChatHandlers.cs:189 | **NO-UI** (no explicit button) |
| Delete group / channel (owner) | No | Yes (channels) | Yes | S:Rpc/ChatHandlers.cs:460 | **NO-UI** |
| Transfer ownership | No | No | Yes | no `channels.editCreator` | **NEITHER** |
| Allowed reactions per chat | No | Yes | Yes | S:Rpc/SocialHandlers.cs:197 | **NO-UI** |
| Sign messages, protected content, join-to-send, hidden members, anti-spam | No | No | Yes | no `channels.toggleSignatures`/`toggleJoinToSend`/…, no `messages.toggleNoForwards` | **NEITHER** |
| Admin log (recent actions) | No | No | Yes | no `channels.getAdminLog` | **NEITHER** |
| Discussion groups / comments | Partial (shows linked chat) | No | Yes | no `channels.setDiscussionGroup`, `messages.getReplies`/`getDiscussionMessage` | **NEITHER** works end to end |
| Statistics, boosts | No | No | Yes | `stats.*` 0/8, no `premium.*` | **NEITHER** |
| Online member count | n/a (TDLib) | No | Yes | TD:DialogParticipantManager.cpp:65 `messages.getOnlines` | Log noise; the online counter is missing |

## 4. Messages

| Feature | Lumina | Custom server | Real Telegram | Evidence | Notes |
|---|---|---|---|---|---|
| Send text with entities | Yes | Yes | Yes | L:features/conversation/data/messages_repository.dart:67; S:Rpc/MessagingHandlers.cs:184; S:Rpc/TextEntities.cs | **WORKS** (E2E) |
| Reply | Yes | Partial | Yes | L:messages_repository.dart:21; S:Rpc/MessagingHandlers.cs:245 | **WORKS** for plain replies. **SILENT** for quote text and entities, reply to a message in another chat (`reply_to_peer_id`) and reply to a story (`inputReplyToStory`, L:features/stories/data/stories_repository.dart:134): all dropped, and the message is sent as a non-reply |
| Edit text | Yes | Yes | Yes | L:messages_repository.dart:162; S:Rpc/MessagingHandlers.cs:494 | **WORKS** (E2E) |
| Edit caption | Yes | Partial | Yes | L:messages_repository.dart:201; S:Rpc/MessagingHandlers.cs:498 | Changing a caption works. Removing a caption gets `MESSAGE_EMPTY`. Media replace isn't supported |
| Edit live location | Yes | Rejects | Yes | L:.../content/rich_cards_content.dart:216 | Moot: live locations can't be sent at all (§5) |
| Delete for me / for everyone | Yes | Yes | Yes | L:messages_repository.dart:212; S:Rpc/MessagingHandlers.cs:533,553 | **WORKS** (E2E) |
| **Forward** (any options) | Yes | **No** | Yes | L:messages_repository.dart:224; no `messages.forwardMessages` | **BROKEN-ON-SERVER**: failed bubbles, no toast. The fwd header (`fwd_from`) isn't modelled anywhere in the server |
| Pin / unpin / unpin all | Yes | Yes | Yes | L:messages_repository.dart:242,251,255; S:Rpc/MessagingHandlers.cs:819,863 | **WORKS** (E2E) |
| Reactions (emoji) | Yes | Yes | Yes | L:messages_repository.dart:432,441; S:Rpc/SocialHandlers.cs:49-195 | **WORKS**. The server's reaction "stickers" are placeholders whose files can't be downloaded (S:Rpc/SocialHandlers.cs:28-47); Lumina draws the emoji instead |
| Custom-emoji / paid reactions | No | Partial / No | Yes | S:Rpc/SocialHandlers.cs:100 | NEITHER, in practice |
| Who reacted | No | Yes | Yes | S:Rpc/SocialHandlers.cs:162 | **NO-UI** |
| Read receipts (ticks) | Yes | Yes | Yes | L:features/notifications/data/notification_center.dart:215; S:Rpc/MessagingHandlers.cs:464,474 | **WORKS** (E2E) |
| Read time ("read at") | Yes | No | Yes (Premium-ish) | L:messages_repository.dart:356; no `messages.getOutboxReadDate` | **BROKEN-ON-SERVER** (toast) |
| Voice/round "listened", view-once opened | Yes | No | Yes | L:messages_repository.dart:495; TD:MessageQueryManager.cpp:2188 `messages.readMessageContents` | **BROKEN-ON-SERVER**. View-once media is never destroyed on the server (privacy). The "unplayed" dot stays on the sender's other devices |
| Mentions badge / read all mentions | Yes | No | Yes | L:chats_repository.dart:75; no `messages.readMentions`/`getUnreadMentions` | **BROKEN-ON-SERVER**. The server never counts mentions |
| Cloud drafts | Yes | No | Yes | L:messages_repository.dart:327; TD:DraftMessageManager.cpp:98,150 | **BROKEN-ON-SERVER**. The draft stays local (unverified), with no cross-device sync |
| **Scheduled messages** | Yes | **No** (`schedule_date` ignored) | Yes | L:core/telegram/send_options.dart:20-22, L:messages_repository.dart:282,288; S:Rpc/MessagingHandlers.cs:189,199 | **SILENT**: delivered immediately. Listing and rescheduling get toasts |
| Send when online | Yes | No | Yes | same as above | **SILENT**: delivered immediately |
| Silent send | Yes | Yes (flag kept) | Yes | S:Rpc/MessagingHandlers.cs:189 | **WORKS**. Moot without server push |
| Typing / upload actions | Yes | Yes | Yes | L:messages_repository.dart:447; S:Rpc/MessagingHandlers.cs:377 | **WORKS** (E2E) |
| Link preview while composing / on messages | Yes | No | Yes | L:messages_repository.dart:81; no `messages.getWebPagePreview`/`getWebPage` | **BROKEN-ON-SERVER**. The server never attaches `messageMediaWebPage` |
| Instant View | Yes | No | Yes | L:features/conversation/presentation/screens/instant_view_screen.dart:54 | **BROKEN-ON-SERVER** |
| Copy message link | Yes | Partial | Yes | L:messages_repository.dart:452; TD:MessagesManager.cpp:15657 | **WORKS**: TDLib builds the link locally. Links point at real `t.me` (S:Rpc/HelpHandlers.cs:43), which is meaningless for this server's chats |
| Channel post view counts | Yes (renders) | No | Yes | TD:MessageQueryManager.cpp:1137 `messages.getMessagesViews`; S:Rpc/MessagingHandlers.cs:256 | **SILENT**: always "1 view" |
| Sponsored messages | Yes | No | Yes | L:messages_repository.dart:469,490 | Harmless: errors are expected, and there are no ads on this server |
| Translate, auto-delete timer, report, polls voters | No | No | Yes | no `messages.translateText`/`setHistoryTTL`/`report` | **NEITHER** |

## 5. Media upload and download

| Feature | Lumina | Custom server | Real Telegram | Evidence | Notes |
|---|---|---|---|---|---|
| Chunked upload (small and big parts, ≤ 4000 MB) | Yes (TDLib) | Yes | Yes | S:Rpc/FileHandlers.cs:16-38; S:Storage/FileStore.cs:19-20 | **WORKS**. All bytes are stored in the database (SQLite or Postgres), which will limit scale |
| Download (`upload.getFile`, ranges) and streaming | Yes | Yes | Yes | L:core/telegram/file_store.dart:43; L:core/media/tdlib_stream_server.dart; S:Rpc/FileHandlers.cs:40-80 | **WORKS**. No CDN and no `upload.getFileHashes` |
| Photos | Yes | Partial | Yes | L:features/conversation/data/resend_content.dart:13; S:Rpc/Mapping.cs:24-37 | **WORKS**, but there's only one size `x` (or `a`/`c` for avatars), all the full original. No `s`/`m` thumbnails and no stripped `i` preview, so the chat list, previews and avatars download whole photos. Lumina's progressive JPEG decoding (commit `65eb8ec`) hides some of this |
| Albums | Yes | Yes | Yes | L:messages_repository.dart:145; S:Rpc/MessagingHandlers.cs:203, S:Rpc/FileHandlers.cs:174 | **WORKS** |
| Video, files, music | Yes | Yes | Yes | L:resend_content.dart:25,39,64; S:Rpc/FileHandlers.cs:126-145 | **WORKS**. Attributes and thumbnails are taken as the client sends them; there's no server-side probing |
| Voice notes, video notes | Yes | Yes | Yes | L:app/app_conversation_extensions.dart:326; L:features/voice/presentation/screens/video_note_recorder_screen.dart:140; S:Rpc/FileHandlers.cs:157-170 | **WORKS** |
| Media spoiler, view-once TTL | Yes | Partial | Yes | S:Rpc/FileHandlers.cs:124,145 | Flags are stored but TTL isn't enforced (see §4) |
| **Poll / quiz send and vote** | Yes | **Rejects / No** | Yes | L:features/media/presentation/widgets/poll_composer.dart:36; L:rich_cards_content.dart:429,524; S:Rpc/FileHandlers.cs:151 | **BROKEN-ON-SERVER**: no `inputMediaPoll`, `messages.sendVote` or `getPollResults` |
| **Location, live location, venue** | Yes | **Rejects** | Yes | L:features/media/presentation/widgets/location_sheet.dart:31-32 | **BROKEN-ON-SERVER**. The live location foreground service runs for nothing |
| Map thumbnails | Yes | No | Yes | L:rich_cards_content.dart:64 → `upload.getWebFile` | **BROKEN-ON-SERVER** |
| Dice / games | No | Rejects | Yes | – | NEITHER |
| Stickers: sets, recent, favourites, send | Yes (panel) | Stub (all empty, `getStickerSet` error) | Yes | L:features/media_panel/data/media_panel_repository.dart:15-22,47; S:Rpc/SettingsHandlers.cs:206-212 | **SILENT**: empty panel. No `stickers.*`, so packs can't be created |
| Animated emoji, reaction animations | Yes | Stub | Yes | L:.../content/text_content.dart:114 | Moot: no animated-emoji set exists |
| Saved GIFs | Yes | Stub (empty), no `saveGif` | Yes | L:media_panel_repository.dart:34; S:Rpc/SettingsHandlers.cs:214 | **SILENT** (empty) |
| GIF search (`@gif` inline bot) | Yes | No | Yes | L:media_panel_repository.dart:40,76 | **BROKEN-ON-SERVER**: no bot exists and there's no `messages.getInlineBotResults` |
| Sending a GIF file from the gallery | Yes | Yes | Yes | L:media_panel_repository.dart:61; S:Rpc/FileHandlers.cs:126 | **WORKS** (an uploaded document with the animated attribute) |
| Custom emoji in text | Yes (renders) | No | Yes (Premium) | L:core/telegram/custom_emoji_store.dart:35 → `messages.getCustomEmojiDocuments` | Moot: none exist on the server |
| Emoji categories and keyword search | Yes | No | Yes | L:messages_repository.dart:413, L:media_panel_repository.dart:28; TD:StickersManager.cpp:244,1468 | **BROKEN-ON-SERVER**: categories and search come back empty (unverified on device); the local emoji grid still works |

## 6. Updates delivery and push

| Feature | Lumina | Custom server | Real Telegram | Evidence | Notes |
|---|---|---|---|---|---|
| Live updates over the open connection | Yes | Yes | Yes | S:Mtproto/UpdateHub.cs:42-59 | **WORKS** (E2E). Each push is sent from its own `Task.Run`, so order isn't guaranteed. TDLib heals gaps with `getDifference` |
| `updates.getState` / `getDifference` | Yes (TDLib) | Yes (user box) | Yes | S:Rpc/MessagingHandlers.cs:691-717 | **WORKS** for private chats and basic groups. `seq` is always 0/1 and `qts` is 0 |
| `updates.getChannelDifference` | Yes (TDLib) | Yes | Yes | S:Rpc/MessagingHandlers.cs:720-760 | **WORKS** when TDLib asks |
| Offline catch-up for channels and supergroups | Yes (TDLib) | **No `updateChannelTooLong`** | Yes | S:Rpc/MessagingHandlers.cs:693-717 (nothing emitted for channels) | **SILENT** (inferred): channel and supergroup posts from while you were offline don't reach the chat list or notifications until the chat is opened |
| Keep-alive connection / periodic sync (no FCM) | Yes | Yes | n/a | android/app/src/main/kotlin/dev/lumina/background/Background.kt | **WORKS** in "connected" mode. The WorkManager "saver" mode is hit by the row above |
| Push tokens (`account.registerDevice`, FCM/UnifiedPush) | No | No | Yes | – | **NEITHER**. Needed if Lumina adopts UnifiedPush |
| Presence (online / last seen) | Yes | Yes | Yes | L:app/lifecycle_watcher.dart:72; S:Rpc/UserHandlers.cs:70; S:Rpc/Presence.cs | **WORKS**. There are no privacy rules (see §11) |

## 7. Calls

| Feature | Lumina | Custom server | Real Telegram | Evidence | Notes |
|---|---|---|---|---|---|
| 1:1 voice calls | Yes | Yes | Yes | L:features/calls/data/calls_repository.dart:26-67; S:Rpc/CallHandlers.cs:74-235; S:Calls/Reflector.cs | **WORKS** (server integration test at tests/NeoMtProto.Tests/IntegrationTests.cs:1072; on-device test still pending). All media goes through the server's UDP reflector on port+1 with P2P off (S:Rpc/CallHandlers.cs:44-62) |
| 1:1 video, screen share | Yes | Yes (signalling relay) | Yes | S:Rpc/CallHandlers.cs:182 | **WORKS** (unverified on device) |
| Rating, debug log | Yes | Stub | Yes | S:Rpc/CallHandlers.cs:236-249 | **WORKS** (accepted and discarded) |
| Missed / ended call service messages | Yes | Yes | Yes | S:Rpc/CallHandlers.cs:199 | **WORKS** |
| Ring while the app is closed | Partial (keep-alive) | Yes (live push only) | Yes (FCM) | – | Same limits as §6 |
| TURN/STUN, multiple reflectors | n/a | No (one reflector) | Yes | S:Rpc/CallHandlers.cs:52-62 | Fine for a single-node server |
| Group voice/video chats, live streams, conference calls | No | No (`phone.*` 10/43) | Yes | – | **NEITHER** |

## 8. Stories

| Feature | Lumina | Custom server | Real Telegram | Evidence | Notes |
|---|---|---|---|---|---|
| Feed, peer stories, viewer | Yes | Yes | Yes | L:features/stories/data/stories_repository.dart:79,89,99; S:Rpc/StoryHandlers.cs:279,306,341 | **WORKS** |
| Post (photo/video, caption, privacy, as a channel) | Yes | Yes | Yes | L:stories_repository.dart:176,185,252; S:Rpc/StoryHandlers.cs:168,255,264 | **WORKS**. The server enforces the privacy rules (S:Rpc/StoryHandlers.cs:50-110) |
| Views, reactions, viewer list | Yes | Yes | Yes | L:stories_repository.dart:107,123,161; S:Rpc/StoryHandlers.cs:446-534 | **WORKS** |
| Channel story interactions | Yes | No | Yes | L:stories_repository.dart:154 → TD:StoryManager.cpp:369 `stories.getStoryReactionsList` | **BROKEN-ON-SERVER** |
| Reply to a story | Yes | Partial | Yes | L:stories_repository.dart:134; S:Rpc/MessagingHandlers.cs:245 | **SILENT**: arrives as a plain message with no story reference |
| Delete own story | Yes | Yes | Yes | L:stories_repository.dart:117; S:Rpc/StoryHandlers.cs:220 | **WORKS** |
| Profile stories (posted to page) | Yes (read) | Yes | Yes | L:features/profile/data/user_profile_repository.dart:39; S:Rpc/StoryHandlers.cs:325 | **WORKS** |
| Edit story, pin / unpin, archive, albums | No | Yes | Yes | S:Rpc/StoryHandlers.cs:200,233,249,333,363-428 | **NO-UI** |
| Stealth mode | Local alternative | Yes | Yes (Premium) | S:Rpc/StoryHandlers.cs:563 | **NO-UI** (Lumina's anonymous viewing just never calls `openStory`) |
| Hide a person's stories | No | Yes | Yes | S:Rpc/StoryHandlers.cs:534,542 | **NO-UI** |
| Story links | No | Yes | Yes | S:Rpc/StoryHandlers.cs:586 | **NO-UI** |
| Report a story | No | No | Yes | – | NEITHER |

## 9. Folders

| Feature | Lumina | Custom server | Real Telegram | Evidence | Notes |
|---|---|---|---|---|---|
| Folders: create, edit, delete, reorder | Yes | Yes | Yes | L:features/folders/data/folders_repository.dart:48-79; S:Rpc/FolderHandlers.cs:19,72,105 | **WORKS** |
| Recommended folders | Yes | Yes | Yes | L:folders_repository.dart:83; S:Rpc/FolderHandlers.cs:29 | **WORKS** |
| Folder tags | Yes | Yes | Yes (Premium) | L:folders_repository.dart:92; S:Rpc/FolderHandlers.cs:114 | TDLib may refuse this client-side because the user isn't Premium (unverified) |
| Mark folder read | Yes | Yes (per-chat reads) | Yes | L:folders_repository.dart:125 | **WORKS** |
| Shareable folder links (`t.me/addlist`), join, updates, QR | Yes | **No** (`chatlists.*` 0/11) | Yes | L:folders_repository.dart:150-205; L:features/folders/presentation/screens/folder_qr_screen.dart | **BROKEN-ON-SERVER** (toast) |

## 10. Profile

| Feature | Lumina | Custom server | Real Telegram | Evidence | Notes |
|---|---|---|---|---|---|
| Name, bio | Yes | Yes | Yes | L:features/profile/data/user_profile_repository.dart:125,127; S:Rpc/ContactsHandlers.cs:146 | **WORKS**. Bio is limited to 70 characters |
| Username (check, set) | Yes | Yes | Yes | L:user_profile_repository.dart:130,135; S:Rpc/ContactsHandlers.cs:126,133 | **WORKS**. One username only, no collectibles |
| Profile photo: set, previous, delete, gallery | Yes | Yes | Yes | L:user_profile_repository.dart:34,110-122; S:Rpc/FileHandlers.cs:181-230 | **WORKS** for static photos only. A video avatar gets `VIDEO_FILE_INVALID` (S:Rpc/FileHandlers.cs:186) |
| Gifts on profile | Yes | No | Yes | L:user_profile_repository.dart:58; `payments.*` 0/76 | **BROKEN-ON-SERVER** (empty or toast) |
| Birthday, personal channel, emoji status, name colours | No | No / Stub | Yes | S:Rpc/SettingsHandlers.cs:201-202,222-225 | **NEITHER** |
| Chat wallpapers (global, per chat, for both sides) | Yes | Yes | Yes | L:features/backgrounds/presentation/background_picker_screen.dart:50,188; S:Rpc/WallpaperHandlers.cs:20-147 | **WORKS** (E2E) |
| Auto-download presets | Yes | Yes | Yes | L:features/auto_download/data/auto_download_service.dart:104,118; S:Rpc/SettingsHandlers.cs:44,51 | **WORKS**. Synced per account |

## 11. Privacy and security

| Feature | Lumina | Custom server | Real Telegram | Evidence | Notes |
|---|---|---|---|---|---|
| Privacy rules (last seen, phone, photo, calls, invites, forwards) | No | No | Yes | no `account.getPrivacy`/`setPrivacy` | **NEITHER**. The server shows the phone to contacts only (hard-coded, S:Rpc/Mapping.cs:66,81) and last seen to everyone it pushes presence to |
| Global privacy settings, content settings | n/a (TDLib) | No | Yes | TD:GlobalPrivacySettings.cpp:34, TD:ConfigManager.cpp:1000 | Log noise |
| Ghost mode (client-side) | Yes | n/a | Partly | L:app/lifecycle_watcher.dart:62-72 | **WORKS** with any server |
| Secret chats | Yes | **No** | Yes | L:features/chat_info/data/chat_info_repository.dart:229; S:Rpc/CallHandlers.cs:26 (DH config only) | **BROKEN-ON-SERVER**: the secret chat closes at once |
| Login security (SMS, rate limits, 2FA) | – | Weak | Yes | S:Rpc/LoginCodes.cs:9-21 (5 attempts per hash) | See executive summary #6 |
| Encrypted local database | Yes | n/a | Passcode | DECISIONS D10 | Client-side |

## 12. Search

| Feature | Lumina | Custom server | Real Telegram | Evidence | Notes |
|---|---|---|---|---|---|
| In-chat search with media filters | Yes | Yes | Yes | L:messages_repository.dart:269; S:Rpc/SocialHandlers.cs:533,559 | **WORKS**. The server scans the whole history on each call, O(n) |
| Chat and people search | Yes | Yes | Yes | L:chats_repository.dart:35,38 | **WORKS** |
| Global server message search | No (local FTS) | Yes | Yes | S:Rpc/SocialHandlers.cs:568 | **NO-UI** (Lumina's own encrypted FTS works offline) |
| Hashtags / public posts | No | No | Yes | – | NEITHER |
| Saved Messages by source chat | No | Partial (`getSavedHistory` yes, `getSavedDialogs` no) | Yes | S:Rpc/SettingsHandlers.cs:165; TD:SavedMessagesManager.cpp:101 | NEITHER, in practice |

## 13. Notifications

| Feature | Lumina | Custom server | Real Telegram | Evidence | Notes |
|---|---|---|---|---|---|
| Local message notifications (reply, mark read) | Yes | n/a | Yes | L:features/notifications/data/notification_center.dart | Works with any server, given updates (§6) |
| Per-chat mute | Yes | Partial | Yes | L:chats_repository.dart:83; S:Rpc/SettingsHandlers.cs:100-115 (stored and pushed to other live sessions); S:Rpc/MessagingHandlers.cs:580 (dialogs return empty settings) | **SILENT**: a new login or device sees every chat unmuted |
| Scope settings (private / groups / channels) | Read only | Yes | Yes | S:Rpc/SettingsHandlers.cs:62-115 | **NO-UI** |
| Reaction / story notification settings | No | Yes | Yes | S:Rpc/SettingsHandlers.cs:131-140 | **NO-UI** |
| Server-side push | No | No | Yes | – | NEITHER (see §6) |

## 14. Bots, inline, keyboards

| Feature | Lumina | Custom server | Real Telegram | Evidence | Notes |
|---|---|---|---|---|---|
| Bot accounts / Bot API | Bot login | No | Yes | L:auth_repository.dart:67 | **BROKEN-ON-SERVER**: no bots can be created (no BotFather, no `auth.importBotAuthorization`) |
| Bot start, welcome card, commands | Yes | No | Yes | L:features/bots/data/bots_repository.dart:30 → `messages.startBot` | **BROKEN-ON-SERVER** (moot without bots) |
| Inline keyboards, callbacks | Yes | No | Yes | L:features/conversation/presentation/widgets/inline_keyboard.dart:45-68 | **BROKEN-ON-SERVER**. The server doesn't store `reply_markup` either |
| Inline mode (`@gif`, `@bot query`) | Yes | No | Yes | L:media_panel_repository.dart:40,76 | **BROKEN-ON-SERVER** |
| Mini apps, payments, games | No | No | Yes | `messages.getAttachMenuBots` stub (S:Rpc/SettingsHandlers.cs:198) | **NEITHER** |

## 15. Premium-only features

| Feature | Lumina | Custom server | Real Telegram | Evidence | Notes |
|---|---|---|---|---|---|
| Premium state, limits, promo | No | No (`help.getPremiumPromo` missing, empty `help.getAppConfig`) | Yes | S:Rpc/HelpHandlers.cs:59-62; TD:Premium.cpp:309 | Nobody is Premium. TDLib falls back to its default limits (unverified which) |
| Premium-gated client features (folder tags, read time, custom emoji) | Some | Server doesn't gate | Yes | – | TDLib gates them client-side, so they're unreachable on this server even though the server would allow them |
| Stars, gifts, TON, boosts | No | No | Yes | – | NEITHER |
| Ad-free toggle | Yes | No | Yes | L:messages_repository.dart:490 | Moot: no ads |

## 16. Proxies and transport

| Feature | Lumina | Custom server | Real Telegram | Evidence | Notes |
|---|---|---|---|---|---|
| SOCKS5 / HTTP proxy | Yes | n/a (transparent) | Yes | L:features/proxy/data/proxy_repository.dart:84-152 | **WORKS**: the tunnel reaches 62.60.191.87 |
| MTProto proxy (`dd`/`ee` secrets) | Yes | n/a | Yes | – | **Likely broken, unverified.** A standard MTProxy forwards to Telegram's own DCs by DC id, not to the custom server, unless that proxy is reconfigured |
| Transports | Yes (TDLib) | abridged, intermediate, padded, obfuscated2 | Plus fake-TLS, HTTP, WebSocket | S:Transport/MtTransport.cs:53-79 | Without fake-TLS the server is easier to fingerprint and block in censored networks |
| Proxy sponsor channel | Yes | Stub (no promo) | Yes | S:Rpc/SettingsHandlers.cs:197 | Moot |

---

## Prioritized fix list

### Server work (NeoMtProto)

Ordered by user impact per unit of effort.

1. **`messages.forwardMessages`** (with `drop_author`, `drop_media_captions`, `silent`, `top_msg_id`).
   Model `fwd_from` and copy media by reference. This also unblocks "save to Saved Messages".
   M. (Summary #1)
2. **Emit `updateChannelTooLong` in `updates.getDifference`** for every channel or supergroup whose
   pts moved since the client's last known state. Or include channel messages directly. S. (#4)
3. **Return the stored per-peer `PeerNotifySettings`** in `messages.getDialogs`/`getPeerDialogs`,
   `users.getFullUser` and `messages.getFullChat`/`channels.getFullChannel`. The
   `SettingsHandlers.For(...)` helper exists but is never called (S:Rpc/SettingsHandlers.cs:87). S. (#5)
4. **Scheduled messages.** Honour `schedule_date`, including the "when online" sentinel
   `0x7FFFFFFE`. Add a scheduled box, `messages.getScheduledHistory`/`getScheduledMessages`,
   `sendScheduledMessages` and `deleteScheduledMessages`, and editing with `schedule_date`.
   Push `updateNewScheduledMessage`. Until then, **reject `schedule_date` with an error**
   instead of sending at once. M. (#2)
5. **More `InputMedia` types**: geo point, live geo (plus `editMessage` with media), venue,
   contact and poll, with `messages.sendVote`, `getPollResults` and close poll. Dice is cheap too.
   M. (#3)
6. **Quick missing methods that Lumina already calls** (S each):
   - `messages.deleteHistory` and `channels.deleteHistory`
   - `messages.saveDraft` and `getAllDrafts`, plus `draft` in dialogs
   - `messages.readMessageContents`, with view-once TTL deletion
   - `messages.getMessagesViews`, with a real view counter
   - `messages.getOutboxReadDate`
   - `messages.readMentions`, with mention counting from entities
   - `messages.markDialogUnread` stored and returned as `unread_mark`
   - `messages.editChatParticipantRank`
   - `channels.toggleSlowMode`
   - `contacts.block`, `unblock` and `getBlocked`, enforced on send and call
   - `auth.resendCode`
   - `stories.getStoryReactionsList`
7. **Accept `editMessage` with empty text when the message has media** (caption removal), and
   `media` replacement. S.
8. **Reply variants**: keep `quote_text`/`quote_entities`/`quote_offset`, `reply_to_peer_id` and
   `inputReplyToStory`, so replies stop degrading silently. S.
9. **Use the contact's stored name** in `ToApi` for the owner (S:Rpc/Mapping.cs:57-71). S.
10. **Login and account security.** Real per-request random codes delivered out of band (by
    default, never a shared code in production), rate limits per phone and IP,
    `account.getAuthorizations`/`resetAuthorization`, and 2FA (`account.getPassword` with
    SRP, `updatePasswordSettings`, `auth.checkPassword`). M.
11. **Privacy rules**: `account.getPrivacy`/`setPrivacy` for status, phone, photo, calls, chat
    invites and forwards, applied in `ToApi` and `Presence`. M.
12. **Photo sizes**: generate `s`/`m`/`x`/`y` thumbnails and a stripped `i` size when a photo is
    stored (S:Rpc/Mapping.cs:24-37). Avatars should get small `a` and `c` sizes. S–M.
13. **`chatlists.*`** (export, check, join, updates, leave suggestions) for folder links. M.
14. **Link previews**: `messages.getWebPagePreview` and server-side `messageMediaWebPage` with
    an OpenGraph fetcher. `messages.getWebPage` for Instant View is optional. M.
15. **Secret chats**: `requestEncryption`, `acceptEncryption`, `discardEncryption` and
    `sendEncrypted*`, plus a `qts` box in `getDifference`. L.
16. **Stickers and GIFs**: `stickers.createStickerSet`, `messages.getStickerSet`/`installStickerSet`,
    `saveGif`, `getCustomEmojiDocuments`, `getEmojiKeywords`/`getEmojiGroups`, and a seed pack. A
    built-in "gif" inline responder would revive Lumina's GIF search without full bot support. M–L.
17. **Bots**: `auth.importBotAuthorization`, `messages.startBot`, `reply_markup` storage,
    `getBotCallbackAnswer`, inline queries and a minimal BotFather. L.
18. **Push**: `account.registerDevice` with a UnifiedPush or Web Push sender, so the "saver" mode
    doesn't depend on keep-alive. M.
19. Later: fake-TLS transport (censorship resistance), `channels.toggleSignatures`/`toggleJoinToSend`/
    `getAdminLog`/`editCreator`, forum topics, discussion threads, `messages.getSavedDialogs`,
    `account.updateBirthday`, video avatars, group calls.
20. Scale and robustness:
    - Many handlers load the whole history to count or filter (`store.History(..., int.MaxValue, ...)`
      in S:Rpc/MessagingHandlers.cs:175, S:Rpc/SocialHandlers.cs, S:Rpc/UserHandlers.cs:36).
    - File bytes live in the database.
    - Pushes run as unordered `Task.Run`s (S:Mtproto/UpdateHub.cs:47-57).

    Fine for a private server now, but worth fixing before growth.

### App work (Lumina)

1. **Make failures visible on a self-hosted server.** Extend `UnsupportedApi` to cover
   `updateMessageSendFailed` with `METHOD_NOT_IMPLEMENTED`/`MEDIA_INVALID`, so a failed forward,
   poll or location says "not supported by this server" instead of showing a bare failed bubble.
   S.
2. **Hide or disable features the server can't do** (capability probing or a per-server feature
   list): forward, schedule and send-when-online, polls, location, live location, contact share,
   secret chat, slow mode, folder links, sticker/GIF tabs, bot-token login. Scheduled sends are the
   urgent one because they fail **silently**. S–M.
3. **Build UI for what the server already supports** (S each):
   - extra invite links and join requests
   - `t.me/+` join with preview (`CheckChatInviteLink`/`JoinChatByInviteLink`, added to
     `L:core/telegram/internal_links.dart`)
   - group and channel photo, public username and allowed reactions
   - delete a channel
   - edit, pin and archive your own stories; story albums
   - close-friends editor and hiding a person's stories
   - who reacted
   - notification scope settings
4. **Server-aware links**: on a custom server, links built by TDLib point at `https://t.me/` (from
   `help.getConfig` `me_url_prefix`). Either show them as server-local or have the server send
   its own prefix. S.
5. **Ongoing items from TELEGRAM_GAP_ANALYSIS.md that need no server work**: passcode lock, share
   into the app, save to gallery, privacy settings UI (once the server has it), sessions and 2FA
   management UI (likewise), translation, report.
6. **Device tests on the custom server**:
   - offline channel catch-up (to confirm executive summary #4)
   - how TDLib reconciles a scheduled send answered with `updateNewMessage`
   - whether a deleted chat history comes back
   - drafts surviving `saveDraft` errors
   - calls through the reflector
   - MTProto-proxy behaviour

## Things I couldn't verify

- **TDLib's client-side behaviour when the server answers unexpectedly**: scheduled sends (summary
  #2), deleted history coming back, drafts after a `saveDraft` failure, and Premium-gated folder
  tags. I inferred these from TDLib's design, not from running it.
- **The offline channel gap** (summary #4) is inferred from the code. It needs a device or E2E
  test.
- **MTProto proxy routing** to a custom server.
- **Emoji search and category results** on the custom server.
- **The calls path end to end on a device.** Only the server-side relay test exists.
- **Line numbers in uncommitted files** (on both sides) may shift while other agents keep editing.
