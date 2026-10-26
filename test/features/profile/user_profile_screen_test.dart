import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/core/telegram/file_store.dart';
import 'package:lumina/core/telegram/telegram_cache.dart';
import 'package:lumina/features/chats/data/chats_repository.dart';
import 'package:lumina/features/profile/data/user_profile_repository.dart';
import 'package:lumina/features/profile/presentation/user_profile_screen.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';

td.ChatPhoto photo(int id) => td.ChatPhoto(id: id, addedDate: 0, sizes: const []);

td.UserFullInfo fullInfo({bool blocked = false, td.ChatPhoto? personal}) => td.UserFullInfo(
  personalPhoto: personal,
  communityId: 0,
  blockList: blocked ? const td.BlockListMain() : null,
  canBeCalled: true,
  supportsVideoCalls: true,
  hasPrivateCalls: false,
  hasPrivateForwards: false,
  hasRestrictedVoiceAndVideoNoteMessages: false,
  hasPostedToProfileStories: false,
  hasSponsoredMessagesEnabled: false,
  needPhoneNumberPrivacyException: false,
  setChatBackground: false,
  usesUnofficialApp: false,
  bio: const td.FormattedText(text: 'Poet of science', entities: []),
  personalChatId: 0,
  giftCount: 0,
  groupInCommonCount: 0,
  incomingPaidMessageStarCount: 0,
  outgoingPaidMessageStarCount: 0,
  giftSettings: const td.GiftSettings(
    showGiftButton: false,
    acceptedGiftTypes: td.AcceptedGiftTypes(
      unlimitedGifts: true,
      limitedGifts: true,
      upgradedGifts: true,
      giftsFromChannels: true,
      premiumSubscription: true,
    ),
  ),
  pendingRatingDate: 0,
);

void main() {
  Future<({FakeTdClient client, List<String> calls})> pump(
    WidgetTester tester, {
    td.ChatPhoto? personal,
    List<td.ChatPhoto> photos = const [],
  }) async {
    final client = FakeTdClient()
      ..respond = (f) => switch (f) {
        td.GetUserFullInfo() => fullInfo(personal: personal),
        td.GetUserProfilePhotos() => td.ChatPhotos(totalCount: photos.length, photos: photos),
        td.GetChatPostedToChatPageStories() => const td.Stories(
          totalCount: 0,
          stories: [],
          pinnedStoryIds: [],
        ),
        td.SearchChatMessages() => const td.FoundChatMessages(
          totalCount: 0,
          messages: [],
          nextFromMessageId: 0,
        ),
        td.GetGroupsInCommon() => const td.Chats(totalCount: 0, chatIds: []),
        td.GetReceivedGifts() => const td.ReceivedGifts(
          totalCount: 0,
          gifts: [],
          areNotificationsEnabled: false,
          nextOffset: '',
        ),
        _ => const td.Ok(),
      };
    final user = fakeUser().copyWith(
      isContact: true,
      usernames: const td.Usernames(
        activeUsernames: ['ada_l'],
        disabledUsernames: [],
        editableUsername: 'ada_l',
        collectibleUsernames: [],
        secondaryUsername: '',
      ),
    );
    final cache = TelegramCache.detached()
      ..apply(td.UpdateUser(user: user))
      ..apply(td.UpdateNewChat(chat: fakeChat(42, title: 'Ada Lovelace')));
    final calls = <String>[];
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: cache),
          RepositoryProvider.value(value: AppPreferences.inMemory()),
          RepositoryProvider(create: (_) => FileStore(client)),
          RepositoryProvider(create: (_) => UserProfileRepository(client)),
          RepositoryProvider(
            create: (_) => ChatsRepository(client: client, cache: cache),
          ),
        ],
        child: MaterialApp(
          home: UserProfileScreen(
            userId: 42,
            onMessage: (_) => calls.add('message'),
            onCall: (_, {required video}) => calls.add(video ? 'video' : 'voice'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    return (client: client, calls: calls);
  }

  testWidgets('shows phone, username, id, bio and every shared tab', (tester) async {
    await pump(tester);
    expect(find.text('Ada Lovelace'), findsWidgets);
    expect(find.text('+447700900000'), findsOneWidget);
    expect(find.text('@ada_l'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('Poet of science'), findsOneWidget);
    await tester.drag(find.byType(NestedScrollView), const Offset(0, -700));
    await tester.pump(const Duration(milliseconds: 500));
    for (final t in ProfileTab.values) {
      expect(find.text(t.label), findsOneWidget, reason: t.label);
    }
  });

  testWidgets('action orbs message, call and video call', (tester) async {
    final h = await pump(tester);
    await tester.tap(find.byTooltip('Message'));
    await tester.tap(find.byTooltip('Voice call'));
    await tester.tap(find.byTooltip('Video call'));
    expect(h.calls, ['message', 'voice', 'video']);
  });

  testWidgets('block asks first, then blocks', (tester) async {
    final h = await pump(tester);
    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Block'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(h.client.sentOf<td.SetMessageSenderBlockList>(), isEmpty, reason: 'confirm first');
    await tester.tap(find.widgetWithText(GestureDetector, 'Block').last);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(h.client.sentOf<td.SetMessageSenderBlockList>().single.blockList, isA<td.BlockListMain>());
  });

  testWidgets('the photo you set for them comes first; tapping the right side shows the next', (
    tester,
  ) async {
    await pump(tester, personal: photo(100), photos: [photo(1), photo(2)]);
    expect(_label('Profile photo 1 of 3, set by you'), findsOneWidget);
    expect(find.text('Set by you · only you see this photo'), findsOneWidget);
    await tester.tapAt(tester.getCenter(find.byType(PageView)) + const Offset(120, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(_label('Profile photo 2 of 3'), findsOneWidget);
    expect(find.text('Set by you · only you see this photo'), findsNothing);
  });
}

Finder _label(String l) => find.byWidgetPredicate((w) => w is Semantics && w.properties.label == l);
