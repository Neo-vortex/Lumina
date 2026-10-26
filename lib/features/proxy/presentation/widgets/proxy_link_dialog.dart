import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/glow_sheet.dart';
import '../../data/proxy_config.dart';
import '../../data/proxy_repository.dart';

/// A proxy link was tapped or opened from another app: ask, then add and
/// switch to it.
Future<void> confirmProxyLink(BuildContext context, ProxyConfig config) async {
  final kind = switch (config.kind) {
    ProxyKind.mtproto => 'MTProto',
    ProxyKind.socks5 => 'SOCKS5',
    ProxyKind.http => 'HTTP',
  };
  final ok = await showGlowConfirm(
    context,
    title: 'Connect through this proxy?',
    message: '$kind proxy ${config.server}:${config.port}',
    confirmLabel: 'Connect',
    icon: Icons.shield_rounded,
    accent: GlowColors.cyan,
  );
  if (!ok || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final added = await context.read<ProxyRepository>().addAll([config]);
    messenger.showSnackBar(
      SnackBar(content: Text(added == 0 ? 'That proxy is already saved' : 'Proxy added')),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
}
