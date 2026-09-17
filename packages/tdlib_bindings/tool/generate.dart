// Generates lib/src/td_api.dart from schema/td_api.tl.
//
//   dart run tool/generate.dart            (from packages/tdlib_bindings)
//
// TL → Dart mapping (JSON interface of TDLib):
//   int32, int53 → int (JSON number)      int64 → int (JSON string, parsed)
//   double → double                        string, bytes (base64) → String
//   Bool → bool                            vector<T> → List<T>
//   object fields → nullable (TDLib omits absent objects)
// Every TL type with several constructors becomes a sealed class; a type with a single
// constructor named like the type becomes one final class. Functions extend TdFunction<R>.
import 'dart:io';

const reservedWords = {
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'base',
  'break',
  'case',
  'catch',
  'class',
  'const', //
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'dynamic',
  'else',
  'enum',
  'export', //
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'Function', //
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'late',
  'library',
  'mixin', //
  'new',
  'null',
  'of',
  'on',
  'operator',
  'part',
  'required',
  'rethrow',
  'return',
  'sealed',
  'set', //
  'show',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'typedef',
  'var', //
  'void', 'when', 'while', 'with', 'yield',
};

/// TL type names that would clash with dart:core or our base classes.
const renamedTypes = {
  'Error': 'TdError',
  'Object': 'TdApiObject',
  'Function': 'TdApiFunction',
};

/// Member names that clash with TdObject / Object members.
const renamedFields = {
  'hashCode',
  'runtimeType',
  'tdType',
  'toJson',
  'toString',
  'noSuchMethod',
  'decodeResult',
};

class Field {
  Field(this.tlName, this.tlType, this.doc);
  final String tlName;
  final String tlType;
  final String doc;
  String get dartName {
    final n = camel(tlName);
    return reservedWords.contains(n) || renamedFields.contains(n) ? '${n}_' : n;
  }
}

class Ctor {
  Ctor(
    this.name,
    this.fields,
    this.resultType,
    this.doc, {
    required this.isFunction,
  });
  final String name; // TL constructor name (lowerCamel)
  final List<Field> fields;
  final String resultType; // TL type (UpperCamel)
  final String doc;
  final bool isFunction;
}

String camel(String snake) {
  final parts = snake.split('_');
  return parts.first +
      parts
          .skip(1)
          .map((p) => p.isEmpty ? '' : p[0].toUpperCase() + p.substring(1))
          .join();
}

String upperFirst(String s) => s[0].toUpperCase() + s.substring(1);
String lowerFirst(String s) => s[0].toLowerCase() + s.substring(1);

String dartTypeName(String tlType) => renamedTypes[tlType] ?? tlType;

