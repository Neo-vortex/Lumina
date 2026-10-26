import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/glow_colors.dart';
import '../../../core/widgets/glow_button.dart';
import '../../../core/widgets/glow_sheet.dart';
import '../data/action_extractor.dart';
import '../domain/writing_tool.dart';

/// Runs a writing tool on text, reporting load stages.
typedef WritingFn = Future<String> Function(
  String text,
  WritingTool tool,
  void Function(ExtractStage stage) onStage,
);

/// The composer's ✨ sheet: pick a tool, watch it work on the phone, compare
/// before and after, then replace the draft (returned) or try again.
Future<String?> showWritingTools(BuildContext context, {required String text, required WritingFn write}) =>
    showGlowSheet<String>(
      context,
      title: 'Writing help',
      accent: GlowColors.magenta,
      builder: (context) => _WritingSheet(text: text, write: write),
    );

class _WritingSheet extends StatefulWidget {
  const _WritingSheet({required this.text, required this.write});

  final String text;
  final WritingFn write;

  @override
  State<_WritingSheet> createState() => _WritingSheetState();
}

class _WritingSheetState extends State<_WritingSheet> {
  WritingTool? _tool;
  ExtractStage? _stage;
  String? _result;
  String? _error;

  Future<void> _run(WritingTool tool) async {
    setState(() {
      _tool = tool;
      _stage = ExtractStage.reading;
      _result = null;
      _error = null;
    });
    try {
      final out = await widget.write(widget.text, tool, (s) {
        if (mounted) setState(() => _stage = s);
      });
      if (!mounted) return;
      setState(() {
        _stage = null;
        _result = out.isEmpty ? null : out;
        _error = out.isEmpty ? 'The model returned nothing. Try again or pick another tool.' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = null;
        _error = e is TimeoutException
            ? 'The on-device model took too long. Try again.'
            : 'The on-device model could not do this ($e).';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
    child: AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: _stage != null
          ? _working()
          : _result != null || _error != null
          ? _outcome()
          : _picker(),
    ),
  );

  Widget _picker() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Runs on your phone; nothing leaves it.', style: TextStyle(color: GlowColors.textMuted)),
      const SizedBox(height: 12),
      for (final t in WritingTool.values.where((t) => !t.isTone))
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(switch (t) {
            WritingTool.rewrite => Icons.auto_fix_high_rounded,
            WritingTool.grammar => Icons.spellcheck_rounded,
            _ => Icons.short_text_rounded,
          }, color: GlowColors.magenta),
          title: Text(t.label),
          subtitle: Text(t.description),
          onTap: () => _run(t),
        ),
      const Padding(
        padding: EdgeInsets.only(top: 8, bottom: 8),
        child: Text(
          'Change tone',
          style: TextStyle(color: GlowColors.violet, fontWeight: FontWeight.w600),
        ),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final t in WritingTool.values.where((t) => t.isTone))
            ActionChip(label: Text(t.label), onPressed: () => _run(t)),
        ],
      ),
    ],
  );

  Widget _working() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox.square(
          dimension: 36,
          child: CircularProgressIndicator(color: GlowColors.magenta, strokeWidth: 2.6),
        ),
        const SizedBox(height: 16),
        Text(switch (_stage!) {
          ExtractStage.preparing => 'Preparing the on-device model (first time only)…',
          ExtractStage.loading => 'Starting the on-device model…',
          ExtractStage.reading => '${_tool!.label}…',
        }, style: const TextStyle(color: GlowColors.textMuted)),
      ],
    ),
  );

  Widget _outcome() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: GlowColors.error),
              const SizedBox(width: 12),
              Expanded(child: Text(_error!)),
            ],
          ),
        )
      else ...[
        _Box(label: 'Before', text: widget.text, color: GlowColors.textMuted),
        const SizedBox(height: 10),
        _Box(label: _tool!.label, text: _result!, color: GlowColors.magenta),
      ],
      const SizedBox(height: 16),
      if (_result != null) GlowButton(label: 'Replace', onPressed: () => Navigator.pop(context, _result)),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton(onPressed: () => _run(_tool!), child: const Text('Try again')),
          TextButton(
            onPressed: () => setState(() => _result = _error = null),
            child: const Text('Other tool'),
          ),
        ],
      ),
    ],
  );
}

class _Box extends StatelessWidget {
  const _Box({required this.label, required this.text, required this.color});

  final String label;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: 0.5)),
      color: color.withValues(alpha: 0.08),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1),
        ),
        const SizedBox(height: 6),
        SelectableText(text),
      ],
    ),
  );
}
