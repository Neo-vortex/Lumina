import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../core/platform/system_channel.dart';
import '../../../core/theme/glow_colors.dart';
import '../../../core/theme/motion.dart';
import '../data/action_extractor.dart';
import '../domain/assistant_action.dart';

/// "AI action" on a message: the tiny on-device model proposes a calendar
/// event, alarm, reminder or note; the user edits and confirms; only then
/// does the app hand it to the system (calendar, clock or notes app).
Future<void> showAssistantActionSheet(
  BuildContext context, {
  required String messageText,
  required AssistantContext assistantContext,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: GlowColors.surfaceHigh,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _ActionSheet(
        messageText: messageText,
        ctx: assistantContext,
        extractor: context.read<ActionExtractor>(),
      ),
    ),
  );
}

class _ActionSheet extends StatefulWidget {
  const _ActionSheet({required this.messageText, required this.ctx, required this.extractor});

  final String messageText;
  final AssistantContext ctx;
  final ActionExtractor extractor;

  @override
  State<_ActionSheet> createState() => _ActionSheetState();
}

class _ActionSheetState extends State<_ActionSheet> {
  ActionDraft? _draft;
  String? _error;
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _notes = TextEditingController();
  var _running = false;

  @override
  void initState() {
    super.initState();
    _extract();
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _extract() async {
    try {
      final d = await widget.extractor.extract(widget.messageText, widget.ctx);
      if (!mounted) return;
      _title.text = d.title;
      _location.text = d.location;
      _notes.text = d.notes;
      setState(() => _draft = d);
    } catch (e) {
      if (mounted) setState(() => _error = 'The on-device model could not read this message ($e).');
    }
  }

  Future<void> _pickDate() async {
    final d = _draft!;
    final now = DateTime.now();
    final initial = d.when ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;
    setState(() {
      d.when = DateTime(date.year, date.month, date.day, initial.hour, initial.minute);
      d.relative = null;
    });
  }

  Future<void> _pickTime() async {
    final d = _draft!;
    final initial = d.when ?? DateTime.now();
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null) return;
    setState(() {
      d.when = DateTime(initial.year, initial.month, initial.day, time.hour, time.minute);
      d.relative = null;
    });
  }

