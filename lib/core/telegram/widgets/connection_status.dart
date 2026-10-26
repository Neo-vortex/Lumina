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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sub ??= context
        .read<TelegramCache>()
        .events
        .where((e) => e is ConnectionChanged)
        .listen((_) => setState(() {}));
  }

  @override
  void dispose() {
    _sub?.cancel();
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
                  const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: GlowColors.amber),
                  ),
                  const SizedBox(width: 10),
                  Text(status, style: const TextStyle(fontSize: 17, color: GlowColors.amber)),
                ],
              ),
      ),
    );
  }
}
