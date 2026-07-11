// Generates exact CPython 3.11 / Unicode 14 lower/upper runtime tables.
//
// The accepted JSON is produced explicitly by
// tool/reference/export_python311_case.py. Normal package use never runs
// Python and never reads the canonical JSON.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _sourcePath =
    'tool/upstream_data/python-3.11-unicode-14.0.0/case_maps.json';
const _outputPath = 'lib/src/generated/python311_case_data.dart';
const _expectedSourceSha256 =
    'f6ab81284aad17b08281af1e2619efca74aec171dfb1701796ea327b3810d9b1';

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
  if (decoded is! Map<String, Object?>) {
    _fail('Canonical source root must be a JSON object.');
  }
  final root = decoded;
  _expect(root['schemaVersion'], 1, 'schemaVersion');
  final sourceInfo = _stringMap(root['source'], 'source');
  _expect(sourceInfo['implementation'], 'CPython', 'source.implementation');
  _expect(sourceInfo['pythonVersion'], '3.11.15', 'source.pythonVersion');
  _expect(sourceInfo['unicodeVersion'], '14.0.0', 'source.unicodeVersion');
  final operations = sourceInfo['operations'];
  if (operations is! List<Object?> ||
      operations.length != 4 ||
      operations[0] != 'str.lower' ||
      operations[1] != 'str.upper' ||
      operations[2] != 'str.isspace' ||
      operations[3] != 'Final_Sigma') {
    _fail(
      'source.operations must identify lower, upper, whitespace, and '
      'Final_Sigma.',
    );
  }

  final counts = _stringMap(root['counts'], 'counts');
  _expect(counts['scalarRecords'], 1112064, 'counts.scalarRecords');
  _expect(counts['lowercaseMappings'], 1433, 'counts.lowercaseMappings');
  _expect(counts['uppercaseMappings'], 1525, 'counts.uppercaseMappings');
  _expect(counts['casedRanges'], 149, 'counts.casedRanges');
  _expect(counts['caseIgnorableRanges'], 427, 'counts.caseIgnorableRanges');
  _expect(counts['whitespaceRanges'], 10, 'counts.whitespaceRanges');
  final digests = _stringMap(root['digests'], 'digests');
  final lower = _parseMappings(root['lowercaseMappings'], 'lowercaseMappings');
  final upper = _parseMappings(root['uppercaseMappings'], 'uppercaseMappings');
  if (lower.length != 1433 || upper.length != 1525) {
    _fail('Case mapping counts do not match their declared values.');
  }
  final cased = _parseRanges(root['casedRanges'], 'casedRanges');
  final ignorable = _parseRanges(
    root['caseIgnorableRanges'],
    'caseIgnorableRanges',
  );
  final whitespace = _parseRanges(root['whitespaceRanges'], 'whitespaceRanges');
  if (cased.length != 149 * 2 ||
      ignorable.length != 427 * 2 ||
      whitespace.length != 10 * 2) {
    _fail('Case-property range counts do not match their declared values.');
  }

  final rendered = _render(
    sourceSha256: sourceSha256,
    lowercaseDigest: _requiredString(digests, 'lowercaseSha256'),
    uppercaseDigest: _requiredString(digests, 'uppercaseSha256'),
    propertiesDigest: _requiredString(digests, 'propertiesSha256'),
    lower: lower,
    upper: upper,
    cased: cased,
    ignorable: ignorable,
    whitespace: whitespace,
  );
  final output = File(_outputPath);
  if (checkOnly) {
    if (!output.existsSync() || output.readAsStringSync() != rendered) {
      _fail('Generated output differs: run this generator without --check.');
    }
    stdout.writeln('verified $_outputPath');
    return;
  }
  output.writeAsStringSync(rendered);
  stdout.writeln('wrote $_outputPath');
}

String _render({
  required String sourceSha256,
  required String lowercaseDigest,
  required String uppercaseDigest,
  required String propertiesDigest,
  required Map<int, List<int>> lower,
  required Map<int, List<int>> upper,
  required List<int> cased,
  required List<int> ignorable,
  required List<int> whitespace,
}) {
  final output = StringBuffer()
    ..writeln('// GENERATED FILE. DO NOT EDIT.')
    ..writeln('// Generator: tool/generators/generate_python311_case.dart')
    ..writeln('// Canonical source: $_sourcePath')
    ..writeln('// Source SHA-256: $sourceSha256')
    ..writeln('// CPython 3.11.15, Unicode 14.0.0 case behavior')
    ..writeln()
    ..writeln('/// Unicode data version used by the Vietnamese oracle.')
    ..writeln("const String python311CaseUnicodeVersion = '14.0.0';")
    ..writeln()
    ..writeln('/// SHA-256 of the canonical generated-table source.')
    ..writeln('const String python311CaseSourceSha256 =')
    ..writeln("    '$sourceSha256';")
    ..writeln()
    ..writeln('/// Exhaustive scalar lowercase-output digest.')
    ..writeln('const String python311LowercaseDigestSha256 =')
    ..writeln("    '$lowercaseDigest';")
    ..writeln()
    ..writeln('/// Exhaustive scalar uppercase-output digest.')
    ..writeln('const String python311UppercaseDigestSha256 =')
    ..writeln("    '$uppercaseDigest';")
    ..writeln()
    ..writeln('/// Exhaustive Cased/Case_Ignorable property digest.')
    ..writeln('const String python311CasePropertiesDigestSha256 =')
    ..writeln("    '$propertiesDigest';")
    ..writeln();
  _writeMap(output, 'python311LowercaseMappings', lower, 'lowercase');
  output.writeln();
  _writeMap(output, 'python311UppercaseMappings', upper, 'uppercase');
  output.writeln();
  _writeRanges(output, 'python311CasedRanges', cased, 'Cased');
  output.writeln();
  _writeRanges(
    output,
    'python311CaseIgnorableRanges',
    ignorable,
    'Case_Ignorable',
  );
  output.writeln();
  _writeRanges(output, 'python311WhitespaceRanges', whitespace, 'Whitespace');
  return output.toString();
}

