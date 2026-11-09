import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/platform/system_channel.dart';
import '../../../../core/telegram/display.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/chat_avatar.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/delete_confirm.dart';
import '../../../../core/widgets/glow_button.dart';
import '../../../../core/widgets/glow_sheet.dart';
import '../../data/contacts_repository.dart';

/// Add or rename [userId] as a contact. People whose number is hidden can
/// be added too: Telegram keeps the contact by account. True once saved.
Future<bool> showContactEditor(BuildContext context, int userId) async {
  final repo = context.read<ContactsRepository>();
  final user = context.read<TelegramCache>().users[userId];
  final adding = !(user?.isContact ?? false);
  final first = TextEditingController(text: user?.firstName ?? '');
  final last = TextEditingController(text: user?.lastName ?? '');
  var sharePhone = false;
  final save = await showGlowSheet<bool>(
    context,
    title: adding ? 'Add to contacts' : 'Edit contact',
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: ChatAvatar.user(user, size: 64)),
            const SizedBox(height: 8),
            Text(
              user == null || user.phoneNumber.isEmpty ? 'Phone number hidden' : '+${user.phoneNumber}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: GlowColors.textMuted),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: first,
              autofocus: adding,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'First name'),
            ),
            TextField(
              controller: last,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Last name'),
            ),
            if (adding)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: sharePhone,
                onChanged: (v) => setState(() => sharePhone = v),
                title: const Text('Share my phone number'),
                subtitle: Text('${Display.userName(user)} will see your number'),
              ),
            const SizedBox(height: 12),
            GlowButton(label: adding ? 'Add contact' : 'Save', onPressed: () => Navigator.pop(context, true)),
          ],
        ),
      ),
    ),
  );
  final firstName = first.text.trim(), lastName = last.text.trim();
  first.dispose();
  last.dispose();
  if (save != true) return false;
  if (firstName.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A first name is needed')));
    }
    return false;
  }
  try {
    await repo.save(userId, firstName: firstName, lastName: lastName, sharePhone: sharePhone);
    return true;
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    return false;
  }
}

/// Share [userId]: as a contact card into a chat, or as text and a link to
/// other apps.
Future<void> showShareContact(BuildContext context, int userId) async {
  final where = await showGlowSheet<String>(
    context,
    title: 'Share contact',
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Icons.send_rounded, color: GlowColors.violet),
          title: const Text('Send to a chat'),
          subtitle: const Text('As a contact card'),
          onTap: () => Navigator.pop(context, 'chat'),
        ),
        ListTile(
          leading: const Icon(Icons.ios_share_rounded, color: GlowColors.cyan),
          title: const Text('Other apps'),
          subtitle: const Text('Name, number and profile link'),
          onTap: () => Navigator.pop(context, 'apps'),
        ),
        const SizedBox(height: 8),
      ],
    ),
  );
  if (where == null || !context.mounted) return;
  final repo = context.read<ContactsRepository>();
  final user = context.read<TelegramCache>().users[userId];
  if (where == 'apps') {
    final phone = user == null || user.phoneNumber.isEmpty ? '' : '\n+${user.phoneNumber}';
    await const SystemChannel().shareText('${Display.userName(user)}$phone\n${repo.linkOf(userId)}');
    return;
  }
  final chatId = await _pickChat(context);
  if (chatId == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await repo.shareTo(chatId, userId);
    messenger.showSnackBar(const SnackBar(content: Text('Contact sent')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
}

/// Opens the phone's own "new contact" screen with [userId]'s details.
Future<void> saveContactToPhone(BuildContext context, int userId) async {
  final user = context.read<TelegramCache>().users[userId];
  final ok = await const SystemChannel().saveToPhoneContacts(
    name: Display.userName(user),
    phone: user == null || user.phoneNumber.isEmpty ? '' : '+${user.phoneNumber}',
    note: context.read<ContactsRepository>().linkOf(userId),
  );
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No contacts app found')));
  }
}

Future<bool> deleteContact(BuildContext context, int userId) async {
  final user = context.read<TelegramCache>().users[userId];
  final repo = context.read<ContactsRepository>();
  final ok = await confirmDelete(
    context,
    title: 'Delete ${Display.userName(user)} from contacts?',
    message: 'Your chat with them stays.',
  );
  if (ok == null) return false;
  try {
    await repo.delete([userId]);
    return true;
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    return false;
  }
}

/// Every action on one person in the contacts list.
Future<void> showContactActions(
  BuildContext context,
  int userId, {
  required VoidCallback onMessage,
  required VoidCallback onProfile,
}) async {
  final user = context.read<TelegramCache>().users[userId];
  final contact = user?.isContact ?? false;
  final action = await showGlowSheet<String>(
    context,
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: ChatAvatar.user(user, size: 40),
          title: Text(Display.userName(user), style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            user == null || user.phoneNumber.isEmpty ? Display.status(user) : '+${user.phoneNumber}',
            style: const TextStyle(color: GlowColors.textMuted),
          ),
        ),
        const Divider(height: 1),
        for (final (id, icon, label, color) in [
          ('message', Icons.chat_bubble_rounded, 'Message', GlowColors.violet),
          ('profile', Icons.person_rounded, 'View profile', null),
          (
            'edit',
            contact ? Icons.edit_rounded : Icons.person_add_rounded,
            contact ? 'Edit' : 'Add to contacts',
            null,
          ),
          ('share', Icons.share_rounded, 'Share', null),
          ('phone', Icons.save_alt_rounded, 'Save to phone', null),
          if (contact) ('delete', Icons.person_remove_rounded, 'Delete', GlowColors.coral),
        ])
          ListTile(
            leading: Icon(icon, color: color),
            title: Text(label, style: TextStyle(color: color == GlowColors.coral ? color : null)),
            onTap: () => Navigator.pop(context, id),
          ),
        const SizedBox(height: 8),
      ],
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case 'message':
      onMessage();
    case 'profile':
      onProfile();
    case 'edit':
      await showContactEditor(context, userId);
    case 'share':
      await showShareContact(context, userId);
    case 'phone':
      await saveContactToPhone(context, userId);
    case 'delete':
      await deleteContact(context, userId);
  }
}

/// A chat from the main list, with a filter.
Future<int?> _pickChat(BuildContext context) {
  final cache = context.read<TelegramCache>();
  final all = cache.chatsIn(const td.ChatListMain()).toList();
  var query = '';
  return showGlowSheet<int>(
    context,
    title: 'Send to…',
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final q = query.toLowerCase();
        final chats = q.isEmpty ? all : all.where((c) => c.title.toLowerCase().contains(q)).toList();
        return SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.6,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Search',
                  ),
                  onChanged: (v) => setState(() => query = v.trim()),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: chats.length,
                  itemBuilder: (context, i) => ListTile(
                    leading: ChatAvatar.chat(chats[i], size: 40),
                    title: Text(chats[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(context, chats[i].id),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
