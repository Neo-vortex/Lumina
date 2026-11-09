import 'package:flutter/material.dart';

import '../../../../app/app_root.dart';

import 'package:path_provider/path_provider.dart';

import '../../../../core/custom_server/custom_server.dart';
import '../../../../core/theme/glow_colors.dart';

/// "Server: …" under the login form. Telegram by default; a self-hosted,
/// Telegram-compatible server once one is trusted.
class ServerButton extends StatefulWidget {
  const ServerButton({super.key});

  @override
  State<ServerButton> createState() => _ServerButtonState();
}

class _ServerButtonState extends State<ServerButton> {
  CustomServer? _current;

  @override
  void initState() {
    super.initState();
    getApplicationSupportDirectory()
        .then((d) {
          if (mounted) setState(() => _current = CustomServer.load(d.path));
        })
        .catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    return TextButton.icon(
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: GlowColors.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => CustomServerSheet(current: current),
      ),
      icon: Icon(current == null ? Icons.public_rounded : Icons.dns_rounded, size: 18),
      label: Text(current == null ? 'Server: Telegram' : 'Server: ${current.address}'),
      style: TextButton.styleFrom(foregroundColor: current == null ? GlowColors.textMuted : GlowColors.cyan),
    );
  }
}

/// Address + RSA key entry, a live MTProto check, then the trust prompt.
class CustomServerSheet extends StatefulWidget {
  const CustomServerSheet({super.key, this.current});

  final CustomServer? current;

  @override
  State<CustomServerSheet> createState() => _CustomServerSheetState();
}

class _CustomServerSheetState extends State<CustomServerSheet> {
  late final _address = TextEditingController(text: widget.current?.address ?? '');

  /// Optional: where the key is published, if not the well-known path.
  final _keyUrl = TextEditingController();
  var _advanced = false;
  String? _error;
  var _busy = false;

  @override
  void dispose() {
    _address.dispose();
    _keyUrl.dispose();
    super.dispose();
  }

  /// Accepts host:port, [v6]:port, a bare host (port 443) or a URL such as
  /// tcp://host:port.
  static ({String host, int port})? parseAddress(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (s.contains('://')) {
      final u = Uri.tryParse(s);
      if (u == null || u.host.isEmpty) return null;
      return (host: u.host, port: u.hasPort ? u.port : 443);
    }
    s = s.split('/').first;
    if (s.startsWith('[')) {
      final end = s.indexOf(']');
      if (end < 0) return null;
      final host = s.substring(1, end);
      final rest = s.substring(end + 1);
      final port = rest.startsWith(':') ? int.tryParse(rest.substring(1)) : 443;
      return port == null ? null : (host: host, port: port);
    }
    final parts = s.split(':');
    if (parts.length == 1) return (host: s, port: 443);
    if (parts.length == 2) {
      final port = int.tryParse(parts[1]);
      if (port == null || port <= 0 || port > 65535) return null;
      return (host: parts[0], port: port);
    }
    return (host: s, port: 443); // a bare IPv6 address
  }

  Future<void> _check() async {
    final addr = parseAddress(_address.text);
    if (addr == null) return setState(() => _error = 'Enter an address like 203.0.113.5:443');
    Uri? keyUrl;
    if (_keyUrl.text.trim().isNotEmpty) {
      final u = Uri.tryParse(_keyUrl.text.trim());
      if (u == null || !u.hasScheme || u.host.isEmpty)
        return setState(() => _error = 'Key URL: enter a full https:// URL');
      keyUrl = u;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    // Both at once: the key over HTTPS, and which keys the MTProto port offers.
    final fetch =
        (keyUrl != null
                ? fetchServerKeyWithFallback(keyUrl)
                : fetchServerKeyFrom(keyUrlCandidates(addr.host, addr.port)))
            .then<Object>((k) => k, onError: (Object e) => e);
    final probe = CustomServer.probe(addr.host, addr.port).then<Object>((f) => f, onError: (Object e) => e);
    final fetched = await fetch;
    final offered = await probe;
    if (!mounted) return;
    setState(() => _busy = false);
    if (fetched is! FetchedKey) {
      return setState(() => _error = fetched is ProbeError ? fetched.message : '$fetched');
    }
    final server = CustomServer(host: addr.host, port: addr.port, rsaPem: fetched.pem);
    final trust = await showDialog<bool>(
      context: context,
      builder: (_) => _TrustDialog(
        server: server,
        fetched: fetched,
        offered: offered is List<int> ? offered : null,
        failure: offered is List<int> ? null : (offered is ProbeError ? offered.message : '$offered'),
      ),
    );
    if (trust != true || !mounted) return;
    await _apply(server);
  }

  Future<void> _apply(CustomServer? server) async {
    final dir = await getApplicationSupportDirectory();
    await CustomServer.save(dir.path, server);
    if (!mounted) return;
    // TDLib starts again on the new server / restored session; no app restart.
    Navigator.of(context).pop();
    await AppRoot.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: GlowColors.outline, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Custom server', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
              'A self-hosted, Telegram-compatible (MTProto) server. Lumina fetches its key, shows you the '
              'fingerprints and asks you to trust them. The server gets its own account and data; Telegram '
              'stays as it was.',
              style: TextStyle(color: GlowColors.textMuted),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _address,
              enabled: !_busy,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Address',
                hintText: '203.0.113.5:443 or tcp://chat.example.org:443',
                prefixIcon: Icon(Icons.dns_rounded),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _advanced = !_advanced),
                icon: Icon(_advanced ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18),
                label: const Text('Advanced'),
                style: TextButton.styleFrom(foregroundColor: GlowColors.textMuted),
              ),
            ),
            if (_advanced)
              TextField(
                controller: _keyUrl,
                enabled: !_busy,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Key URL (optional)',
                  hintText: 'https://host/.well-known/mtproto-key.pem',
                  prefixIcon: Icon(Icons.key_rounded),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: GlowColors.error)),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: GlowColors.violetDeep,
                foregroundColor: GlowColors.text,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _busy ? null : _check,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: GlowColors.cyan),
                    )
                  : const Icon(Icons.verified_user_rounded),
              label: Text(_busy ? 'Checking…' : 'Check server'),
            ),
            if (widget.current != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: _busy ? null : () => _apply(null), child: const Text('Back to Telegram')),
            ],
          ],
        ),
      ),
    );
  }
}

