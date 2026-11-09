import 'core/perf/frame_stats.dart';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'app/app_root.dart';
import 'core/config/native_licenses.dart';
import 'core/storage/app_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Services such as VoiceRecorder are ChangeNotifiers handed out through
  // RepositoryProvider and listened to explicitly (ListenableBuilder), never
  // via context.watch; the provider package's debug check doesn't apply.
  Provider.debugCheckInvalidValueType = null;
  registerNativeLicenses();
  // The server (Telegram or custom) and a restored session are settled
  // before the first TDLib client; AppRoot.reload repeats this to switch.
  final (paths, preferences) = await (prepareTdlib(), AppPreferences.load()).wait;
  FrameStats.start();
  // Perf builds: every user widget's build lands on the timeline, so slow
  // frames can be pinned on the widgets that built in them.
  if (FrameStats.enabled) {
    debugProfileBuildsEnabledUserWidgets = true;
    debugProfileLayoutsEnabled = true;
  }
  runApp(AppRoot(client: newTdClient(), paths: paths, preferences: preferences));
}
