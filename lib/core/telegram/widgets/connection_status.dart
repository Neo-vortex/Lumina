import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../theme/glow_colors.dart';
import '../telegram_cache.dart';

/// Title that turns into "Connecting…" / "Waiting for network…" while TDLib
/// is not ready, with a soft pulsing dot (announced to TalkBack).
class ConnectionAwareTitle extends StatefulWidget {
  const ConnectionAwareTitle({super.key, required this.title, this.glow});

  final String title;
  final Color? glow;

  @override
  State<ConnectionAwareTitle> createState() => _ConnectionAwareTitleState();
}

class _ConnectionAwareTitleState extends State<ConnectionAwareTitle> {
  StreamSubscription<CacheEvent>? _sub;
  Timer? _settle;

  /// The spinner rests as a static icon after this long in one state, so a
  /// slow proxy doesn't keep the screen producing frames for minutes.
  bool _settled = false;

  void _restartSettle() {
    _settle?.cancel();
    _settled = false;
    _settle = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _settled = true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sub ??= context
        .read<TelegramCache>()
        .events
        .where((e) => e is ConnectionChanged)
        .listen((_) => setState(_restartSettle));
    if (_settle == null) _restartSettle();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _settle?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<TelegramCache>().connectionState;
    final status = switch (state) {
      td.ConnectionStateReady() => null,
      td.ConnectionStateWaitingForNetwork() => 'Waiting for network…',
      td.ConnectionStateConnectingToProxy() => 'Connecting to proxy…',
      td.ConnectionStateConnecting() => 'Connecting…',
      td.ConnectionStateUpdating() => 'Updating…',
    };
    return Semantics(
      liveRegion: status != null,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: status == null
            ? Text(
                widget.title,
                key: const ValueKey('title'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  shadows: widget.glow == null
                      ? null
                      : [Shadow(color: widget.glow!.withValues(alpha: 0.7), blurRadius: 14)],
                ),
              )
            : Row(
                key: ValueKey(status),
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 14,
                    child: _settled
                        ? const Icon(Icons.cloud_sync_outlined, size: 14, color: GlowColors.amber)
                        : const CircularProgressIndicator(strokeWidth: 2, color: GlowColors.amber),
                  ),
                  const SizedBox(width: 10),
                  Text(status, style: const TextStyle(fontSize: 17, color: GlowColors.amber)),
                ],
              ),
      ),
    );
  }
}
