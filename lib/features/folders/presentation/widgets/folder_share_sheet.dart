import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/platform/system_channel.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/chat_avatar.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/glow_button.dart';
import '../../../../core/widgets/glow_sheet.dart';
import '../../bloc/folder_links_cubit.dart';
import '../../data/folders_repository.dart';
import '../screens/folder_qr_screen.dart';

/// Share a folder: its invite links (copy, share, QR, edit, revoke) and
/// "New link". Converts a rule-based folder to a chat list first.
Future<void> showFolderShareSheet(
  BuildContext context, {
  required int folderId,
  required String title,
  required Color color,
}) => showGlowSheet<void>(
  context,
  title: 'Share “$title”',
  accent: color,
  builder: (_) => BlocProvider(
    create: (_) => FolderLinksCubit(
      repository: context.read<FoldersRepository>(),
      cache: context.read<TelegramCache>(),
      folderId: folderId,
    )..load(),
    child: _ShareBody(title: title, color: color, outer: context),
  ),
);

class _ShareBody extends StatelessWidget {
  const _ShareBody({required this.title, required this.color, required this.outer});

  final String title;
  final Color color;
  final BuildContext outer;

  Future<void> _editLink(BuildContext context, {td.ChatFolderInviteLink? link}) async {
    final cubit = context.read<FolderLinksCubit>();
    final cache = context.read<TelegramCache>();
    final name = TextEditingController(text: link?.name ?? '');
    final chosen = {...(link?.chatIds ?? cubit.state.shareable)};
    final ok = await showGlowSheet<bool>(
      context,
      title: link == null ? 'New invite link' : 'Edit invite link',
      accent: color,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                maxLength: 32,
                decoration: const InputDecoration(labelText: 'Link name (optional)'),
              ),
              for (final id in cubit.state.shareable)
                CheckboxListTile(
                  value: chosen.contains(id),
                  onChanged: (v) => setState(() => v! ? chosen.add(id) : chosen.remove(id)),
                  secondary: cache.chats[id] == null ? null : ChatAvatar.chat(cache.chats[id]!, size: 32),
                  title: Text(cache.chats[id]?.title ?? 'Chat'),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: GlowButton(
                  label: link == null ? 'Create link' : 'Save',
                  onPressed: chosen.isEmpty ? null : () => Navigator.pop(context, true),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;
    if (link == null) {
      await cubit.create(name.text.trim(), chosen.toList());
    } else {
      await cubit.edit(link, name.text.trim(), chosen.toList());
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FolderLinksCubit, FolderLinksState>(
      builder: (context, s) {
        final cubit = context.read<FolderLinksCubit>();
        if (s.loading)
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          );
        if (s.needsConversion) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Telegram shares folders that are a plain list of chats. This one picks chats by type or '
                  'excludes some. Convert it to the list of chats it shows right now?',
                  style: TextStyle(color: GlowColors.textMuted),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: GlowButton(label: 'Convert to a chat list', onPressed: cubit.convert),
                ),
                if (s.error != null) Text(s.error!, style: const TextStyle(color: GlowColors.error)),
              ],
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final l in s.links)
              ListTile(
                leading: Icon(Icons.link_rounded, color: color),
                title: Text(
                  l.name.isEmpty ? l.inviteLink : l.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${l.chatIds.length} chats · ${l.inviteLink}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => _editLink(context, link: l),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Copy',
                      icon: const Icon(Icons.copy_rounded),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: l.inviteLink));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(content: Text('Link copied')));
                        }
                      },
                    ),
                    IconButton(
                      tooltip: 'Share',
                      icon: const Icon(Icons.share_rounded),
                      onPressed: () => const SystemChannel().shareText(l.inviteLink),
                    ),
                    IconButton(
                      tooltip: 'QR code',
                      icon: const Icon(Icons.qr_code_2_rounded),
                      onPressed: () =>
                          Navigator.of(outer)
                              .push(FolderQrScreen.route(url: l.inviteLink, title: title, color: color)),
                    ),
                    IconButton(
                      tooltip: 'Revoke',
                      icon: const Icon(Icons.link_off_rounded, color: GlowColors.coral),
                      onPressed: () async {
                        final ok = await showGlowConfirm(
                          context,
                          title: 'Revoke this link?',
                          message: 'People who already joined keep the folder.',
                          confirmLabel: 'Revoke',
                          icon: Icons.link_off_rounded,
                          destructive: true,
                        );
                        if (ok) await cubit.delete(l);
                      },
                    ),
                  ],
                ),
              ),
            ListTile(
              leading: const Icon(Icons.add_link_rounded, color: GlowColors.cyan),
              title: const Text('New link'),
              onTap: s.shareable.isEmpty ? null : () => _editLink(context),
              subtitle: s.shareable.isEmpty ? const Text('None of these chats can be shared') : null,
            ),
            if (s.error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(s.error!, style: const TextStyle(color: GlowColors.error)),
              ),
          ],
        );
      },
    );
  }
}
