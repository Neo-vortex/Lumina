import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/config/app_config.dart';
import '../core/media/tdlib_stream_server.dart';
import '../core/storage/app_preferences.dart';
import '../core/storage/secure_store.dart';
import '../core/tdlib/td_client.dart';
import '../core/tdlib/td_paths.dart';
import '../core/telegram/custom_emoji_store.dart';
import '../core/telegram/file_store.dart';
import '../core/telegram/display.dart';
import '../core/telegram/telegram_cache.dart';
import '../core/theme/glow_theme.dart';
import '../features/auth/bloc/auth_bloc.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/calls/bloc/call_cubit.dart';
import '../features/calls/data/call_engine.dart';
import '../features/calls/data/calls_repository.dart';
import '../features/calls/presentation/call_host.dart';
import '../features/chats/data/chats_repository.dart';
import '../features/conversation/data/messages_repository.dart';
import 'auth_gate.dart';
import 'feature_wiring.dart';
import 'lifecycle_watcher.dart';

/// Composition root: wires repositories, caches and blocs, then the UI.
/// Everything is provided above [MaterialApp] so pushed routes see it.
class LuminaApp extends StatelessWidget {
  const LuminaApp({
    super.key,
    required this.client,
    required this.paths,
    required this.preferences,
    this.secureStore,
    this.settings = const TdSettings.fromEnvironment(),
  });

  final TdClient client;
  final TdPaths paths;
  final AppPreferences preferences;
  final SecureStore? secureStore;
  final TdSettings settings;

  @override
  Widget build(BuildContext context) {
    final secure = secureStore ?? SecureStore();
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<TdClient>.value(value: client),
        RepositoryProvider<TdPaths>.value(value: paths),
        RepositoryProvider<SecureStore>.value(value: secure),
        RepositoryProvider<AppPreferences>.value(value: preferences),
        RepositoryProvider(create: (_) => TelegramCache(client), dispose: (c) => c.dispose()),
        RepositoryProvider(create: (_) => FileStore(client), dispose: (f) => f.dispose()),
        RepositoryProvider(create: (_) => CustomEmojiStore(client)),
        RepositoryProvider(create: (c) => TdStreamServer(c.read<FileStore>()), dispose: (s) => s.stop()),
        RepositoryProvider(
          create: (_) =>
              AuthRepository(client: client, secureStore: secure, paths: paths, settings: settings),
        ),
        RepositoryProvider(
          create: (c) => ChatsRepository(client: client, cache: c.read<TelegramCache>()),
        ),
        RepositoryProvider(
          create: (_) => MessagesRepository(client: client, prefs: preferences),
        ),
        ...featureProviders(),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (context) =>
                AuthBloc(repository: context.read<AuthRepository>())..add(const AuthStarted()),
          ),
          // App-wide and not lazy: incoming calls ring wherever the user is.
          BlocProvider(
            lazy: false,
            create: (context) {
              final engine = context.read<CallEngine>();
              final cache = context.read<TelegramCache>();
              return CallCubit(
                repository: context.read<CallsRepository>(),
                engine: engine,
                system: engine is CallSystem ? engine as CallSystem : null,
                nameOf: (id) => Display.userName(cache.users[id]),
                useCallingAccount: () => preferences.callsUseCallingAccount,
              );
            },
          ),
        ],
        child: MaterialApp(
          title: 'Lumina',
          debugShowCheckedModeBanner: false,
          theme: buildGlowTheme(),
          themeMode: ThemeMode.dark,
          navigatorKey: appNavigatorKey,
          builder: (context, child) =>
              CallHost(navigatorKey: appNavigatorKey, child: child ?? const SizedBox.shrink()),
          home: const LifecycleWatcher(child: AuthGate()),
        ),
      ),
    );
  }
}
