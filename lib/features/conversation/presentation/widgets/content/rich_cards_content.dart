import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../../core/tdlib/td_client.dart';
import '../../../../../core/tdlib/td_errors.dart';
import '../../../../../core/telegram/link_opener.dart';
import '../../../../../core/telegram/widgets/formatted_text_view.dart';
import '../../../../../core/theme/glow_colors.dart';
import '../../../../../core/theme/motion.dart';
import '../../screens/conversation_screen.dart';

void _snack(BuildContext context, String text) =>
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

String _geo(td.Location l, String label) =>
    'geo:${l.latitude},${l.longitude}?q=${l.latitude},${l.longitude}(${Uri.encodeComponent(label)})';

/// Location, live location and venue messages: a place card with "Open in
/// maps"; live ones show time left and, for the sender, "Stop sharing".
class LocationContent extends StatelessWidget {
  const LocationContent({
    super.key,
    required this.message,
    required this.textColor,
    required this.mutedColor,
    required this.footer,
  });

  final td.Message message;
  final Color textColor;
  final Color mutedColor;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final (location, title, subtitle, live, expiresIn) = switch (message.content) {
      td.MessageVenue(:final venue) => (venue.location, venue.title, venue.address, 0, 0),
      td.MessageLocation(:final location) => (
        location,
        'Location',
        '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}',
        0,
        0,
      ),
      td.MessageLiveLocation(
        location: td.LiveLocation(:final location, :final livePeriod),
        :final expiresIn,
      ) =>
        (
          location,
          'Live location',
          '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}',
          livePeriod,
          expiresIn,
        ),
      _ => (const td.Location(latitude: 0, longitude: 0, horizontalAccuracy: 0), 'Location', '', 0, 0),
    };
    final isLive = live > 0 && expiresIn > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => openLink(context, _geo(location, title)),
            child: Container(
              width: 240,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [
                    GlowColors.coral.withValues(alpha: 0.30),
                    GlowColors.violet.withValues(alpha: 0.18),
                  ],
                ),
              ),
              child: Row(
                children: [
                  LivePulse(
                    active: isLive,
                    child: const Icon(Icons.place_rounded, color: Colors.white, size: 30),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
                        ),
                        if (subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: mutedColor, fontSize: 12.5),
                          ),
                        if (live > 0)
                          Text(
                            isLive ? '${_left(expiresIn)} left' : 'Sharing ended',
                            style: TextStyle(color: isLive ? GlowColors.cyan : mutedColor, fontSize: 12.5),
                          ),
                      ],
                    ),
                  ),
                  Icon(Icons.open_in_new_rounded, color: mutedColor, size: 18),
                ],
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLive && message.isOutgoing)
                TextButton.icon(
                  onPressed: () async {
                    try {
                      await context.read<TdClient>().invoke<td.Message>(
                        td.EditMessageLiveLocation(
                          chatId: message.chatId,
                          messageId: message.id,
                          // Null stops sharing.
                          location: null,
                        ),
                      );
                    } on TdException catch (e) {
                      if (context.mounted) _snack(context, e.message);
                    }
                  },
                  icon: const Icon(Icons.stop_circle_outlined, size: 18, color: GlowColors.coral),
                  label: const Text('Stop sharing', style: TextStyle(color: GlowColors.coral)),
                ),
              footer,
            ],
          ),
        ],
      ),
    );
  }

  static String _left(int s) => s >= 3600 ? '${(s / 3600).ceil()} h' : '${(s / 60).ceil()} min';
}

