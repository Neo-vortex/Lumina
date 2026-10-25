import 'package:flutter/material.dart';

import '../../../../core/theme/glow_colors.dart';
import '../../../../core/theme/motion.dart';

enum LoginMode { phone, bot }

/// Two-segment toggle with a gliding, glowing selection pill.
class LoginModeToggle extends StatelessWidget {
  const LoginModeToggle({super.key, required this.mode, required this.onChanged});

  final LoginMode mode;
  final ValueChanged<LoginMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: GlowColors.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: GlowColors.outlineStrong),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final half = constraints.maxWidth / 2;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: Motion.standard,
                curve: Motion.move,
                left: mode == LoginMode.phone ? 0 : half,
                width: half,
                top: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: GlowColors.active,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: glow(GlowColors.violet, intensity: 0.5),
                  ),
                ),
              ),
              Row(children: [_segment('Phone', LoginMode.phone), _segment('Bot token', LoginMode.bot)]),
            ],
          );
        },
      ),
    );
  }

  Widget _segment(String label, LoginMode value) {
    final selected = mode == value;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        inMutuallyExclusiveGroup: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => onChanged(value),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : GlowColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
