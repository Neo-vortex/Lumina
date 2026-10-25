import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handy_tdlib_next/api.dart' as td;

import '../../../../core/telegram/display.dart';
import '../../../../core/telegram/permissions.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/chat_avatar.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/glow_background.dart';
import '../../../chats/data/chats_repository.dart';
import '../../data/chat_info_repository.dart';
import '../widgets/contact_picker.dart';
import '../widgets/permissions_sheet.dart';

/// Profile / group / channel info with admin tools (spec §6.2, §6.3).
class ChatInfoScreen extends StatefulWidget {
  const ChatInfoScreen({super.key, required this.chatId, required this.openChat});

  final int chatId;

  /// Opens another chat (discussion group, private chat with a member).
  final void Function(BuildContext context, int chatId) openChat;

  static Route<void> route(int chatId, {required void Function(BuildContext, int) openChat}) =>
      MaterialPageRoute(
        builder: (_) => ChatInfoScreen(chatId: chatId, openChat: openChat),
      );

  @override
  State<ChatInfoScreen> createState() => _ChatInfoScreenState();
}

class _ChatInfoScreenState extends State<ChatInfoScreen> {
  late final ChatInfoRepository _repo = context.read<ChatInfoRepository>();
  late final TelegramCache _cache = context.read<TelegramCache>();
  ChatDetails? _details;
  List<td.ChatMember> _members = const [];
  String? _error;

