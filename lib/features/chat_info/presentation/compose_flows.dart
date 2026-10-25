import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handy_tdlib_next/api.dart' as td;

import '../../../core/tdlib/td_errors.dart';
import '../../../core/theme/glow_colors.dart';
import '../data/chat_info_repository.dart';
import 'widgets/contact_picker.dart';

/// Opens a chat by id; supplied by the composition root so this feature
/// doesn't depend on the conversation feature.
typedef OpenChat = void Function(BuildContext context, int chatId);

/// "New message / group / channel / secret chat" flows behind the compose orb.
class ComposeFlows {
  const ComposeFlows(this.openChat);

  final OpenChat openChat;

  Future<void> newMessage(BuildContext context) async {
    final ids = await ContactPickerScreen.pick(context, title: 'New message');
    if (ids == null || ids.isEmpty || !context.mounted) return;
    await _create(context, (r) => r.privateChat(ids.first));
  }

  Future<void> newSecretChat(BuildContext context) async {
    final ids = await ContactPickerScreen.pick(context, title: 'New secret chat');
    if (ids == null || ids.isEmpty || !context.mounted) return;
    await _create(context, (r) => r.createSecretChat(ids.first));
  }

  Future<void> newGroup(BuildContext context) async {
    final ids = await ContactPickerScreen.pick(
      context,
      title: 'New group',
      multiple: true,
      actionLabel: 'Next',
    );
    if (ids == null || !context.mounted) return;
    final fields = await _askFields(context, 'Group name', const ['Name']);
    if (fields == null || fields[0].isEmpty || !context.mounted) return;
    await _create(context, (r) => r.createGroup(fields[0], ids));
  }

  Future<void> newChannel(BuildContext context) async {
    final fields = await _askFields(context, 'New channel', const ['Name', 'Description (optional)']);
    if (fields == null || fields[0].isEmpty || !context.mounted) return;
    await _create(context, (r) => r.createChannel(fields[0], fields[1]));
  }

  Future<void> _create(BuildContext context, Future<td.Chat> Function(ChatInfoRepository) create) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final chat = await create(context.read<ChatInfoRepository>());
      if (context.mounted) openChat(context, chat.id);
    } on TdException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  static Future<List<String>?> _askFields(BuildContext context, String title, List<String> labels) async {
    final controllers = [for (final _ in labels) TextEditingController()];
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlowColors.surfaceHigh,
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < labels.length; i++)
              TextField(
                controller: controllers[i],
                autofocus: i == 0,
                maxLines: i == 0 ? 1 : 4,
                minLines: 1,
                decoration: InputDecoration(labelText: labels[i]),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, [for (final c in controllers) c.text.trim()]),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    for (final c in controllers) {
      c.dispose();
    }
    return result;
  }
}
