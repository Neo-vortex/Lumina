/// Model and parser for TDLib's td_api.tl.
library;

/// Declared in the scheme header; never generated.
const _builtinConstructors = {'double', 'string', 'int32', 'int53', 'int64', 'bytes', 'boolFalse', 'boolTrue'};

const _primitiveTypes = {'double', 'string', 'int32', 'int53', 'int64', 'bytes', 'Bool'};

final class TlType {
  const TlType(this.name, [this.element]);

  /// TL type name, or `vector` with [element] set.
  final String name;
  final TlType? element;

  bool get isVector => name == 'vector';
  bool get isPrimitive => _primitiveTypes.contains(name);

  static TlType parse(String source) {
    if (source.startsWith('vector<') && source.endsWith('>')) {
      return TlType('vector', parse(source.substring(7, source.length - 1)));
    }
    return TlType(source);
  }

  @override
  String toString() => isVector ? 'vector<$element>' : name;
}

final class TlField {
  const TlField(this.name, this.type, this.doc);

  final String name;
  final TlType type;
  final String doc;
}

final class TlConstructor {
  const TlConstructor({
    required this.name,
    required this.fields,
    required this.result,
    required this.doc,
    required this.isFunction,
  });

  final String name;
  final List<TlField> fields;

  /// Boxed result type: the abstract class, the class itself, or a function's return type.
  final String result;
  final String doc;
  final bool isFunction;
}

final class TlClass {
  const TlClass(this.name, this.doc);

  final String name;
  final String doc;
}

final class TlSchema {
  const TlSchema(this.classes, this.objects, this.functions);

  final Map<String, TlClass> classes;
  final List<TlConstructor> objects;
  final List<TlConstructor> functions;
}

final _constructor = RegExp(r'^(\w+)((?: \w+:[\w<>]+)*) = (\w+);$');

/// `@key value` pairs; a tag must follow whitespace, so `user@example.com` is text.
final _tag = RegExp(r'(?:^|\s)@(\w+)\s+(.*?)(?=\s@\w+\s|$)');

TlSchema parseTl(String source) {
  final classes = <String, TlClass>{};
  final objects = <TlConstructor>[];
  final functions = <TlConstructor>[];
  var docs = <String, String>{};
  String? lastKey;
  var inFunctions = false;

  void flushClass() {
    final name = docs['class'];
    if (name == null) return;
    classes[name] = TlClass(name, docs['description'] ?? '');
    docs = {};
    lastKey = null;
  }

  for (final raw in source.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) {
      flushClass();
      continue;
    }
    if (line == '---functions---') {
      flushClass();
      docs = {};
      inFunctions = true;
      continue;
    }
    if (line.startsWith('//')) {
      final text = line.substring(2);
      if (text.startsWith('-')) {
        final key = lastKey;
        if (key != null) docs[key] = '${docs[key]} ${text.substring(1).trim()}'.trim();
        continue;
      }
      final trimmed = text.trimLeft();
      if (trimmed.startsWith('@class') || trimmed.startsWith('@description')) {
        flushClass();
        docs = {};
      }
      for (final m in _tag.allMatches(text)) {
        lastKey = m[1]!;
        docs[m[1]!] = m[2]!.trim();
      }
      continue;
    }

    final m = _constructor.firstMatch(line);
    if (m == null) {
      // Header declarations: `double ? = Double;`, `vector {t:Type} # [ t ] = Vector t;`
      if (line.contains(' ? = ') || line.startsWith('vector {')) continue;
      throw FormatException('Unrecognized TL line', line);
    }
    final name = m[1]!;
    if (_builtinConstructors.contains(name)) {
      docs = {};
      continue;
    }
    final fields = [
      for (final arg in m[2]!.trim().split(' ').where((a) => a.isNotEmpty)) _field(arg, docs),
    ];
    (inFunctions ? functions : objects).add(
      TlConstructor(
        name: name,
        fields: fields,
        result: m[3]!,
        doc: docs['description'] ?? '',
        isFunction: inFunctions,
      ),
    );
    docs = {};
    lastKey = null;
  }
  return TlSchema(classes, objects, functions);
}

TlField _field(String arg, Map<String, String> docs) {
  final i = arg.indexOf(':');
  final name = arg.substring(0, i);
  // A field called `description` is documented as `@param_description`.
  final doc = docs[name == 'description' ? 'param_description' : name] ?? '';
  return TlField(name, TlType.parse(arg.substring(i + 1)), doc);
}
