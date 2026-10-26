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
  name: td.ChatFolderName(
    text: td.FormattedText(text: name, entities: entities),
    animateCustomEmoji: true,
  ),
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
    expect(
      FolderDraft.empty().copyWith(name: 'Thirteen char').validate(),
      'Names can be at most 12 characters',
    );
    expect(FolderDraft.empty().copyWith(name: 'A').validate(), 'Add chats or chat types');
    expect(FolderDraft.empty().copyWith(name: 'A', included: const [1]).validate(), isNull);
    expect(FolderDraft.empty().copyWith(name: 'A', excludeRead: true, includeBots: true).validate(), isNull);
  });

  test('sharing needs a plain chat list', () {
    expect(FolderDraft.empty().copyWith(name: 'A', included: const [1]).canShare, isTrue);
    expect(FolderDraft.empty().copyWith(name: 'A', includeGroups: true).canShare, isFalse);
    expect(
      FolderDraft.empty().copyWith(name: 'A', included: const [1], excluded: const [2]).canShare,
      isFalse,
    );
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
