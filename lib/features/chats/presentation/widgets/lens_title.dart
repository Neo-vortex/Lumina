import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../core/telegram/widgets/connection_status.dart';
import '../../domain/lens_entry.dart';
import 'chat_list_extensions.dart';

/// "Work ▾": the current lens, glowing in its colour. Tap opens the picker.
class LensTitle extends StatelessWidget {
  const LensTitle({
    super.key,
    required this.entry,
    required this.color,
    this.onTap,
    this.onHoldStart,
    this.onHoldMove,
    this.onHoldEnd,
    this.onHoldCancel,
  });

  final LensEntry entry;
  final Color color;
  final VoidCallback? onTap;

  /// Hold and slide (the folder gesture picker); null keeps it tap-only.
  final GestureLongPressStartCallback? onHoldStart;
  final GestureLongPressMoveUpdateCallback? onHoldMove;
  final GestureLongPressEndCallback? onHoldEnd;
  final VoidCallback? onHoldCancel;

  @override
  Widget build(BuildContext context) {
    final title = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: ConnectionAwareTitle(
            title: entry.title,
            glow: onTap == null ? null : color,
            onStatusTap: () => ChatListExtensions.of(context).openConnectionSettings(context),
          ),
        ),
        if (onTap != null) Icon(Icons.expand_more_rounded, color: color),
      ],
    );
    if (onTap == null) return Align(alignment: Alignment.centerLeft, child: title);
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        label: onHoldStart == null
            ? 'Chat folder: ${entry.title}. Double tap to switch'
            : 'Chat folder: ${entry.title}. Double tap to switch, or hold and slide',
        excludeSemantics: true,
        child: _hold(
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4), child: title),
          ),
        ),
      ),
    );
  }

  Widget _hold(Widget child) {
    if (onHoldStart == null) return child;
    return RawGestureDetector(
      gestures: {
        LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
          () => LongPressGestureRecognizer(duration: const Duration(milliseconds: 250)),
          (r) => r
            ..onLongPressStart = onHoldStart
            ..onLongPressMoveUpdate = onHoldMove
            ..onLongPressEnd = onHoldEnd
            ..onLongPressCancel = onHoldCancel,
        ),
      },
      child: child,
    );
  }
}
