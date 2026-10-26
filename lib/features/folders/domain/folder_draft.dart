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
