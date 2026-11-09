import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/tdlib/td_client.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/chat_avatar.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../data/messages_repository.dart';

/// Pick destination chats and forward options. [hideSenderInitially] comes
/// from "Forward without sender". True once something was forwarded.
Future<bool> showForwardSheet(
  BuildContext context, {
  required int fromChatId,
  required List<int> messageIds,
  bool hideSenderInitially = false,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: GlowColors.surfaceHigh,
    showDragHandle: true,
    builder: (context) => _ForwardSheet(
      fromChatId: fromChatId,
      messageIds: messageIds,
      hideSenderInitially: hideSenderInitially,
    ),
  ).then((sent) => sent ?? false);
}

class _ForwardSheet extends StatefulWidget {
  const _ForwardSheet({
    required this.fromChatId,
    required this.messageIds,
    required this.hideSenderInitially,
  });

  final int fromChatId;
  final List<int> messageIds;
  final bool hideSenderInitially;

  @override
  State<_ForwardSheet> createState() => _ForwardSheetState();
}

class _ForwardSheetState extends State<_ForwardSheet> {
  late var _hideSender = widget.hideSenderInitially;
  var _removeCaption = false;
  var _query = '';
  final _targets = <int>{};
  var _sending = false;

  /// Saved Messages (the chat with yourself), always offered first even if
  /// it isn't in the chat list yet.
  int? _savedId;

  @override
  void initState() {
    super.initState();
    final client = context.read<TdClient>();
    client
        .invoke<td.User>(const td.GetMe())
        .then((me) => client.invoke<td.Chat>(td.CreatePrivateChat(userId: me.id, force: false)))
        .then((chat) {
          if (mounted) setState(() => _savedId = chat.id);
        })
        .catchError((Object _) {});
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    final repo = context.read<MessagesRepository>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      for (final chatId in _targets) {
        await repo.forward(
          toChatId: chatId,
          fromChatId: widget.fromChatId,
          messageIds: widget.messageIds,
          hideSender: _hideSender,
          removeCaption: _removeCaption,
        );
      }
      if (mounted) Navigator.pop(context, true);
      messenger.showSnackBar(
        SnackBar(content: Text('Forwarded to ${_targets.length} chat${_targets.length == 1 ? '' : 's'}')),
      );
    } catch (e) {
      if (mounted) setState(() => _sending = false);
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    final chats = cache
        .chatsIn(const td.ChatListMain())
        .where((c) => _query.isEmpty || c.title.toLowerCase().contains(_query.toLowerCase()))
        .where(
          (c) =>
              c.permissions.canSendBasicMessages ||
              c.type is td.ChatTypePrivate ||
              c.type is td.ChatTypeSupergroup,
        )
        .where((c) => c.id != _savedId)
        .toList();
    final savedId = _savedId;
    final showSaved = savedId != null && (_query.isEmpty || 'saved messages'.contains(_query.toLowerCase()));
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Forward to…',
                  border: InputBorder.none,
                ),
                onChanged: (q) => setState(() => _query = q),
              ),
            ),
            SwitchListTile(
              value: _hideSender,
              onChanged: (v) => setState(() => _hideSender = v),
              title: const Text('Hide sender name'),
              subtitle: const Text('Sends a copy without "Forwarded from"'),
            ),
            if (_hideSender)
              SwitchListTile(
                value: _removeCaption,
                onChanged: (v) => setState(() => _removeCaption = v),
                title: const Text('Remove captions'),
              ),
            const Divider(height: 1, color: GlowColors.outline),
            Expanded(
              child: ListView.builder(
                itemCount: chats.length + (showSaved ? 1 : 0),
                itemBuilder: (context, index) {
                  if (showSaved && index == 0) {
                    final selected = _targets.contains(savedId);
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 21,
                        backgroundColor: GlowColors.violetDeep,
                        child: const Icon(Icons.bookmark_rounded, color: Colors.white),
                      ),
                      title: const Text('Saved Messages'),
                      trailing: Icon(
                        selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        color: selected ? GlowColors.violet : GlowColors.outlineStrong,
                      ),
                      onTap: () =>
                          setState(() => selected ? _targets.remove(savedId) : _targets.add(savedId)),
                    );
                  }
                  final chat = chats[index - (showSaved ? 1 : 0)];
                  final selected = _targets.contains(chat.id);
                  return ListTile(
                    leading: ChatAvatar.chat(chat, size: 42, glowIntensity: selected ? 0.6 : 0),
                    title: Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Icon(
                      selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      color: selected ? GlowColors.violet : GlowColors.outlineStrong,
                    ),
                    onTap: () => setState(() => selected ? _targets.remove(chat.id) : _targets.add(chat.id)),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: GlowColors.violetDeep,
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: _targets.isEmpty || _sending ? null : _send,
                icon: const Icon(Icons.send_rounded),
                label: Text(_targets.isEmpty ? 'Choose chats' : 'Forward to ${_targets.length}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
