# Bots 1/5: Welcome Card and Bot Profile — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new bot chat shows a glowing welcome card (bot photo/animation, description, Start), `t.me/bot?start=x` links pass `x` to Start, and the bot's profile shows a bot section (About, description, commands, privacy policy).

**Architecture:** New feature `lib/features/bots/` with `BotsRepository` (TDLib: full info cached, start message) and `BotStartLinks` (pending start parameters per chat). The conversation screen gets an `emptyChat` hook on `ConversationExtensions`; `UserProfileScreen` gets an optional `botSection` builder. Wiring stays in `lib/app/`.

**Tech Stack:** Flutter, flutter_bloc (RepositoryProvider), TDLib via `lumina_tdlib`.

**Spec:** `docs/superpowers/specs/2026-10-27-bot-support-design.md` (sections "Welcome card", "Profile"; build order item 1)

## Global Constraints

- Build/test only via `tool/flutter.sh` (`tool/flutter.sh test --timeout 60s <path>`).
- Feature-first: presentation never calls `TdClient` directly; the conversation and profile features never import `features/bots` (hooks only, wired in `lib/app/`).
- Colors from `GlowColors`, durations/curves from `Motion`; no stock dialogs; semantics on custom interactive widgets; touch targets ≥ 48 dp.
- `GlowButton` shimmers: no `pumpAndSettle` while one is on screen. Widget tests at 1080x2400 @3x.
- `dart format` only touched files (page width 110); analyzer clean for touched files.
- Stage explicit paths only; never the owner's local edits. Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

- Bot whose full info fails to load (network, TDLib error): the chat still works; the welcome card shows name + Start without description/media — Task 3 test.
- Start tapped twice quickly: one `/start` only — Task 3 test.
- A bot chat with history (not empty): no welcome card — Task 3 test.
- `t.me/<name>?start=` link for a user or channel that is not a bot: no start parameter stored, link opens the chat normally — Task 2 test.
- Profile of a regular (non-bot) user: no bot section — Task 4 test.

---

### Task 1: BotsRepository

**Files:**
- Create: `lib/features/bots/data/bots_repository.dart`
- Test: `test/features/bots/bots_repository_test.dart`

**Interfaces:**
- Produces: `class BotsRepository { BotsRepository(TdClient client); Future<td.BotInfo?> info(int botUserId); Future<void> start({required int botUserId, required int chatId, String parameter = ''}); }` — `info` caches successful results per user id; on `TdException` returns null (not cached, so a later call retries).

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/bots/data/bots_repository.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';

td.UserFullInfo fullWithBot(td.BotInfo? bot) => fakeUserFullInfo().copyWith(botInfo: bot);

const bot = td.BotInfo(
  shortDescription: 'Weather in a tap',
  description: 'I tell you the weather.',
  managerBotUserId: 0,
  commands: [td.BotCommand(command: 'today', description: 'Weather today')],
  privacyPolicyUrl: 'https://example.org/p',
  webAppBackgroundLightColor: -1,
  webAppBackgroundDarkColor: -1,
  webAppHeaderLightColor: -1,
  webAppHeaderDarkColor: -1,
  canGetRevenueStatistics: false,
  canManageEmojiStatus: false,
  hasMediaPreviews: false,
);

