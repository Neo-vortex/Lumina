import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/glow_button.dart';
import '../../../../core/widgets/glow_sheet.dart';
import '../../data/proxy_config.dart';
import '../../data/proxy_repository.dart';

/// A proxy link was tapped (a channel's button, a message, another app):
/// show what it is, check whether it answers, then connect or just save it.
Future<void> confirmProxyLink(BuildContext context, ProxyConfig config) async {
  final repo = context.read<ProxyRepository>();
  final messenger = ScaffoldMessenger.of(context);
  final choice = await showGlowSheet<bool>(
    context,
    title: 'Proxy',
    accent: GlowColors.cyan,
    builder: (context) => _ProxySheet(config: config, repo: repo),
  );
  if (choice == null) return;
  try {
    await repo.add(config, enable: choice);
    messenger.showSnackBar(SnackBar(content: Text(choice ? 'Connected through the proxy' : 'Proxy saved')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
}

class _ProxySheet extends StatefulWidget {
  const _ProxySheet({required this.config, required this.repo});

  final ProxyConfig config;
  final ProxyRepository repo;

  @override
  State<_ProxySheet> createState() => _ProxySheetState();
}

class _ProxySheetState extends State<_ProxySheet> {
  // null: checking; >= 0: online in ms; -1: unreachable.
  int? _ms;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _ms = null);
    final watch = Stopwatch()..start();
    try {
      await widget.repo.test(widget.config);
      if (mounted) setState(() => _ms = watch.elapsedMilliseconds);
    } catch (_) {
      if (mounted) setState(() => _ms = -1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.config;
    final kind = switch (c.kind) {
      ProxyKind.mtproto => 'MTProto',
      ProxyKind.socks5 => 'SOCKS5',
      ProxyKind.http => 'HTTP',
    };
    final (statusColor, status) = switch (_ms) {
      null => (GlowColors.textMuted, 'Checking…'),
      -1 => (GlowColors.coral, 'Unreachable right now'),
      final ms => (GlowColors.teal, 'Online · $ms ms'),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.shield_rounded, color: GlowColors.cyan),
            title: Text('${c.server}:${c.port}'),
            subtitle: Text(kind),
          ),
          Row(
            children: [
              if (_ms == null)
                const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2))
              else
                Icon(Icons.circle, size: 12, color: statusColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(status, style: TextStyle(color: statusColor)),
              ),
              if (_ms != null) TextButton(onPressed: _check, child: const Text('Check again')),
            ],
          ),
          const SizedBox(height: 16),
          GlowButton(label: 'Connect', onPressed: () => Navigator.pop(context, true)),
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Save only')),
        ],
      ),
    );
  }
}
