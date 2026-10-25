import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'app/app.dart';
import 'core/storage/app_preferences.dart';
import 'core/tdlib/td_isolate_client.dart';
import 'core/tdlib/td_paths.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Services such as VoiceRecorder are ChangeNotifiers handed out through
  // RepositoryProvider and listened to explicitly (ListenableBuilder), never
  // via context.watch; the provider package's debug check doesn't apply.
  Provider.debugCheckInvalidValueType = null;
  final (paths, preferences) = await (TdPaths.resolve(), AppPreferences.load()).wait;
  // One TdClient per process. After Android kills the process this simply
  // runs again; TDLib reloads the session from its database and goes
  // straight to authorizationStateReady.
  runApp(LuminaApp(client: TdIsolateClient(), paths: paths, preferences: preferences));
}
