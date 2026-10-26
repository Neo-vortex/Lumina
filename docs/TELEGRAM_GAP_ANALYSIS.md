# Lumina vs. official Telegram for Android: feature gap analysis

Date: 2026-10-26. Code: worktree `Lumina-tdlib`, branch `tdlib-own-bindings`
(TDLib 1.8.69, `packages/lumina_tdlib`), including the uncommitted work
(channel Subscribe/Mute bar, proxy QR scanner and header button, video
download progress). Baseline: the official Telegram Android app as of 2026.

## How this was checked

- I read `docs/AGENT_HANDOFF.md`, `ARCHITECTURE.md`, `DECISIONS.md`, `README.md` and
  the chat-folders spec. The README is stale: it still says TDLib 1.8.36 and "phases 1–2".
- Then I checked the claims against the code. I listed every `td.<Function>(` call
  in `lib/` (all TDLib access goes through `import 'package:lumina_tdlib/api.dart' as td;`)
  and read the repositories, menus, composer, chat list, chat info, settings and
  `AndroidManifest.xml`.
- To decide whether a feature can be built, I checked
  `packages/lumina_tdlib/lib/src/tdapi/functions/` (1,076 functions). Where a feature
  is missing, its TDLib entry point is named in the Evidence column.
- "Present" means there is working code. It doesn't mean a device test passed. Much of
  calls, notifications and streaming is still marked "device test pending" in the handoff.
