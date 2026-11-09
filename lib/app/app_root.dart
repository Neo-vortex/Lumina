import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lumina_tdlib/api.dart' as td;
import 'package:path_provider/path_provider.dart';

import '../core/accounts/account_store.dart';
import '../core/custom_server/custom_server.dart';
import '../core/storage/app_preferences.dart';
import '../core/storage/secure_store.dart';
import '../core/tdlib/td_client.dart';
import '../core/tdlib/td_isolate_client.dart';
import '../core/tdlib/td_paths.dart';
import '../core/theme/glow_colors.dart';
import '../features/session_backup/data/session_backup.dart';
import 'app.dart';

/// Gets TDLib's next client ready: a restored session goes in place, the
/// chosen server (custom or Telegram) goes to the environment, and the
/// folders of that server's account are resolved.
Future<TdPaths> prepareTdlib() async {
  final support = (await getApplicationSupportDirectory()).path;
  // Which account runs now (several can live on the phone; one runs at a time).
  final accounts = await AccountStore.load(support);
  AccountStore.current = accounts;
  AccountStore.reloadApp ??= AppRoot.reload;
  try {
    await SessionRestore.applyPending(support, SecureStore(), accounts: accounts);
  } catch (_) {
    // A failed restore leaves the previous data; sign-in shows as usual.
  }
  // A fresh account follows the server picked on the sign-in screen.
  await accounts.syncPendingServer();
  final account = accounts.active;
  final server = account.customServer;
  try {
    if (server == null) {
      CustomServer.clearEnvironment();
    } else {
      server.applyToEnvironment();
    }
    return await TdPaths.forAccount(account);
  } catch (_) {
    // An unreadable key: fall back to Telegram rather than not starting.
    CustomServer.clearEnvironment();
    return TdPaths.resolve();
  }
}

TdClient newTdClient() => TdIsolateClient(logVerbosity: kReleaseMode ? 1 : 2);

/// Owns the TDLib client. [reload] swaps it for a new one (switching servers,
/// restoring a session) without restarting the app: the old client is
/// closed, then the whole app is rebuilt on the new one.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key, required this.client, required this.paths, required this.preferences});

  final TdClient client;
  final TdPaths paths;
  final AppPreferences preferences;

  static _AppRootState? _instance;

  /// Closes TDLib and starts it again on the current server settings.
  static Future<void> reload() => _instance?._reload() ?? Future.value();

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  late TdClient _client = widget.client;
  late TdPaths _paths = widget.paths;
  var _generation = 0;
  var _switching = false;

  @override
  void initState() {
    super.initState();
    AppRoot._instance = this;
  }

  @override
  void dispose() {
    if (AppRoot._instance == this) AppRoot._instance = null;
    super.dispose();
  }

  Future<void> _reload() async {
    if (_switching) return;
    final old = _client;
    // Unmount the app first: nothing may use the old client while it closes.
    setState(() => _switching = true);
    await WidgetsBinding.instance.endOfFrame;
    await _close(old);
    TdPaths paths;
    try {
      paths = await prepareTdlib().timeout(const Duration(seconds: 20));
    } catch (_) {
      // Never leave the switch spinner up: start on Telegram's default
      // folder rather than not at all.
      CustomServer.clearEnvironment();
      paths = await TdPaths.resolve();
    }
    if (!mounted) return;
    setState(() {
      _client = newTdClient();
      _paths = paths;
      _generation++;
      _switching = false;
    });
  }

  /// TDLib's `close`, then waits for `authorizationStateClosed` (the
  /// database is released) before the isolates go.
  static Future<void> _close(TdClient client) async {
    final closed = client.updates
        .where((u) => u is td.UpdateAuthorizationState && u.authorizationState is td.AuthorizationStateClosed)
        .first
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () =>
              const td.UpdateAuthorizationState(authorizationState: td.AuthorizationStateClosed()),
        );
    try {
      // A wedged client (e.g. its folder deleted under it) may never answer.
      await client.invoke<td.Ok>(const td.Close()).timeout(const Duration(seconds: 10));
      await closed;
    } catch (_) {
      // Already closed, not running, or stuck: dispose anyway.
    }
    await client.dispose().timeout(const Duration(seconds: 5), onTimeout: () {});
  }

  @override
  Widget build(BuildContext context) {
    if (_switching) {
      return const ColoredBox(
        color: GlowColors.background,
        child: Center(child: CircularProgressIndicator(color: GlowColors.violet)),
      );
    }
    return LuminaApp(
      key: ValueKey(_generation),
      client: _client,
      paths: _paths,
      preferences: widget.preferences,
    );
  }
}
