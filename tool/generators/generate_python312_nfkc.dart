// Generates the exact Python 3.12.11 / Unicode 15.0.0 NFKC runtime tables.
//
// The accepted JSON is produced explicitly by
// tool/reference/export_python312_nfkc.py. Normal package use never runs
// Python and never reads the canonical JSON.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _sourcePath =
    'tool/upstream_data/python-3.12.11-unicode-15.0.0/nfkc_tables.json';
const _outputPath = 'lib/src/generated/python312_nfkc_data.dart';
const _expectedSourceSha256 =
    '3d278827be7b9a477ce3ad354ef6e5419a29f14ed25dd4668d3221e845e0122a';

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
  _expect(sourceInfo['pythonVersion'], '3.12.11', 'source.pythonVersion');
  _expect(sourceInfo['unicodeVersion'], '15.0.0', 'source.unicodeVersion');
  final normalizationForms = sourceInfo['normalizationForms'];
  if (normalizationForms is! List<Object?> ||
      normalizationForms.length != 2 ||
      normalizationForms[0] != 'NFC' ||
      normalizationForms[1] != 'NFKC') {
    _fail('source.normalizationForms must be [NFC, NFKC].');
  }

  final counts = _stringMap(root['counts'], 'counts');
  final digests = _stringMap(root['digests'], 'digests');
  final decompositions = _stringMap(root['decompositions'], 'decompositions');
  final canonicalDecompositions = _stringMap(
    root['canonicalDecompositions'],
    'canonicalDecompositions',
  );
  final combiningClasses = _stringMap(
    root['combiningClasses'],
    'combiningClasses',
  );
  final compositions = _stringMap(root['compositions'], 'compositions');
  final properties = _stringMap(root['properties'], 'properties');
  _expect(counts['decompositions'], 5857, 'counts.decompositions');
  _expect(
    counts['canonicalDecompositions'],
    2061,
    'counts.canonicalDecompositions',
  );
  _expect(counts['combiningClasses'], 922, 'counts.combiningClasses');
  _expect(counts['compositions'], 941, 'counts.compositions');
  _expect(counts['alphabeticRanges'], 659, 'counts.alphabeticRanges');
  _expect(counts['decimalDigitRanges'], 68, 'counts.decimalDigitRanges');
  _expect(counts['digitRanges'], 89, 'counts.digitRanges');
  _expect(counts['whitespaceRanges'], 10, 'counts.whitespaceRanges');
  _expect(counts['scalarDigestRecords'], 1112064, 'counts.scalarDigestRecords');
  _expect(
    counts['sequenceDigestRecords'],
    21111,
    'counts.sequenceDigestRecords',
  );

  final rendered = _render(
    sourceSha256: sourceSha256,
    scalarDigest: _requiredString(digests, 'scalarNfkcSha256'),
    sequenceDigest: _requiredString(digests, 'sequenceNfkcSha256'),
    scalarNfcDigest: _requiredString(digests, 'scalarNfcSha256'),
    sequenceNfcDigest: _requiredString(digests, 'sequenceNfcSha256'),
    propertyDigest: _requiredString(digests, 'propertySha256'),
    decompositions: decompositions,
    canonicalDecompositions: canonicalDecompositions,
    combiningClasses: combiningClasses,
    compositions: compositions,
    alphabeticRanges: _parseRanges(
      properties['alphabeticRanges'],
      'properties.alphabeticRanges',
      valued: false,
    ),
    decimalDigitRanges: _parseRanges(
      properties['decimalDigitRanges'],
      'properties.decimalDigitRanges',
      valued: true,
    ),
    digitRanges: _parseRanges(
      properties['digitRanges'],
      'properties.digitRanges',
      valued: true,
    ),
    whitespaceRanges: _parseRanges(
      properties['whitespaceRanges'],
      'properties.whitespaceRanges',
      valued: false,
    ),
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
  required String scalarDigest,
  required String sequenceDigest,
  required String scalarNfcDigest,
  required String sequenceNfcDigest,
  required String propertyDigest,
  required Map<String, Object?> decompositions,
  required Map<String, Object?> canonicalDecompositions,
  required Map<String, Object?> combiningClasses,
  required Map<String, Object?> compositions,
  required List<int> alphabeticRanges,
  required List<int> decimalDigitRanges,
  required List<int> digitRanges,
  required List<int> whitespaceRanges,
}) {
  final output = StringBuffer()
    ..writeln('// GENERATED FILE. DO NOT EDIT.')
    ..writeln('// Generator: tool/generators/generate_python312_nfkc.dart')
    ..writeln('// Canonical source: $_sourcePath')
    ..writeln('// Source SHA-256: $sourceSha256')
    ..writeln('// CPython 3.12.11, Unicode 15.0.0, NFC/NFKC')
    ..writeln()
    ..writeln('/// Unicode data version used by the pinned CPython runtime.')
    ..writeln("const String python312UnicodeVersion = '15.0.0';")
    ..writeln()
    ..writeln('/// SHA-256 of the canonical generated-table source.')
    ..writeln('const String python312NfkcSourceSha256 =')
    ..writeln("    '$sourceSha256';")
    ..writeln()
    ..writeln('/// Exhaustive scalar NFKC output digest.')
    ..writeln('const String python312NfkcScalarDigestSha256 =')
    ..writeln("    '$scalarDigest';")
    ..writeln()
    ..writeln('/// Adversarial sequence NFKC output digest.')
    ..writeln('const String python312NfkcSequenceDigestSha256 =')
    ..writeln("    '$sequenceDigest';")
    ..writeln()
    ..writeln('/// Exhaustive scalar NFC output digest.')
    ..writeln('const String python312NfcScalarDigestSha256 =')
    ..writeln("    '$scalarNfcDigest';")
    ..writeln()
    ..writeln('/// Adversarial sequence NFC output digest.')
    ..writeln('const String python312NfcSequenceDigestSha256 =')
    ..writeln("    '$sequenceNfcDigest';")
    ..writeln()
    ..writeln('/// Exhaustive Python scalar-property digest.')
    ..writeln('const String python312PropertyDigestSha256 =')
    ..writeln("    '$propertyDigest';")
    ..writeln()
    ..writeln('/// Unicode-15 decimal-digit regular-expression class.')
    ..writeln('const String python312DecimalDigitPattern =')
    ..writeln("    r'${_decimalPattern(decimalDigitRanges)}';")
    ..writeln()
    ..writeln('/// Compatibility decomposition table used by NFKC.')
    ..writeln(
      'const Map<int, String> python312NfkdDecompositions = <int, String>{',
    );
  _writeDecompositions(output, decompositions);
  output
    ..writeln('};')
    ..writeln()
    ..writeln('/// Canonical decomposition table used by NFC.')
    ..writeln(
      'const Map<int, String> python312NfdDecompositions = <int, String>{',
    );
  _writeDecompositions(output, canonicalDecompositions);
  output
    ..writeln('};')
    ..writeln()
    ..writeln('/// Nonzero canonical combining classes by scalar.')
    ..writeln(
      'const Map<int, int> python312CanonicalCombiningClasses = <int, int>{',
    );
  for (final entry in _sortedHexEntries(combiningClasses)) {
    final value = entry.value;
    if (value is! int || value <= 0 || value > 255) {
      _fail('Invalid combining class for ${entry.key}: $value.');
    }
    output.writeln('  0x${entry.key}: $value,');
  }
  output
    ..writeln('};')
    ..writeln()
    ..writeln('/// Packed canonical pair-to-composite mappings.')
    ..writeln(
      'const Map<int, int> python312CanonicalCompositions = <int, int>{',
    );
  final compositionEntries = compositions.entries.toList()
    ..sort((left, right) {
      final leftPair = _parseHexKeyPair(left.key);
      final rightPair = _parseHexKeyPair(right.key);
      return _pairKey(leftPair).compareTo(_pairKey(rightPair));
    });
  for (final entry in compositionEntries) {
    final pair = _parseHexKeyPair(entry.key);
    final composite = entry.value;
    if (composite is! String || !_isHex(composite)) {
      _fail('Invalid composition value for ${entry.key}: $composite.');
    }
    output.writeln(
      '  0x${_pairKey(pair).toRadixString(16).toUpperCase()}: '
      '0x$composite,',
    );
  }
  output
    ..writeln('};')
    ..writeln();
  _writeIntList(output, 'python312AlphabeticRanges', alphabeticRanges);
  output.writeln();
  _writeIntList(output, 'python312DecimalDigitRanges', decimalDigitRanges);
  output.writeln();
  _writeIntList(output, 'python312DigitRanges', digitRanges);
  output.writeln();
  _writeIntList(output, 'python312WhitespaceRanges', whitespaceRanges);
  return output.toString();
}

