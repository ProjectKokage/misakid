// Generates compact CPython 3.12.11 Unicode data for the spaCy adapter.
//
// The accepted JSON is captured explicitly by
// tool/reference/export_python312_spacy_unicode.py. Normal package use never
// runs Python and never reads the canonical JSON.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const _sourcePath =
    'tool/upstream_data/python-3.12.11-unicode-15.0.0/'
    'spacy_unicode_tables.json';
const _outputPath =
    'packages/misakid_spacy_en/lib/src/tokenizer/python_unicode.dart';
const _sharedOutputPath = 'lib/src/core/python312_unicode.dart';
const _expectedSourceSha256 =
    '1e7928f616c36560748f466b047720011faa0c49db1b459a443eec318e01da6f';
const _expectedBehaviorSha256 =
    '68d7a4099fb5f72477218518178e89c1e8446b65dfdb2790f4747efb11bf4ffc';
const _beginMarker = '// BEGIN GENERATED UNICODE DATA.';
const _endMarker = '// END GENERATED UNICODE DATA.';
const _sharedBeginMarker = '// BEGIN GENERATED SHARED CASE DATA.';
const _sharedEndMarker = '// END GENERATED SHARED CASE DATA.';

void main(List<String> arguments) {
  final checkOnly = arguments.length == 1 && arguments.single == '--check';
  if (arguments.isNotEmpty && !checkOnly) {
    stderr.writeln('Usage: dart run ${Platform.script.path} [--check]');
    exitCode = 64;
    return;
  }

  final source = File(_sourcePath);
  if (!source.existsSync()) {
    _fail('Missing canonical source $_sourcePath.');
  }
  final sourceBytes = source.readAsBytesSync();
  final sourceSha256 = sha256.convert(sourceBytes).toString();
  if (sourceSha256 != _expectedSourceSha256) {
    _fail(
      'Canonical source checksum mismatch: expected '
      '$_expectedSourceSha256, got $sourceSha256.',
    );
  }
  final decoded = jsonDecode(utf8.decode(sourceBytes));
  final root = _stringMap(decoded, 'root');
  _expect(root['schemaVersion'], 1, 'schemaVersion');
  final sourceInfo = _stringMap(root['source'], 'source');
  _expect(sourceInfo['implementation'], 'CPython', 'source.implementation');
  _expect(sourceInfo['pythonVersion'], '3.12.11', 'source.pythonVersion');
  _expect(sourceInfo['unicodeVersion'], '15.0.0', 'source.unicodeVersion');
  final digests = _stringMap(root['digests'], 'digests');
  _expect(
    digests['decodedBehaviorSha256'],
    _expectedBehaviorSha256,
    'digests.decodedBehaviorSha256',
  );

  final counts = _stringMap(root['counts'], 'counts');
  final properties = _stringMap(root['properties'], 'properties');
  final alphabetic = _ranges(
    properties['alphabeticRanges'],
    'properties.alphabeticRanges',
  );
  final digits = _ranges(properties['digitRanges'], 'properties.digitRanges');
  final uppercase = _ranges(
    properties['uppercaseRanges'],
    'properties.uppercaseRanges',
  );
  final words = _ranges(
    properties['wordRangesWithoutUnderscore'],
    'properties.wordRangesWithoutUnderscore',
  );
  final cased = _ranges(properties['casedRanges'], 'properties.casedRanges');
  final caseIgnorable = _ranges(
    properties['caseIgnorableRanges'],
    'properties.caseIgnorableRanges',
  );
  final whitespace = _ranges(
    properties['whitespaceRanges'],
    'properties.whitespaceRanges',
  );
  final lowercase = _lowercaseMappings(root['lowercaseMappings']);

  _expectCount(counts, 'alphabeticRanges', alphabetic.length ~/ 2, 659);
  _expectCount(counts, 'digitRanges', digits.length ~/ 2, 83);
  _expectCount(counts, 'uppercaseRanges', uppercase.length ~/ 2, 651);
  _expectCount(counts, 'wordRangesWithoutUnderscore', words.length ~/ 2, 747);
  _expectCount(counts, 'casedRanges', cased.length ~/ 2, 157);
  _expectCount(counts, 'caseIgnorableRanges', caseIgnorable.length ~/ 2, 437);
  _expectCount(counts, 'whitespaceRanges', whitespace.length ~/ 2, 10);
  _expectCount(counts, 'lowercaseMappings', lowercase.length, 1433);

  final adapterRendered = _render(
    sourceSha256: sourceSha256,
    behaviorSha256: _expectedBehaviorSha256,
    alphabetic: alphabetic,
    digits: digits,
    uppercase: uppercase,
    words: words,
    cased: cased,
    caseIgnorable: caseIgnorable,
    whitespace: whitespace,
    lowercase: lowercase,
  );
  final sharedRendered = _renderShared(
    sourceSha256: sourceSha256,
    behaviorSha256: _expectedBehaviorSha256,
    cased: cased,
    caseIgnorable: caseIgnorable,
    lowercase: lowercase,
  );
  _updateTarget(
    path: _outputPath,
    beginMarker: _beginMarker,
    endMarker: _endMarker,
    rendered: adapterRendered,
    checkOnly: checkOnly,
  );
  _updateTarget(
    path: _sharedOutputPath,
    beginMarker: _sharedBeginMarker,
    endMarker: _sharedEndMarker,
    rendered: sharedRendered,
    checkOnly: checkOnly,
  );
}

