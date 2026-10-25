import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handy_tdlib_next/api.dart' as td;
import 'package:intl/intl.dart';

import '../../../../core/tdlib/td_errors.dart';
import '../../../../core/telegram/display.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/telegram/widgets/formatted_text_view.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../data/messages_repository.dart';
import '../widgets/message_menu.dart';
import '../widgets/schedule_picker.dart';

/// A chat's scheduled messages (Telegram's "Scheduled" view): when each
/// goes out, and send now / reschedule / edit / delete.
class ScheduledMessagesScreen extends StatefulWidget {
  const ScheduledMessagesScreen({super.key, required this.chat});

  final td.Chat chat;

  static Route<void> route(td.Chat chat) =>
      MaterialPageRoute(builder: (_) => ScheduledMessagesScreen(chat: chat));

  @override
  State<ScheduledMessagesScreen> createState() => _ScheduledMessagesScreenState();
}

class _ScheduledMessagesScreenState extends State<ScheduledMessagesScreen> {
  late final MessagesRepository _repo = context.read<MessagesRepository>();
  StreamSubscription<void>? _changes;
  List<td.Message>? _messages;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
    _changes = _repo.scheduledChanges(widget.chat.id).listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 250), _load);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final m = await _repo.scheduled(widget.chat.id);
      if (mounted) setState(() => _messages = m..sort((a, b) => _when(a).compareTo(_when(b))));
    } on TdException catch (e) {
      if (mounted) _snack(e.message);
    }
  }

  static int _when(td.Message m) => switch (m.schedulingState) {
    td.MessageSchedulingStateSendAtDate(:final sendDate) => sendDate,
    _ => 0, // "When online" first.
  };

  void _snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> _run(Future<void> Function() f, String done) async {
    try {
      await f();
      _snack(done);
      await _load();
    } on TdException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _actions(td.Message m) async {
    final text = messageText(m);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: GlowColors.surfaceHigh,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.send_rounded, color: GlowColors.cyan),
              title: const Text('Send now'),
              onTap: () => Navigator.pop(context, 'now'),
            ),
            ListTile(
              leading: const Icon(Icons.schedule_rounded),
              title: const Text('Reschedule'),
              onTap: () => Navigator.pop(context, 'reschedule'),
            ),
            if (widget.chat.type is td.ChatTypePrivate)
              ListTile(
                leading: const Icon(Icons.wifi_tethering_rounded),
                title: const Text('Send when online'),
                onTap: () => Navigator.pop(context, 'online'),
              ),
            if (text != null && m.content is td.MessageText)
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: const Text('Edit text'),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: GlowColors.coral),
              title: const Text('Delete', style: TextStyle(color: GlowColors.coral)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    final chatId = widget.chat.id;
    switch (choice) {
      case 'now':
        await _run(() => _repo.sendScheduledNow(chatId, m.id), 'Sent');
      case 'reschedule':
        final current = _when(m);
        final at = await pickScheduleTime(
          context,
          initial: current == 0 ? null : DateTime.fromMillisecondsSinceEpoch(current * 1000),
        );
        if (at != null) await _run(() => _repo.reschedule(chatId, m.id, at: at), 'Rescheduled');
      case 'online':
        await _run(() => _repo.reschedule(chatId, m.id, whenOnline: true), 'Will send when they’re online');
      case 'edit':
        final edited = await _editText(text!.text);
        if (edited != null && edited.isNotEmpty) {
          await _run(() => _repo.editText(chatId, m.id, edited), 'Saved');
        }
      case 'delete':
        await _run(() => _repo.delete(chatId, [m.id], forEveryone: true), 'Deleted');
    }
  }

  Future<String?> _editText(String initial) async {
    final c = TextEditingController(text: initial);
    final r = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlowColors.surfaceHigh,
        title: const Text('Edit scheduled message'),
        content: TextField(controller: c, autofocus: true, minLines: 1, maxLines: 8),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    c.dispose();
    return r;
  }

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    final messages = _messages;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Scheduled'),
            Text(widget.chat.title, style: const TextStyle(fontSize: 13, color: GlowColors.textMuted)),
          ],
        ),
      ),
      body: messages == null
          ? const Center(child: CircularProgressIndicator(color: GlowColors.cyan))
          : messages.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Nothing scheduled.\nLong-press the send button to schedule a message.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: GlowColors.textMuted),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
              itemCount: messages.length,
              itemBuilder: (context, i) {
                final m = messages[i];
                final when = _when(m);
                final dt = when == 0 ? null : DateTime.fromMillisecondsSinceEpoch(when * 1000);
                final prevWhen = i == 0 ? -1 : _when(messages[i - 1]);
                final newDay =
                    i == 0 ||
                    (dt != null &&
                        (prevWhen == 0 ||
                            !DateUtils.isSameDay(DateTime.fromMillisecondsSinceEpoch(prevWhen * 1000), dt)));
                final text = messageText(m);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (newDay)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                        child: Text(
                          dt == null ? 'WHEN ONLINE' : DateFormat.yMMMMEEEEd().format(dt).toUpperCase(),
                          style: const TextStyle(
                            color: GlowColors.violet,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                    Card(
                      color: GlowColors.surface,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _actions(m),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: text != null && m.content is td.MessageText
                                    ? FormattedTextView(text, maxLines: 6, overflow: TextOverflow.ellipsis)
                                    : Text(Display.preview(cache, m)),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Icon(
                                    dt == null ? Icons.wifi_tethering_rounded : Icons.schedule_rounded,
                                    size: 16,
                                    color: GlowColors.cyan,
                                  ),
                                  if (dt != null)
                                    Text(
                                      DateFormat.Hm().format(dt),
                                      style: const TextStyle(color: GlowColors.textMuted),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