void _writeDecompositions(
  StringBuffer output,
  Map<String, Object?> decompositions,
) {
  final decompositionEntries = _sortedHexEntries(decompositions);
  for (final entry in decompositionEntries) {
    final codePoints = _parseHexSequence(entry.value, entry.key);
    final literal = _dartScalarString(codePoints);
    final line = '  0x${entry.key}: $literal,';
    if (line.length <= 80) {
      output.writeln(line);
    } else {
      output
        ..writeln('  0x${entry.key}:')
        ..writeln('      $literal,');
    }
  }
}

void _writeIntList(StringBuffer output, String name, List<int> values) {
  final description = switch (name) {
    'python312AlphabeticRanges' =>
      'Packed inclusive ranges for Python `str.isalpha`.',
    'python312DecimalDigitRanges' =>
      'Packed inclusive ranges and values for Python decimal digits.',
    'python312DigitRanges' =>
      'Packed inclusive ranges and values for Python digits.',
    'python312WhitespaceRanges' =>
      'Packed inclusive ranges for Python whitespace.',
    _ => throw StateError('Missing generated range documentation for $name.'),
  };
  output.writeln('/// $description');
  output.writeln('const List<int> $name = <int>[');
  for (final value in values) {
    output.writeln('  0x${value.toRadixString(16).toUpperCase()},');
  }
  output.writeln('];');
}

