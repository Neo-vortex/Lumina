# Full bot support — design

Date: 2026-10-27. Status: approved in conversation, spec awaiting review.

## Goal

Bots work fully in Lumina, in Lumina's own glowing style (not a copy of
Telegram). Inline keyboards under messages already exist
(`conversation/presentation/widgets/inline_keyboard.dart`). This adds:
reply keyboards, a command palette, the bot menu button and web apps,
inline mode, a welcome card for new bots, and bot info in the profile.
Scope is the user chatting *with* bots (not logged in as one).

Build order, one commit series each: (1) welcome card + profile section,
(2) command palette, (3) reply keyboards, (4) inline mode, (5) menu
button + web apps.

## Decisions (owner)

| Topic | Choice |
|---|---|
| Web apps | Custom Tab by default; setting to open in Lumina's own sheet (WebView) |
| Reply keyboards | ≤ 6 buttons: chip strip above the composer; more: panel in the keyboard's place |
| Commands | Command palette (search sheet: commands, menu button, web app) |
| Inline mode | Panel above the composer, draggable up into a full sheet |
| New bot | Welcome card in the empty chat (media, description, Start) |

## Architecture

New feature folder `lib/features/bots/`:

- `data/bots_repository.dart` — TDLib only here: `getUserFullInfo`
  (`botInfo`: description, photo/animation, commands, menu button,
  privacy policy url, web app), `getChatAdministrators`/group bot
  commands as needed, `getInlineQueryResults` (with `nextOffset`),
  `sendInlineQueryResultMessage`, `openWebApp` / `closeWebApp` /
  `getWebAppUrl` / `sendWebAppData`. Full info cached per bot user id.
- `bloc/bot_chat_cubit.dart` — one per bot chat or group with bots:
  current reply keyboard (from the newest message with one), keyboard
  open/hidden, bot info, inline query state (text, results, next
  offset, loading/error).
- Widgets: `ReplyKeyboardStrip`, `ReplyKeyboardPanel`, `CommandPalette`,
  `InlineResultsPanel`, `BotWelcomeCard`, `BotProfileSection`,
  `WebAppSheet`.

Wiring only through `app/feature_wiring.dart`; the conversation feature
never imports `features/bots`. New `ConversationExtensions` hooks:

- `aboveComposer(context, chat)` — strip or inline panel;
- `keyboardReplacement(context, chat)` — the reply keyboard panel in the
  keyboard area, with a toggle in the composer;
- `composerLeading(context, chat)` — the `/` (or menu) button;
- `emptyChat(context, chat)` — the welcome card.

The profile gets a `BotProfileSection` slot. Messages and `replyMarkup`
changes reach the cubit through TDLib updates.

Settings → Chats: "Open web apps in: Browser tab / Lumina" (default
Browser tab). New dependency: `webview_flutter` (Lumina mode only).

## Behaviour

### Reply keyboards
- Keyboard in force = newest message whose `replyMarkup` is
  `ReplyMarkupShowKeyboard`; `ReplyMarkupRemoveKeyboard` clears it. In
  groups, a `isPersonal` keyboard applies only when the message mentions
  or replies to the user.
- ≤ 6 buttons → strip; more → panel replacing the system keyboard, with
  a keyboard/buttons toggle in the composer.
- Tap sends the button text. `oneTime` keyboards hide after a tap
  (reopenable from the toggle).
- `RequestPhoneNumber` → confirm sheet, sends own contact.
  `RequestLocation` → confirm sheet, sends coarse current location.
  `RequestPoll` → opens poll creation. `RequestUsers`/`RequestChat` →
  "Not supported yet" (needs a picker); `RequestManagedBot` likewise.
  `KeyboardButtonTypeWebApp` opens the web app (see Web apps).
- `ReplyMarkupForceReply` starts a reply to that message and uses its
  `inputFieldPlaceholder`.

### Command palette
- Opens from the `/` button, or when `/` is typed at the start of the
  message (pre-filtered by what follows).
- Sections: Open app (web app, if any), menu-button commands, all
  commands with descriptions; search field filters.
- Tap sends `/cmd`; in a group with more than one bot, `/cmd@botname`.
- If the bot's menu button is a web app, it is the palette's first item
  and the leading button shows the bot's menu label.

### Inline mode
- `@bot ` (space after a username of an inline bot) opens the panel.
  Queries are debounced 400 ms; answers for older text are dropped.
- Media results (photo, GIF, sticker, video) in a 3-column grid; others
  as glass cards. Paging via `nextOffset` at the end of the list.
- Drag up to the full sheet. Tap sends the result and clears the
  composer. The bot's `button` (switch to PM / web app) is a pill on top.

### Web apps
- Entry points: palette "Open app", menu button, web-app inline and
  reply-keyboard buttons.
- Browser tab mode: `openLink` (Custom Tab), as today.
- Lumina mode: glowing sheet, 90% height, bot name, close and ⋯ (reload,
  open in browser). Bridge handles: theme params, viewport, `sendData`,
  `close`, `openLink`, main button and back button. Other events are
  refused (the web app gets an error/false answer).

### Welcome card
- Shown when a bot chat has no messages: bot photo or animation,
  description, big Start. Start sends `/start`, or `/start <param>` when
  opened from a `t.me/bot?start=…` link.

### Profile
- Bot section: description, short description ("About"), commands list,
  privacy policy (if any), Open app.

## Errors

- No stock dialogs. TDLib errors: toast, or an inline line in the panel
  or palette.
- Failed full info hides the extras; the chat still works.
- Failed inline query: "Couldn't reach @bot" + Retry; stale answers
  dropped.
- Web app page fails to load: "Open in browser". Unknown bridge events
  are refused.
- Share buttons always confirm; declining sends nothing.
- Without permission to post, the keyboard, `/` button and inline panel
  are hidden.

## Testing

TDD. Repository tests with `FakeTdClient` (requests built correctly,
paging). Cubit tests: keyboard in force (newest, remove, one-time,
personal), inline debounce and stale drops, welcome visibility. Widget
tests (1080×2400 @3x, `--timeout`, no `pumpAndSettle` with `GlowButton`):
strip vs panel at 6/7 buttons, tap sends, one-time hides; palette filter
and `@botname`; inline grid vs list, drag to sheet, tap sends; Start with
param; share confirmation. Web-app bridge message handling tested
without a WebView. Device check with real bots for inline mode, reply
keyboards and one web app.
