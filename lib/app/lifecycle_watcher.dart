import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../core/storage/app_preferences.dart';
import '../core/tdlib/td_client.dart';
import '../features/auth/bloc/auth_bloc.dart';
import '../features/auth/domain/auth_step.dart';
import '../features/assistant/data/action_extractor.dart';
import '../features/maintenance/data/storage_repository.dart';
import '../features/transcription/data/whisper_service.dart';
import '../features/maintenance/presentation/widgets/background_settings.dart';
import '../features/search/data/message_indexer.dart';

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
    context.read<ActionExtractor>().releaseMemory().ignore();
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
          context.read<StorageRepository>().autoClean().catchError((_) {}).ignore();
          maybeShowBatteryPrompt(
            context,
            alreadyShown: _prefs.batteryPromptShown,
            markShown: () => _prefs.batteryPromptShown = true,
          ).ignore();
        }
      },
      child: widget.child,
    );
  }
}
