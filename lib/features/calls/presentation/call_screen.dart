import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handy_tdlib_next/api.dart' as td;

import '../../../core/telegram/display.dart';
import '../../../core/telegram/telegram_cache.dart';
import '../../../core/telegram/widgets/chat_avatar.dart';
import '../../../core/theme/glow_colors.dart';
import '../../../core/theme/motion.dart';
import '../../../core/widgets/glow_background.dart';
import '../bloc/call_cubit.dart';

/// The call, full screen: who, how it's going, key emojis, and controls.
/// Back minimizes it (the "return to call" pill brings it back).
class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  /// True while a CallScreen is on screen: CallHost then neither pushes
  /// another nor shows the return pill.
  static final visible = ValueNotifier(false);

  static Route<void> route() => PageRouteBuilder(
    pageBuilder: (_, _, _) => const CallScreen(),
    transitionDuration: Motion.screen,
    transitionsBuilder: (_, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Motion.enter),
      child: child,
    ),
  );

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // After this frame: CallHost rebuilds on it and is above the Navigator.
    WidgetsBinding.instance.addPostFrameCallback((_) => CallScreen.visible.value = true);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && context.read<CallCubit>().state.connectedAt != null) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.addPostFrameCallback((_) => CallScreen.visible.value = false);
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<String?> Function() action) async {
    final error = await action();
    if (error != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CallCubit>();
    return BlocConsumer<CallCubit, CallState>(
      listenWhen: (a, b) => a.phase != b.phase,
      listener: (context, state) {
        // A call that ended without a rating to give closes by itself.
        if (state.phase == CallPhase.ended && !state.needRating) {
          Future<void>.delayed(const Duration(milliseconds: 1600), () {
            if (!mounted || cubit.state.phase != CallPhase.ended) return;
            cubit.dismiss();
            Navigator.of(this.context).maybePop();
          });
        }
        if (state.phase == CallPhase.idle) Navigator.of(context).maybePop();
      },
      builder: (context, state) {
        final cache = context.read<TelegramCache>();
        final userId = state.userId ?? 0;
        final name = Display.userName(cache.users[userId]);
        final chat = cache.chats[userId];
        final live = state.phase == CallPhase.active;
        return Scaffold(
          backgroundColor: GlowColors.backgroundDeep,
          body: GlowBackground(
            child: SafeArea(
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      tooltip: 'Minimize',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
                    ),
                  ),
                  const Spacer(),
                  _Halo(
                    active: live || state.phase == CallPhase.incoming || state.ringing,
                    color: state.phase == CallPhase.incoming ? GlowColors.cyan : GlowColors.violet,
                    child: ChatAvatar(id: userId, title: name, photo: chat?.photo, size: 132),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _status(state),
                      style: TextStyle(color: live ? GlowColors.cyan : GlowColors.textMuted, fontSize: 16),
                    ),
                  ),
                  if (live && state.signalBars != null) ...[
                    const SizedBox(height: 6),
                    _Bars(state.signalBars!),
                  ],
                  if (state.emojis.isNotEmpty && state.phase != CallPhase.ended) ...[
                    const SizedBox(height: 22),
                    _Emojis(emojis: state.emojis, name: name),
                  ],
                  if (state.held) ...[
                    const SizedBox(height: 12),
                    const Text('On hold', style: TextStyle(color: GlowColors.amber)),
                  ],
                  const Spacer(),
                  if (state.phase == CallPhase.ended)
                    _Ended(
                      state: state,
                      onRate: (stars) => cubit.rate(stars),
                      onClose: () {
                        cubit.dismiss();
                        Navigator.of(context).maybePop();
                      },
                    )
                  else if (state.phase == CallPhase.incoming)
                    _IncomingControls(
                      video: state.video,
                      onDecline: cubit.hangUp,
                      onAccept: () => _run(cubit.accept),
                    )
                  else
                    _Controls(
                      muted: state.muted,
                      speaker: state.speaker,
                      onMute: cubit.toggleMute,
                      onSpeaker: cubit.toggleSpeaker,
                      onHangUp: cubit.hangUp,
                    ),
                  const SizedBox(height: 36),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _status(CallState s) {
    final connected = s.connectedAt;
    return switch (s.phase) {
      CallPhase.idle || CallPhase.requesting => 'Calling…',
      CallPhase.outgoing => s.ringing ? 'Ringing…' : 'Calling…',
      CallPhase.incoming => s.video ? 'Incoming video call' : 'Incoming call',
      CallPhase.connecting => 'Connecting…',
      CallPhase.active =>
        connected == null ? 'Connected' : Display.duration(DateTime.now().difference(connected).inSeconds),
      CallPhase.reconnecting => 'Reconnecting…',
      CallPhase.ending => 'Ending…',
      CallPhase.ended => s.error ?? _endText(s.endReason),
    };
  }

  static String _endText(td.CallDiscardReason? r) => switch (r) {
    td.CallDiscardReasonMissed() => 'Missed call',
    td.CallDiscardReasonDeclined() => 'Call declined',
    td.CallDiscardReasonDisconnected() => 'Call disconnected',
    _ => 'Call ended',
  };
}

/// The avatar's glow; it breathes while ringing or talking.
class _Halo extends StatefulWidget {
  const _Halo({required this.active, required this.color, required this.child});
  final bool active;
  final Color color;
  final Widget child;

  @override
  State<_Halo> createState() => _HaloState();
}

class _HaloState extends State<_Halo> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Motion.pulse);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Halo old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.active && Motion.ambientEnabled(context)) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, child) {
      final t = widget.active ? Curves.easeInOut.transform(_c.value) : 0.0;
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.25 + 0.3 * t),
              blurRadius: 30 + 30 * t,
              spreadRadius: 4 + 10 * t,
            ),
          ],
        ),
        child: child,
      );
    },
    child: widget.child,
  );
}

