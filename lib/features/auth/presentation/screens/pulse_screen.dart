import 'package:flutter/material.dart';

import '../../../../core/theme/glow_colors.dart';
import '../../../../core/theme/motion.dart';
import '../../../../core/widgets/glow_background.dart';
import '../../../../core/widgets/glow_sigil.dart';

/// Booting, closing, or restarting the client: a slowly pulsing sigil.
class PulseScreen extends StatefulWidget {
  const PulseScreen({super.key, required this.caption});

  final String caption;

  @override
  State<PulseScreen> createState() => _PulseScreenState();
}

class _PulseScreenState extends State<PulseScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: Motion.pulse);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.ambientEnabled(context)) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.value = 0.5;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlowBackground(
        drift: true,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: Tween(
                  begin: 0.95,
                  end: 1.04,
                ).animate(CurvedAnimation(parent: _pulse, curve: Motion.move)),
                child: const GlowSigil(size: 88),
              ),
              const SizedBox(height: 28),
              Semantics(
                liveRegion: true,
                child: Text(widget.caption, style: const TextStyle(color: GlowColors.textMuted)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
