import 'package:flutter/material.dart';

import '../theme/glow_colors.dart';
import 'glow_button.dart';

/// Lumina's sheet for choices and small inputs (instead of stock dialogs):
/// rounded, lifted from the bottom, with a soft glowing top edge.
Future<T?> showGlowSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  Color accent = GlowColors.violet,
  String? title,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black54,
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    // The glow is a shadow only; the Material underneath is the surface, so
    // list tiles in the sheet have something to paint their splashes on.
    child: Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: 0.25), blurRadius: 32, offset: const Offset(0, -6)),
        ],
      ),
      child: Material(
        color: GlowColors.surfaceHigh,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          side: BorderSide(color: accent.withValues(alpha: 0.6), width: 1.5),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: GlowColors.outlineStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                  child: Semantics(
                    header: true,
                    child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                ),
              Flexible(
                child: SingleChildScrollView(child: Builder(builder: builder)),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);

/// A confirmation as a glowing sheet: sigil, title, message, optional
/// extra content, one clear action. True only when confirmed.
Future<bool> showGlowConfirm(
  BuildContext context, {
  required String title,
  String? message,
  required String confirmLabel,
  IconData icon = Icons.help_outline_rounded,
  Color accent = GlowColors.violet,
  bool destructive = false,
  WidgetBuilder? body,
}) async {
  final color = destructive ? GlowColors.coral : accent;
  final ok = await showGlowSheet<bool>(
    context,
    accent: color,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.15),
              boxShadow: glow(color, intensity: 0.7),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: GlowColors.textMuted),
            ),
          ],
          if (body != null) ...[const SizedBox(height: 12), body(context)],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: destructive
                ? GlowButton.warm(label: confirmLabel, onPressed: () => Navigator.pop(context, true))
                : GlowButton(label: confirmLabel, onPressed: () => Navigator.pop(context, true)),
          ),
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ],
      ),
    ),
  );
  return ok ?? false;
}
