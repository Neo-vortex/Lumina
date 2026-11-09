import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/custom_server/custom_server.dart';
import '../../../core/storage/secure_store.dart';
import '../../../core/theme/glow_colors.dart';
import '../data/session_backup.dart';

/// Login screen: "Back up session to" — a backup server address that is
/// saved when the login starts and used once it succeeds. On a custom server
/// it starts out as that server's own backup API (host:8080).
class BackupTargetField extends StatefulWidget {
  const BackupTargetField({super.key, required this.controller});

  final TextEditingController controller;

  @override
  State<BackupTargetField> createState() => _BackupTargetFieldState();
}

class _BackupTargetFieldState extends State<BackupTargetField> {
  /// The custom server being signed in to; null on Telegram.
  CustomServer? _server;
  var _loaded = false;
  var _open = false;

  @override
  void initState() {
    super.initState();
    getApplicationSupportDirectory()
        .then((d) {
          if (mounted) {
            setState(() {
              _server = CustomServer.load(d.path);
              _loaded = true;
            });
          }
        })
        .catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: _open
          ? Padding(
              padding: const EdgeInsets.only(top: 14),
              child: TextField(
                controller: widget.controller,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Back up session to (optional)',
                  hintText: '192.168.1.27:8080',
                  prefixIcon: Icon(Icons.cloud_upload_rounded),
                ),
              ),
            )
          : Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  final server = _server;
                  if (server != null && widget.controller.text.trim().isEmpty) {
                    final host = server.host.contains(':') ? '[${server.host}]' : server.host;
                    widget.controller.text = '$host:8080';
                  }
                  setState(() => _open = true);
                },
                icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                label: const Text('Back up this session after login'),
                style: TextButton.styleFrom(foregroundColor: GlowColors.textMuted),
              ),
            ),
    );
  }
}

/// Saves the login screen's backup target (if any) so the backup runs as
/// soon as the sign-in completes.
Future<void> rememberBackupTarget(SessionBackupService service, String raw) async {
  final u = BackupConfig.parseEndpoint(raw);
  if (u == null) return;
  await service.configure(BackupConfig(endpoint: u));
}

/// After signing in to a custom server: asks once whether to back the
/// session up to that same server's HTTP API (port 8080).
Future<void> offerCustomServerBackup(
  BuildContext context,
  SessionBackupService service,
  SecureStore secure,
) async {
  await service.load();
  if (service.config != null) return;
  final server = CustomServer.load((await getApplicationSupportDirectory()).path);
  if (server == null) return;
  final askedKey = 'session_backup.asked.${server.storageId}';
  if (await secure.readSecret(askedKey) != null) return;
  await secure.writeSecret(askedKey, '1');
  final endpoint = BackupConfig.parseEndpoint(server.host.contains(':') ? '[${server.host}]' : server.host)!;
  if (!context.mounted) return;
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: GlowColors.surface,
      icon: const Icon(Icons.cloud_upload_rounded, color: GlowColors.cyan),
      title: const Text('Back up this session?'),
      content: Text(
        'Lumina can store this session on ${endpoint.authority} so you can restore it on any phone, even a '
        'fresh install. Debug: the backup is not encrypted on the server.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: GlowColors.violetDeep),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Back up'),
        ),
      ],
    ),
  );
  if (yes == true) await service.configure(BackupConfig(endpoint: endpoint));
}
