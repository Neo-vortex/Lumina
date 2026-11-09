import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/accounts/account_switcher.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/lumina_glass.dart' show GlassMode, glassModeOf;
import '../../../../core/theme/motion.dart';

/// Floating, frosted bottom bar: Chats · Contacts · [center] · Settings.
class GlowNavBar extends StatelessWidget {
  const GlowNavBar({
    super.key,
    required this.index,
    required this.onSelect,
    required this.center,
    this.chatsBadge = 0,
  });

  final int index;

  /// Unread messages in the folder the chat list shows (0 hides it).
  final int chatsBadge;
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
                // Glass off: a solid bar, no blur pass while lists scroll under it.
                child: BackdropFilter(
                  enabled: glassModeOf(context) != GlassMode.off,
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    height: 64,
                    decoration: BoxDecoration(
                      color: GlowColors.surface.withValues(
                        alpha: glassModeOf(context) == GlassMode.off ? 0.97 : 0.78,
                      ),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: GlowColors.outline),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              _Tab(
                                icon: Icons.forum_rounded,
                                label: 'Chats',
                                selected: index == 0,
                                onTap: () => onSelect(0),
                                badge: chatsBadge,
                                onLongPress: () => showAccountSwitcher(context),
                              ),
                              _Tab(
                                icon: Icons.people_alt_rounded,
                                label: 'Contacts',
                                selected: index == 1,
                                onTap: () => onSelect(1),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 84),
                        Expanded(
                          child: Row(
                            children: [
                              _Tab(
                                icon: Icons.tune_rounded,
                                label: 'Settings',
                                selected: index == 2,
                                onTap: () => onSelect(2),
                                // Hold to switch accounts, like Telegram.
                                onLongPress: () => showAccountSwitcher(context),
                              ),
                            ],
                          ),
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
  const _Tab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.badge = 0,
  });

  final int badge;

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

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
          onLongPress: onLongPress,
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
                child: badge <= 0
                    ? Icon(icon, color: color)
                    : Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(icon, color: color),
                          Positioned(top: -7, left: 14, child: _Badge(count: badge)),
                        ],
                      ),
              ),
              Text(label, style: TextStyle(fontSize: 11, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Unread count over a tab icon.
class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final text = count > 999 ? '999+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: GlowColors.violet,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: GlowColors.surface, width: 1.5),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, height: 1, fontWeight: FontWeight.w700, color: GlowColors.onAccent),
      ),
    );
  }
}