void main() {
  test('bot info is fetched once and cached', () async {
    final client = FakeTdClient()..respond = (f) => f is td.GetUserFullInfo ? fullWithBot(bot) : const td.Ok();
    final repo = BotsRepository(client);
    expect((await repo.info(9))!.description, 'I tell you the weather.');
    await repo.info(9);
    expect(client.sentOf<td.GetUserFullInfo>(), hasLength(1));
  });

  test('a failed lookup returns null and is retried next time', () async {
    var fail = true;
    final client = FakeTdClient()
      ..respond = (f) => fail ? const td.TdError(code: 500, message: 'boom') : fullWithBot(bot);
    final repo = BotsRepository(client);
    expect(await repo.info(9), isNull);
    fail = false;
    expect(await repo.info(9), isNotNull);
  });

  test('start sends sendBotStartMessage with the parameter', () async {
    final client = FakeTdClient()..respond = (_) => fakeMessage(1);
    await BotsRepository(client).start(botUserId: 9, chatId: 9, parameter: 'ref42');
    final s = client.sentOf<td.SendBotStartMessage>().single;
    expect((s.botUserId, s.chatId, s.parameter), (9, 9, 'ref42'));
  });
}
```

Before running: check `test/helpers/fakes.dart` for a `fakeUserFullInfo()`; if missing, add one there building `td.UserFullInfo` with every required field false/0/empty/null (read the constructor in `packages/lumina_tdlib/lib/src/tdapi/objects/user_full_info.dart` and the `td.BotInfo` constructor in `bot_info.dart`; adjust the `bot` constant above to the real required fields). Include `fakeUserFullInfo` in the commit.

- [ ] **Step 2: Run, expect FAIL** (`bots_repository.dart` missing).

Run: `tool/flutter.sh test --timeout 60s test/features/bots/bots_repository_test.dart`

- [ ] **Step 3: Implement**

```dart
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/tdlib/td_client.dart';
import '../../../core/tdlib/td_errors.dart';

/// TDLib requests for chatting with bots: their profile info (cached) and
/// /start.
class BotsRepository {
  BotsRepository(this._client);

  final TdClient _client;
  final _info = <int, td.BotInfo>{};

  /// The bot's description, photo, commands, menu button…; null when the
  /// user is not a bot or the lookup failed (retried next call).
  Future<td.BotInfo?> info(int botUserId) async {
    if (_info[botUserId] case final cached?) return cached;
    try {
      final full = await _client.invoke<td.UserFullInfo>(td.GetUserFullInfo(userId: botUserId));
      final bot = full.botInfo;
      if (bot != null) _info[botUserId] = bot;
      return bot;
    } on TdException {
      return null;
    }
  }

  /// "Start": `/start` with an optional deep-link [parameter].
  Future<void> start({required int botUserId, required int chatId, String parameter = ''}) => _client
      .invoke<td.Message>(td.SendBotStartMessage(botUserId: botUserId, chatId: chatId, parameter: parameter));
}
```

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add lib/features/bots/data/bots_repository.dart test/features/bots/bots_repository_test.dart test/helpers/fakes.dart
git commit -m "Bots: repository for bot info and /start"
```

---

### Task 2: Start links (`t.me/<bot>?start=…`)

**Files:**
- Create: `lib/features/bots/data/bot_start_links.dart`
- Modify: `lib/app/feature_wiring.dart` (`appLinkHandlers()` gets a handler; providers get `BotsRepository`, `BotStartLinks`)
- Test: `test/features/bots/bot_start_links_test.dart`

**Interfaces:**
- Consumes: `TdClient`.
- Produces:
  - `class BotStartLinks { BotStartLinks(TdClient client); static ({String username, String parameter})? parse(Uri uri); Future<int?> resolve(Uri uri); String? take(int chatId); String? peek(int chatId); }`
  - `parse`: host `t.me` / `telegram.me` (any case), single path segment (the username), query `start` present → record; `tg://resolve?domain=x&start=y` too. Otherwise null.
  - `resolve`: `SearchPublicChat(username)`; only when the chat is private with a bot user (`GetUser`, `type is td.UserTypeBot`) stores `parameter` under the chat id and returns the chat id; otherwise returns null and stores nothing. TDLib errors → null.
  - `take` returns and removes; `peek` returns without removing.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/bots/data/bot_start_links.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';