void _updateTarget({
  required String path,
  required String beginMarker,
  required String endMarker,
  required String rendered,
  required bool checkOnly,
}) {
  final output = File(path);
  if (!output.existsSync()) {
    _fail('Missing generated target $path.');
  }
  final current = output.readAsStringSync();
  final begin = current.indexOf(beginMarker);
  final end = current.indexOf(endMarker);
  if (begin < 0 || end <= begin) {
    _fail('Generated target $path lacks unique data markers.');
  }
  final secondBegin = current.indexOf(beginMarker, begin + 1);
  final secondEnd = current.indexOf(endMarker, end + 1);
  if (secondBegin >= 0 || secondEnd >= 0) {
    _fail('Generated target $path contains duplicate data markers.');
  }
  final dataEnd = end + endMarker.length;
  final expected = current.replaceRange(begin, dataEnd, rendered);
  if (checkOnly) {
    if (current != expected) {
      _fail(
        'Generated output $path differs: run this generator without --check.',
      );
    }
    stdout.writeln('verified $path');
    return;
  }
  output.writeAsStringSync(expected);
  stdout.writeln('wrote $path');
}

String _render({
  required String sourceSha256,
  required String behaviorSha256,
  required List<int> alphabetic,
  required List<int> digits,
  required List<int> uppercase,
  required List<int> words,
  required List<int> cased,
  required List<int> caseIgnorable,
  required List<int> whitespace,
  required Map<int, String> lowercase,
}) {
  final blocks = <({String name, Uint8List bytes, int count})>[
    (
      name: 'alphabetic',
      bytes: _encodeRanges(alphabetic),
      count: alphabetic.length ~/ 2,
    ),
    (name: 'digit', bytes: _encodeRanges(digits), count: digits.length ~/ 2),
    (
      name: 'uppercase',
      bytes: _encodeRanges(uppercase),
      count: uppercase.length ~/ 2,
    ),
    (name: 'cased', bytes: _encodeRanges(cased), count: cased.length ~/ 2),
    (
      name: 'caseIgnorable',
      bytes: _encodeRanges(caseIgnorable),
      count: caseIgnorable.length ~/ 2,
    ),
    (name: 'word', bytes: _encodeRanges(words), count: words.length ~/ 2),
    (
      name: 'lowercase',
      bytes: _encodeLowercaseMappings(lowercase),
      count: lowercase.length,
    ),
  ];
  final output = StringBuffer()
    ..writeln(_beginMarker)
    ..writeln('// Generator:')
    ..writeln('//   tool/generators/generate_python312_spacy_unicode.dart')
    ..writeln('// Canonical source:')
    ..writeln('//   $_sourcePath')
    ..writeln('// Source SHA-256: $sourceSha256')
    ..writeln('// Decoded behavior SHA-256: $behaviorSha256')
    ..writeln();
  for (final block in blocks) {
    output
      ..writeln('const int _${block.name}DataCount = ${block.count};')
      ..writeln('// Decoded SHA-256: ${sha256.convert(block.bytes)}')
      ..writeln('const String _${block.name}Data =');
    final encoded = base64Encode(block.bytes);
    for (var start = 0; start < encoded.length; start += 80) {
      final end = start + 80 < encoded.length ? start + 80 : encoded.length;
      final terminator = end == encoded.length ? ';' : '';
      output.writeln("    '${encoded.substring(start, end)}'$terminator");
    }
    output.writeln();
  }
  output.writeln('const List<int> _whitespaceRanges = <int>[');
  for (final value in whitespace) {
    output.writeln('  0x${value.toRadixString(16)},');
  }
  output
    ..writeln('];')
    ..write(_endMarker);
  return output.toString();
}

