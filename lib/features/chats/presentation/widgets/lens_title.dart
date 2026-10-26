import 'package:flutter/material.dart';

import '../../../../core/telegram/widgets/connection_status.dart';
import '../../domain/lens_entry.dart';

/// "Work ▾": the current lens, glowing in its colour. Tap opens the picker.
class LensTitle extends StatelessWidget {
  const LensTitle({super.key, required this.entry, required this.color, this.onTap});

  final LensEntry entry;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final title = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: ConnectionAwareTitle(title: entry.title, glow: onTap == null ? null : color),
        ),
        if (onTap != null) Icon(Icons.expand_more_rounded, color: color),
      ],
    );
    if (onTap == null) return Align(alignment: Alignment.centerLeft, child: title);
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        label: 'Chat folder: ${entry.title}. Double tap to switch',
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4), child: title),
        ),
      ),
    );
  }
}