void main() {
  test('parses t.me and tg:// start links, and nothing else', () {
    expect(BotStartLinks.parse(Uri.parse('https://t.me/WeatherBot?start=ref42')), (
      username: 'WeatherBot',
      parameter: 'ref42',
    ));
    expect(BotStartLinks.parse(Uri.parse('tg://resolve?domain=WeatherBot&start=x')), (
      username: 'WeatherBot',
      parameter: 'x',
    ));
    expect(BotStartLinks.parse(Uri.parse('https://t.me/WeatherBot')), isNull);
    expect(BotStartLinks.parse(Uri.parse('https://t.me/c/123?start=x')), isNull);
    expect(BotStartLinks.parse(Uri.parse('https://example.org/WeatherBot?start=x')), isNull);
  });

  test('a bot link stores the parameter for its chat until taken', () async {
    final client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.SearchPublicChat() => fakeChat(9),
        td.GetUser() => fakeUser(bot: true).copyWith(id: 9),
        _ => const td.Ok(),
      };
    final links = BotStartLinks(client);
    expect(await links.resolve(Uri.parse('https://t.me/WeatherBot?start=ref42')), 9);
    expect(links.peek(9), 'ref42');
    expect(links.take(9), 'ref42');
    expect(links.take(9), isNull);
  });

  test('a start link to a non-bot stores nothing', () async {
    final client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.SearchPublicChat() => fakeChat(9),
        td.GetUser() => fakeUser().copyWith(id: 9),
        _ => const td.Ok(),
      };
    final links = BotStartLinks(client);
    expect(await links.resolve(Uri.parse('https://t.me/ada?start=x')), isNull);
    expect(links.peek(9), isNull);
  });

  test('an unknown username resolves to nothing', () async {
    final client = FakeTdClient()..respond = (_) => const td.TdError(code: 400, message: 'USERNAME_NOT_OCCUPIED');
    expect(await BotStartLinks(client).resolve(Uri.parse('https://t.me/nobody?start=x')), isNull);
  });
}
```

Check `fakeUser({bool bot})` in `fakes.dart` sets `type: td.UserTypeBot(...)` when `bot` is true (it exists: `fakeUser({bool bot = false})`).

- [ ] **Step 2: Run, expect FAIL.**

Run: `tool/flutter.sh test --timeout 60s test/features/bots/bot_start_links_test.dart`

- [ ] **Step 3: Implement**

```dart
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/tdlib/td_client.dart';
import '../../../core/tdlib/td_errors.dart';

/// `t.me/<bot>?start=<parameter>` deep links: the parameter waits here for
/// the bot chat's Start button.
class BotStartLinks {
  BotStartLinks(this._client);

  final TdClient _client;
  final _pending = <int, String>{};

  static ({String username, String parameter})? parse(Uri uri) {
    final start = uri.queryParameters['start'];
    if (start == null) return null;
    if (uri.scheme == 'tg' && uri.host == 'resolve') {
      final domain = uri.queryParameters['domain'];
      return domain == null || domain.isEmpty ? null : (username: domain, parameter: start);
    }
    final host = uri.host.toLowerCase();
    if (host != 't.me' && host != 'telegram.me') return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length != 1) return null;
    return (username: segments.single, parameter: start);
  }

  /// The bot chat's id when [uri] is a start link to a bot (the parameter is
  /// then pending for it), else null.
  Future<int?> resolve(Uri uri) async {
    final link = parse(uri);
    if (link == null) return null;
    try {
      final chat = await _client.invoke<td.Chat>(td.SearchPublicChat(username: link.username));
      if (chat.type case td.ChatTypePrivate(:final userId)) {
        final user = await _client.invoke<td.User>(td.GetUser(userId: userId));
        if (user.type is! td.UserTypeBot) return null;
        _pending[chat.id] = link.parameter;
        return chat.id;
      }
      return null;
    } on TdException {
      return null;
    }
  }

  String? peek(int chatId) => _pending[chatId];

  String? take(int chatId) => _pending.remove(chatId);
}
```

Wiring in `feature_wiring.dart`:
- Providers (near the other repositories): `RepositoryProvider<BotsRepository>(create: (c) => BotsRepository(c.read<TdClient>())),` and `RepositoryProvider<BotStartLinks>(create: (c) => BotStartLinks(c.read<TdClient>())),`.
- `appLinkHandlers()` add:

```dart
  InternalLinkHandler(
    matches: (uri) => BotStartLinks.parse(uri) != null,
    open: (context, uri) async {
      final chatId = await context.read<BotStartLinks>().resolve(uri);
      if (chatId != null && context.mounted) {
        await Navigator.of(context).push(ConversationScreen.route(chatId));
      } else if (context.mounted) {
        await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      }
    },
  ),
