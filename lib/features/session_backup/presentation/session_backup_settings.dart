import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/glow_colors.dart';
import '../../settings/presentation/widgets/settings_section.dart';
import '../data/session_backup.dart';

/// Settings → Data & storage → Session backup.
class SessionBackupSettings extends StatefulWidget {
  const SessionBackupSettings({super.key});

  @override
  State<SessionBackupSettings> createState() => _SessionBackupSettingsState();
}

class _SessionBackupSettingsState extends State<SessionBackupSettings> {
  late final SessionBackupService _service = context.read<SessionBackupService>();

  @override
  void initState() {
    super.initState();
    _service.load();
  }

  Future<void> _backupNow() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _service.backupNow();
      messenger.showSnackBar(const SnackBar(content: Text('Session backed up')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Backup failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final c = _service.config;
        final last = _service.lastBackup;
        final status = switch (_service.state) {
          BackupState.running => 'Backing up…',
          BackupState.failed => 'Last attempt failed: ${_service.lastError}',
          _ => last == null ? 'No backup yet' : 'Last backup ${_ago(last)}',
        };
        return SettingsSection(
          title: 'Session backup',
          children: [
            if (c == null)
              ListTile(
                leading: const Icon(Icons.cloud_upload_rounded, color: GlowColors.violet),
                title: const Text('Back up this session'),
                subtitle: const Text(
                  'Stored on your backup server so a fresh install can restore it. Works for Telegram and '
                  'custom-server accounts.',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: GlowColors.surface,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  builder: (_) => _SetupSheet(service: _service),
                ),
              )
            else ...[
              ListTile(
                leading: Icon(
                  _service.state == BackupState.failed ? Icons.cloud_off_rounded : Icons.cloud_done_rounded,
                  color: _service.state == BackupState.failed ? GlowColors.error : GlowColors.cyan,
                ),
                title: Text(c.endpoint.authority),
                subtitle: Text(status),
              ),
              SwitchListTile(
                activeThumbColor: GlowColors.cyan,
                title: const Text('Back up automatically'),
                subtitle: const Text('When you sign in, then about once a day'),
                value: c.auto,
                onChanged: _service.setAuto,
              ),
              ListTile(
                leading: const Icon(Icons.backup_rounded),
                title: const Text('Back up now'),
                enabled: _service.state != BackupState.running,
                onTap: _backupNow,
              ),
              ListTile(
                leading: const Icon(Icons.link_off_rounded, color: GlowColors.textMuted),
                title: const Text('Disconnect backup server'),
                subtitle: const Text('Backups already uploaded stay on the server'),
                onTap: _service.disconnect,
              ),
            ],
          ],
        );
      },
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}

/// Just the backup server's address; it needs no account (debug backups).
class _SetupSheet extends StatefulWidget {
  const _SetupSheet({required this.service});

  final SessionBackupService service;

  @override
  State<_SetupSheet> createState() => _SetupSheetState();
}

class _SetupSheetState extends State<_SetupSheet> {
  final _endpoint = TextEditingController();
  String? _error;
  var _busy = false;

  @override
  void dispose() {
    _endpoint.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final u = BackupConfig.parseEndpoint(_endpoint.text);
    if (u == null) return setState(() => _error = 'Enter the backup server, e.g. 192.168.1.27:8080');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await BackupApiClient(u).list(); // reachable, and open backups enabled
      await widget.service.configure(BackupConfig(endpoint: u));
      if (mounted) Navigator.pop(context);
      await widget.service.backupNow().catchError((_) {});
    } catch (e) {
      if (mounted) setState(() => _error = e is BackupError ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Session backup', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text(
            'Uploads this session (Telegram or custom server) so any Lumina, even a fresh install, can '
            'restore it. Debug: backups are NOT encrypted on the server and anyone who can reach it can '
            'download them.',
            style: TextStyle(color: GlowColors.textMuted),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _endpoint,
            enabled: !_busy,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Backup server',
              hintText: '192.168.1.27:8080',
              prefixIcon: Icon(Icons.dns_rounded),
            ),
            onSubmitted: (_) => _connect(),
          ),
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
            onPressed: _busy ? null : _connect,
            child: Text(_busy ? 'Please wait…' : 'Back up now and daily'),
          ),
        ],
      ),
    );
  }
}
