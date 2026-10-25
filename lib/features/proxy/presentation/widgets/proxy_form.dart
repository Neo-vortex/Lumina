import 'package:flutter/material.dart';

import '../../../../core/theme/glow_colors.dart';
import '../../data/proxy_config.dart';

/// Add / edit a proxy. [tester] checks it before saving.
Future<ProxyConfig?> showProxyForm(
  BuildContext context, {
  ProxyConfig? initial,
  required Future<void> Function(ProxyConfig) tester,
}) {
  return showModalBottomSheet<ProxyConfig>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: GlowColors.surfaceHigh,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _ProxyForm(initial: initial, tester: tester),
    ),
  );
}

class _ProxyForm extends StatefulWidget {
  const _ProxyForm({this.initial, required this.tester});

  final ProxyConfig? initial;
  final Future<void> Function(ProxyConfig) tester;

  @override
  State<_ProxyForm> createState() => _ProxyFormState();
}

class _ProxyFormState extends State<_ProxyForm> {
  late var _kind = widget.initial?.kind ?? ProxyKind.mtproto;
  late final _server = TextEditingController(text: widget.initial?.server);
  late final _port = TextEditingController(text: widget.initial?.port.toString());
  late final _user = TextEditingController(text: widget.initial?.username);
  late final _pass = TextEditingController(text: widget.initial?.password);
  late final _secret = TextEditingController(text: widget.initial?.secret);
  late var _httpOnly = widget.initial?.httpOnly ?? false;
  String? _status;
  var _testing = false;

  @override
  void dispose() {
    for (final c in [_server, _port, _user, _pass, _secret]) {
      c.dispose();
    }
    super.dispose();
  }

  ProxyConfig? _build() {
    final port = int.tryParse(_port.text.trim());
    if (_server.text.trim().isEmpty || port == null || port <= 0 || port > 65535) return null;
    if (_kind == ProxyKind.mtproto && _secret.text.trim().isEmpty) return null;
    return ProxyConfig(
      server: _server.text.trim(),
      port: port,
      kind: _kind,
      username: _user.text.trim(),
      password: _pass.text,
      secret: _secret.text.trim(),
      httpOnly: _httpOnly,
    );
  }

  Future<void> _test() async {
    final c = _build();
    if (c == null) {
      setState(() => _status = 'Fill in server, port${_kind == ProxyKind.mtproto ? ' and secret' : ''}');
      return;
    }
    setState(() {
      _testing = true;
      _status = 'Testing…';
    });
    try {
      await widget.tester(c);
      setState(() => _status = 'Works ✓');
    } catch (e) {
      setState(() => _status = 'Failed: $e');
    } finally {
      setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.initial == null ? 'Add proxy' : 'Edit proxy',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            SegmentedButton<ProxyKind>(
              segments: const [
                ButtonSegment(value: ProxyKind.mtproto, label: Text('MTProto')),
                ButtonSegment(value: ProxyKind.socks5, label: Text('SOCKS5')),
                ButtonSegment(value: ProxyKind.http, label: Text('HTTP')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _server,
              decoration: const InputDecoration(labelText: 'Server'),
              keyboardType: TextInputType.url,
            ),
            TextField(
              controller: _port,
              decoration: const InputDecoration(labelText: 'Port'),
              keyboardType: TextInputType.number,
            ),
            if (_kind == ProxyKind.mtproto)
              TextField(
                controller: _secret,
                decoration: const InputDecoration(labelText: 'Secret'),
              )
            else ...[
              TextField(
                controller: _user,
                decoration: const InputDecoration(labelText: 'Username (optional)'),
              ),
              TextField(
                controller: _pass,
                decoration: const InputDecoration(labelText: 'Password (optional)'),
                obscureText: true,
              ),
              if (_kind == ProxyKind.http)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _httpOnly,
                  onChanged: (v) => setState(() => _httpOnly = v),
                  title: const Text('HTTP only (no TLS CONNECT)'),
                ),
            ],
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(_status!, style: const TextStyle(color: GlowColors.cyan)),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: _testing ? null : _test, child: const Text('Test')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: GlowColors.violetDeep),
                    onPressed: () {
                      final c = _build();
                      if (c == null) {
                        setState(() => _status = 'Check server and port');
                      } else {
                        Navigator.pop(context, c);
                      }
                    },
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