```

(imports: `bot_start_links.dart`, `bots_repository.dart`, `conversation_screen.dart`, `package:url_launcher/url_launcher.dart` — check which already exist in the file.)

- [ ] **Step 4: Run, expect PASS.** Then `tool/flutter.sh analyze lib/app lib/features/bots`.

- [ ] **Step 5: Commit**

```bash
git add lib/features/bots/data/bot_start_links.dart lib/app/feature_wiring.dart test/features/bots/bot_start_links_test.dart
git commit -m "Bots: t.me start links wait for the bot chat's Start"
```

---

### Task 3: Welcome card in an empty bot chat

**Files:**
- Modify: `lib/features/conversation/presentation/widgets/conversation_extensions.dart` (new hook)
- Modify: `lib/features/conversation/presentation/screens/conversation_screen.dart:486-520` (show the hook when the chat is empty)
- Create: `lib/features/bots/presentation/bot_welcome_card.dart`
- Modify: `lib/app/app_conversation_extensions.dart` (implement the hook)
- Test: `test/features/bots/bot_welcome_card_test.dart`

**Interfaces:**
- Consumes: `BotsRepository.info/start` (Task 1), `BotStartLinks.peek/take` (Task 2).
- Produces:
  - `ConversationExtensions.emptyChat(BuildContext context, td.Chat chat)` → `Widget?` (default null).
  - `class BotWelcomeCard extends StatefulWidget { const BotWelcomeCard({super.key, required this.botUserId, required this.chatId, required this.title}); }` — reads `BotsRepository` and `BotStartLinks` from context.

Card layout (centred in the empty chat, max width 360): glass container (`GlowColors.surface` 85%, radius 28, border `GlowColors.violet` 45%, `glow(GlowColors.violet, intensity: 0.3)`). Top: bot animation (`LoopingGif(file: animation.animation)`) or photo (`TdFileImage(file: largest photo size)`) in a rounded 16:9 box when present; else `ChatAvatar` 72. Then title (18, w700), description (15, `GlowColors.text`, height 1.4) when non-empty, then a `GlowButton` "Start" full width. Loading info: show title + Start immediately; description/media fade in when info arrives (`AnimatedSize` + `AnimatedOpacity`, `Motion.standard`). Start: disabled while sending (one send only), calls `start(botUserId, chatId, parameter: links.take(chatId) ?? '')`; on `TdException` re-enables and shows a toast with the message.

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/tdlib/td_client.dart';
import 'package:lumina/core/telegram/file_store.dart';
import 'package:lumina/features/bots/data/bot_start_links.dart';
import 'package:lumina/features/bots/data/bots_repository.dart';
import 'package:lumina/features/bots/presentation/bot_welcome_card.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';
import 'bots_repository_test.dart' show bot, fullWithBot;

void main() {
  late FakeTdClient client;
  late BotStartLinks links;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    links = BotStartLinks(client);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<TdClient>.value(value: client),
          RepositoryProvider(create: (_) => FileStore(client)),
          RepositoryProvider(create: (_) => BotsRepository(client)),
          RepositoryProvider.value(value: links),
        ],
        child: const MaterialApp(
          home: Scaffold(body: BotWelcomeCard(botUserId: 9, chatId: 9, title: 'Weather Bot')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('shows the description and Start sends /start once', (tester) async {
    final sent = Completer<td.TdObject>();
    client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.GetUserFullInfo() => fullWithBot(bot),
        td.SendBotStartMessage() => sent.future,
        _ => const td.Ok(),
      };
    await pump(tester);
    expect(find.text('Weather Bot'), findsOneWidget);
    expect(find.text('I tell you the weather.'), findsOneWidget);
    await tester.tap(find.text('Start'));
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(client.sentOf<td.SendBotStartMessage>(), hasLength(1));
    sent.complete(fakeMessage(1));
    await tester.pump();
  });

  testWidgets('a pending start link parameter goes with Start', (tester) async {
    client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.GetUserFullInfo() => fullWithBot(bot),
        td.SearchPublicChat() => fakeChat(9),
        td.GetUser() => fakeUser(bot: true).copyWith(id: 9),
        td.SendBotStartMessage() => fakeMessage(1),
        _ => const td.Ok(),
      };
    await pump(tester);
    await links.resolve(Uri.parse('https://t.me/WeatherBot?start=ref42'));
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(client.sentOf<td.SendBotStartMessage>().single.parameter, 'ref42');
  });

  testWidgets('without bot info the card still offers Start', (tester) async {
    client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.GetUserFullInfo() => const td.TdError(code: 500, message: 'down'),
        td.SendBotStartMessage() => fakeMessage(1),
        _ => const td.Ok(),
      };
    await pump(tester);
    expect(find.text('Weather Bot'), findsOneWidget);
    expect(find.text('I tell you the weather.'), findsNothing);
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(client.sentOf<td.SendBotStartMessage>().single.parameter, '');
  });
}
```

