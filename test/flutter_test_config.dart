import 'dart:async';

import 'package:provider/provider.dart';

/// Applied to every test file: matches main.dart (services that are
/// ChangeNotifiers are provided via RepositoryProvider and listened to
/// explicitly).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  Provider.debugCheckInvalidValueType = null;
  await testMain();
}
