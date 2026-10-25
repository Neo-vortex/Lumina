import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handy_tdlib_next/api.dart' as td;

import '../core/storage/app_preferences.dart';
import '../core/tdlib/td_client.dart';
import '../features/auth/bloc/auth_bloc.dart';
import '../features/auth/domain/auth_step.dart';

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

class _LifecycleWatcherState extends State<LifecycleWatcher> {
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
    _prefs.changes.removeListener(_syncOnline);
    _listener?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (a, b) => a.step is! AuthReady && b.step is AuthReady,
      listener: (_, _) => _syncOnline(),
      child: widget.child,
    );
  }
}