String _renderShared({
  required String sourceSha256,
  required String behaviorSha256,
  required List<int> cased,
  required List<int> caseIgnorable,
  required Map<int, String> lowercase,
}) {
  final blocks = <({String name, Uint8List bytes, int count})>[
    (
      name: 'python312Cased',
      bytes: _encodeRanges(cased),
      count: cased.length ~/ 2,
    ),
    (
      name: 'python312CaseIgnorable',
      bytes: _encodeRanges(caseIgnorable),
      count: caseIgnorable.length ~/ 2,
    ),
    (
      name: 'python312Lowercase',
      bytes: _encodeLowercaseMappings(lowercase),
      count: lowercase.length,
    ),
  ];
  final output = StringBuffer()
    ..writeln(_sharedBeginMarker)
    ..writeln('// Generator:')
    ..writeln('//   tool/generators/generate_python312_spacy_unicode.dart')
    ..writeln('// Canonical source:')
    ..writeln('//   $_sourcePath')
    ..writeln('// Source SHA-256: $sourceSha256')
    ..writeln('// Decoded behavior SHA-256: $behaviorSha256')
    ..writeln();
  for (final block in blocks) {
    output
      ..writeln('const int _${block.name}DataCount = ${block.count};')
      ..writeln('// Decoded SHA-256: ${sha256.convert(block.bytes)}')
      ..writeln('const String _${block.name}Data =');
    final encoded = base64Encode(block.bytes);
    for (var start = 0; start < encoded.length; start += 80) {
      final end = start + 80 < encoded.length ? start + 80 : encoded.length;
      final terminator = end == encoded.length ? ';' : '';
      output.writeln("    '${encoded.substring(start, end)}'$terminator");
    }
    output.writeln();
  }
  output.write(_sharedEndMarker);
  return output.toString();
}

Uint8List _encodeRanges(List<int> ranges) {
  final output = BytesBuilder(copy: false);
  var previousEnd = -1;
  for (var index = 0; index < ranges.length; index += 2) {
    final start = ranges[index];
    final end = ranges[index + 1];
    _writeUnsignedLeb128(output, start - previousEnd - 1);
    _writeUnsignedLeb128(output, end - start);
    previousEnd = end;
  }
  return output.takeBytes();
}

Uint8List _encodeLowercaseMappings(Map<int, String> mappings) {
  final output = BytesBuilder(copy: false);
  var previous = -1;
  for (final entry in mappings.entries) {
    final bytes = utf8.encode(entry.value);
    _writeUnsignedLeb128(output, entry.key - previous - 1);
    _writeUnsignedLeb128(output, bytes.length);
    output.add(bytes);
    previous = entry.key;
  }
  return output.takeBytes();
}

void _writeUnsignedLeb128(BytesBuilder output, int value) {
  if (value < 0) {
    _fail('Cannot encode a negative unsigned varint.');
  }
  var remaining = value;
  do {
    var byte = remaining & 0x7f;
    remaining >>= 7;
    if (remaining != 0) byte |= 0x80;
    output.addByte(byte);
  } while (remaining != 0);
}

List<int> _ranges(Object? value, String label) {
  if (value is! List<Object?>) {
    _fail('$label must be a JSON array.');
  }
  final result = <int>[];
  var previousEnd = -1;
  for (var index = 0; index < value.length; index++) {
    final pair = value[index];
    if (pair is! List<Object?> || pair.length != 2) {
      _fail('$label[$index] must contain two hexadecimal bounds.');
    }
    final start = _hexScalar(pair[0], '$label[$index][0]');
    final end = _hexScalar(pair[1], '$label[$index][1]');
    if (start <= previousEnd || end < start) {
      _fail('$label[$index] must be sorted, disjoint, and non-empty.');
    }
    result
      ..add(start)
      ..add(end);
    previousEnd = end;
  }
  return result;
}

Map<int, String> _lowercaseMappings(Object? value) {
  final encoded = _stringMap(value, 'lowercaseMappings');
  final entries = <MapEntry<int, String>>[];
  for (final entry in encoded.entries) {
    final scalar = _hexScalar(entry.key, 'lowercaseMappings key');
    final mapped = entry.value;
    if (mapped is! String ||
        mapped.isEmpty ||
        mapped == String.fromCharCode(scalar)) {
      _fail('lowercaseMappings[${entry.key}] must be a non-identity string.');
    }
    entries.add(MapEntry<int, String>(scalar, mapped));
  }
  entries.sort((left, right) => left.key.compareTo(right.key));
  var previous = -1;
  final result = <int, String>{};
  for (final entry in entries) {
    if (entry.key <= previous) {
      _fail('lowercaseMappings must use unique scalar keys.');
    }
    result[entry.key] = entry.value;
    previous = entry.key;
  }
  return result;
}

int _hexScalar(Object? value, String label) {
  if (value is! String || !RegExp(r'^[0-9A-F]+$').hasMatch(value)) {
    _fail('$label must be uppercase hexadecimal.');
  }
  final scalar = int.parse(value, radix: 16);
  if (scalar < 0 || scalar > 0x10ffff || scalar >= 0xd800 && scalar <= 0xdfff) {
    _fail('$label is not a Unicode scalar.');
  }
  return scalar;
}

Map<String, Object?> _stringMap(Object? value, String label) {
  if (value is! Map<String, Object?>) {
    _fail('$label must be a JSON object.');
  }
  return value;
}

void _expectCount(
  Map<String, Object?> counts,
  String name,
  int actual,
  int expected,
) {
  _expect(counts[name], expected, 'counts.$name');
  if (actual != expected) {
    _fail('$name decoded count mismatch: expected $expected, got $actual.');
  }
}

void _expect(Object? actual, Object? expected, String label) {
  if (actual != expected) {
    _fail('$label mismatch: expected $expected, got $actual.');
  }
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
