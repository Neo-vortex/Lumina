import '../core/accounts/account_store.dart';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../core/platform/system_channel.dart';
import '../core/storage/app_preferences.dart';
import '../core/tdlib/td_client.dart';
import '../features/auth/bloc/auth_bloc.dart';
import '../features/auth/domain/auth_step.dart';
import '../core/build/build_flavor.dart';
import '../features/assistant/data/action_extractor.dart';
import '../features/maintenance/data/storage_repository.dart';
import '../features/transcription/data/whisper_service.dart';
import '../features/maintenance/presentation/widgets/background_settings.dart';
import '../features/search/data/message_indexer.dart';
import '../features/session_backup/data/session_backup.dart';
import '../features/session_backup/presentation/backup_on_login.dart';
import '../core/storage/secure_store.dart';
import '../core/telegram/display.dart';

/// App lifecycle duties (spec §10.2):
/// * re-checks the TDLib receive loop on resume (the process may have been
///   frozen while cached);
/// * tells TDLib whether the app is in the foreground (`online` option),
///   unless the user chose "Appear offline" or the account is a bot.
class LifecycleWatcher extends StatefulWidget {
  const LifecycleWatcher({super.key, required this.child});

  final Widget child;

  @override
  State<LifecycleWatcher> createState() => _LifecycleWatcherState();
}

class _LifecycleWatcherState extends State<LifecycleWatcher> with WidgetsBindingObserver {
  AppLifecycleListener? _listener;
  late final AppPreferences _prefs = context.read<AppPreferences>();
  var _foreground = true;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(
      onResume: () {
        _foreground = true;
        context.read<TdClient>().ensureReceiving();
        _syncOnline();
      },
      onPause: () {
        _foreground = false;
        _syncOnline();
      },
    );
    _prefs.changes.addListener(_syncOnline);
    WidgetsBinding.instance.addObserver(this);
  }

  /// Low-RAM devices (4 GB): give back the on-device models' memory first.
  @override
  void didHaveMemoryPressure() {
    if (kOnDeviceLlm) context.read<ActionExtractor>().releaseMemory().ignore();
    context.read<WhisperService>().releaseMemory();
  }

  void _syncOnline() {
    final step = context.read<AuthBloc>().state.step;
    if (step is! AuthReady || step.capabilities.isBot) return;
    final online = _foreground && !_prefs.appearOffline;
    context
        .read<TdClient>()
        .invoke<td.Ok>(
          td.SetOption(
            name: 'online',
            value: td.OptionValueBoolean(value: online),
          ),
        )
        .ignore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _prefs.changes.removeListener(_syncOnline);
    _listener?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (a, b) => a.step is! AuthReady && b.step is AuthReady,
      listener: (context, state) {
        _syncOnline();
        final step = state.step;
        if (step is AuthReady) {
          context.read<MessageIndexer>().activate(isBot: step.capabilities.isBot).ignore();
          // The account switcher shows who each account is.
          AccountStore.current
              ?.updateActive(
                userId: step.me.id,
                name: Display.userName(step.me),
                phone: step.me.phoneNumber,
                username: step.me.usernames?.activeUsernames.firstOrNull,
              )
              .ignore();
          context.read<StorageRepository>().autoClean().catchError((_) {}).ignore();
          // Session backup: on a custom server, offer it once; then back up
          // now (if set up, also from the login screen) and about daily.
          final backup = context.read<SessionBackupService>();
          final me = step.me;
          final label = '${Display.userName(me)}${me.phoneNumber.isEmpty ? '' : ' (+${me.phoneNumber})'}';
          (step.capabilities.isBot
                  ? Future<void>.value()
                  : offerCustomServerBackup(context, backup, context.read<SecureStore>()))
              .catchError((_) {})
              .then((_) => backup.onSignedIn(me.id, label: label))
              .catchError((_) {})
              .ignore();
          // Without POST_NOTIFICATIONS (Android 13+) every message
          // notification is dropped silently; ask first, then the battery
          // prompt.
          final battery = context;
          (step.capabilities.isBot ? Future.value(true) : const SystemChannel().requestNotifications())
              .catchError((_) => false)
              .then((_) {
                if (!battery.mounted) return;
                maybeShowBatteryPrompt(
                      battery,
                      alreadyShown: _prefs.batteryPromptShown,
                      markShown: () => _prefs.batteryPromptShown = true,
                    )
                    .then((_) {
                      if (battery.mounted && !step.capabilities.isBot) {
                        return maybeShowCallScreenPrompt(battery);
                      }
                    })
                    .catchError((_) {})
                    .ignore();
              })
              .ignore();
        }
      },
      child: widget.child,
    );
  }
}