Also add to `test/features/conversation/conversation_initial_load_test.dart` (or a new `test/features/conversation/empty_chat_hook_test.dart` if that file's harness doesn't fit) a test that the screen shows `ConversationExtensions.emptyChat` only when the loaded history is empty: a fake extensions subclass returning `const Text('WELCOME')`; with zero messages → finds 'WELCOME'; with one message → finds nothing. Reuse that file's pump helper (read it first and follow its provider setup).

- [ ] **Step 2: Run, expect FAIL** (card file missing; hook missing).

Run: `tool/flutter.sh test --timeout 60s test/features/bots/bot_welcome_card_test.dart`

- [ ] **Step 3: Implement**

`conversation_extensions.dart`, after `headerActions`:

```dart
  /// Shown in place of the message list while the chat has no messages
  /// (a bot's welcome card); null shows the plain empty list.
  Widget? emptyChat(BuildContext context, td.Chat chat) => null;
```

`conversation_screen.dart`: in the `Stack` children, replace the `if (state.initialLoading) … else NotificationListener(...)` branch with:

```dart
              if (state.initialLoading)
                const Center(child: CircularProgressIndicator(color: GlowColors.violet))
              else if (_rows.isEmpty && !state.hasOlder && extensions.emptyChat(context, chat) case final empty?)
                Center(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: empty))
              else
                NotificationListener<ScrollNotification>(
```

(`extensions` is `ConversationExtensions.of(context)`; if no local of that name exists in this builder, add `final extensions = ConversationExtensions.of(context);` at the top of the builder.)

`bot_welcome_card.dart`: implement per the layout above. Skeleton:

```dart
class _BotWelcomeCardState extends State<BotWelcomeCard> {
  td.BotInfo? _info;
  var _sending = false;

  @override
  void initState() {
    super.initState();
    context.read<BotsRepository>().info(widget.botUserId).then((i) {
      if (mounted) setState(() => _info = i);
    });
  }

  Future<void> _start() async {
    if (_sending) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await context.read<BotsRepository>().start(
        botUserId: widget.botUserId,
        chatId: widget.chatId,
        parameter: context.read<BotStartLinks>().take(widget.chatId) ?? '',
      );
    } on TdException catch (e) {
      if (mounted) setState(() => _sending = false);
      messenger?.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
  // build: per the layout; Start → GlowButton(label: 'Start', onPressed: _sending ? null : _start)
}
```

Check `GlowButton`'s constructor in `lib/core/widgets/glow_button.dart` and use its real parameter names.

`app_conversation_extensions.dart`:

```dart
  @override
  Widget? emptyChat(BuildContext context, td.Chat chat) {
    final userId = switch (chat.type) {
      td.ChatTypePrivate(:final userId) => userId,
      _ => null,
    };
    if (userId == null) return null;
    final user = context.read<TelegramCache>().users[userId];
    if (user?.type is! td.UserTypeBot) return null;
    return BotWelcomeCard(botUserId: userId, chatId: chat.id, title: chat.title);
  }
```

- [ ] **Step 4: Run the card tests and the empty-chat hook test, expect PASS.**

Run: `tool/flutter.sh test --timeout 60s test/features/bots test/features/conversation`

- [ ] **Step 5: Commit**