void _writeMap(
  StringBuffer output,
  String name,
  Map<int, List<int>> values,
  String operation,
) {
  output
    ..writeln('/// Non-identity Python `$operation` mappings by scalar.')
    ..writeln('const Map<int, String> $name = <int, String>{');
  for (final entry in values.entries) {
    output.writeln(
      '  0x${entry.key.toRadixString(16).toUpperCase()}: '
      '${_dartScalarString(entry.value)},',
    );
  }
  output.writeln('};');
}

void _writeRanges(
  StringBuffer output,
  String name,
  List<int> values,
  String property,
) {
  output
    ..writeln('/// Packed inclusive Unicode `$property` ranges.')
    ..writeln('const List<int> $name = <int>[');
  for (final value in values) {
    output.writeln('  0x${value.toRadixString(16).toUpperCase()},');
  }
  output.writeln('];');
}

Map<int, List<int>> _parseMappings(Object? value, String label) {
  final source = _stringMap(value, label);
  final entries = <MapEntry<int, List<int>>>[];
  for (final entry in source.entries) {
    if (!_isHex(entry.key)) {
      _fail('$label contains invalid hexadecimal key ${entry.key}.');
    }
    final codePoint = int.parse(entry.key, radix: 16);
    if (!_isScalar(codePoint)) {
      _fail('$label contains invalid scalar ${entry.key}.');
    }
    final raw = entry.value;
    if (raw is! String || raw.isEmpty) {
      _fail('$label.${entry.key} must be a hexadecimal sequence.');
    }
    final mapped = <int>[];
    for (final part in raw.split(' ')) {
      if (!_isHex(part)) {
        _fail('$label.${entry.key} contains invalid scalar $part.');
      }
      final scalar = int.parse(part, radix: 16);
      if (!_isScalar(scalar)) {
        _fail('$label.${entry.key} contains invalid scalar $part.');
      }
      mapped.add(scalar);
    }
    if (mapped.length == 1 && mapped.single == codePoint) {
      _fail('$label.${entry.key} is an identity mapping.');
    }
    entries.add(MapEntry<int, List<int>>(codePoint, mapped));
  }
  entries.sort((left, right) => left.key.compareTo(right.key));
  return <int, List<int>>{for (final entry in entries) entry.key: entry.value};
}

List<int> _parseRanges(Object? value, String label) {
  if (value is! List<Object?>) {
    _fail('$label must be a JSON array.');
  }
  final result = <int>[];
  var previousEnd = -1;
  for (var index = 0; index < value.length; index++) {
    final raw = value[index];
    if (raw is! List<Object?> || raw.length != 2) {
      _fail('$label[$index] must contain two hexadecimal bounds.');
    }
    final startRaw = raw[0];
    final endRaw = raw[1];
    if (startRaw is! String ||
        endRaw is! String ||
        !_isHex(startRaw) ||
        !_isHex(endRaw)) {
      _fail('$label[$index] has invalid bounds.');
    }
    final start = int.parse(startRaw, radix: 16);
    final end = int.parse(endRaw, radix: 16);
    if (!_isScalar(start) ||
        !_isScalar(end) ||
        start > end ||
        start <= previousEnd) {
      _fail('$label[$index] is not a sorted disjoint scalar range.');
    }
    result
      ..add(start)
      ..add(end);
    previousEnd = end;
  }
  return result;
}

String _dartScalarString(List<int> codePoints) {
  final output = StringBuffer("'");
  for (final codePoint in codePoints) {
    output.write(
      codePoint <= 0xffff
          ? '\\u${codePoint.toRadixString(16).padLeft(4, '0')}'
          : '\\u{${codePoint.toRadixString(16)}}',
    );
  }
  output.write("'");
  return output.toString();
}

Map<String, Object?> _stringMap(Object? value, String label) {
  if (value is! Map<String, Object?>) {
    _fail('$label must be a JSON object.');
  }
  return value;
}

String _requiredString(Map<String, Object?> values, String key) {
  final value = values[key];
  if (value is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    _fail('$key must be a lowercase SHA-256 string.');
  }
  return value;
}

bool _isHex(String value) =>
    value.isNotEmpty && RegExp(r'^[0-9A-F]+$').hasMatch(value);

bool _isScalar(int value) =>
    value >= 0 && value <= 0x10ffff && (value < 0xd800 || value > 0xdfff);

void _expect(Object? actual, Object expected, String label) {
  if (actual != expected) {
    _fail('$label must be $expected, got $actual.');
  }
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
