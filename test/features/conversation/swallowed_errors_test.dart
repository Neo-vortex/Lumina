import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/storage/app_preferences.dart';
import 'package:lumina/features/conversation/data/messages_repository.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../helpers/fakes.dart';

/// Callers swallow these failures with `.catchError((_) {})`, which throws
/// unless the future's runtime type is really `Future<void>`.
void main() {
  late MessagesRepository repo;

  setUp(() {
    final client = FakeTdClient()
      ..respond = (_) => const td.TdError(code: 400, message: 'CHAT_WRITE_FORBIDDEN');
    repo = MessagesRepository(client: client, prefs: AppPreferences.inMemory());
  });

  test('a failed draft save can be ignored', () async {
    await repo.saveDraft(1, 'hello').catchError((_) {});
  });

  test('a failed sponsored click can be ignored', () async {
    await repo.clickSponsored(1, 2).catchError((_) {});
  });

  test('a failed ad-free toggle can be ignored', () async {
    await repo.setSponsoredEnabled(false).catchError((_) {});
  });
}