```bash
git add lib/features/conversation/presentation/widgets/conversation_extensions.dart lib/features/conversation/presentation/screens/conversation_screen.dart lib/features/bots/presentation/bot_welcome_card.dart lib/app/app_conversation_extensions.dart test/features/bots/bot_welcome_card_test.dart test/features/conversation/
git commit -m "Bots: welcome card with Start in an empty bot chat"
```

---

### Task 4: Bot section in the profile

**Files:**
- Modify: `lib/features/profile/presentation/user_profile_screen.dart` (optional `botSection` builder, shown under the info rows)
- Create: `lib/features/bots/presentation/bot_profile_section.dart`
- Modify: `lib/app/app_conversation_extensions.dart` (pass the builder where `UserProfileScreen` is built; also any other `UserProfileScreen(` call sites — `grep -rn "UserProfileScreen(" lib`)
- Modify: `docs/REMAINING.md`
- Test: `test/features/bots/bot_profile_section_test.dart`

**Interfaces:**
- Produces:
  - `UserProfileScreen({..., Widget Function(BuildContext context, td.User user, td.UserFullInfo full)? botSection})` — called only when `user.type is td.UserTypeBot` and `_full?.botInfo != null`.
  - `class BotProfileSection extends StatelessWidget { const BotProfileSection({super.key, required this.info}); final td.BotInfo info; }` — rows: About (`shortDescription`, if non-empty), description (if non-empty and different from About), "Commands" header + one row per command (`/cmd` + description), "Privacy policy" row (opens `privacyPolicyUrl` with `openLink`) when non-empty. Glass section like the existing info rows (`GlowColors.surface`, radius 18, border `outline`).

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/features/bots/presentation/bot_profile_section.dart';

import 'bots_repository_test.dart' show bot;

void main() {
  testWidgets('lists about, description, commands and the privacy policy', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: BotProfileSection(info: bot)))),
    );
    expect(find.text('Weather in a tap'), findsOneWidget);
    expect(find.text('I tell you the weather.'), findsOneWidget);
    expect(find.text('/today'), findsOneWidget);
    expect(find.text('Weather today'), findsOneWidget);
    expect(find.text('Privacy policy'), findsOneWidget);
  });

  testWidgets('empty parts are left out', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BotProfileSection(
            info: bot.copyWith(shortDescription: '', commands: const [], privacyPolicyUrl: ''),
          ),
        ),
      ),
    );
    expect(find.text('Commands'), findsNothing);
    expect(find.text('Privacy policy'), findsNothing);
  });
}
```

And in the profile screen's test (find it: `grep -rln UserProfileScreen test`), add: a regular user with `botSection: (_, _, _) => const Text('BOT')` → 'BOT' not found; a bot user whose full info has `botInfo` → 'BOT' found. Follow that test file's existing pump/provider setup.

- [ ] **Step 2: Run, expect FAIL.**

Run: `tool/flutter.sh test --timeout 60s test/features/bots/bot_profile_section_test.dart`

- [ ] **Step 3: Implement** the section per the interface; in `user_profile_screen.dart` after the `_InfoRow`s column:

```dart
                      if (widget.botSection != null &&
                          user.type is td.UserTypeBot &&
                          _full != null &&
                          _full!.botInfo != null) ...[
                        const SizedBox(height: 16),
                        widget.botSection!(context, user, _full!),
                      ],
```

In `app_conversation_extensions.dart` pass `botSection: (context, user, full) => BotProfileSection(info: full.botInfo!),`.

- [ ] **Step 4: Run bots + profile tests, then the full suite**

Run: `tool/flutter.sh test --timeout 60s test/features/bots test/features/profile` then `tool/flutter.sh test --timeout 60s`
Expected: all PASS.

- [ ] **Step 5: Docs, format, analyze, commit**

`docs/REMAINING.md`: under item 2 (Full bot support) note "1/5 done: welcome card, start links, profile section"; add to the Done list.

```bash
dart format <touched files>
tool/flutter.sh analyze lib test
git add lib/features/profile/presentation/user_profile_screen.dart lib/features/bots/presentation/bot_profile_section.dart lib/app/app_conversation_extensions.dart test/features/bots/bot_profile_section_test.dart test/features/profile/ docs/REMAINING.md
git commit -m "Bots: bot section in the profile"
```
