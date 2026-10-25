import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/theme/glow_colors.dart';
import '../../../../core/theme/motion.dart';

/// Floating, frosted bottom bar: Chats · [center] · Settings.
class GlowNavBar extends StatelessWidget {
  const GlowNavBar({super.key, required this.index, required this.onSelect, required this.center});

  final int index;
  final ValueChanged<int> onSelect;
  final Widget center;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: SizedBox(
          height: 76,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    height: 64,
                    decoration: BoxDecoration(
                      color: GlowColors.surface.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: GlowColors.outline),
                    ),
                    child: Row(
                      children: [
                        _Tab(
                          icon: Icons.forum_rounded,
                          label: 'Chats',
                          selected: index == 0,
                          onTap: () => onSelect(0),
                        ),
                        const SizedBox(width: 84),
                        _Tab(
                          icon: Icons.tune_rounded,
                          label: 'Settings',
                          selected: index == 1,
                          onTap: () => onSelect(1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(top: -14, child: center),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? GlowColors.cyan : GlowColors.textMuted;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(32),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: Motion.standard,
                curve: Motion.move,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: selected ? glow(GlowColors.cyan, intensity: 0.4) : null,
                ),
                child: Icon(icon, color: color),
              ),
              Text(label, style: TextStyle(fontSize: 11, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
