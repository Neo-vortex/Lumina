import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib_next/api.dart' as td;
import 'package:lumina/features/stories/presentation/story_message_opener.dart';
import 'package:lumina/features/stories/presentation/widgets/story_areas_layer.dart';

td.Story _story(List<td.StoryArea> areas) => td.Story(
  id: 1,
  senderChatId: 42,
  date: 1760000000,
  isBeingSent: false,
  isBeingEdited: false,
  isEdited: false,
  isPostedToChatPage: false,
  isVisibleOnlyForSelf: false,
  canBeDeleted: false,
  canBeEdited: false,
  canBeForwarded: true,
  canBeReplied: true,
  canToggleIsPostedToChatPage: false,
  canGetStatistics: false,
  canGetInteractions: false,
  hasExpiredViewers: false,
  privacySettings: const td.StoryPrivacySettingsEveryone(exceptUserIds: []),
  content: const td.StoryContentUnsupported(),
  areas: areas,
  caption: const td.FormattedText(text: '', entities: []),
);

const _middle = td.StoryAreaPosition(
  xPercentage: 50,
  yPercentage: 50,
  widthPercentage: 60,
  heightPercentage: 20,
  rotationAngle: 0,
  cornerRadiusPercentage: 0,
);

void main() {
  testWidgets('a reposted message area opens that message, pausing the story', (tester) async {
    final opened = <(int, int)>[];
    final busy = <bool>[];
    await tester.pumpWidget(
      RepositoryProvider(
        create: (_) =>
            StoryMessageOpener((context, chatId, messageId) async => opened.add((chatId, messageId))),
        child: MaterialApp(
          home: SizedBox(
            width: 360,
            height: 640,
            child: StoryAreasLayer(
              story: _story(const [
                td.StoryArea(
                  position: _middle,
                  type: td.StoryAreaTypeMessage(chatId: -100777, messageId: 2048),
                ),
              ]),
              onReact: (_) {},
              onBusy: busy.add,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Open message'));
    await tester.pump();
    expect(opened, [(-100777, 2048)]);
    expect(busy, [true, false]);
  });

  testWidgets('without an opener the message area is not shown', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StoryAreasLayer(
          story: _story(const [
            td.StoryArea(position: _middle, type: td.StoryAreaTypeMessage(chatId: 1, messageId: 2)),
          ]),
          onReact: (_) {},
        ),
      ),
    );
    expect(find.bySemanticsLabel('Open message'), findsNothing);
  });
}
