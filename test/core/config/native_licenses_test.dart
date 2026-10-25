import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/core/config/native_licenses.dart';

void main() {
  test('notices split into packages and text, comments skipped', () {
    final notices = parseNotices('''
# Generated; do not edit.
=== WebRTC
Copyright (c) 2011, The WebRTC project authors.

=== libyuv, libvpx
BSD

PATENTS
''');
    expect(notices, hasLength(2));
    expect(notices[0].$1, ['WebRTC']);
    expect(notices[0].$2, 'Copyright (c) 2011, The WebRTC project authors.');
    expect(notices[1].$1, ['libyuv', 'libvpx']);
    expect(notices[1].$2, 'BSD\n\nPATENTS');
  });

  test('an empty file has no notices', () {
    expect(parseNotices(''), isEmpty);
    expect(parseNotices('# only a comment'), isEmpty);
  });
}
