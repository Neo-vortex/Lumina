import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/chat_avatar.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/glow_button.dart';
import '../../../../core/widgets/glow_sheet.dart';
import '../../bloc/join_folder_cubit.dart';
import '../../data/folders_repository.dart';

/// Opened by a `t.me/addlist` link ([url]), or by "+N new" on a joined
/// shared folder ([folderId] and [chatIds]).
Future<void> showJoinFolderSheet(BuildContext context, {String? url, int? folderId, List<int>? chatIds}) {
  final repo = context.read<FoldersRepository>();
  final cache = context.read<TelegramCache>();
  return showGlowSheet<void>(
    context,
    accent: GlowColors.cyan,
    builder: (_) => BlocProvider(
      create: (_) =>
          (url != null
                ? JoinFolderCubit.link(repository: repo, url: url)
                : JoinFolderCubit.newChats(
                    repository: repo,
                    cache: cache,
                    folderId: folderId!,
                    chatIds: chatIds!,
                  ))
            ..load(),
      child: _JoinBody(isLink: url != null),
    ),
  );
}

class _JoinBody extends StatelessWidget {
  const _JoinBody({required this.isLink});

  final bool isLink;

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    return BlocConsumer<JoinFolderCubit, JoinFolderState>(
      listenWhen: (a, b) => b.done && !a.done,
      listener: (context, s) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.existing ? 'Joined ${s.selected.length} chats' : 'Folder “${s.title}” added'),
          ),
        );
      },
      builder: (context, s) {
        final cubit = context.read<JoinFolderCubit>();
        if (s.loading)
          return const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          );
        if (s.chatIds.isEmpty && s.error != null) {
          return Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.link_off_rounded, color: GlowColors.coral, size: 40),
                const SizedBox(height: 12),
                Text(s.error!, textAlign: TextAlign.center),
              ],
            ),
          );
        }
        final action = !isLink || s.existing
            ? 'Join ${s.selected.length} chat${s.selected.length == 1 ? '' : 's'}'
            : 'Add folder';
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: GlowColors.cyan.withValues(alpha: 0.15),
                  boxShadow: glow(GlowColors.cyan, intensity: 0.7),
                ),
                child: const Icon(Icons.folder_shared_rounded, color: GlowColors.cyan, size: 28),
              ),
              const SizedBox(height: 12),
              Text(s.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              Text(
                isLink ? '${s.chatIds.length} chats' : '${s.chatIds.length} new chats in this folder',
                style: const TextStyle(color: GlowColors.textMuted),
              ),
              const SizedBox(height: 8),
              for (final id in s.chatIds)
                Builder(
                  builder: (context) {
                    final chat = cache.chats[id];
                    final members = chat == null ? null : cache.supergroupOf(chat)?.memberCount;
                    final already = s.alreadyIn.contains(id);
                    return CheckboxListTile(
                      value: already || s.selected.contains(id),
                      onChanged: already ? null : (_) => cubit.toggle(id),
                      secondary: chat == null
                          ? const Icon(Icons.chat_rounded)
                          : ChatAvatar.chat(chat, size: 36),
                      title: Text(chat?.title ?? 'Chat', maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        already
                            ? 'Already joined'
                            : (members == null || members == 0 ? '' : '$members members'),
                      ),
                    );
                  },
                ),
              if (s.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(s.error!, style: const TextStyle(color: GlowColors.error)),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: GlowButton(
                  label: action,
                  busy: s.joining,
                  onPressed: s.joining || (s.existing && s.selected.isEmpty) ? null : cubit.join,
                ),
              ),
              if (!isLink)
                TextButton(onPressed: s.joining ? null : cubit.notNow, child: const Text('Not now')),
            ],
          ),
        );
      },
    );
  }
}
