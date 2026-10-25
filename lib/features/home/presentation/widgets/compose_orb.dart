import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/glow_colors.dart';
import '../../../../core/theme/motion.dart';
import '../../../auth/bloc/auth_bloc.dart';
import '../../../auth/domain/auth_step.dart';

/// One entry of the radial compose menu.
class ComposeAction {
  const ComposeAction({
    required this.icon,
    required this.label,
    required this.onSelected,
    this.botAllowed = false,
    this.visible,
  });

  final IconData icon;
  final String label;
  final void Function(BuildContext context) onSelected;

  /// Shown for bot accounts too.
  final bool botAllowed;

  /// Hides the entry when it returns false (e.g. stories turned off).
  final bool Function(BuildContext context)? visible;
}

/// Compose actions contributed by features, provided by the composition root.
class ComposeActions {
  const ComposeActions(this.actions);
  final List<ComposeAction> actions;
}

/// The central orb. Tapping it blooms into a radial menu of compose actions
/// (spec §9.2) arranged on an arc above the bar.
class ComposeOrb extends StatefulWidget {
  const ComposeOrb({super.key});

  @override
  State<ComposeOrb> createState() => _ComposeOrbState();
}

class _ComposeOrbState extends State<ComposeOrb> {
  Future<void> _open() async {
    HapticFeedback.lightImpact();
    final isBot = switch (context.read<AuthBloc>().state.step) {
      AuthReady(:final capabilities) => capabilities.isBot,
      _ => false,
    };
    List<ComposeAction> actions;
    try {
      actions = context.read<ComposeActions>().actions;
    } on ProviderNotFoundException {
      actions = const [];
    }
    actions = actions.where((a) => (!isBot || a.botAllowed) && (a.visible?.call(context) ?? true)).toList();
    if (actions.isEmpty) return;
    final box = context.findRenderObject() as RenderBox;
    final center = box.localToGlobal(box.size.center(Offset.zero));
    final chosen = await Navigator.of(context).push<ComposeAction>(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierLabel: 'Close compose menu',
        barrierColor: Colors.black54,
        transitionDuration: Motion.standard,
        reverseTransitionDuration: Motion.micro,
        pageBuilder: (context, animation, _) =>
            _RadialMenu(center: center, actions: actions, animation: animation),
      ),
    );
    if (chosen != null && mounted) chosen.onSelected(context);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Compose',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: _open,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const SweepGradient(
              colors: [
                GlowColors.violetDeep,
                GlowColors.magentaDeep,
                GlowColors.coral,
                GlowColors.violetDeep,
              ],
            ),
            boxShadow: [...glow(GlowColors.magenta), ...glow(GlowColors.violet, intensity: 0.4)],
          ),
          child: const Icon(Icons.edit_rounded, color: Colors.white, size: 26),
        ),
      ),
    );
  }
}

class _RadialMenu extends StatelessWidget {
  const _RadialMenu({required this.center, required this.actions, required this.animation});

  final Offset center;
  final List<ComposeAction> actions;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    const radius = 118.0;
    final n = actions.length;
    return Stack(
      children: [
        for (var i = 0; i < n; i++)
          AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              // Spread on an upper arc from 200° to 340°.
              final t = n == 1 ? 0.5 : i / (n - 1);
              final angle = (200 + 140 * t) * math.pi / 180;
              final p = Curves.easeOutBack.transform(animation.value);
              final pos = center + Offset(math.cos(angle), math.sin(angle)) * radius * p;
              return Positioned(
                left: pos.dx - 36,
                top: pos.dy - 36,
                child: Opacity(opacity: animation.value.clamp(0.0, 1.0), child: child),
              );
            },
            child: _Petal(action: actions[i]),
          ),
      ],
    );
  }
}

class _Petal extends StatelessWidget {
  const _Petal({required this.action});

  final ComposeAction action;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: Column(
        children: [
          Semantics(
            button: true,
            label: action.label,
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () => Navigator.pop(context, action),
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: GlowColors.surfaceHigh,
                  border: Border.all(color: GlowColors.violet.withValues(alpha: 0.7)),
                  boxShadow: glow(GlowColors.violet, intensity: 0.5),
                ),
                child: Icon(action.icon, color: GlowColors.text),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            action.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: const TextStyle(fontSize: 11, color: GlowColors.text, shadows: [Shadow(blurRadius: 4)]),
          ),
        ],
      ),
    );
  }
}
