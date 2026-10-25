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

/// The orb's menu: glowing pills rising from the orb, one per action
/// (a fan of round buttons got crowded beyond four actions, and its labels
/// collided). Staggered rise; reduced motion shows them at once.
class _RadialMenu extends StatelessWidget {
  const _RadialMenu({required this.center, required this.actions, required this.animation});

  final Offset center;
  final List<ComposeAction> actions;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final ambient = Motion.ambientEnabled(context);
    final n = actions.length;
    // Material ancestor: real text styles (not the debug fallback) and ink.
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            // Just above the orb (64 dp tall, centred on [center]).
            bottom: size.height - center.dy + 44,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < n; i++)
                  AnimatedBuilder(
                    animation: animation,
                    builder: (context, child) {
                      // The pill nearest the orb (last) appears first.
                      final order = n - 1 - i;
                      final start = ambient ? (order * 0.08).clamp(0.0, 0.5) : 0.0;
                      final t = ambient
                          ? Curves.easeOutCubic.transform(
                              ((animation.value - start) / (1 - start)).clamp(0.0, 1.0),
                            )
                          : animation.value;
                      return Opacity(
                        opacity: t,
                        child: Transform.translate(offset: Offset(0, (1 - t) * 24), child: child),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _Petal(action: actions[i], hue: i / math.max(1, n - 1)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Petal extends StatelessWidget {
  const _Petal({required this.action, required this.hue});

  final ComposeAction action;

  /// 0…1 down the column: shifts the icon's glow from violet to magenta.
  final double hue;

  @override
  Widget build(BuildContext context) {
    final accent = Color.lerp(GlowColors.violet, GlowColors.magenta, hue)!;
    return Semantics(
      button: true,
      label: action.label,
      excludeSemantics: true,
      child: Material(
        color: GlowColors.surfaceHigh,
        shape: StadiumBorder(side: BorderSide(color: accent.withValues(alpha: 0.55))),
        elevation: 0,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => Navigator.pop(context, action),
          child: Container(
            constraints: const BoxConstraints(minWidth: 200, minHeight: 52),
            padding: const EdgeInsets.fromLTRB(8, 6, 22, 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              boxShadow: glow(accent, intensity: 0.35),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // White only on the deep tones (contrast rule).
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.lerp(GlowColors.violetDeep, GlowColors.magentaDeep, hue)!,
                        Color.lerp(GlowColors.violetDeep, GlowColors.magentaDeep, 1 - hue)!,
                      ],
                    ),
                  ),
                  child: Icon(action.icon, color: Colors.white, size: 21),
                ),
                const SizedBox(width: 14),
                Text(
                  action.label,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: GlowColors.text),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
