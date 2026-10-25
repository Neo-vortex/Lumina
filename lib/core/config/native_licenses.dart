import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Lumina's license and where its source is (GPL-3.0-or-later requires the
/// offer; docs/DECISIONS.md D14).
const luminaLegalese =
    'Lumina is free software under the GNU GPL, version 3 or later.\n'
    'Source code: https://github.com/Neo-vortex/Lumina';

/// Notices for native code that Flutter's automatic list doesn't know about
/// (the calls engine), shown on the licenses page.
void registerNativeLicenses({AssetBundle? bundle}) {
  LicenseRegistry.addLicense(() async* {
    final String text;
    try {
      text = await (bundle ?? rootBundle).loadString('assets/licenses/calls_engine.txt');
    } catch (_) {
      return;
    }
    for (final (packages, body) in parseNotices(text)) {
      yield LicenseEntryWithLineBreaks(packages, body);
    }
  });
}

/// Splits the generated notices file: `=== a, b` headers, then the text.
/// Lines starting with `#` before the first header are comments.
@visibleForTesting
List<(List<String>, String)> parseNotices(String text) {
  final out = <(List<String>, String)>[];
  List<String>? names;
  final body = StringBuffer();
  void flush() {
    final n = names;
    if (n != null) out.add((n, body.toString().trim()));
    body.clear();
  }

  for (final line in const LineSplitter().convert(text)) {
    if (line.startsWith('=== ')) {
      flush();
      names = [for (final n in line.substring(4).split(',')) n.trim()];
    } else if (names != null) {
      body.writeln(line);
    }
  }
  flush();
  return out;
}