/// What the server presented, and whether its MTProto port offers the key
/// it published.
class _TrustDialog extends StatelessWidget {
  const _TrustDialog({
    required this.server,
    required this.fetched,
    required this.offered,
    required this.failure,
  });

  final CustomServer server;
  final FetchedKey fetched;
  final List<int>? offered;
  final String? failure;

  @override
  Widget build(BuildContext context) {
    final key = fetched.key;
    final offered = this.offered;
    final matches = offered != null && offered.contains(key.fingerprint);
    final (icon, color, verdict) = failure != null
        ? (Icons.cloud_off_rounded, GlowColors.amber, 'Could not reach the MTProto port: $failure')
        : matches
        ? (Icons.verified_rounded, GlowColors.cyan, 'The MTProto server offers the published key.')
        : (
            Icons.gpp_bad_rounded,
            GlowColors.error,
            'The MTProto server does NOT offer this key. Login will fail.',
          );
    final cert = fetched.certificate;
    final df = MaterialLocalizations.of(context);
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: GlowColors.textMuted, fontSize: 12)),
          const SizedBox(height: 2),
          SelectableText(value, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
        ],
      ),
    );
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w700, color: GlowColors.text),
      ),
    );
    return AlertDialog(
      backgroundColor: GlowColors.surface,
      title: const Text('Trust this server?'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Icon(icon, color: color),
                  const SizedBox(width: 10),
                  Expanded(child: Text(verdict)),
                ],
              ),
            ),
            row('Address', server.address),
            heading('Server key (MTProto)'),
            row('Fingerprint', key.fingerprintHex),
            row('SHA-256', key.sha256Hex),
            row('Type', 'RSA ${key.bits}-bit'),
            if (offered != null)
              row(
                'Fingerprints the server offers',
                offered.isEmpty ? '(none)' : offered.map(RsaPublicKey.fingerprintToHex).join('\n'),
              ),
            heading(fetched.url.scheme == 'https' ? 'HTTPS certificate' : 'Key download'),
            row('Fetched from', '${fetched.url}'),
            if (fetched.url.scheme != 'https')
              row('Certificate', 'None: fetched over plain HTTP (HTTPS failed). Check the key fingerprint.'),
            if (cert != null) ...[
              row(
                'Trust',
                fetched.caTrusted
                    ? 'Verified by a certificate authority'
                    : cert.selfSigned
                    ? 'Self-signed (not verified by any authority)'
                    : 'Not verified (unknown authority, expired or wrong host)',
              ),
              row('Subject', cert.subject),
              row('Issuer', cert.issuer),
              row('Valid', '${df.formatShortDate(cert.validFrom)} – ${df.formatShortDate(cert.validTo)}'),
              row('SHA-256', cert.fingerprint),
            ],
            const Text(
              'Compare the fingerprints with the ones your server administrator gave you. Everything you send '
              'goes to this server.',
              style: TextStyle(color: GlowColors.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: matches ? GlowColors.violetDeep : GlowColors.error),
          onPressed: failure == null && !matches ? null : () => Navigator.pop(context, true),
          child: Text(matches ? 'Trust and connect' : 'Trust anyway'),
        ),
      ],
    );
  }
}