  Future<void> _run() async {
    final d = _draft!;
    d
      ..title = _title.text.trim().isEmpty ? 'Reminder' : _title.text.trim()
      ..location = _location.text.trim()
      ..notes = _notes.text.trim();
    const system = SystemChannel();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _running = true);
    var ok = false;
    final when = d.when ?? DateTime.now().add(const Duration(hours: 1));
    final source = 'From ${widget.ctx.senderName} on Telegram:\n${widget.messageText}';
    try {
      switch (d.kind) {
        case ActionKind.calendar:
          ok = await system.insertCalendarEvent(
            title: d.title,
            begin: when,
            end: when.add(d.duration),
            location: d.location.isEmpty ? null : d.location,
            description: [if (d.notes.isNotEmpty) d.notes, source].join('\n\n'),
          );
        case ActionKind.alarm:
          ok = await system.setAlarm(hour: when.hour, minutes: when.minute, message: d.title);
        case ActionKind.reminder:
          final relative = d.relative;
          if (relative != null && relative < const Duration(hours: 24)) {
            ok = await system.setTimer(seconds: relative.inSeconds, message: d.title);
          } else {
            ok = await system.insertCalendarEvent(
              title: d.title,
              begin: when,
              end: when.add(const Duration(minutes: 15)),
              description: source,
              reminder: true,
            );
          }
        case ActionKind.note:
          ok = await system.createNote(
            title: d.title,
            text: [if (d.notes.isNotEmpty) d.notes, widget.messageText].join('\n\n'),
          );
        case ActionKind.none:
          ok = true;
      }
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    Navigator.pop(context);
    if (!ok) {
      messenger.showSnackBar(const SnackBar(content: Text('No app on this phone can handle that action')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _draft;
    return SafeArea(
      child: AnimatedSize(
        duration: Motion.standard,
        curve: Motion.enter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: _error != null
              ? _Message(icon: Icons.error_outline_rounded, text: _error!)
              : d == null
              ? const _Thinking()
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.auto_awesome_rounded, color: GlowColors.cyan),
                          SizedBox(width: 8),
                          Text(
                            'Suggested action',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Worked out on this phone. Check it before saving.',
                        style: TextStyle(color: GlowColors.textMuted, fontSize: 13),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final k in ActionKind.values.where((k) => k != ActionKind.none))
                            ChoiceChip(
                              avatar: Icon(_icon(k), size: 18),
                              label: Text(_label(k)),
                              selected: d.kind == k,
                              selectedColor: GlowColors.violetDeep,
                              onSelected: (_) => setState(() => d.kind = k),
                            ),
                        ],
                      ),
                      if (d.kind == ActionKind.none)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            'Nothing to schedule was found. Pick an action above to create one anyway.',
                            style: TextStyle(color: GlowColors.textMuted),
                          ),
                        )
                      else ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _title,
                          decoration: const InputDecoration(labelText: 'Title'),
                        ),
                        if (d.kind != ActionKind.note) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: d.kind == ActionKind.alarm ? null : _pickDate,
                                  icon: const Icon(Icons.event_rounded),
                                  label: Text(
                                    d.relative != null
                                        ? 'In ${_human(d.relative!)}'
                                        : d.when == null
                                        ? 'Pick date'
                                        : DateFormat.MMMEd().format(d.when!),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _pickTime,
                                  icon: const Icon(Icons.schedule_rounded),
                                  label: Text(d.when == null ? 'Pick time' : DateFormat.Hm().format(d.when!)),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (d.kind == ActionKind.calendar) ...[
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                            initialValue: const [15, 30, 60, 90, 120, 240].contains(d.duration.inMinutes)
                                ? d.duration.inMinutes
                                : 60,
                            decoration: const InputDecoration(labelText: 'Duration'),
                            dropdownColor: GlowColors.surfaceHigh,
                            items: [
                              for (final m in const [15, 30, 60, 90, 120, 240])
                                DropdownMenuItem(value: m, child: Text(m < 60 ? '$m min' : '${m / 60} h')),
                            ],
                            onChanged: (m) => setState(() => d.duration = Duration(minutes: m ?? 60)),
                          ),
                          TextField(
                            controller: _location,
                            decoration: const InputDecoration(labelText: 'Location'),
                          ),
                        ],
                        TextField(
                          controller: _notes,
                          minLines: 1,
                          maxLines: 3,
                          decoration: const InputDecoration(labelText: 'Notes'),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: GlowColors.violetDeep,
                          minimumSize: const Size.fromHeight(52),
                        ),
                        onPressed: _running || d.kind == ActionKind.none ? null : _run,
                        icon: Icon(_icon(d.kind)),
                        label: Text(switch (d.kind) {
                          ActionKind.calendar => 'Add to calendar',
                          ActionKind.alarm => 'Set alarm',
                          ActionKind.reminder => d.relative != null ? 'Start timer' : 'Add reminder',
                          ActionKind.note => 'Save note',
                          ActionKind.none => 'Choose an action',
                        }),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  static String _human(Duration d) =>
      d.inMinutes < 60 ? '${d.inMinutes} min' : (d.inHours < 24 ? '${d.inHours} h' : '${d.inDays} days');

  static IconData _icon(ActionKind k) => switch (k) {
    ActionKind.calendar => Icons.event_available_rounded,
    ActionKind.alarm => Icons.alarm_rounded,
    ActionKind.reminder => Icons.notifications_active_rounded,
    ActionKind.note => Icons.sticky_note_2_rounded,
    ActionKind.none => Icons.auto_awesome_rounded,
  };

  static String _label(ActionKind k) => switch (k) {
    ActionKind.calendar => 'Event',
    ActionKind.alarm => 'Alarm',
    ActionKind.reminder => 'Reminder',
    ActionKind.note => 'Note',
    ActionKind.none => 'None',
  };
}

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 28),
    child: Column(
      children: [
        SizedBox.square(
          dimension: 36,
          child: CircularProgressIndicator(color: GlowColors.cyan, strokeWidth: 2.6),
        ),
        SizedBox(height: 16),
        Text('Reading the message on your phone…', style: TextStyle(color: GlowColors.textMuted)),
      ],
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Row(
      children: [
        Icon(icon, color: GlowColors.error),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
