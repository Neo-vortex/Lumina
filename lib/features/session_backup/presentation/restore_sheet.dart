import 'package:flutter/material.dart';

import '../../../app/app_root.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/storage/secure_store.dart';
import '../../../core/telegram/display.dart';
import '../../../core/theme/glow_colors.dart';
import '../data/session_backup.dart';

/// "Restore from backup" under the login form: works on a fresh install, for
/// Telegram and custom-server accounts alike.
class RestoreButton extends StatelessWidget {
  const RestoreButton({super.key});

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: () => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: GlowColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const RestoreSheet(),
    ),
    icon: const Icon(Icons.settings_backup_restore_rounded, size: 18),
    label: const Text('Restore from backup'),
    style: TextButton.styleFrom(foregroundColor: GlowColors.textMuted),
  );
}

class RestoreSheet extends StatefulWidget {
  const RestoreSheet({super.key});

  @override
  State<RestoreSheet> createState() => _RestoreSheetState();
}

class _RestoreSheetState extends State<RestoreSheet> {
  final _endpoint = TextEditingController();
  String? _error;
  List<BackupInfo>? _backups;
  BackupInfo? _picked;
  var _busy = false;

  @override
  void dispose() {
    _endpoint.dispose();
    super.dispose();
  }

  Uri? get _uri => BackupConfig.parseEndpoint(_endpoint.text);

  Future<void> _run(Future<void> Function() step) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await step();
    } catch (e) {
      if (mounted) setState(() => _error = e is BackupError ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _run(() async {
    final u = _uri;
    if (u == null) throw const BackupError('Enter the backup server, e.g. 192.168.1.27:8080');
    final list = await BackupApiClient(u).list();
    setState(() {
      _backups = list;
      _picked = list.firstOrNull;
    });
  });

  Future<void> _delete(BackupInfo b) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlowColors.surfaceHigh,
        title: const Text('Delete this backup?'),
        content: Text(
          '${b.label ?? b.kind} will be removed from the backup server. '
          'The account itself and its other sessions aren\'t affected.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: GlowColors.coral),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    await _run(() async {
      await BackupApiClient(_uri!).delete(b.name);
      final left = [...?_backups]..removeWhere((x) => x.name == b.name);
      setState(() {
        _backups = left;
        if (_picked?.name == b.name) _picked = left.firstOrNull;
      });
    });
  }

  Future<void> _restore() => _run(() async {
    final picked = _picked;
    if (picked == null) throw const BackupError('Pick a backup');
    final data = await BackupApiClient(_uri!).get(picked.name);
    final support = await getApplicationSupportDirectory();
    if (!mounted) return;
    final secure = context.read<SecureStore>();
    await SessionRestore.stage(support.path, secure, data);
    // The restored client keeps backing up to the same place.
    if (mounted) {
      try {
        await context.read<SessionBackupService>().configure(BackupConfig(endpoint: _uri!));
      } catch (_) {}
    }
    if (!mounted) return;
    // TDLib starts again on the new server / restored session; no app restart.
    Navigator.of(context).pop();
    await AppRoot.reload();
  });

  @override
  Widget build(BuildContext context) {
    final backups = _backups;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Restore a session', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
              'Pick a backup from your backup server. You\'ll be signed in to that Telegram or custom-server '
              'account without a login code.',
              style: TextStyle(color: GlowColors.textMuted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _endpoint,
              enabled: !_busy && backups == null,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Backup server',
                hintText: '192.168.1.27:8080',
                prefixIcon: Icon(Icons.dns_rounded),
              ),
              onSubmitted: (_) => _load(),
            ),
            if (backups != null) ...[
              const SizedBox(height: 14),
              if (backups.isEmpty)
                const Text('No backups on this server yet', style: TextStyle(color: GlowColors.textMuted))
              else
                RadioGroup<String>(
                  groupValue: _picked?.name,
                  onChanged: (n) => setState(() => _picked = backups.firstWhere((b) => b.name == n)),
                  child: Column(
                    children: [
                      for (final b in backups)
                        RadioListTile<String>(
                          value: b.name,
                          contentPadding: EdgeInsets.zero,
                          secondary: IconButton(
                            tooltip: 'Delete backup',
                            onPressed: _busy ? null : () => _delete(b),
                            icon: const Icon(Icons.delete_outline_rounded, color: GlowColors.coral),
                          ),
                          title: Row(
                            children: [
                              Icon(
                                b.kind == 'Telegram' ? Icons.send_rounded : Icons.dns_rounded,
                                color: GlowColors.cyan,
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Flexible(child: Text(b.label ?? b.kind, overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                          subtitle: Text(
                            '${b.kind} · ${MaterialLocalizations.of(context).formatMediumDate(b.created)} · '
                            '${Display.fileSize(b.size)}',
                          ),
                        ),
                    ],
                  ),
                ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: GlowColors.error)),
            ],
            const SizedBox(height: 18),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: GlowColors.violetDeep,
                foregroundColor: GlowColors.text,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _busy || (backups != null && backups.isEmpty)
                  ? null
                  : (backups == null ? _load : _restore),
              child: Text(
                _busy ? 'Please wait…' : (backups == null ? 'Show backups' : 'Restore and restart'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
