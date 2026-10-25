import 'package:flutter/material.dart';

import '../theme/glow_colors.dart';
import '../theme/motion.dart';

/// Gradient pill button that breathes softly while it can be pressed.
class GlowButton extends StatefulWidget {
  const GlowButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.gradient = GlowColors.active,
    this.glowColor = GlowColors.magenta,
    this.foreground = Colors.white,
  });

  /// Warm action (log out, reset): amber → coral with dark text (UX-01).
  const GlowButton.warm({super.key, required this.label, required this.onPressed, this.busy = false})
    : gradient = GlowColors.outgoing,
      glowColor = GlowColors.coral,
      foreground = GlowColors.onAccent;

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final Gradient gradient;
  final Color glowColor;
  final Color foreground;

  @override
  State<GlowButton> createState() => _GlowButtonState();
}

class _GlowButtonState extends State<GlowButton> with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(vsync: this, duration: Motion.breath);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.ambientEnabled(context)) {
      if (!_breath.isAnimating) _breath.repeat(reverse: true);
    } else {
      _breath.value = 0.5;
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.busy ? '${widget.label}, in progress' : widget.label,
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _breath,
        builder: (context, child) {
          final intensity = enabled ? 0.3 + 0.5 * _breath.value : 0.0;
          return AnimatedOpacity(
            duration: Motion.micro,
            opacity: enabled || widget.busy ? 1 : 0.45,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: widget.gradient,
                borderRadius: BorderRadius.circular(28),
                boxShadow: enabled ? glow(widget.glowColor, intensity: intensity) : const [],
              ),
              child: child,
            ),
          );
        },
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: enabled ? widget.onPressed : null,
            child: SizedBox(
              height: 56,
              child: Center(
                child: widget.busy
                    ? SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: widget.foreground),
                      )
                    : Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: widget.foreground,
                          letterSpacing: 0.3,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