String _decimalPattern(List<int> ranges) {
  final pattern = StringBuffer('[');
  for (var index = 0; index < ranges.length; index += 3) {
    final start = ranges[index];
    final end = ranges[index + 1];
    pattern.write(_regexScalar(start));
    if (end != start) {
      pattern
        ..write('-')
        ..write(_regexScalar(end));
    }
  }
  pattern.write(']');
  return pattern.toString();
}

String _regexScalar(int codePoint) => codePoint <= 0xffff
    ? '\\u${codePoint.toRadixString(16).padLeft(4, '0')}'
    : '\\u{${codePoint.toRadixString(16)}}';

List<int> _parseRanges(Object? value, String label, {required bool valued}) {
  if (value is! List<Object?>) {
    _fail('$label must be a JSON array.');
  }
  final width = valued ? 3 : 2;
  final result = <int>[];
  var previousEnd = -1;
  for (var index = 0; index < value.length; index++) {
    final raw = value[index];
    if (raw is! List<Object?> || raw.length != width) {
      _fail('$label[$index] must contain exactly $width values.');
    }
    final startRaw = raw[0];
    final endRaw = raw[1];
    if (startRaw is! String ||
        endRaw is! String ||
        !_isHex(startRaw) ||
        !_isHex(endRaw)) {
      _fail('$label[$index] has invalid hexadecimal bounds.');
    }
    final start = int.parse(startRaw, radix: 16);
    final end = int.parse(endRaw, radix: 16);
    if (start > end || start <= previousEnd || end > 0x10ffff) {
      _fail('$label[$index] is not a sorted disjoint scalar range.');
    }
    result
      ..add(start)
      ..add(end);
    previousEnd = end;
    if (valued) {
      final startValue = raw[2];
      if (startValue is! int || startValue < 0 || startValue > 9) {
        _fail('$label[$index] has invalid start value $startValue.');
      }
      result.add(startValue);
    }
  }
  return result;
}

List<MapEntry<String, Object?>> _sortedHexEntries(Map<String, Object?> values) {
  final entries = values.entries.toList();
  for (final entry in entries) {
    if (!_isHex(entry.key)) {
      _fail('Invalid hexadecimal key: ${entry.key}.');
    }
  }
  entries.sort(
    (left, right) => int.parse(
      left.key,
      radix: 16,
    ).compareTo(int.parse(right.key, radix: 16)),
  );
  return entries;
}

List<int> _parseHexSequence(Object? value, String label) {
  if (value is! String || value.isEmpty) {
    _fail('Invalid hexadecimal sequence for $label: $value.');
  }
  final parts = value.split(' ');
  if (parts.any((part) => !_isHex(part))) {
    _fail('Invalid hexadecimal sequence for $label: $value.');
  }
  return <int>[for (final part in parts) int.parse(part, radix: 16)];
}

List<int> _parseHexKeyPair(String value) {
  final parts = value.split(' ');
  if (parts.length != 2 || parts.any((part) => !_isHex(part))) {
    _fail('Invalid composition key: $value.');
  }
  return <int>[for (final part in parts) int.parse(part, radix: 16)];
}

int _pairKey(List<int> pair) => (pair[0] << 21) | pair[1];

String _dartScalarString(List<int> codePoints) {
  final escaped = StringBuffer("'");
  for (final codePoint in codePoints) {
    if (codePoint <= 0xffff) {
      escaped.write('\\u${codePoint.toRadixString(16).padLeft(4, '0')}');
    } else {
      escaped.write('\\u{${codePoint.toRadixString(16)}}');
    }
  }
  escaped.write("'");
  return escaped.toString();
}

Map<String, Object?> _stringMap(Object? value, String label) {
  if (value is! Map<String, Object?>) {
    _fail('$label must be a JSON object.');
  }
  return value;
}

String _requiredString(Map<String, Object?> values, String key) {
  final value = values[key];
  if (value is! String || value.isEmpty) {
    _fail('$key must be a non-empty string.');
  }
  return value;
}

void _expect(Object? actual, Object expected, String label) {
  if (actual != expected) {
    _fail('$label must be $expected, got $actual.');
  }
}

bool _isHex(String value) => RegExp(r'^[0-9A-F]+$').hasMatch(value);

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