- **Effort:** S = up to about 2 days, M = up to about 2 weeks, L = more than 2 weeks
  (one experienced developer, including UI work in Lumina's own design).
- "unverified" means I couldn't confirm the behaviour from the code alone.

## Summary

| Status | Rows |
|---|---|
| Present | 91 |
| Partial | 24 |
| Missing | 166 |
| Planned | 10 |
| Not possible on TDLib 1.8.69 (or for a third-party app) | 3 |
| **Total** | **294** |

The Lumina-only rows in the tables (bot-token login, story history and so on)
count as Present.

Lumina covers everyday one-to-one and small-group messaging well: text with full
formatting, replies with quotes, forwarding, scheduling, albums, voice and round
video, polls, live location, Instant View, stories, 1:1 calls and proxies. It also
has several strong features official Telegram lacks: offline Whisper transcription,
on-device AI actions, encrypted local full-text search, story history, ghost mode
and a connection that works without Firebase.

The biggest gaps are in these areas:
1. **Telegram links and entities aren't interactive.** @mentions, hashtags and bot
   commands can't be tapped. Every `t.me` link opens in the browser, including
   invite links and `+join` links.
2. **Bots don't work in practice.** Inline and reply keyboards aren't rendered,
   there are no callbacks, no inline mode, no mini apps and no payments.
3. **Account and profile management is missing:** profile editing, Telegram privacy
   settings, blocked users, sessions, 2FA, multiple accounts and QR login.
4. **Large-community features are missing:** forum topics, channel comments
   (threads), join requests, invite-link management, admin log, statistics and
   boosts.
5. **There are no sticker, GIF or emoji panels.** Animated stickers and custom emoji
   show as still images.
6. **Android integration is thin:** you can't share into Lumina, `t.me` links from
   other apps don't open it, and there are no Direct Share targets, widgets,
   shortcuts or Android Auto support.
7. **I found two small real bugs.** "Mark as read" on an unread chat doesn't read it.
   "Edit" on a captioned media message calls `EditMessageText`.

Almost everything missing can be built on TDLib 1.8.69. The exceptions are Premium
or Stars purchases through Google Play billing (only Telegram's own app can use it)
and People Nearby (removed by Telegram, so there's no API). Push without FCM and
without a persistent service is possible through UnifiedPush (`RegisterDevice`).

---

## 1. Account & login

| Feature | Official Telegram | Lumina status | Evidence | Effort | Notes |
|---|---|---|---|---|---|
| Phone login (SMS, app, call, flash/missed call, Fragment, SMS word/phrase codes) | Yes | Present | `features/auth/data/auth_repository.dart:64,71`; all `AuthenticationCodeType*` handled | – | Inline error table per spec |
| 2FA password at login | Yes | Present | `auth_repository.dart:76` | – | |
| Forgot 2FA password (email recovery / reset) at login | Yes | Missing | `RequestAuthenticationPasswordRecovery`, `CheckAuthenticationPasswordRecoveryCode`, `RecoverAuthenticationPassword` unused | S | Users who forgot their password are stuck |
| Login email setup + email code | Yes | Present | `auth_repository.dart:83,86` | – | "Sign in with Google" email token not offered (Lumina avoids Google services) |
| Sign-up / registration, terms of service | Yes | Partial | `RegisterUser` at `auth_repository.dart:79` | S | `AcceptTermsOfService` unused; the ToS text isn't shown (unverified whether TDLib requires it here) |
| Log in on this device with a QR code | Yes | Missing | `RequestQrCodeAuthentication` unused; `presentation/screens/other_device_screen.dart:10` only shows the link as text | S | Should render a QR |
| Scan a QR to log in Desktop/Web | Yes | Missing | `ConfirmQrCodeAuthentication` unused | S | The new `flutter_zxing` scanner (`proxy_scan_screen.dart`) can be reused |
| Passkey login and managing passkeys | Yes (2025+) | Missing | `CheckAuthenticationPasskey`, `AddLoginPasskey`, `GetLoginPasskeys` exist | M | Needs Android Credential Manager |
| Multiple accounts | Yes (up to 3, more with Premium) | Missing | DECISIONS D9: "one live client per process" | L | TDLib supports several client ids; touches `TdClient`, the cache, notifications and calls |
| Active sessions list, terminate one or all, auto-terminate period | Yes | Missing | `GetActiveSessions`, `TerminateSession`, `TerminateAllOtherSessions`, `SetInactiveSessionTtl` unused | S | Security-critical |
| Manage 2FA (set/change/remove password, recovery email) | Yes | Missing | `GetPasswordState`, `SetPassword`, `SetRecoveryEmailAddress` unused | S | |
| Change phone number | Yes | Missing | phone-number change flow (`SendPhoneNumberCode` with change type, `CheckPhoneNumberCode`) unused | M | |
| Change login email | Yes | Missing | `SetLoginEmailAddress` unused | S | |
| Delete account / account self-destruct period | Yes | Missing | `DeleteAccount`, `SetAccountTtl` unused | S | |
| Edit own profile: name, bio, username(s), birthday, personal channel | Yes | Missing | `SetName`, `SetBio`, `SetUsername`, `SetBirthdate`, `SetPersonalChat` unused; Settings header is read-only (`features/settings/presentation/screens/settings_screen.dart:104-127`) | S | |
| Set or remove profile photo/video, emoji avatar | Yes | Missing | `SetProfilePhoto`, `DeleteProfilePhoto` unused | S | |
| Log out (full wipe), reset local data, session-revoked notice | Yes | Present | `auth_repository.dart:96,103`; DECISIONS D11 | – | |
| Proxy reachable from the login screen | Yes | Present | handoff §5.5; `feature_wiring.dart` | – | |
| Log in to a custom Telegram server | No | Planned | needs a TDLib patch (owner plan) | M | Lumina-only goal |

## 2. Chat list

| Feature | Official Telegram | Lumina status | Evidence | Effort | Notes |
|---|---|---|---|---|---|
| Main chat list with paging and live updates | Yes | Present | `features/chats/data/chats_repository.dart:18`; `bloc/chat_list_cubit.dart` | – | Timeline-ribbon design |
| Pin / unpin chats | Yes | Present | `presentation/widgets/chat_actions_sheet.dart:222` | – | Reordering pinned chats (`SetPinnedChats`) is missing |
| Mark as unread | Yes | Present | `chat_actions_sheet.dart:227` | – | |
| Mark as read | Yes | Partial | `chat_actions_sheet.dart:198,227` → `ToggleChatIsMarkedAsUnread(false)` (`chats_repository.dart:62`) | S | **Bug:** for a chat with `unreadCount > 0` this only clears the manual flag. It never calls `ViewMessages`/`ReadChatList`, so the chat stays unread |
| Mute / unmute | Yes | Partial | `chats_repository.dart:65-76` | S | Mute "forever" only: no 1 h/8 h/2 d/custom durations, no "disable sound" |
| Delete chat / leave group or channel | Yes | Partial | `chats_repository.dart:79-88` | S | Private chats: always `revoke: false`, so "also delete for X" is missing. No "Clear history" or "Delete and block". Owners can't delete a group/channel (`DeleteChat`) |
| Archive (list, archive/unarchive, keep unmuted chats archived, hide archive) | Yes | Planned | no `ChatListArchive` UI; `AddChatToList`, `SetArchiveChatListSettings` unused; spec `docs/superpowers/specs/2026-10-26-chat-folders-design.md` | M | Part of the folders design ("Archive" lens) |
| Chat folders: tabs, create/edit/delete/reorder, include/exclude rules | Yes | Planned | `CreateChatFolder`, `EditChatFolder`, `ReorderChatFolders` unused; spec above | M | |
| Shareable folder links (`t.me/addlist`), "+N new chats" | Yes | Planned | `CreateChatFolderInviteLink`, `AddChatFolderByInviteLink` unused | M | In the spec |
| Folder tags (Premium), recommended folders | Yes | Planned | `ToggleChatFolderTags`, `GetRecommendedChatFolders` | S | In the spec |
| Swipe actions on chat rows (archive, pin, read, mute, delete; configurable) | Yes | Missing | rows only have `onLongPress` (`presentation/screens/chats_screen.dart:177`) | S | |
| Multi-select chats (bulk mute/archive/delete/read) | Yes | Missing | – | S | |
| Stories strip above the list | Yes | Present | `ChatRowExtensions` halos + "Glimpses" (`features/stories/presentation/screens/glimpses_screen.dart`) | – | Not a top bar, by owner decision |
| Unread count, mention badge, draft, typing, online dot, read ticks | Yes | Present | `presentation/widgets/timeline_chat_row.dart:81-124,220` | – | |
| Unread reactions badge | Yes | Missing | `chat.unreadReactionCount` not shown | S | |
| Verified / scam / fake / Premium star / emoji-status badges | Yes | Missing | `emojiStatus` only copied (`core/telegram/telegram_cache.dart:359`); `verificationStatus` unused | S | Scam/fake labels matter for safety |
| Search: local chats, server chats, public username | Yes | Present | `chats_repository.dart:32-54` | – | |
| Global message search | Yes (server, all chats, filters) | Partial | local FTS index only (`chats_screen.dart:55`); `SearchMessages` unused | M | Finds only indexed history; no media-type/date/chat-type filters |
| Search public posts and hashtags across Telegram | Yes | Missing | `SearchPublicPosts`, `SearchHashtags`, `SearchPublicMessagesByTag` unused | M | |
| Top people / recent searches | Yes | Missing | `GetTopChats`, `AddRecentlyFoundChat` unused | S | |
| "Proxy sponsor" chat tag and hide option | Yes (tag) | Present | uncommitted `timeline_chat_row.dart` `_SponsorTag`; `chat_list_cubit.dart` filter | – | Hiding is a Lumina extra |
| Chat list for bot accounts | No | Present | `chats_screen.dart:120-150` | – | Lumina-only |

## 3. Messaging: composing and sending

| Feature | Official Telegram | Lumina status | Evidence | Effort | Notes |
|---|---|---|---|---|---|
| Rich text: bold, italic, underline, strikethrough, spoiler, code, pre, quote, expandable quote, link | Yes | Present | `features/conversation/presentation/widgets/formatting_controller.dart:82-139`; `ParseMarkdown` `data/messages_repository.dart:67` | – | |
| Reply, and reply with a quoted passage | Yes | Present | `message_menu.dart:158-187` | – | The quote position is the first match only (handoff §2.3 D) |
| Reply to a message in another chat ("Reply in…") | Yes | Missing | `InputMessageReplyToExternalMessage` unused | S | |
| Forward, including without sender and without captions, multi-select, many targets | Yes | Present | `widgets/forward_sheet.dart:109-116`; `messages_repository.dart:188` | – | |
| Edit text messages | Yes | Present | `messages_repository.dart:153-173` | – | |
| Edit captions / replace media / edit checklist | Yes | Partial | the menu shows "Edit" for any `canBeEdited` message (`message_menu.dart:98`), but only `EditMessageText` exists | S | **Likely bug:** editing a photo caption calls `EditMessageText` on non-text content (unverified on device). `EditMessageCaption` and `EditMessageMedia` are unused |
| Delete for me / for everyone, bulk delete | Yes | Present | `messages_repository.dart:175` | – | |
| Pin / unpin with notify and only-for-me options | Yes | Present | `messages_repository.dart:198-209` | – | |
| Several pinned messages: cycle in the banner, list all, unpin all | Yes | Partial | the banner loads only `GetChatPinnedMessage` | S | `UnpinAllChatMessages` and a pinned-list view are missing |
| Scheduled messages: send, list, send now, reschedule, delete | Yes | Present | `screens/scheduled_messages_screen.dart`; `messages_repository.dart:239-255` | – | |
| Silent send / send when online | Yes | Present | `core/widgets/send_options_sheet.dart` | – | |
| Cloud drafts, including the reply | Yes | Present | `messages_repository.dart:275-295` | – | |
| Drafts in read-only channels | n/a | Planned | owner's fix list | S | |
| Link preview while composing (size, position, remove) | Yes | Present | `widgets/composer.dart:293-338` | – | |
| Albums (grouped photos/videos) | Yes | Present | `SendMessageAlbum` `messages_repository.dart:145` | – | |
| Send as file / original quality | Yes | Present | `media/presentation/screens/send_media_screen.dart:226` | – | |
| Media spoiler and view-once photos/videos | Yes | Present | `media/data/media_sender.dart:111,155-156,180-181` | – | |
| Caption above media | Yes | Missing | `showCaptionAboveMedia: false` hard-coded (`media_sender.dart:154,179`) | S | |
| Video cover and start timestamp | Yes | Missing | `startTimestamp: 0`, no cover (`media_sender.dart:171`) | S | |
| Media editor before sending (crop, rotate, draw, text, stickers, filters, enhance; video trim/mute) | Yes | Missing | the review screen offers caption, spoiler, view-once and conversion only (`send_media_screen.dart`) | L | The ffmpeg converter (codec, size, bitrate) is a Lumina extra |
| Voice messages: record, preview, send, waveform | Yes | Present | `features/voice/data/voice_recorder.dart`; `app/app_conversation_extensions.dart:239` | – | Tap to start/stop instead of hold; no slide-to-lock gesture (owner design) |
| Round video messages: record and send | Yes | Present | `voice/presentation/screens/video_note_recorder_screen.dart:119` | – | Front camera only, no camera flip while recording (unverified) |
| Polls: anonymous, multiple answers, quiz with explanation | Yes | Present | `media/presentation/widgets/poll_composer.dart:36-51` | – | |
| Poll extras: time limit / close date, adding options later, list of voters | Yes | Missing | `openPeriod: 0`, `closeDate: 0` (`poll_composer.dart:50-51`); `AddPollOption`, `GetPollVoters` unused | S | |
| Checklists / to-do lists: send, mark done, add tasks | Yes (2025+) | Missing | `InputMessageChecklist`, `MarkChecklistTasksAsDone`, `AddChecklistTasks` unused | M | Received checklists show as a generic card |
| Location and live location (kept updated in the background) | Yes | Present | `media/presentation/widgets/location_sheet.dart:31`; `media/data/live_location_service.dart` | – | |
| Send a venue (place search) | Yes | Missing | no `InputMessageVenue` | S | Official uses an inline venue bot |
| Share a contact | Yes | Present | `app_conversation_extensions.dart:292-296` | – | |
| Music files with tags and cover | Yes | Present | `media_sender.dart:122-135` | – | |
| Dice / slot / dart animated games | Yes | Missing | `InputMessageDice` unused; received dice are generic (`core/telegram/display.dart:135`) | S | |
| In-app emoji panel (categories, search, recent, keyword suggestions) | Yes | Missing | the composer is a plain `TextField` + attach + orb (`composer.dart:222-282`) | M | Users rely on the system keyboard |
| Sticker panel: installed, recent, favourites, search, sending | Yes | Missing | `GetInstalledStickerSets`, `GetRecentStickers`, `SearchStickers` unused; `InputMessageSticker` never sent | M | |
| GIF panel: saved GIFs, search | Yes | Missing | `GetSavedAnimations`, `InputMessageAnimation` unused | M | |
| Typing custom emoji (Premium) | Yes | Missing | – | M | Rendering exists, see §4 |
| Autocomplete for @mentions, #hashtags and /commands | Yes | Missing | no autocomplete in `composer.dart` | M | |
| "Send as" (post as a channel in groups) | Yes | Missing | `GetChatAvailableMessageSenders`, `SetChatMessageSender` unused | S | |
| Message effects (animated send effects in private chats) | Yes | Missing | `MessageSendOptions.effectId` never set; `GetMessageEffect` unused | M | |
| Paid messages (Stars to message users or groups that charge) | Yes (2025+) | Missing | `paidMessageStarCount` never set | M | Sending to such users will fail |
| Typing / upload / recording chat actions | Yes | Present | `messages_repository.dart:330`; `ChatAction*` | – | Can be hidden (ghost mode) |
| AI text tools (compose, fix, rephrase, summarize) | Yes (2026) | Missing | `ComposeTextWithAi`, `FixTextWithAi`, `SummarizeMessage` exist | M | Lumina has its own on-device LLM, but only for calendar/alarm/note actions |

## 4. Messaging: reading and interacting

| Feature | Official Telegram | Lumina status | Evidence | Effort | Notes |
|---|---|---|---|---|---|
| Rendering text, photo, video, GIF, document, static sticker, location/venue, contact, poll, voice, music, round video, animated emoji, service messages | Yes | Present | `conversation/presentation/widgets/content/message_content_view.dart:51-122`; `core/telegram/display.dart:155-184` | – | |
| Animated stickers (TGS Lottie, WebM video) | Yes | Partial | only the thumbnail is shown (`content/sticker_content.dart:15`) | M | Needs a Lottie/rlottie renderer and looping WebM |
| Animated custom emoji in text | Yes | Partial | static thumbnail (`core/telegram/widgets/formatted_text_view.dart:452`) | M | Same renderer as above |
| Checklists, gifts, giveaways, paid media, invoices, games, forwarded stories, dice | Yes | Partial | all fall to `GenericContent` (`message_content_view.dart:115-121`) | M | A one-line placeholder; you can't interact with them |
| Emoji reactions: add, remove, counts | Yes | Present | `messages_repository.dart:301-327`; `widgets/reactions_row.dart` | – | |
| Custom-emoji reactions and Premium reactions | Yes | Missing | filtered out (`messages_repository.dart:307`); `reactions_row.dart:20` draws emoji only | S | Received custom-emoji reactions are invisible |
| Paid star reactions | Yes | Missing | `AddPendingPaidMessageReaction` unused | S | |
| List of who reacted | Yes | Missing | `GetMessageAddedReactions` unused | S | |
| Read ticks | Yes | Present | `message_bubble.dart:99` | – | |
| "Seen by" list in small groups, read time in private chats | Yes | Missing | `GetMessageViewers`, `GetMessageReadDate` unused | S | |
| View counter on channel posts | Yes | Present | `message_bubble.dart:379-384` | – | |
| Channel post author signatures | Yes | Missing | `authorSignature` never rendered | S | |
| Name colours / accent colours / profile backgrounds | Yes | Missing | `accentColorId` only copied (`telegram_cache.dart:380`) | S | Lumina uses its own palette by design |
| Forward header; tapping a reply jumps to the original | Yes | Present | `message_bubble.dart:188-189,484` | – | |
| Tapping @mentions, mention names, #hashtags, $cashtags or /bot commands | Yes | Missing | `onMention` is never passed by any caller; hashtag, bot command and mention-name entities are styled only (`formatted_text_view.dart:230-241`) | S | High impact: people can't be opened from messages |
| In-app handling of `t.me/…` and `tg://` links (users, chats, invite links, messages, stickers, proxies, addlists, boosts) | Yes | Missing | every URL goes to a Custom Tab or the browser (`core/telegram/link_opener.dart:11-24`); `GetInternalLinkType` unused | M | High impact: invite links, `t.me/channel/123` and proxy links all leave the app |
| Media timestamps in captions (seek on tap) | Yes | Partial | styled, but no caller passes `onMediaTimestamp` | S | |
| Text spoilers, media spoilers | Yes | Present | `formatted_text_view.dart:203`; `content/media_content.dart` | – | |
| Opening view-once media | Yes | Present | `OpenMessageContent` `messages_repository.dart:379` | – | Keeping it is declined by design |
| Select text, copy, copy message link | Yes | Present | `message_menu.dart:94-108` | – | |
| Translate a message or a whole chat | Yes (whole chat needs Premium) | Missing | `TranslateText`, `TranslateMessageText` unused | S | Whisper "Translate to English" works on voice only |
| Voice and round-video transcription | Yes (Premium, or limited free) | Present | `features/transcription/` (offline Whisper) | – | Offline, free, no limits. Telegram's server `RecognizeSpeech` isn't used |
| Translate button contrast | n/a | Planned | owner's fix list | S | |
| Report a message, chat, spam or reactions | Yes | Missing | `ReportChat`, `ReportMessageReactions`, `ReportSupergroupSpam` unused | S | Also missing from the stories viewer (`ReportStory`) |
| Save photo/video/file to the gallery or Downloads | Yes | Missing | no save action in `media/presentation/screens/media_viewer_screen.dart` or `content/document_content.dart`; no MediaStore code | S | |
| Share media or text to other apps | Yes | Missing | no share action anywhere (no `share_plus`/ACTION_SEND for messages) | S | |
| Video player: gestures, speed, streaming while downloading, download progress | Yes | Present | `media/presentation/widgets/video_player_view.dart` (+ uncommitted progress bar) | – | VLC-based, stronger than official |
| Picture-in-picture video (Android PiP) | Yes | Missing | no `enterPictureInPictureMode` in `android/` | S | |
| Background audio with a media notification and lock-screen controls | Yes | Missing | no `audio_service`/MediaSession in the code | M | Unverified whether playback continues when the screen locks |
| Playback speed for voice and audio | Yes (0.2–2.5×) | Present | `core/media/audio_playback.dart`; `general_settings.dart` 0.5–4× | – | |
| In-chat search with filters (photos, videos, files, links, voice) | Yes | Partial | `screens/chat_search_screen.dart:51-57` | S | No search by sender, no music/GIF/round filters, no jump-to-date calendar |
| Shared media in profiles (media grid, files, links, music, voice, GIFs, groups in common) | Yes | Missing | chat info has only extension tabs (story history); `GetGroupsInCommon` unused | M | Reachable today only through chat search filters |
| Jump to latest with unread count; unread divider; day headers | Yes | Present | `screens/conversation_screen.dart:400,468,495,545` | – | |
| Jump to next unread mention or reaction inside a chat | Yes | Missing | – | S | |
| Instant View | Yes | Present | `screens/instant_view_screen.dart` | – | Embedded HTML isn't run, by design |
| Sponsored messages (show, click, report) | Yes | Present | `messages_repository.dart:353-376` | – | Reporting (`ReportChatSponsoredMessage`) is missing |
| Comments on channel posts (discussion threads) | Yes | Missing | `GetMessageThread`, `GetMessageThreadHistory` unused | M | High impact for channel readers |
| Saved Messages split by source chat ("saved dialogs") | Yes | Missing | `LoadSavedMessagesTopics` unused | M | Saved Messages opens as an ordinary chat |
| Saved Messages tags (Premium) | Yes | Missing | `GetSavedMessagesTags`, `SetSavedMessagesTagLabel` unused | S | |
| Fact checks on posts | Yes | Missing | `factCheck` not rendered (unverified on real data) | S | |
| Screenshot blocking in protected chats and secret chats | Yes | Partial | copy and save disabled (`message_menu.dart:46`), but no `FLAG_SECURE` anywhere | S | |
| Auto-delete timer (per chat, secret-chat timer) | Yes | Missing | `SetChatMessageAutoDeleteTime` unused; only the service message is shown | S | |

## 5. Groups & channels

| Feature | Official Telegram | Lumina status | Evidence | Effort | Notes |
|---|---|---|---|---|---|
| Create group, channel, secret chat | Yes | Present | `features/chat_info/data/chat_info_repository.dart:209-229` | – | Stock dialogs; designed flows are Planned |
| Designed new group / new channel flows (replacing stock dialogs) | n/a | Planned | owner's list | M | |
| Create a forum group or supergroup directly, set its photo during creation | Yes | Missing | `isForum: false` (`chat_info_repository.dart:219`); basic groups only for "New group" | S | |
| Edit title and description | Yes | Present | `chat_info_repository.dart:163-167` | – | |
| Change group or channel photo | Yes | Missing | `SetChatPhoto` unused | S | |
| Public / private type and username (and collectible usernames) | Yes | Missing | `SetSupergroupUsername` unused | S | |
| Member list, search, add, remove | Yes | Present | `chat_info_repository.dart:81-131` | – | |
| Promote and demote admins with rights and custom title | Yes | Present | `chat_info_repository.dart:135-152` (`SetChatMemberStatus`, `SetChatMemberTag`) | – | |
| Per-member restrictions with expiry; banned and restricted lists; unban | Yes | Partial | "Remove" = `BanChatMember(bannedUntilDate: 0)` (`:130-132`) | S | No timed restrictions, no lists, no unban |
| Default permissions and slow mode | Yes | Present | `chat_info_repository.dart:156-161`; `widgets/permissions_sheet.dart` | – | |
| Primary invite link: create, copy, replace | Yes | Present | `chat_info_repository.dart:169-185` | – | |
| Extra invite links (name, expiry, usage limit, approval, subscription price), list, revoke, see who joined | Yes | Missing | `GetChatInviteLinks`, `EditChatInviteLink`, `RevokeChatInviteLink`, `GetChatInviteLinkMembers` unused | M | |
| Join requests: approve or decline; toggle join-by-request | Yes | Missing | `GetChatJoinRequests`, `ProcessChatJoinRequest(s)`, `ToggleSupergroupJoinByRequest` unused | S | |
| Join by invite link (`t.me/+…`, `joinchat`), with a preview | Yes | Missing | `CheckChatInviteLink`, `JoinChatByInviteLink` unused | S | Also blocked by the link handling in §4 |
| Join a public group / subscribe to a channel; Mute bar in channels | Yes | Present | `JoinChat` (`chat_info_repository.dart:187`); uncommitted `_ReadOnlyBar` (`conversation_screen.dart:654`) | – | |
| Leave | Yes | Present | `chats_repository.dart:86` | – | |
| Delete group or channel (owner) | Yes | Missing | `DeleteChat` unused | S | |
| Transfer ownership | Yes | Missing | `TransferChatOwnership` unused | S | |
| Recent actions (admin log) | Yes | Missing | `GetChatEventLog` unused | M | |
| Channel and group statistics, message and story stats | Yes | Missing | `GetChatStatistics`, `GetMessageStatistics`, `GetStoryStatistics` unused | M | Needs charts |
| Boosts: boost a chat, boost status and levels, boost links, unrestrict-by-boost | Yes | Missing | `BoostChat`, `GetChatBoostStatus` unused | M | `CanPostStory` boost-needed message only (`stories_repository.dart:182`) |
| Show and open the linked discussion group | Yes | Present | `chat_info_screen.dart` (`linkedChatId`) | – | |
| Set or unlink the discussion group | Yes | Missing | `SetChatDiscussionGroup` unused | S | |
| Sign messages / show author profiles | Yes | Missing | `ToggleSupergroupSignMessages` unused | S | |
| Automatic translation toggle for channels | Yes | Missing | `ToggleSupergroupHasAutomaticTranslation` unused | S | |
| Similar-channel recommendations | Yes | Missing | `GetChatSimilarChats` unused | S | |
| Channel direct messages (a channel's DM inbox, paid) | Yes (2025+) | Missing | `SetChatDirectMessagesGroup`, `LoadDirectMessagesChatTopics` unused | M | |
| Suggested posts | Yes (2025+) | Missing | `ApproveSuggestedPost`, `DeclineSuggestedPost` unused | M | |
| Monetization: revenue, ad share, Stars/TON withdrawals | Yes | Missing | `GetChatRevenueStatistics`, `GetStarRevenueStatistics` unused | M | Niche |
| Allowed reactions per chat | Yes | Missing | `SetChatAvailableReactions` unused | S | |
| Anti-spam, hidden members, history for new members, protected content, join-to-send | Yes | Missing | `ToggleSupergroupHasAggressiveAntiSpamEnabled`, `ToggleSupergroupHasHiddenMembers`, `ToggleSupergroupIsAllHistoryAvailable`, `ToggleChatHasProtectedContent`, `ToggleSupergroupJoinToSendMessages` unused | S | |
| Forum topics: list, open, create, edit, close, pin, hide General | Yes | Missing | `GetForumTopics`, `CreateForumTopic`, `GetForumTopicHistory` unused; topic typing ignored (`telegram_cache.dart:154`) | L | High impact: many large groups are forums |
| Group sticker set / custom emoji set | Yes | Missing | `SetSupergroupStickerSet`, `SetSupergroupCustomEmojiStickerSet` unused | S | |
| Paid channel subscriptions | Yes | Missing | `CreateChatSubscriptionInviteLink` unused | M | |
| Communities (TDLib 1.8.69) | Yes | Missing | `CreateCommunity` exists; DECISIONS D5 and D15 | M | |

## 6. Calls

| Feature | Official Telegram | Lumina status | Evidence | Effort | Notes |
|---|---|---|---|---|---|
| 1:1 voice calls | Yes | Present | `features/calls/data/calls_repository.dart:26`; tgcalls engine | – | Device test pending (handoff §2.3 B) |
| 1:1 video: front/back camera, switch while in a call | Yes | Present | `calls/presentation/call_screen.dart:471-479` | – | Device test pending |
| Screen sharing in 1:1 calls | Yes | Present | `call_screen.dart:484`; `ScreenPip.kt` | – | Includes a camera bubble composited into the stream (Lumina extra) |
| Key emojis, rating, debug log | Yes | Present | `call_screen.dart:361`; `calls_repository.dart:67` | – | |
| Calls through a SOCKS5 proxy | Yes | Present | handoff §5.7 step 7 | – | |
| System Phone app integration (Telecom, Bluetooth, car, call log) | Yes (ConnectionService) | Present | `CallTelecom.kt` | – | Lumina adds a managed calling account that the Google dialer can use |
| Incoming calls while the app is closed | Yes (FCM) | Partial | depends on the keep-alive service (`android/.../background/Background.kt`) | – | No FCM; "saver" mode can't ring |
| Recent calls list (Calls tab, missed/outgoing filters) | Yes | Missing | `SearchCallMessages` unused; the nav bar has Chats and Settings only (`home/presentation/widgets/glow_nav_bar.dart:42-50`) | S | |
| Android picture-in-picture during video calls | Yes | Missing | in-app "return to call" pill only (`call_host.dart`) | S | |
| Proximity sensor and earpiece routing | Yes | Partial | Speaker toggle present (`call_screen.dart:498`) | S | Proximity wake lock is unverified |
| Group voice/video chats (join, speak, raise hand, video, screen share, recording) | Yes | Missing | `CreateVideoChat`, `JoinGroupCall` unused; the JNI wraps 1:1 only (`android/calls-engine/src/lumina_calls_jni.cpp`) | L | Needs tgcalls `GroupInstance` |
| Live streams (RTMP) and viewing | Yes | Missing | `GetVideoChatRtmpUrl` unused | L | |
| Conference calls (group calls from 1:1, invite links, E2E) | Yes (2025+) | Missing | group-call functions unused | L | |
| Live stories | Yes (2026) | Missing | `StartLiveStory`, `JoinLiveStory` unused; recognized only in `CanPostStory` (`stories_repository.dart:188`) | L | |

## 7. Bots & mini apps

| Feature | Official Telegram | Lumina status | Evidence | Effort | Notes |
|---|---|---|---|---|---|
| Inline keyboards: callback, URL, switch-inline, login-URL, web-app, copy and pay buttons | Yes | Missing | `replyMarkup` is never rendered (only copied in `telegram_cache.dart:366`); `GetCallbackQueryAnswer` unused | M | High impact: most bots can't be used |
| Reply keyboards (custom keyboard instead of the system one), force reply, remove keyboard | Yes | Missing | `replyMarkupMessageId` ignored | S | |
| Bot "Start" button, start parameters, command menu, menu button | Yes | Missing | `GetCommands`/bot info commands unused | S | Unverified whether a new bot chat shows any start action |
| Inline bots (`@gif`, `@vid`, `@bot query`) | Yes | Missing | `GetInlineQueryResults`, `SendInlineQueryResultMessage` unused | M | |
| Mini apps / web apps (menu button, attachment menu, main app, full screen, home-screen shortcut) | Yes | Missing | `OpenWebApp`, `GetMainWebApp` unused | L | Conflicts with the "no embedded WebView" decision (handoff 2.2 #17); a Custom Tab can't host the JS bridge |
| Payments (invoices, Stars, receipts) | Yes | Missing | `GetPaymentForm`, `SendPaymentForm` unused; `MessageInvoice` is generic | M | |
| HTML5 games | Yes | Missing | `MessageGame` generic | M | Needs a WebView too |
| Bot verification badges, affiliate programs, bot business connection, ephemeral bot replies | Yes | Missing | – | M | Niche |
| Log in as a bot account | No | Present | `auth_repository.dart:69`; `auth/domain/account_capabilities.dart` | – | Lumina-only |

## 8. Business (Telegram Business, Premium)

| Feature | Official Telegram | Lumina status | Evidence | Effort | Notes |
|---|---|---|---|---|---|
| Opening hours, location, start page/intro | Yes | Missing | `SetBusinessOpeningHours`, `SetBusinessLocation`, `SetBusinessStartPage` unused | M | Also not shown on business profiles |
| Greeting and away messages | Yes | Missing | `SetBusinessGreetingMessageSettings`, `SetBusinessAwayMessageSettings` | M | |
| Quick replies (`/shortcut`) | Yes | Missing | `LoadQuickReplyShortcuts`, `SendQuickReplyShortcutMessages` | M | |
| Business chat links | Yes | Missing | `CreateBusinessChatLink` | S | |
| Connected business bots | Yes | Missing | `SetBusinessConnectedBot` | S | |

## 9. Premium, Stars, gifts, TON

| Feature | Official Telegram | Lumina status | Evidence | Effort | Notes |
|---|---|---|---|---|---|
| Buy Premium through Google Play | Yes | Not possible on TDLib 1.8.69 | `AssignStoreTransaction` needs a Play purchase for Telegram's own package | – | A third-party app can link to `@PremiumBot` or a gift-code page instead |
| Show Premium status, limits and features | Yes | Missing | `GetPremiumState`, `GetPremiumLimit` unused | S | |
| Emoji status: set and display | Yes | Missing | `SetEmojiStatus` unused; not drawn next to names | S | |
| Stars: balance, transactions, subscriptions | Yes | Missing | `GetStarTransactions`, `GetStarSubscriptions` unused | M | |
| Buy Stars in-app | Yes | Not possible on TDLib 1.8.69 | Play billing restriction, as above | – | Fragment/bot links possible |
| Gifts: send, receive, show on profile, upgrade, transfer, resale, auctions, collections, crafting | Yes | Missing | `SendGift`, `GetReceivedGifts`, `UpgradeGift`, `TransferGift` unused; `MessageGift` generic | L | |
| Collectible usernames and numbers | Yes | Missing | `GetCollectibleItemInfo` unused | S | |
| Giveaways: view and join | Yes | Missing | `GetGiveawayInfo` unused | S | |
| TON wallet (2026 TDLib API) | Yes | Missing | `LoadTonWalletState`, `SendTonWalletTransfer` | L | |
| Premium ad-free switch | Yes | Present | `general_settings.dart` `ChannelAdsSettings`; `ToggleHasSponsoredMessagesEnabled` | – | Plus a local hide for non-Premium users |

## 10. Stories

| Feature | Official Telegram | Lumina status | Evidence | Effort | Notes |
|---|---|---|---|---|---|
| Watch stories: halos, viewer, swipe between people, reactions, replies | Yes | Present | `features/stories/presentation/screens/story_viewer_screen.dart`; `stories_repository.dart:105-135` | – | Bottom-left ring, not top bars (owner design) |
| Post photo/video stories, caption, post as a channel | Yes | Present | `stories_repository.dart:167-249` | – | |
| Story privacy: everyone, contacts, close friends | Yes | Partial | `stories_repository.dart:14-16` | S | "Selected people", "except", allow screenshots/forwarding and the 6/12/48 h periods are missing; captions have no formatting (`entities: const []`) |
| Story stickers and areas: link, location, reaction, (weather) | Yes | Partial | `domain/story_decoration.dart`; `presentation/widgets/story_areas_layer.dart` | M | You can't create weather, mention, repost or music areas (handoff §2.3 E) |
| Story editor: drawing, text styles, filters, dual camera | Yes | Missing | – | L | |
| Viewers list with reactions | Yes | Present | `presentation/widgets/story_viewers_sheet.dart` | – | |
| Edit or delete your own story | Yes | Missing | `EditStory`, `DeleteStory` unused | S | |
| Profile page stories, pinning, archive, albums | Yes | Missing | `GetChatPostedToChatPageStories`, `GetChatArchivedStories`, `ToggleStoryIsPostedToChatPage`, story-album API unused | M | |
| Repost or share a story to chats | Yes | Missing | – | S | |
| Stealth mode (Premium) | Yes | Missing | `ActivateStoryStealthMode` unused | S | Lumina's "View stories anonymously" (never calls `openStory`) is a client-side alternative |
| Hide a person's stories (move to archive), story notifications | Yes | Missing | `SetChatActiveStoriesList` / story notification settings unused | S | Only a global "Hide stories" switch |
| Report a story | Yes | Missing | `ReportStory` unused | S | |
| Some story content types | Yes | Partial | "This story type is not supported yet" (`story_viewer_screen.dart:425`) | M | |
| Story history of other people, saved locally | No | Present | `stories/data/saved_stories_store.dart` | – | Lumina-only |

## 11. Contacts & people

| Feature | Official Telegram | Lumina status | Evidence | Effort | Notes |
|---|---|---|---|---|---|
| Contacts list | Yes | Partial | `chat_info/presentation/widgets/contact_picker.dart` (only inside "New message"/"Add members") | S | No Contacts screen sorted by last seen |
| Add, edit or delete a contact | Yes | Missing | `AddContact`, `RemoveContacts` unused | S | |
| Phone-book sync and import | Yes | Missing | no `READ_CONTACTS` in `AndroidManifest.xml`; `ImportContacts` unused | M | |
| Find by username or phone | Yes | Present | `SearchPublicChat`, `SearchUserByPhoneNumber` | – | |
| Close friends list editing | Yes | Missing | `SetCloseFriends`, `GetCloseFriends` unused | S | Story privacy offers "Close friends", but you can't edit the list |
| Blocked users: block, unblock, list | Yes | Missing | `SetMessageSenderBlockList`, `GetBlockedMessageSenders` unused | S | High impact, safety |
| User profile: bio, username, phone | Yes | Present | `chat_info_repository.dart:71-78` | – | |
| User profile extras: photo gallery, birthday, personal channel, business info, groups in common, gifts | Yes | Missing | `GetUserProfilePhotos`, `GetGroupsInCommon` unused | M | |
| Birthdays (set, show, contact reminders) | Yes | Missing | `SetBirthdate` unused | S | |
| People Nearby | Removed by Telegram (2024) | Not possible on TDLib 1.8.69 | no nearby function in `tdapi/functions/` | – | |
| Invite friends (SMS/share) | Yes | Missing | – | S | |

## 12. Privacy & security

| Feature | Official Telegram | Lumina status | Evidence | Effort | Notes |
|---|---|---|---|---|---|
| Server privacy rules: last seen, phone number, profile photo, forwards, calls (P2P), group invites, voice messages, bio, birthday, gifts | Yes | Missing | `GetUserPrivacySettingRules`, `SetUserPrivacySettingRules` unused | M | High impact |
| Who can message me / paid messages from non-contacts | Yes | Missing | `SetNewChatPrivacySettings` unused | S | |
| Hide read time | Yes | Missing | `SetReadDatePrivacySettings` unused | S | |
| Ghost mode: no read receipts, typing, online status or story views | Partly (Premium stealth only) | Present | `features/settings/presentation/widgets/general_settings.dart`; `app/lifecycle_watcher.dart:62` | – | Client-side, Lumina extra |
| Passcode or biometric app lock, hide content in the app switcher | Yes | Missing | none (no `local_auth`, no `FLAG_SECURE`) | S | Purely client-side |
| Default auto-delete timer for new chats | Yes | Missing | `SetDefaultMessageAutoDeleteTime` unused | S | |
| Secret chats: create, chat | Yes | Present | `chat_info_repository.dart:228` | – | |
| Secret chat extras: self-destruct timer, key visualisation | Yes | Partial | – | S | Unverified that the key image is shown; the timer is missing |
| Sensitive content filter switch (18+) | Yes | Missing | the option is never set | S | |
| Local database encrypted with a Keystore key | Yes (passcode-based) | Present | DECISIONS D10 | – | |
| Delete synced contacts, frequent-contacts toggle, payment data cleanup | Yes | Missing | – | S | |

## 13. Notifications & sounds

| Feature | Official Telegram | Lumina status | Evidence | Effort | Notes |
|---|---|---|---|---|---|
| Message notifications with sender avatars, inline reply and "Mark as read" | Yes | Present | `features/notifications/data/notification_center.dart:113-208`; `android/.../background/MessageNotifications.kt:84-90` | – | Device test pending |
| Push delivery | FCM | Partial | keep-alive service or 15-minute WorkManager sync (`Background.kt`) | M | No FCM by design. UnifiedPush (`RegisterDevice`) is the planned option |
| Settings for private / group / channel notifications (on/off, preview, sound) | Yes | Missing | `SetScopeNotificationSettings` unused (scope settings are read only, `telegram_cache.dart`) | S | |
| Per-chat exceptions: custom sound, mute durations, preview | Yes | Missing | only `muteFor` forever/0 (`chats_repository.dart:65-76`) | S | |
| Custom notification sounds (upload your own) | Yes | Missing | `AddSavedNotificationSound` unused | S | |
| In-app sounds, vibration and banners while the app is open | Yes | Missing | the notification centre posts nothing in the foreground | S | |
| Reaction and story notification settings | Yes | Missing | `SetReactionNotificationSettings` unused | S | |
| Conversation shortcuts (Android 11+ "Conversations" section, per-chat priority) | Yes | Missing | no `ShortcutInfo` / `setShortcutId` in `MessageNotifications.kt` | S | |
| Launcher unread badge | Yes | Missing | unverified | S | |
| Full-screen incoming-call notification | Yes | Present | `CallService.kt` | – | |

## 14. Data & storage, network

| Feature | Official Telegram | Lumina status | Evidence | Effort | Notes |
|---|---|---|---|---|---|
| Storage usage by type, clear cache, keep media for N days | Yes | Present | `features/maintenance/presentation/widgets/storage_settings.dart`; `data/storage_repository.dart:62-70` | – | |
| Per-chat storage breakdown, maximum cache size | Yes | Missing | `GetStorageStatistics` per-chat data isn't shown | S | |
| Auto-download by network (mobile, Wi-Fi, roaming) and media type, with size limits | Yes | Missing | `GetAutoDownloadSettingsPresets` unused; no settings | M | Unverified what Lumina downloads automatically today (media is fetched on display) |
| Network usage statistics | Yes | Missing | `GetNetworkStatistics` unused | S | |
| Tell TDLib the network type | Yes | Missing | `SetNetworkType` unused | S | Affects TDLib's own auto-download and stats |
| Data saver / less data for calls | Yes | Missing | – | S | |
| Downloads manager (list, pause, search) | Yes | Missing | `AddFileToDownloads`, `SearchFileDownloads` unused | M | |
| Proxies: SOCKS5, HTTP, MTProto; list, test, ping, share, edit | Yes | Present | `features/proxy/data/proxy_repository.dart:84-152` | – | |
| Proxy QR scan, header proxy button | Partly | Present | uncommitted `proxy_scan_screen.dart`, `proxy_button.dart` | – | |
| Automatic proxy switching | Yes | Missing | – | S | |
| Streaming playback while downloading | Yes | Present | `core/media/tdlib_stream_server.dart` | – | Device test pending |

## 15. Appearance

| Feature | Official Telegram | Lumina status | Evidence | Effort | Notes |
|---|---|---|---|---|---|
| Light theme / follow system / auto night mode | Yes | Missing | `themeMode: ThemeMode.dark` fixed (`app/app.dart:98`) | M | Design work for the "Glowing Relaxation" palette |
| Chat wallpapers (global, per chat, set for both sides) | Yes | Missing | `SetChatBackground`, `SetDefaultBackground` unused; received backgrounds not drawn | M | |
| Chat themes (including gift themes) | Yes | Missing | `SetChatTheme` unused | M | |
| Custom themes (create, share `.attheme`) | Yes | Missing | – | L | Conflicts with Lumina's fixed design language |
| Message text size, bubble corner radius | Yes | Missing | – | S | Unverified that the system font scale is fully respected |
| Alternative app icons | Yes | Missing | – | S | |
| Reduce motion / animations | Yes (power saving) | Present | `core/theme/motion.dart` (`Motion.ambientEnabled`) | – | |
| Distinct non-Telegram visual design | No | Present | `core/theme/` | – | Lumina-only |
| 120 Hz smoothness work | Yes | Planned | owner's list | M | |

## 16. Languages & localization

| Feature | Official Telegram | Lumina status | Evidence | Effort | Notes |
|---|---|---|---|---|---|
| UI in about 20 official and many community languages | Yes | Missing | strings are hard-coded English; no l10n setup | L | TDLib language packs (`GetLanguagePackStrings`) could supply translations |
| RTL interface | Yes | Partial | Flutter mirrors only for RTL locales, and Lumina has none; Instant View handles `isRtl` (`instant_view_screen.dart:100`) | M | Unverified how Arabic/Persian text aligns in bubbles |
| Message translation | Yes | Missing | see §4 | S | |
| Speech dictation language | No | Present | `transcription/presentation/widgets/speech_settings.dart:53` | – | |

## 17. Accessibility

| Feature | Official Telegram | Lumina status | Evidence | Effort | Notes |
|---|---|---|---|---|---|
| Screen-reader labels and 48 dp targets on custom widgets | Yes | Present | conventions §6; e.g. `timeline_chat_row.dart:128`, `call_screen.dart:332,361` | – | No TalkBack pass on a device yet (handoff §8) |
| Reduced motion | Yes | Present | `motion.dart` | – | |
| Large text / font scaling | Yes | Partial | unverified | S | |
| Audio transcription for deaf users | Premium | Present | Whisper | – | Free and offline |
| Contrast issues (translate button) | n/a | Planned | owner's fix list | S | |

## 18. Sharing and Android integration

| Feature | Official Telegram | Lumina status | Evidence | Effort | Notes |
|---|---|---|---|---|---|
| Share into the app from other apps (text, links, files, multiple media) | Yes | Missing | the only activity intent-filter is MAIN/LAUNCHER (`android/app/src/main/AndroidManifest.xml:55-58`) | S | High impact |
| Direct Share targets (recent chats in the system share sheet) | Yes | Missing | no sharing shortcuts | S | |
| Open `t.me` / `tg://` links from other apps | Yes | Missing | no VIEW intent-filters | S | Needs the link handling from §4 |
| Share messages or media out to other apps | Yes | Missing | – | S | |
| Home-screen widgets (chats, shortcuts) | Yes | Missing | – | M | |
| Launcher shortcuts (long-press icon, pinned chat shortcuts) | Yes | Missing | – | S | |
| Android Auto messaging | Yes | Missing | no `com.google.android.gms.car.application` meta-data | S | The MessagingStyle reply and read actions already exist |
| Notification bubbles | Yes | Missing | no `BubbleMetadata` | M | |
| Video picture-in-picture | Yes | Missing | see §4 | S | |
| Telecom / Phone-app integration | Yes | Present | `CallTelecom.kt` | – | |
| System actions from messages (calendar, alarm, timer, note) | No | Present | `features/assistant/`; `MainActivity.kt:173-215` | – | Lumina-only |

## 19. Saved, files, downloads

| Feature | Official Telegram | Lumina status | Evidence | Effort | Notes |
|---|---|---|---|---|---|
| Saved Messages as a chat | Yes | Present | the self chat opens like any chat | – | No special entry point found (unverified) |
| Saved Messages by source chat, tags | Yes | Missing | see §4 | M | |
| Downloads manager | Yes | Missing | see §14 | M | |
| Attach from the system photo picker, camera, files | Yes | Present | `media/presentation/widgets/attach_sheet.dart:50-56` | – | |
| Sticker and emoji pack management (add, remove, reorder, archived, trending, create your own) | Yes | Missing | `ChangeStickerSet`, `ReorderInstalledStickerSets`, `GetTrendingStickerSets`, `CreateNewStickerSet` unused | M | Opening a sticker pack from a message is missing too |

## 20. Telegram Passport and other

| Feature | Official Telegram | Lumina status | Evidence | Effort | Notes |
|---|---|---|---|---|---|
| Telegram Passport | Yes | Missing | `GetPassportAuthorizationForm`, `SetPassportElement` unused | M | Rarely used |
| Import chats from other messengers | Yes | Missing | `ImportMessages` unused | M | |
| Clear all drafts | Yes | Missing | `ClearAllDraftMessages` unused | S | |
| Mark a whole folder or list as read | Yes | Missing | `ReadChatList` unused | S | Part of the folders plan |
| "Tips" channel, FAQ, ask a volunteer | Yes | Missing | – | S | Low value |
| Power-saving modes | Yes | Present | background modes `connected` / `saver` / `off` (`Background.kt`) | – | Different scope: connection, not animations |
| Bot-account support in the UI | No | Present | `home/presentation/widgets/bot_limitations_card.dart` | – | Lumina-only |

---

## Top 25 gaps to close next

Ranked by user impact against effort, highest value first.

1. **Tappable mentions, hashtags and bot commands, plus in-app `t.me`/`tg://` links**
   (`GetInternalLinkType`, `CheckChatInviteLink`, `JoinChatByInviteLink`). Right now
   every Telegram link leaves the app, and invite links can't be used at all. S–M.
2. **Fix the two bugs.** "Mark as read" on unread chats should call
   `ViewMessages`/`ReadChatList`. "Edit" on captioned media should use
   `EditMessageCaption`. Both are visible failures and each takes about an hour. S.
3. **Inline and reply keyboards with callback buttons.** Without them almost every
   bot (and many channels' URL buttons) can't be used. M.
4. **Share into Lumina and Direct Share targets.** Sharing a link or photo "to
   Telegram" is one of the most common Android flows, and Lumina doesn't appear in
   the share sheet. S–M.
5. **Block, unblock and report users, chats and messages.** These are basic safety
   tools; all the APIs exist. S.
6. **Save to gallery and share out from the media viewer.** Users can't keep a
   received photo or video today. S.
7. **Profile editing** (name, bio, username, photo, birthday). New users can't even
   set a photo. S.
8. **Chat folders and Archive** (already designed). Without Archive, archived chats
   are unreachable, and folders are central to heavy users. M.
9. **Sticker, GIF and emoji panels.** Stickers and GIFs are a large share of Telegram
   traffic, and Lumina can't send either. M.
10. **Animated stickers and custom emoji** (Lottie/WebM). Every received animated
    sticker and Premium emoji looks frozen. M.
11. **Comments on channel posts** (message threads). Channels are a core use case,
    and their discussions are unreachable. M.
12. **Telegram privacy settings** (last seen, phone, photo, calls, invites,
    messages). Users can't control what others see, apart from client-side ghost
    mode. M.
13. **Active sessions, QR confirm for Desktop and 2FA management.** These are
    security essentials; the QR scanner already exists. S.
14. **Per-message translation** (`TranslateMessageText`). It's cheap to add and
    expected in international chats; the planned contrast fix goes in the same pass. S.
15. **Notification settings**: scope settings, per-chat exceptions, mute durations,
    in-app alerts. Without them, muting is all or nothing. S–M.
16. **Contacts**: a Contacts screen, add/edit/delete, optional phone-book import.
    Today the contact list only appears inside pickers. S–M.
17. **Group admin basics**: change photo, username, join requests, extra invite
    links, banned list, delete the group. Without these admins have to fall back to
    the official app. M.
18. **Forum topics.** Many large groups are forums, and Lumina shows them as one
    flat chat. L.
19. **Own stories**: edit, delete, pin to profile; edit the close-friends list.
    Posting works, but a mistake can't be undone. S.
20. **Reactions**: custom-emoji and paid reactions, and who reacted. Received
    custom reactions are currently invisible. S.
21. **Passcode or biometric lock** with a hidden app-switcher preview. It's
    client-side only and a common privacy request. S–M.
22. **Auto-download settings and network usage**, plus `SetNetworkType`. These
    matter for mobile-data users in the censored regions Lumina targets. M.
23. **Light theme and chat wallpapers.** Today the app is dark-only, and wallpapers
    set by chat partners aren't shown. M.
24. **Multiple accounts.** It's a big architectural change, but a top request among
    power users. L.
25. **Group voice/video chats and live streams.** They need tgcalls `GroupInstance`
    and are the largest remaining calls gap. L.

Just outside the top 25: UI localization and RTL (L), a calls list (S), checklists (M),
Android Auto (S), Saved Messages topics (M), mini apps (L, conflicts with the
no-WebView decision), and multi-account-aware notifications.

---

## What Lumina has that official Telegram doesn't

For fairness, these are features Lumina has that the official Android app lacks, or
does differently:

- **Offline Whisper transcription** of voice and round-video messages, with
  "Translate to English". It's free and unlimited and nothing is sent to a server.
  Official transcription is server-side and Premium-gated or limited.
  (`features/transcription/`, bundled `ggml-base-q5_1.bin`.)
- **Offline dictation** by long-pressing the send orb, with optional auto-send.
- **On-device LLM actions** (SmolLM2-360M on llama.cpp). A message can become a
  calendar event, alarm, timer/reminder or note through system intents, after an
  editable confirmation (`features/assistant/`, DECISIONS D13).
- **Encrypted local full-text search** (SQLite3MultipleCiphers, FTS5 trigram +
  unicode61) across all indexed messages, including substring and CJK search.
  It's instant and works offline (`features/search/`).
- **Story history.** Other people's stories can be saved to the device, one tab per
  person, with optional auto-save, so they can be rewatched after 24 hours.
  Forward-protected stories are respected (`stories/data/saved_stories_store.dart`).
- **Free ghost mode:** no read receipts, no typing, appear offline, anonymous story
  views and manual "Mark as read". Official only has Premium stealth mode for
  stories and the read-time privacy setting.
- **Hiding channel ads without Premium** (local, with a terms warning) and hiding
  the proxy sponsor channel.
- **Pre-send video conversion with ffmpeg**: compact variants, an H.264
  "compatible" version for HEVC/VP9/AV1/10-bit sources, and an advanced mode for
  codec, size, bitrate, fps and audio (`media/data/video_presets.dart`).
- **VLC playback with streaming over a loopback HTTP range server.** It plays codecs
  the official player can't, and adds gestures (double-tap ±10 s, scrub, brightness
  and volume, pinch zoom) and download progress on the seek bar.
- **Voice and audio speed up to 4×.** Official stops at about 2–2.5×.
- **Screen sharing with a camera bubble composited into one stream** in 1:1 calls
  (`ScreenPip.kt`).
- **A managed Phone-app calling account**, so the Google dialer can start Lumina
  calls even when Lumina isn't running.
- **No Google services:** no Firebase. A keep-alive service or WorkManager handles
  notifications, so it works on de-Googled phones. It's GPL-3.0 and built in CI from
  pinned TDLib.
- **Bot-token login**, so a bot account can be used interactively.
- **Its own UI** ("Glowing Relaxation": timeline ribbon, compose orb, story halos,
  the Glimpses vertical story stream) instead of a Telegram look-alike.
- **Keystore-held database key**, with backups disabled so a database never leaves
  without its key (DECISIONS D10).
- **Proxy restore after logout.** Proxy secrets live in Keystore storage and are
  re-added after the TDLib database is wiped.