/// The live-location dot: three pulses when sharing starts and after each
/// update, then still (pulsing for the whole sharing period, up to hours,
/// redrew the screen at the display rate). None under reduced motion.
@visibleForTesting
class LivePulse extends StatefulWidget {
  const LivePulse({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<LivePulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pulse();
  }

  @override
  void didUpdateWidget(LivePulse old) {
    super.didUpdateWidget(old);
    _pulse();
  }

  void _pulse() {
    if (!widget.active || !Motion.ambientEnabled(context)) {
      _c.stop();
      _c.value = 0;
      return;
    }
    if (!_c.isAnimating) _c.repeat(count: 3).whenCompleteOrCancel(() => _c.value = 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, child) => Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: GlowColors.coral,
        boxShadow: widget.active
            ? [
                BoxShadow(
                  color: GlowColors.coral.withValues(alpha: 1 - _c.value),
                  blurRadius: 4,
                  spreadRadius: 10 * _c.value,
                ),
              ]
            : null,
      ),
      child: child,
    ),
    child: widget.child,
  );
}

/// A shared contact: name, number, and "Message" when they're on Telegram.
class ContactContent extends StatelessWidget {
  const ContactContent({
    super.key,
    required this.contact,
    required this.textColor,
    required this.mutedColor,
    required this.footer,
  });

  final td.Contact contact;
  final Color textColor;
  final Color mutedColor;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final name = '${contact.firstName} ${contact.lastName}'.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                backgroundColor: GlowColors.cyan.withValues(alpha: 0.25),
                child: Text(name.isEmpty ? '?' : name.characters.first, style: TextStyle(color: textColor)),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? 'Contact' : name,
                    style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
                  ),
                  if (contact.phoneNumber.isNotEmpty)
                    Text(
                      '+${contact.phoneNumber.replaceFirst('+', '')}',
                      style: TextStyle(color: mutedColor),
                    ),
                ],
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (contact.userId != 0)
                TextButton(
                  onPressed: () async {
                    try {
                      final chat = await context.read<TdClient>().invoke<td.Chat>(
                        td.CreatePrivateChat(userId: contact.userId, force: false),
                      );
                      if (context.mounted) {
                        await Navigator.of(context).push(ConversationScreen.route(chat.id));
                      }
                    } on TdException catch (e) {
                      if (context.mounted) _snack(context, e.message);
                    }
                  },
                  child: const Text('Message'),
                )
              else if (contact.phoneNumber.isNotEmpty)
                TextButton(
                  onPressed: () => openLink(context, 'tel:+${contact.phoneNumber.replaceFirst('+', '')}'),
                  child: const Text('Call'),
                ),
              footer,
            ],
          ),
        ],
      ),
    );
  }
}

/// Polls and quizzes: vote (single, or several then "Vote"), results with
/// bars, quiz answer feedback, retract, and "Stop poll" for the author.
class PollContent extends StatefulWidget {
  const PollContent({
    super.key,
    required this.message,
    required this.poll,
    required this.textColor,
    required this.mutedColor,
    required this.footer,
  });

  final td.Message message;
  final td.Poll poll;
  final Color textColor;
  final Color mutedColor;
  final Widget footer;

  @override
  State<PollContent> createState() => _PollContentState();
}

class _PollContentState extends State<PollContent> {
  final _picked = <int>{};
  var _busy = false;

