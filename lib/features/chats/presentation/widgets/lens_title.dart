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

  Widget _hold(Widget child) => onHoldStart == null
      ? child
      : _HoldDetector(
          onStart: onHoldStart!,
          onMove: onHoldMove,
          onEnd: onHoldEnd,
          onCancel: onHoldCancel,
          child: child,
        );
}

/// The long-press driving the folder gesture picker. If it leaves the tree
/// mid-hold (holding switched off, one folder left), the hold is cancelled
/// rather than left hanging with the overlay up.
class _HoldDetector extends StatefulWidget {
  const _HoldDetector({required this.onStart, this.onMove, this.onEnd, this.onCancel, required this.child});

  final GestureLongPressStartCallback onStart;
  final GestureLongPressMoveUpdateCallback? onMove;
  final GestureLongPressEndCallback? onEnd;
  final VoidCallback? onCancel;
  final Widget child;

  @override
  State<_HoldDetector> createState() => _HoldDetectorState();
}

class _HoldDetectorState extends State<_HoldDetector> {
  var _holding = false;

  @override
  void dispose() {
    if (_holding) widget.onCancel?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    gestures: {
      LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
        () => LongPressGestureRecognizer(duration: const Duration(milliseconds: 250)),
        (r) => r
          ..onLongPressStart = (d) {
            _holding = true;
            widget.onStart(d);
          }
          ..onLongPressMoveUpdate = (d) {
            widget.onMove?.call(d);
          }
          ..onLongPressEnd = (d) {
            _holding = false;
            widget.onEnd?.call(d);
          }
          ..onLongPressCancel = () {
            if (!_holding) return;
            _holding = false;
            widget.onCancel?.call();
          },
      ),
    },
    child: widget.child,
  );
}
