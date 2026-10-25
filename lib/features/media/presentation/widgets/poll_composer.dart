import 'package:flutter/material.dart';
import 'package:handy_tdlib_next/api.dart' as td;

import '../../../../core/theme/glow_colors.dart';

/// Builds a poll: question, 2–10 options, anonymous / multiple answers /
/// quiz (with the correct answer and an explanation).
Future<td.InputMessageContent?> composePoll(BuildContext context) => Navigator.of(context).push(
  MaterialPageRoute<td.InputMessageContent>(fullscreenDialog: true, builder: (_) => const _PollComposer()),
);

class _PollComposer extends StatefulWidget {
  const _PollComposer();

  @override
  State<_PollComposer> createState() => _PollComposerState();
}

class _PollComposerState extends State<_PollComposer> {
  static const _maxOptions = 10;
  final _question = TextEditingController();
  final _explanation = TextEditingController();
  final _options = [TextEditingController(), TextEditingController()];
  var _anonymous = true;
  var _multiple = false;
  var _quiz = false;
  int? _correct;

  @override
  void dispose() {
    _question.dispose();
    _explanation.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> get _filled => [
    for (final c in _options)
      if (c.text.trim().isNotEmpty) c.text.trim(),
  ];

  bool get _valid =>
      _question.text.trim().isNotEmpty &&
      _filled.length >= 2 &&
      (!_quiz || (_correct != null && _correct! < _filled.length));

  void _onOptionChanged(int i) {
    // Keep one empty row at the end, like Telegram.
    if (i == _options.length - 1 && _options[i].text.isNotEmpty && _options.length < _maxOptions) {
      _options.add(TextEditingController());
    }
    setState(() {});
  }

  td.FormattedText _f(String s) => td.FormattedText(text: s, entities: const []);

  void _create() {
    final options = _filled;
    Navigator.pop(
      context,
      td.InputMessagePoll(
        question: _f(_question.text.trim()),
        options: [for (final o in options) _f(o)],
        isAnonymous: _anonymous,
        type: _quiz
            ? td.PollTypeQuiz(correctOptionId: _correct!, explanation: _f(_explanation.text.trim()))
            : td.PollTypeRegular(allowMultipleAnswers: _multiple),
        openPeriod: 0,
        closeDate: 0,
        isClosed: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_quiz ? 'New quiz' : 'New poll'),
      actions: [TextButton(onPressed: _valid ? _create : null, child: const Text('Create'))],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _question,
          autofocus: true,
          maxLength: 300,
          minLines: 1,
          maxLines: 3,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Question'),
        ),
        const SizedBox(height: 8),
        Text(
          _quiz ? 'OPTIONS · tap the correct answer' : 'OPTIONS',
          style: const TextStyle(
            color: GlowColors.violet,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
        RadioGroup<int>(
          groupValue: _correct,
          onChanged: (v) => setState(() => _correct = v),
          child: Column(
            children: [
              for (var i = 0; i < _options.length; i++)
                Row(
                  children: [
                    if (_quiz) Radio<int>(value: i, enabled: _options[i].text.trim().isNotEmpty),
                    Expanded(
                      child: TextField(
                        controller: _options[i],
                        maxLength: 100,
                        onChanged: (_) => _onOptionChanged(i),
                        decoration: InputDecoration(hintText: 'Option ${i + 1}', counterText: ''),
                      ),
                    ),
                    if (_options.length > 2)
                      IconButton(
                        tooltip: 'Remove option',
                        onPressed: () => setState(() {
                          _options.removeAt(i).dispose();
                          if (_correct == i) _correct = null;
                        }),
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _anonymous,
          onChanged: (v) => setState(() => _anonymous = v),
          title: const Text('Anonymous voting'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _multiple,
          onChanged: _quiz ? null : (v) => setState(() => _multiple = v),
          title: const Text('Multiple answers'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _quiz,
          onChanged: (v) => setState(() {
            _quiz = v;
            if (v) _multiple = false;
          }),
          title: const Text('Quiz mode'),
          subtitle: const Text('One correct answer'),
        ),
        if (_quiz)
          TextField(
            controller: _explanation,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'Explanation (optional)'),
          ),
      ],
    ),
  );
}
