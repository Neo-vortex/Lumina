import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/glow_background.dart';
import '../../data/proxy_config.dart';
import '../../data/proxy_repository.dart';
import '../widgets/proxy_form.dart';
import 'proxy_scan_screen.dart';

/// Proxy list (spec §5): toggles, active indicator, add/edit, test, share.
class ProxyScreen extends StatefulWidget {
  const ProxyScreen({super.key});

  static Route<void> route() => MaterialPageRoute(builder: (_) => const ProxyScreen());

  @override
  State<ProxyScreen> createState() => _ProxyScreenState();
}

class _ProxyScreenState extends State<ProxyScreen> {
  late final ProxyRepository _repo = context.read<ProxyRepository>();
  List<SavedProxy> _proxies = const [];
  final _ping = <int, String>{};
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final list = await _repo.list();
      if (mounted) setState(() => _proxies = list);
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      _snack('$e');
    }
    await _refresh();
  }

  Future<void> _test(SavedProxy p) async {
    setState(() => _ping[p.id] = 'Testing…');
    try {
      final rtt = await _repo.ping(p.id);
      setState(() => _ping[p.id] = '${rtt.inMilliseconds} ms');
    } catch (e) {
      setState(() => _ping[p.id] = 'Unavailable');
    }
  }

  Future<void> _edit([SavedProxy? existing]) async {
    final config = await showProxyForm(context, initial: existing?.config, tester: _repo.test);
    if (config == null) return;
    await _run(() async {
      if (existing == null) {
        await _repo.add(config);
      } else {
        await _repo.edit(existing.id, config.copyWith(enabled: existing.config.enabled));
      }
    });
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final found = ProxyConfig.parseLinks(data?.text ?? '');
    if (found.isEmpty) {
      _snack('No proxy link in the clipboard');
      return;
    }
    await _import(found);
  }

  Future<void> _scan() async {
    final found = await ProxyScanScreen.scan(context);
    if (found != null && mounted) await _import(found);
  }

  Future<void> _import(List<ProxyConfig> found) => _run(() async {
    final added = await _repo.addAll(found);
    _snack(switch (added) {
      0 => found.length == 1 ? 'That proxy is already saved' : 'Those proxies are already saved',
      1 => 'Proxy added',
      _ => 'Added $added proxies. Tap one to use it',
    });
  });

  @override
  Widget build(BuildContext context) {
    final active = _proxies.where((p) => p.config.enabled).firstOrNull;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: GlowColors.background,
        title: const Text('Proxy'),
        actions: [
          IconButton(
            tooltip: 'Scan QR code',
            icon: const Icon(Icons.qr_code_scanner_rounded),
            onPressed: _scan,
          ),
          IconButton(
            tooltip: 'Paste proxy links',
            icon: const Icon(Icons.content_paste_rounded),
            onPressed: _paste,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: GlowColors.violetDeep,
        onPressed: _edit,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add proxy'),
      ),
      body: GlowBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
                  SwitchListTile(
                    value: active != null,
                    onChanged: _proxies.isEmpty
                        ? null
                        : (on) => _run(() => on ? _repo.enable((_proxies.first).id) : _repo.disableAll()),
                    title: const Text('Use proxy'),
                    subtitle: Text(
                      active == null ? 'Direct connection' : 'Connected through ${active.config.server}',
                    ),
                  ),
                  if (_proxies.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Add a SOCKS5, HTTP or MTProto proxy, scan a proxy QR code, or copy t.me/proxy links '
                        'and tap paste.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: GlowColors.textMuted),
                      ),
                    ),
                  for (final p in _proxies)
                    Card(
                      color: GlowColors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(color: p.config.enabled ? GlowColors.cyan : GlowColors.outline),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: p.config.enabled ? GlowColors.cyan : GlowColors.outlineStrong,
                            boxShadow: p.config.enabled ? glow(GlowColors.cyan) : null,
                          ),
                        ),
                        title: Text('${p.config.server}:${p.config.port}'),
                        subtitle: Text(
                          [
                            p.config.kind.name.toUpperCase(),
                            if (p.config.enabled) 'active',
                            ?_ping[p.id],
                          ].join(' · '),
                        ),
                        onTap: () => p.config.enabled ? null : _run(() => _repo.enable(p.id)),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) async {
                            switch (v) {
                              case 'test':
                                await _test(p);
                              case 'edit':
                                await _edit(p);
                              case 'share':
                                final link = await _repo.shareLink(p.id);
                                if (link != null) {
                                  await Clipboard.setData(ClipboardData(text: link));
                                  _snack('Link copied');
                                }
                              case 'delete':
                                await _run(() => _repo.remove(p.id));
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'test', child: Text('Test connection')),
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(value: 'share', child: Text('Copy share link')),
                            PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
