import 'dart:async';

import 'package:flutter/widgets.dart';

/// Rebuilds once a second until [until] passes, telling [builder] how long
/// submission stays blocked (FLOOD_WAIT and resend countdowns).
class FloodGate extends StatefulWidget {
  const FloodGate({super.key, required this.until, required this.builder, this.now = DateTime.now});

  final DateTime? until;
  final Widget Function(BuildContext context, Duration? remaining) builder;
  final DateTime Function() now;

  @override
  State<FloodGate> createState() => _FloodGateState();
}

class _FloodGateState extends State<FloodGate> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(FloodGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.until != widget.until) _schedule();
  }

  void _schedule() {
    _ticker?.cancel();
    if (_remaining() == null) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remaining() == null) _ticker?.cancel();
      setState(() {});
    });
  }

  Duration? _remaining() {
    final until = widget.until;
    if (until == null) return null;
    final left = until.difference(widget.now());
    return left > Duration.zero ? left : null;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _remaining());
}

String formatCountdown(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}
