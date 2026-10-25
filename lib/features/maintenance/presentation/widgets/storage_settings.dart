import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/storage/app_preferences.dart';
import '../../../../core/telegram/display.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../settings/presentation/widgets/settings_section.dart';
import '../../data/storage_repository.dart';

/// Settings → Storage: cache usage by type, clearing, and "keep media".
class StorageSettings extends StatefulWidget {
  const StorageSettings({super.key});

  @override
  State<StorageSettings> createState() => _StorageSettingsState();
}

class _StorageSettingsState extends State<StorageSettings> {
  static const _keepOptions = {3: '3 days', 7: '1 week', 30: '1 month', 0: 'Forever'};

  late final StorageRepository _repo = context.read<StorageRepository>();
  StorageUsage? _usage;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final u = await _repo.usage();
      if (mounted) setState(() => _usage = u);
    } catch (_) {}
  }

  Future<void> _clear() async {
    final usage = _usage;
    final picked = await showModalBottomSheet<Set<CacheKind>>(
      context: context,
      showDragHandle: true,
      backgroundColor: GlowColors.surfaceHigh,
      builder: (context) => _ClearSheet(usage: usage),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final before = usage?.total ?? 0;
    try {
      await _repo.clear(kinds: picked.length == CacheKind.values.length ? null : picked);
      await _refresh();
      final freed = before - (_usage?.total ?? before);
      messenger.showSnackBar(
        SnackBar(content: Text(freed > 0 ? 'Freed ${Display.fileSize(freed)}' : 'Cache cleared')),
      );
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not clear the cache')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.read<AppPreferences>();
    final usage = _usage;
    return ListenableBuilder(
      listenable: prefs.changes,
      builder: (context, _) => SettingsSection(
        title: 'Storage',
        children: [
          ListTile(
            leading: const Icon(Icons.sd_storage_rounded, color: GlowColors.cyan),
            title: Text(usage == null ? 'Measuring…' : 'Media cache: ${Display.fileSize(usage.total)}'),
            subtitle: usage == null
                ? null
                : Text(
                    [
                      for (final e
                          in usage.byKind.entries.where((e) => e.value > 0).toList()
                            ..sort((a, b) => b.value.compareTo(a.value)))
                        '${e.key.label} ${Display.fileSize(e.value)}',
                      'Database ${Display.fileSize(usage.databaseBytes)}',
                    ].join(' · '),
                  ),
            trailing: _busy
                ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                : TextButton(onPressed: usage == null ? null : _clear, child: const Text('Clear')),
          ),
          ListTile(
            leading: const Icon(Icons.auto_delete_rounded, color: GlowColors.textMuted),
            title: const Text('Keep media'),
            subtitle: const Text(
              'Cached files not opened for longer are removed. They download again when needed.',
            ),
            trailing: DropdownButton<int>(
              value: _keepOptions.containsKey(prefs.keepMediaDays) ? prefs.keepMediaDays : 0,
              underline: const SizedBox.shrink(),
              dropdownColor: GlowColors.surfaceHigh,
              items: [
                for (final e in _keepOptions.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) {
                prefs.keepMediaDays = v ?? 0;
                _repo.autoClean().then((_) => _refresh()).ignore();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ClearSheet extends StatefulWidget {
  const _ClearSheet({required this.usage});

  final StorageUsage? usage;

  @override
  State<_ClearSheet> createState() => _ClearSheetState();
}

class _ClearSheetState extends State<_ClearSheet> {
  late final _picked = CacheKind.values.toSet();

  @override
  Widget build(BuildContext context) {
    final sizes = widget.usage?.byKind ?? const {};
    final total = _picked.fold<int>(0, (s, k) => s + (sizes[k] ?? 0));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text('Clear cache', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Messages stay; only downloaded copies are removed.',
                style: TextStyle(color: GlowColors.textMuted),
              ),
            ),
            for (final k in CacheKind.values)
              CheckboxListTile(
                value: _picked.contains(k),
                onChanged: (v) => setState(() => v == true ? _picked.add(k) : _picked.remove(k)),
                title: Text(k.label),
                secondary: Text(
                  Display.fileSize(sizes[k] ?? 0),
                  style: const TextStyle(color: GlowColors.textMuted),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: GlowColors.violetDeep,
                  minimumSize: const Size.fromHeight(50),
                ),
                onPressed: _picked.isEmpty ? null : () => Navigator.pop(context, _picked),
                child: Text('Clear ${Display.fileSize(total)}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
