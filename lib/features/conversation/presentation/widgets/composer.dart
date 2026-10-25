import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handy_tdlib_next/api.dart' as td;

import '../../../../core/telegram/display.dart';
import '../../../../core/telegram/telegram_cache.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/theme/motion.dart';
import '../../data/messages_repository.dart';
import 'send_orb.dart';

/// Message composer: reply/edit strip, attach button, multiline field and
/// the send orb. Voice recording and dictation are delegated through
/// callbacks so their features own the details.
class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.controller,
    required this.replyTo,
    required this.editing,
    required this.onSend,
    required this.onCancelMode,
    required this.onChanged,
    this.onAttach,
    this.onVoice,
    this.onDictate,
    this.recordingOverlay,
    this.orbMode,
  });

  final TextEditingController controller;
  final td.Message? replyTo;
  final td.Message? editing;
  final Future<void> Function(String text, SendOptions options) onSend;
  final VoidCallback onCancelMode;
  final ValueChanged<String> onChanged;
  final VoidCallback? onAttach;
  final VoidCallback? onVoice;
  final VoidCallback? onDictate;

  /// Replaces the text row while recording (waveform, timer).
  final Widget? recordingOverlay;

  /// Forces the orb mode (e.g. stop while recording, busy while dictating).
  final OrbMode? orbMode;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  var _sending = false;

  static const _fullCharge = 160;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onText() => setState(() {});

  Future<void> _send([SendOptions options = const SendOptions()]) async {
    final text = widget.controller.text;
    if (text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    await widget.onSend(text, options);
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _sendOptions() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: GlowColors.surfaceHigh,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.notifications_off_rounded),
              title: const Text('Send without sound'),
              onTap: () => Navigator.pop(context, 'silent'),
            ),
            ListTile(
              leading: const Icon(Icons.schedule_send_rounded),
              title: const Text('Schedule message'),
              onTap: () => Navigator.pop(context, 'schedule'),
            ),
            ListTile(
              leading: const Icon(Icons.wifi_tethering_rounded),
              title: const Text('Send when online'),
              subtitle: const Text('Delivered as soon as they come online'),
              onTap: () => Navigator.pop(context, 'online'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'silent':
        await _send(const SendOptions(silent: true));
      case 'online':
        await _send(const SendOptions(whenOnline: true));
      case 'schedule':
        final now = DateTime.now();
        final date = await showDatePicker(
          context: context,
          firstDate: now,
          lastDate: now.add(const Duration(days: 365)),
          initialDate: now,
        );
        if (date == null || !mounted) return;
        final time = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
        );
        if (time == null) return;
        final at = DateTime(date.year, date.month, date.day, time.hour, time.minute);
        if (at.isBefore(DateTime.now())) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Pick a time in the future')));
          }
          return;
        }
        await _send(SendOptions(scheduleAt: at));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    final hasText = text.trim().isNotEmpty;
    final mode = widget.orbMode ?? (_sending ? OrbMode.busy : (hasText ? OrbMode.send : OrbMode.mic));
    final contextMessage = widget.editing ?? widget.replyTo;

    return Material(
      color: GlowColors.background,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSize(
              duration: Motion.micro,
              curve: Motion.enter,
              child: contextMessage == null
                  ? const SizedBox(width: double.infinity)
                  : _ContextStrip(
                      message: contextMessage,
                      editing: widget.editing != null,
                      onCancel: widget.onCancelMode,
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (widget.recordingOverlay == null && widget.onAttach != null)
                    IconButton(
                      tooltip: 'Attach',
                      onPressed: widget.onAttach,
                      icon: const Icon(Icons.add_circle_outline_rounded, color: GlowColors.cyan),
                    ),
                  Expanded(
                    child:
                        widget.recordingOverlay ??
                        Container(
                          constraints: const BoxConstraints(minHeight: 48),
                          decoration: BoxDecoration(
                            color: GlowColors.surface,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: GlowColors.outlineStrong),
                          ),
                          child: TextField(
                            controller: widget.controller,
                            onChanged: widget.onChanged,
                            minLines: 1,
                            maxLines: 6,
                            textCapitalization: TextCapitalization.sentences,
                            keyboardType: TextInputType.multiline,
                            decoration: InputDecoration(
                              hintText: widget.editing != null ? 'Edit message' : 'Message',
                              hintStyle: const TextStyle(color: GlowColors.textMuted),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                            ),
                          ),
                        ),
                  ),
                  const SizedBox(width: 8),
                  SendOrb(
                    mode: mode,
                    charge: hasText ? (text.length / _fullCharge).clamp(0.08, 1.0) : 0,
                    onTap: switch (mode) {
                      OrbMode.send => _send,
                      OrbMode.mic => widget.onVoice ?? () {},
                      OrbMode.stop => widget.onVoice ?? () {},
                      OrbMode.busy => () {},
                    },
                    onLongPress: hasText && widget.editing == null
                        ? _sendOptions
                        : (!hasText ? widget.onDictate : null),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContextStrip extends StatelessWidget {
  const _ContextStrip({required this.message, required this.editing, required this.onCancel});

  final td.Message message;
  final bool editing;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final cache = context.read<TelegramCache>();
    final accent = editing ? GlowColors.amber : GlowColors.cyan;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
      child: Row(
        children: [
          Icon(editing ? Icons.edit_rounded : Icons.reply_rounded, color: accent, size: 20),
          const SizedBox(width: 10),
          Container(width: 2, height: 32, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  editing
                      ? 'Editing'
                      : 'Reply to ${message.isOutgoing ? 'yourself' : Display.senderName(cache, message.senderId)}',
                  style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                Text(
                  Display.preview(cache, message),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: GlowColors.textMuted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: editing ? 'Cancel editing' : 'Cancel reply',
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded, color: GlowColors.textMuted),
          ),
        ],
      ),
    );
  }
}