void main(List<String> args) {
  final root = File(Platform.script.toFilePath()).parent.parent;
  final tl = File('${root.path}/schema/td_api.tl').readAsLinesSync();
  final commit = File('${root.path}/schema/TDLIB_COMMIT')
      .readAsStringSync()
      .trim();

  final ctors = <Ctor>[];
  final classDocs = <String, String>{};
  var inFunctions = false;
  var descr = '';
  final fieldDocs = <String, String>{};
  String? lastDocKey;

  for (final raw in tl) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line == '---functions---') {
      inFunctions = true;
      continue;
    }
    if (line == '---types---') {
      inFunctions = false;
      continue;
    }
    if (line.startsWith('//')) {
      var text = line.substring(2);
      if (text.startsWith('-')) {
        // continuation of the previous doc line
        if (lastDocKey == null) continue;
        final cont = text.substring(1).trim();
        if (lastDocKey == '@description') {
          descr = '$descr $cont';
        } else {
          fieldDocs[lastDocKey] = '${fieldDocs[lastDocKey]} $cont';
        }
        continue;
      }
      // Split on " @key " markers: "@class X @description ..." or "@description ... @field ..."
      final parts = RegExp(r'@(\w+)\s+([^@]*)').allMatches(text);
      String? className;
      for (final m in parts) {
        final key = m.group(1)!;
        final value = m.group(2)!.trim();
        if (key == 'class') {
          className = value;
        } else if (key == 'description') {
          if (className != null) {
            classDocs[className] = value;
          } else {
            descr = value;
            lastDocKey = '@description';
          }
        } else {
          fieldDocs[key] = value;
          lastDocKey = key;
        }
      }
      continue;
    }
    // Constructor / function line: name [fields] = Type;
    final m = RegExp(r'^([a-zA-Z0-9_.]+)\s*(.*?)\s*=\s*([A-Za-z0-9_<>]+)\s*;$')
        .firstMatch(line);
    if (m == null) {
      stderr.writeln('skip: $line');
      continue;
    }
    final name = m.group(1)!;
    final result = m.group(3)!;
    if (const {
      'Double',
      'String',
      'Int32',
      'Int53',
      'Int64',
      'Bytes',
      'Bool',
    }.contains(result)) {
      descr = '';
      fieldDocs.clear();
      continue;
    }
    final fields = <Field>[];
    for (final f in m.group(2)!.split(RegExp(r'\s+'))) {
      if (f.isEmpty) continue;
      final i = f.indexOf(':');
      final fname = f.substring(0, i);
      final ftype = f.substring(i + 1);
      final docKey = fname == 'description' ? 'param_description' : fname;
      fields.add(
        Field(fname, ftype, fieldDocs[docKey] ?? fieldDocs[fname] ?? ''),
      );
    }
    ctors.add(Ctor(name, fields, result, descr, isFunction: inFunctions));
    descr = '';
    fieldDocs.clear();
    lastDocKey = null;
  }

  // Group type constructors by result type.
  final byType = <String, List<Ctor>>{};
  for (final c in ctors.where((c) => !c.isFunction)) {
    byType.putIfAbsent(c.resultType, () => []).add(c);
  }

  String dartType(String tl) {
    if (tl.startsWith('vector<')) {
      return 'List<${dartType(tl.substring(7, tl.length - 1))}>';
    }
    switch (tl) {
      case 'int32':
      case 'int53':
      case 'int64':
        return 'int';
      case 'double':
        return 'double';
      case 'string':
      case 'bytes':
        return 'String';
      case 'Bool':
        return 'bool';
    }
    // Object type: constructor name (lowerCamel) or abstract type (UpperCamel).
    final t = tl[0] == tl[0].toUpperCase() ? tl : ctorClassName(byType, tl);
    return dartTypeName(t);
  }

  bool isObject(String tl) =>
      !tl.startsWith('vector<') &&
      !const {
        'int32',
        'int53',
        'int64',
        'double',
        'string',
        'bytes',
        'Bool',
      }.contains(tl);

  String fieldDecl(Field f) {
    final t = dartType(f.tlType);
    return isObject(f.tlType) ? '$t?' : t;
  }

  String decode(String tl, String expr) {
    if (tl.startsWith('vector<')) {
      final inner = tl.substring(7, tl.length - 1);
      return '(($expr as List?) ?? const []).map((e) => ${decode(inner, 'e')}).toList()';
    }
    switch (tl) {
      case 'int32':
      case 'int53':
        return '(($expr as num?) ?? 0).toInt()';
      case 'int64':
        return 'int.parse(($expr as String?) ?? \'0\')';
      case 'double':
        return '(($expr as num?) ?? 0).toDouble()';
      case 'string':
      case 'bytes':
        return '(($expr as String?) ?? \'\')';
      case 'Bool':
        return '(($expr as bool?) ?? false)';
    }
    return '${dartType(tl)}.fromJson($expr as Map<String, Object?>)';
  }

  String decodeField(Field f) {
    if (isObject(f.tlType)) {
      return "json['${f.tlName}'] == null ? null : ${decode(f.tlType, "json['${f.tlName}']")}";
    }
    return decode(f.tlType, "json['${f.tlName}']");
  }

  String encode(String tl, String expr) {
    if (tl.startsWith('vector<')) {
      final inner = tl.substring(7, tl.length - 1);
      return '$expr.map((e) => ${encode(inner, 'e')}).toList()';
    }
    switch (tl) {
      case 'int64':
        return '$expr.toString()';
      case 'int32':
      case 'int53':
      case 'double':
      case 'string':
      case 'bytes':
      case 'Bool':
        return expr;
    }
    return '$expr.toJson()';
  }

  String encodeField(Field f) => isObject(f.tlType)
      ? '${f.dartName}?.toJson()'
      : encode(f.tlType, f.dartName);

  String doc(String text, [String indent = '']) {
    if (text.isEmpty) return '';
    final safe = text
        .replaceAll('*/', '* /')
        .replaceAllMapped(RegExp(r'<[^>]+>'), (m) => '`${m[0]}`');
    return '$indent/// $safe\n';
  }

  final out = StringBuffer()
    ..writeln(
      '// GENERATED by tool/generate.dart from schema/td_api.tl (TDLib commit $commit).',
    )
    ..writeln('// Do not edit by hand.')
    ..writeln(
      '// ignore_for_file: lines_longer_than_80_chars, unnecessary_cast',
    )
    ..writeln()
    ..writeln("import 'td_object.dart';")
    ..writeln("export 'td_object.dart';")
    ..writeln();

  final ctorNames = <String>{};
  void writeClass(Ctor c, {String? parent, String? className}) {
    final name = className ?? dartTypeName(upperFirst(c.name));
    ctorNames.add(name);
    final ext =
        parent ??
        (c.isFunction ? 'TdFunction<${dartType(c.resultType)}>' : 'TdObject');
    out.write(doc(c.doc));
    out.writeln('final class $name extends $ext {');
    for (final f in c.fields) {
      out.write(doc(f.doc, '  '));
      out.writeln('  final ${fieldDecl(f)} ${f.dartName};');
    }
    out.writeln();
    if (c.fields.isEmpty) {
      out.writeln('  const $name();');
    } else {
      out.write('  const $name({');
      for (final f in c.fields) {
        out.write(
          isObject(f.tlType)
              ? 'this.${f.dartName}, '
              : 'required this.${f.dartName}, ',
        );
      }
      out.writeln('});');
    }
    out.writeln();
    out.writeln("  static const String constructorType = '${c.name}';");
    out.writeln('  @override');
    out.writeln('  String get tdType => constructorType;');
    out.writeln();
    out.writeln(
      '  factory $name.fromJson(Map<String, Object?> json) => $name(',
    );
    for (final f in c.fields) {
      out.writeln('        ${f.dartName}: ${decodeField(f)},');
    }
    out.writeln('      );');
    out.writeln();
    out.writeln('  @override');
    out.writeln('  Map<String, Object?> toJson() => {');
    out.writeln("        '@type': constructorType,");
    for (final f in c.fields) {
      out.writeln("        '${f.tlName}': ${encodeField(f)},");
    }
    out.writeln('      };');
    if (c.isFunction) {
      out.writeln();
      out.writeln('  @override');
      out.writeln(
        '  ${dartType(c.resultType)} decodeResult(Map<String, Object?> json) => ${dartType(c.resultType)}.fromJson(json);',
      );
    }
    out.writeln('}');
    out.writeln();
  }

  final sealedTypes = <String>[];
  for (final entry in byType.entries) {
    final tlType = entry.key;
    final list = entry.value;
    final typeName = dartTypeName(tlType);
    if (list.length == 1 && lowerFirst(tlType) == list.single.name) {
      writeClass(list.single, className: typeName);
      continue;
    }
    sealedTypes.add(typeName);
    out.write(doc(classDocs[tlType] ?? ''));
    out.writeln('sealed class $typeName extends TdObject {');
    out.writeln('  const $typeName();');
    out.writeln();
    out.writeln(
      '  static $typeName fromJson(Map<String, Object?> json) => switch (json[\'@type\']) {',
    );
    for (final c in list) {
      out.writeln(
        "        '${c.name}' => ${dartTypeName(upperFirst(c.name))}.fromJson(json),",
      );
    }
    out.writeln(
      "        final t => throw ArgumentError('unknown $tlType constructor: \$t'),",
    );
    out.writeln('      };');
    out.writeln('}');
    out.writeln();
    for (final c in list) {
      writeClass(c, parent: typeName);
    }
  }

  for (final c in ctors.where((c) => c.isFunction)) {
    writeClass(c);
  }

  // Global decoder for updates and responses.
  out.writeln('/// Decodes any TDLib object by its `@type`.');
  out.writeln(
    'TdObject tdObjectFromJson(Map<String, Object?> json) => switch (json[\'@type\']) {',
  );
  for (final c in ctors.where((c) => !c.isFunction)) {
    final list = byType[c.resultType]!;
    final name = (list.length == 1 && lowerFirst(c.resultType) == c.name)
        ? dartTypeName(c.resultType)
        : dartTypeName(upperFirst(c.name));
    out.writeln("      '${c.name}' => $name.fromJson(json),");
  }
  out.writeln(
    "      final t => throw ArgumentError('unknown TDLib type: \$t'),",
  );
  out.writeln('    };');

  final target = File('${root.path}/lib/src/td_api.dart');
  target.writeAsStringSync(out.toString());
  final fmt = Process.runSync('dart', [
    'format',
    target.path,
  ], runInShell: true);
  if (fmt.exitCode != 0) {
    stderr.writeln(fmt.stderr);
  }
  stdout.writeln(
    'wrote ${target.path}: ${ctors.where((c) => !c.isFunction).length} constructors, '
    '${ctors.where((c) => c.isFunction).length} functions, ${sealedTypes.length} sealed types',
  );
}

/// Dart class name for a TL constructor referenced as a field type (lowerCamel in TL).
String ctorClassName(Map<String, List<Ctor>> byType, String ctorName) {
  for (final entry in byType.entries) {
    for (final c in entry.value) {
      if (c.name == ctorName) {
        if (entry.value.length == 1 && lowerFirst(entry.key) == c.name) {
          return entry.key;
        }
        return upperFirst(c.name);
      }
    }
  }
  throw StateError('unknown constructor $ctorName');
}