  td.Chat get _chat => _cache.chats[widget.chatId]!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _repo.details(_chat);
      final members = d.canGetMembers ? await _repo.members(_chat) : const <td.ChatMember>[];
      if (mounted) {
        setState(() {
          _details = d;
          _members = members;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> _run(Future<void> Function() f, {String? done}) async {
    try {
      await f();
      if (done != null) _snack(done);
      await _load();
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _editText({
    required String title,
    required String initial,
    required Future<void> Function(String) save,
    int lines = 1,
  }) async {
    final c = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlowColors.surfaceHigh,
        title: Text(title),
        content: TextField(controller: c, autofocus: true, minLines: lines, maxLines: lines == 1 ? 1 : 6),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (value != null) await _run(() => save(value));
  }

  Future<void> _memberActions(td.ChatMember m) async {
    final userId = switch (m.memberId) {
      td.MessageSenderUser(:final userId) => userId,
      _ => null,
    };
    if (userId == null) return;
    final rights = _cache.adminRights(_chat);
    final iAmCreator = _cache.myStatus(_chat) is td.ChatMemberStatusCreator;
    final canPromote = iAmCreator || (rights?.canPromoteMembers ?? false);
    final canRestrict = iAmCreator || (rights?.canRestrictMembers ?? false);
    final isAdmin = m.status is td.ChatMemberStatusAdministrator;
    final isOwner = m.status is td.ChatMemberStatusCreator;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: GlowColors.surfaceHigh,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.chat_rounded),
              title: const Text('Message'),
              onTap: () => Navigator.pop(context, 'message'),
            ),
            if (canPromote && !isOwner && !isAdmin)
              ListTile(
                leading: const Icon(Icons.shield_rounded, color: GlowColors.cyan),
                title: const Text('Make admin'),
                onTap: () => Navigator.pop(context, 'promote'),
              ),
            if (canPromote && isAdmin)
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: const Text('Remove admin rights'),
                onTap: () => Navigator.pop(context, 'demote'),
              ),
            if (canRestrict && !isOwner)
              ListTile(
                leading: const Icon(Icons.person_remove_rounded, color: GlowColors.coral),
                title: const Text('Remove from group', style: TextStyle(color: GlowColors.coral)),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'message':
        final chat = await _repo.privateChat(userId);
        if (mounted) widget.openChat(context, chat.id);
      case 'promote':
        final channel = _cache.isChannel(_chat);
        await _run(
          () => _repo.setAdmin(
            _chat,
            userId,
            td.ChatAdministratorRights(
              canManageChat: true,
              canChangeInfo: true,
              canPostMessages: channel,
              canEditMessages: channel,
              canDeleteMessages: true,
              canInviteUsers: true,
              canRestrictMembers: !channel,
              canPinMessages: true,
              canManageTopics: false,
              canPromoteMembers: false,
              canManageVideoChats: true,
              canPostStories: channel,
              canEditStories: channel,
              canDeleteStories: channel,
              isAnonymous: false,
            ),
          ),
          done: 'Promoted to admin',
        );
      case 'demote':
        await _run(() => _repo.setAdmin(_chat, userId, null), done: 'Admin rights removed');
      case 'remove':
        await _run(() => _repo.removeMember(_chat, m.memberId), done: 'Removed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = _cache.chats[widget.chatId];
    if (chat == null) return const Scaffold();
    final d = _details;
    final isChannel = _cache.isChannel(chat);
    final isGroup = chat.type is td.ChatTypeBasicGroup || (chat.type is td.ChatTypeSupergroup && !isChannel);
    final isAdmin = _cache.isAdmin(chat);
    final rights = _cache.adminRights(chat);
    final isCreator = _cache.myStatus(chat) is td.ChatMemberStatusCreator;
    final canEditInfo =
        isCreator || (rights?.canChangeInfo ?? false) || (isGroup && chat.permissions.canChangeInfo);
    final canInvite =
        isCreator || (rights?.canInviteUsers ?? false) || (isGroup && chat.permissions.canInviteUsers);
    final peer = _cache.peerUser(chat);

    return Scaffold(
      body: GlowBackground(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              backgroundColor: Colors.transparent,
              pinned: true,
              actions: [
                if (canEditInfo)
                  IconButton(
                    tooltip: 'Edit name',
                    icon: const Icon(Icons.edit_rounded),
                    onPressed: () =>
                        _editText(title: 'Name', initial: chat.title, save: (v) => _repo.setTitle(chat, v)),
                  ),
              ],
            ),
            SliverToBoxAdapter(
              child: Column(
                children: [
                  Hero(tag: 'avatar-${chat.id}', child: ChatAvatar.chat(chat, size: 104, glowIntensity: 0.6)),
                  const SizedBox(height: 16),
                  Text(
                    chat.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    peer != null
                        ? Display.status(peer)
                        : '${d?.memberCount ?? _cache.supergroupOf(chat)?.memberCount ?? 0} ${isChannel ? 'subscribers' : 'members'}',
                    style: const TextStyle(color: GlowColors.textMuted),
                  ),
                  if (peer?.usernames?.activeUsernames.firstOrNull case final u?)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('@$u', style: const TextStyle(color: GlowColors.cyan)),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Action(
                        icon: chat.notificationSettings.muteFor > 0
                            ? Icons.notifications_off_rounded
                            : Icons.notifications_rounded,
                        label: chat.notificationSettings.muteFor > 0 ? 'Unmute' : 'Mute',
                        onTap: () => _run(
                          () => context.read<ChatsRepository>().setMuted(
                            chat.id,
                            chat.notificationSettings.muteFor == 0,
                          ),
                        ),
                      ),
                      if (chat.type is td.ChatTypeSupergroup && !_cache.isMember(chat))
                        _Action(
                          icon: Icons.login_rounded,
                          label: 'Join',
                          onTap: () => _run(() => _repo.join(chat), done: 'Joined'),
                        ),
                      if (isGroup && canInvite)
                        _Action(
                          icon: Icons.person_add_rounded,
                          label: 'Add',
                          onTap: () async {
                            final ids = await ContactPickerScreen.pick(
                              context,
                              title: 'Add members',
                              multiple: true,
                              actionLabel: 'Add',
                            );
                            if (ids != null && ids.isNotEmpty) {
                              await _run(() => _repo.addMembers(chat, ids), done: 'Added');
                            }
                          },
                        ),
                      if (isGroup && isAdmin)
                        _Action(
                          icon: Icons.tune_rounded,
                          label: 'Permissions',
                          onTap: () async {
                            final r = await showPermissionsSheet(
                              context,
                              permissions: chat.permissions,
                              slowMode: d?.slowModeDelay ?? 0,
                              supportsSlowMode: chat.type is td.ChatTypeSupergroup,
                            );
                            if (r == null) return;
                            await _run(() async {
                              await _repo.setPermissions(chat, r.permissions);
                              if (chat.type is td.ChatTypeSupergroup &&
                                  r.slowMode != (d?.slowModeDelay ?? 0)) {
                                await _repo.setSlowMode(chat, r.slowMode);
                              }
                            }, done: 'Saved');
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!, style: const TextStyle(color: GlowColors.error)),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList.list(
                children: [
                  if ((d?.description ?? '').isNotEmpty || canEditInfo)
                    _Card(
                      child: ListTile(
                        title: Text(
                          peer != null ? 'Bio' : 'Description',
                          style: const TextStyle(color: GlowColors.violet, fontSize: 13),
                        ),
                        subtitle: SelectableText(
                          (d?.description ?? '').isEmpty ? 'Add a description' : d!.description,
                          style: const TextStyle(color: GlowColors.text, fontSize: 15),
                        ),
                        trailing: canEditInfo && peer == null
                            ? const Icon(Icons.edit_rounded, size: 18)
                            : null,
                        onTap: canEditInfo && peer == null
                            ? () => _editText(
                                title: 'Description',
                                initial: d?.description ?? '',
                                lines: 4,
                                save: (v) => _repo.setDescription(chat, v),
                              )
                            : null,
                      ),
                    ),
                  if (d?.inviteLink != null || (canInvite && peer == null))
                    _Card(
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.link_rounded, color: GlowColors.cyan),
                            title: Text(d?.inviteLink?.inviteLink ?? 'No invite link yet'),
                            subtitle: const Text('Invite link'),
                            onTap: d?.inviteLink == null
                                ? null
                                : () {
                                    Clipboard.setData(ClipboardData(text: d!.inviteLink!.inviteLink));
                                    _snack('Link copied');
                                  },
                          ),
                          if (canInvite)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () => _run(
                                    () => _repo.newInviteLink(chat).then((l) {
                                      Clipboard.setData(ClipboardData(text: l.inviteLink));
                                    }),
                                    done: 'New link copied',
                                  ),
                                  child: const Text('Create link'),
                                ),
                                if (isAdmin)
                                  TextButton(
                                    onPressed: () =>
                                        _run(() => _repo.replacePrimaryLink(chat), done: 'Old link revoked'),
                                    child: const Text(
                                      'Revoke & replace',
                                      style: TextStyle(color: GlowColors.coral),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  if ((d?.linkedChatId ?? 0) != 0)
                    _Card(
                      child: ListTile(
                        leading: const Icon(Icons.forum_rounded, color: GlowColors.amber),
                        title: Text(isChannel ? 'Discussion group' : 'Linked channel'),
                        subtitle: Text(_cache.chats[d!.linkedChatId]?.title ?? 'Open'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => widget.openChat(context, d.linkedChatId),
                      ),
                    ),
                  if (_members.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                      child: Text(
                        '${isChannel ? 'SUBSCRIBERS' : 'MEMBERS'} · ${d?.memberCount ?? _members.length}',
                        style: const TextStyle(
                          color: GlowColors.violet,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                    _Card(
                      child: Column(
                        children: [
                          for (final m in _members)
                            _MemberTile(member: m, onTap: isAdmin ? () => _memberActions(m) : null),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member, this.onTap});

  final td.ChatMember member;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    final u = switch (member.memberId) {
      td.MessageSenderUser(:final userId) => cache.users[userId],
      _ => null,
    };
    final badge = switch (member.status) {
      td.ChatMemberStatusCreator(:final customTitle) => customTitle.isEmpty ? 'owner' : customTitle,
      td.ChatMemberStatusAdministrator(:final customTitle) => customTitle.isEmpty ? 'admin' : customTitle,
      td.ChatMemberStatusRestricted() => 'restricted',
      _ => null,
    };
    return ListTile(
      leading: ChatAvatar.user(u, size: 40),
      title: Text(Display.userName(u)),
      subtitle: Text(Display.status(u), style: const TextStyle(color: GlowColors.textMuted, fontSize: 12)),
      trailing: badge == null
          ? null
          : Text(badge, style: const TextStyle(color: GlowColors.cyan, fontSize: 12)),
      onTap: onTap,
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: GlowColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: GlowColors.outline),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 78,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: GlowColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: GlowColors.outline),
        ),
        child: Column(
          children: [
            Icon(icon, color: GlowColors.cyan),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    ),
  );
}
