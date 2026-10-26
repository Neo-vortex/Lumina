import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/tdlib/td_errors.dart';
import 'package:lumina/features/folders/domain/folder_errors.dart';

void main() {
  test('known TDLib errors read as sentences that name the limit', () {
    expect(folderErrorText(TdException(400, 'CHATLISTS_TOO_MUCH')), contains('folder limit'));
    expect(folderErrorText(TdException(400, 'FILTER_INCLUDE_TOO_MUCH')), contains('too many chats'));
    expect(folderErrorText(TdException(400, 'INVITE_SLUG_EXPIRED')), 'This folder link has expired');
    expect(folderErrorText(TdException(400, 'FILTER_ID_INVALID')), 'This folder was deleted');
  });

  test('unknown errors fall back to the message', () {
    expect(folderErrorText(TdException(500, 'Something odd')), 'Something odd');
    expect(folderErrorText(StateError('x')), 'Bad state: x');
  });
}
