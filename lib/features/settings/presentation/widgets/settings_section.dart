import 'package:flutter/material.dart';

import '../../../../core/theme/glow_colors.dart';

class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Semantics(
              header: true,
              child: Text(
                title.toUpperCase(),
                style: const TextStyle(
                  color: GlowColors.violet,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: GlowColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: GlowColors.outline),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}
