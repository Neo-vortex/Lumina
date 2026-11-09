import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../theme/glow_colors.dart';
import '../telegram_cache.dart';

/// The chat list title (the folder name, always shown) with a glowing
/// status capsule beside it while TDLib isn't ready: a dot and one word in
/// the state's colour. The dot pulses for a few seconds, then rests, so a
/// slow proxy doesn't keep the screen drawing. Tapping the capsule runs
/// [onStatusTap] (connection and proxy settings). Announced to TalkBack.
class ConnectionAwareTitle extends StatefulWidget {
  const ConnectionAwareTitle({super.key, required this.title, this.glow, this.gradient, this.onStatusTap});

  final String title;
  final Color? glow;

  /// Paints the title in this gradient (left to right).
  final List<Color>? gradient;
  final VoidCallback? onStatusTap;

  @override
  State<ConnectionAwareTitle> createState() => _ConnectionAwareTitleState();
}

class _ConnectionAwareTitleState extends State<ConnectionAwareTitle> with SingleTickerProviderStateMixin {
  StreamSubscription<CacheEvent>? _sub;
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  void _restartPulse() {
    _pulse
      ..stop()
      ..value = 0;
    // Three breaths (~3 s), then the dot holds still.
    _pulse.repeat(reverse: true, count: 3).whenCompleteOrCancel(() {
      if (mounted) _pulse.value = 1;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sub == null) {
      _sub = context
          .read<TelegramCache>()
          .events
          .where((e) => e is ConnectionChanged)
          .listen((_) => setState(_restartPulse));
      _restartPulse();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  Widget _title() {
    const base = TextStyle(fontSize: 22, fontWeight: FontWeight.w600);
    final glow = widget.glow;
    final gradient = widget.gradient;
    final shadows = glow == null ? null : [Shadow(color: glow.withValues(alpha: 0.7), blurRadius: 14)];
    if (gradient == null || gradient.length < 2) {
      return Text(
        widget.title,
        overflow: TextOverflow.ellipsis,
        style: base.copyWith(shadows: shadows),
      );
    }
    // The glow under, the gradient-filled letters over it.
    return Stack(
      children: [
        if (shadows != null)
          Text(
            widget.title,
            overflow: TextOverflow.ellipsis,
            style: base.copyWith(color: Colors.transparent, shadows: shadows),
          ),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(colors: gradient).createShader(bounds),
          child: Text(
            widget.title,
            overflow: TextOverflow.ellipsis,
            style: base.copyWith(color: Colors.white),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<TelegramCache>().connectionState;
    final status = switch (state) {
      td.ConnectionStateReady() => null,
      td.ConnectionStateWaitingForNetwork() => ('No network', GlowColors.coral, 'Waiting for network'),
      td.ConnectionStateConnectingToProxy() => ('Proxy…', GlowColors.violet, 'Connecting to proxy'),
      td.ConnectionStateConnecting() => ('Connecting', GlowColors.amber, 'Connecting'),
      td.ConnectionStateUpdating() => ('Updating', GlowColors.cyan, 'Updating'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: _title()),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          child: status == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Semantics(
                    liveRegion: true,
                    button: widget.onStatusTap != null,
                    label: '${status.$3}. Double tap for connection settings',
                    excludeSemantics: true,
                    child: GestureDetector(
                      onTap: widget.onStatusTap,
                      child: _Capsule(label: status.$1, color: status.$2, pulse: _pulse),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _Capsule extends StatelessWidget {
  const _Capsule({required this.label, required this.color, required this.pulse});

  final String label;
  final Color color;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: 0.5)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: pulse,
          builder: (context, _) => Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.35 + 0.5 * pulse.value),
                  blurRadius: 4 + 6 * pulse.value,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}