  Future<void> _call(td.TdFunction f) async {
    setState(() => _busy = true);
    try {
      await context.read<TdClient>().invoke<td.Ok>(f);
      _picked.clear();
    } on TdException catch (e) {
      if (mounted) _snack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _vote(List<int> ids) => unawaited(
    _call(td.SetPollAnswer(chatId: widget.message.chatId, messageId: widget.message.id, optionIds: ids)),
  );

  @override
  Widget build(BuildContext context) {
    final p = widget.poll;
    final voted = p.options.any((o) => o.isChosen);
    final showResults = voted || p.isClosed;
    final multiple = p.allowsMultipleAnswers;
    final correct = switch (p.type) {
      td.PollTypeRegular() => const <int>{},
      td.PollTypeQuiz(:final correctOptionIds) => correctOptionIds.toSet(),
    };
    final isQuiz = p.type is td.PollTypeQuiz;
    final explanation = switch (p.type) {
      td.PollTypeQuiz(:final explanation) when showResults && explanation.text.isNotEmpty => explanation,
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: SizedBox(
        width: 280,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            FormattedTextView(
              p.question,
              style: TextStyle(color: widget.textColor, fontWeight: FontWeight.w600, fontSize: 15.5),
            ),
            const SizedBox(height: 2),
            Text(
              [
                if (p.isClosed) 'Final results' else if (isQuiz) 'Quiz' else 'Poll',
                if (p.isAnonymous) 'anonymous',
                if (multiple) 'multiple answers',
              ].join(' · '),
              style: TextStyle(color: widget.mutedColor, fontSize: 12.5),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < p.options.length; i++)
              _OptionRow(
                option: p.options[i],
                showResults: showResults,
                picked: _picked.contains(i),
                multiple: multiple,
                correct: correct.contains(i)
                    ? true
                    : (correct.isNotEmpty && p.options[i].isChosen ? false : null),
                textColor: widget.textColor,
                mutedColor: widget.mutedColor,
                onTap: showResults || _busy
                    ? null
                    : () {
                        if (multiple) {
                          setState(() => _picked.contains(i) ? _picked.remove(i) : _picked.add(i));
                        } else {
                          _vote([i]);
                        }
                      },
              ),
            if (explanation != null)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: GlowColors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: FormattedTextView(
                  explanation,
                  style: TextStyle(color: widget.textColor, fontSize: 13.5),
                ),
              ),
            Row(
              children: [
                Text(
                  p.totalVoterCount == 0
                      ? 'No votes yet'
                      : '${p.totalVoterCount} ${p.totalVoterCount == 1 ? 'vote' : 'votes'}',
                  style: TextStyle(color: widget.mutedColor, fontSize: 12.5),
                ),
                const Spacer(),
                if (multiple && !showResults && _picked.isNotEmpty)
                  TextButton(
                    onPressed: _busy ? null : () => _vote(_picked.toList()..sort()),
                    child: const Text('Vote'),
                  ),
                if (voted && !p.isClosed && !isQuiz)
                  TextButton(onPressed: _busy ? null : () => _vote(const []), child: const Text('Retract')),
                if (widget.message.isOutgoing && !p.isClosed)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () =>
                              _call(td.StopPoll(chatId: widget.message.chatId, messageId: widget.message.id)),
                    child: const Text('Stop'),
                  ),
              ],
            ),
            Align(alignment: Alignment.centerRight, child: widget.footer),
          ],
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.showResults,
    required this.picked,
    required this.multiple,
    required this.correct,
    required this.textColor,
    required this.mutedColor,
    required this.onTap,
  });

  final td.PollOption option;
  final bool showResults;
  final bool picked;
  final bool multiple;

  /// Quiz: true for the right answer, false for the user's wrong pick.
  final bool? correct;
  final Color textColor;
  final Color mutedColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = correct == true
        ? GlowColors.teal
        : (correct == false ? GlowColors.coral : GlowColors.cyan);
    final pct = option.votePercentage / 100;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (showResults)
                  SizedBox(
                    width: 42,
                    child: Text(
                      '${option.votePercentage}%',
                      style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      multiple
                          ? (picked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded)
                          : Icons.radio_button_unchecked_rounded,
                      size: 20,
                      color: mutedColor,
                    ),
                  ),
                Expanded(
                  child: FormattedTextView(option.text, style: TextStyle(color: textColor, fontSize: 14.5)),
                ),
                if (option.isChosen)
                  Icon(
                    correct == false ? Icons.close_rounded : Icons.check_circle_rounded,
                    size: 18,
                    color: accent,
                  ),
                if (correct == true && !option.isChosen) Icon(Icons.check_rounded, size: 18, color: accent),
              ],
            ),
            if (showResults)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 42),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: pct),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => LinearProgressIndicator(
                      value: v,
                      minHeight: 5,
                      color: accent,
                      backgroundColor: mutedColor.withValues(alpha: 0.2),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