class _Bars extends StatelessWidget {
  const _Bars(this.bars);
  final int bars;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Connection quality $bars of 4',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < 4; i++)
          Container(
            width: 4,
            height: 6.0 + i * 4,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: i < bars ? GlowColors.cyan : GlowColors.outlineStrong,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    ),
  );
}

/// Key verification: both sides see the same four emojis.
class _Emojis extends StatelessWidget {
  const _Emojis({required this.emojis, required this.name});
  final List<String> emojis;
  final String name;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Encryption key emojis ${emojis.join(' ')}. Tap for details',
    excludeSemantics: true,
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: GlowColors.surfaceHigh,
          title: Text(emojis.join(' '), textAlign: TextAlign.center, style: const TextStyle(fontSize: 34)),
          content: Text(
            'If $name sees the same emojis, this call is end-to-end encrypted and nobody is in the middle.',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Text(emojis.join('  '), style: const TextStyle(fontSize: 26)),
      ),
    ),
  );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color = GlowColors.surfaceHigh,
    this.foreground = GlowColors.text,
    this.selected = false,
    this.size = 64,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color color;
  final Color foreground;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Semantics(
        button: true,
        toggled: selected,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: selected ? GlowColors.text : color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox.square(
              dimension: size,
              child: Icon(icon, color: selected ? GlowColors.onAccent : foreground, size: size * 0.42),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      // The button already carries the label for screen readers.
      ExcludeSemantics(
        child: Text(label, style: const TextStyle(color: GlowColors.textMuted, fontSize: 13)),
      ),
    ],
  );
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.muted,
    required this.speaker,
    required this.onMute,
    required this.onSpeaker,
    required this.onHangUp,
  });

  final bool muted;
  final bool speaker;
  final VoidCallback onMute;
  final VoidCallback onSpeaker;
  final VoidCallback onHangUp;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      _RoundButton(
        icon: speaker ? Icons.volume_up_rounded : Icons.volume_down_rounded,
        label: 'Speaker',
        selected: speaker,
        onPressed: onSpeaker,
      ),
      _RoundButton(
        icon: Icons.call_end_rounded,
        label: 'End',
        color: GlowColors.coral,
        foreground: GlowColors.onAccent,
        size: 76,
        onPressed: onHangUp,
      ),
      _RoundButton(
        icon: muted ? Icons.mic_off_rounded : Icons.mic_rounded,
        label: muted ? 'Unmute' : 'Mute',
        selected: muted,
        onPressed: onMute,
      ),
    ],
  );
}

class _IncomingControls extends StatelessWidget {
  const _IncomingControls({required this.video, required this.onDecline, required this.onAccept});
  final bool video;
  final VoidCallback onDecline;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      _RoundButton(
        icon: Icons.call_end_rounded,
        label: 'Decline',
        color: GlowColors.coral,
        foreground: GlowColors.onAccent,
        size: 76,
        onPressed: onDecline,
      ),
      _RoundButton(
        icon: video ? Icons.videocam_rounded : Icons.call_rounded,
        label: 'Answer',
        color: GlowColors.cyan,
        foreground: GlowColors.onAccent,
        size: 76,
        onPressed: onAccept,
      ),
    ],
  );
}

class _Ended extends StatefulWidget {
  const _Ended({required this.state, required this.onRate, required this.onClose});
  final CallState state;
  final void Function(int stars) onRate;
  final VoidCallback onClose;

  @override
  State<_Ended> createState() => _EndedState();
}

class _EndedState extends State<_Ended> {
  var _stars = 0;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (widget.state.needRating) ...[
        const Text('How was the call?'),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                tooltip: '$i ${i == 1 ? 'star' : 'stars'}',
                iconSize: 34,
                onPressed: () {
                  setState(() => _stars = i);
                  widget.onRate(i);
                },
                icon: Icon(
                  i <= _stars ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: GlowColors.amber,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
      ],
      _RoundButton(icon: Icons.close_rounded, label: 'Close', onPressed: widget.onClose),
    ],
  );
}
