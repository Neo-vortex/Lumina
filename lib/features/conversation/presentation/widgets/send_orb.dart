import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/glow_colors.dart';
import '../../../../core/theme/motion.dart';

enum OrbMode { mic, send, stop, busy }

/// The send orb (spec §9.2): a circular gradient that fills with light as
/// the message grows, pulses at full charge, shows a mic when empty and
/// morphs into a stop square while recording.
///
/// Gestures: tap = send / start-stop voice recording; long-press = dictation
/// (empty) or send options (with text).
class SendOrb extends StatefulWidget {
  const SendOrb({
    super.key,
    required this.mode,
    required this.charge,
    required this.onTap,
    this.onLongPress,
    this.size = 52,
  });

  final OrbMode mode;

  /// 0..1: how "full" the message is (text length).
  final double charge;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double size;

  @override
  State<SendOrb> createState() => _SendOrbState();
}

class _SendOrbState extends State<SendOrb> with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: Motion.pulse);
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(SendOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final ambient = Motion.ambientEnabled(context);
    final pulsing = ambient && (widget.charge >= 1 || widget.mode == OrbMode.stop);
    if (pulsing && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!pulsing && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
    if (ambient && widget.charge > 0 && !_wave.isAnimating) _wave.repeat();
    if ((!ambient || widget.charge == 0) && _wave.isAnimating) _wave.stop();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (widget.mode) {
      OrbMode.mic => 'Record voice message. Long press to dictate',
      OrbMode.send => 'Send message. Long press for send options',
      OrbMode.stop => 'Stop recording',
      OrbMode.busy => 'Working',
    };
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: widget.mode == OrbMode.busy
            ? null
            : () {
                HapticFeedback.lightImpact();
                widget.onTap();
              },
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                Feedback.forLongPress(context);
                widget.onLongPress!();
              },
        child: SizedBox.square(
          dimension: math.max(widget.size, 48),
          child: AnimatedBuilder(
            animation: Listenable.merge([_pulse, _wave]),
            builder: (context, _) {
              final pulse = _pulse.value;
              return Transform.scale(
                scale: 1 + 0.06 * pulse,
                child: CustomPaint(
                  painter: _OrbPainter(
                    charge: widget.charge.clamp(0.0, 1.0),
                    wave: _wave.value,
                    pulse: pulse,
                    recording: widget.mode == OrbMode.stop,
                  ),
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: Motion.micro,
                      transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                      child: switch (widget.mode) {
                        OrbMode.mic => const Icon(
                          Icons.mic_rounded,
                          key: ValueKey('mic'),
                          color: Colors.white,
                        ),
                        OrbMode.send => const Icon(
                          Icons.arrow_upward_rounded,
                          key: ValueKey('send'),
                          color: Colors.white,
                        ),
                        OrbMode.stop => Container(
                          key: const ValueKey('stop'),
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        OrbMode.busy => const SizedBox.square(
                          key: ValueKey('busy'),
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                        ),
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({required this.charge, required this.wave, required this.pulse, required this.recording});

  final double charge;
  final double wave;
  final double pulse;
  final bool recording;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 2;
    final glowColor = recording ? GlowColors.coral : GlowColors.magenta;

    // Outer glow grows with charge and pulse.
    final glowStrength = recording ? 0.6 + 0.4 * pulse : 0.25 + 0.5 * charge + 0.25 * pulse;
    canvas.drawCircle(
      c,
      r + 2,
      Paint()
        ..color = glowColor.withValues(alpha: 0.18 + 0.15 * glowStrength)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 + 10 * glowStrength),
    );

    final circle = Rect.fromCircle(center: c, radius: r);
    canvas.save();
    canvas.clipPath(Path()..addOval(circle));
    // Base gradient (white icon needs the deep variants for contrast).
    canvas.drawRect(
      circle,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: recording
              ? const [Color(0xFFB8433C), Color(0xFF8E2E5E)]
              : const [GlowColors.violetDeep, GlowColors.magentaDeep],
        ).createShader(circle),
    );
    // Rising light: a wavy luminous fill whose level follows the charge.
    if (charge > 0 && !recording) {
      final level = circle.bottom - circle.height * (0.12 + 0.88 * charge);
      final path = Path()..moveTo(circle.left, circle.bottom);
      for (var x = circle.left; x <= circle.right; x += 2) {
        final y = level + math.sin((x / circle.width) * 2 * math.pi + wave * 2 * math.pi) * 2.5;
        path.lineTo(x, y);
      }
      path
        ..lineTo(circle.right, circle.bottom)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [GlowColors.amber.withValues(alpha: 0.55), GlowColors.magenta.withValues(alpha: 0.25)],
          ).createShader(circle),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.charge != charge || old.wave != wave || old.pulse != pulse || old.recording != recording;
}
