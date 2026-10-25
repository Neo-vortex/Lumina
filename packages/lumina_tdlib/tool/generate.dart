/// Regenerates lib/src/tdapi from schema/td_api.tl and schema/VERSION.
/// Run from packages/lumina_tdlib: `dart run tool/generate.dart`
library;

import 'dart:io';

import 'src/emit.dart';
import 'src/tl.dart';

void main() {
  final schema = parseTl(File('schema/td_api.tl').readAsStringSync());
  final version = TdlibVersion.parse(File('schema/VERSION').readAsStringSync());
  final files = emitLibrary(schema, version);

  final out = Directory('lib/src/tdapi');
  if (out.existsSync()) out.deleteSync(recursive: true);
  for (final MapEntry(key: path, value: content) in files.entries) {
    File('${out.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }
  stdout.writeln('Generated ${files.length} files for TDLib ${version.version} (${version.commit.substring(0, 9)})');
}
