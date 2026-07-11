// Deterministically transforms the pinned Korean g2pkc runtime data.
//
// Sources: hexgrad/misaki fba1236595f2d2bf21d414ba6e57d25256afada3,
// copied/adapted from 5Hyeons/StyleTTS2 a895e5bff1d7a22dff2f2d32dafb7c4c4e0ee4b7
// under Apache-2.0. See THIRD_PARTY_NOTICES.md.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _upstreamCommit = 'fba1236595f2d2bf21d414ba6e57d25256afada3';
const _sourceRoot = 'tool/upstream_data/$_upstreamCommit/misaki/g2pkc';
const _outputPath = 'lib/src/generated/korean_g2pkc_data.dart';
const _idiomsSha256 =
    'd49682e430bf7743715d0510a5e1b32cd902db80fcdeaea783d9abcaec3f7ac5';
const _tableSha256 =
    '61aca8535fd75f16ca71df59bc5eeab625073edfd50732fda3f12b30ccade31f';

void main(List<String> arguments) {
  final check = arguments.length == 1 && arguments.single == '--check';
  if (arguments.isNotEmpty && !check) {
    stderr.writeln(
      'Usage: dart run tool/generators/generate_korean_g2pkc_data.dart '
      '[--check]',
    );
    exitCode = 64;
    return;
  }

  final output = _generate();
  final destination = File(_outputPath);
  if (check) {
    if (!destination.existsSync() || destination.readAsStringSync() != output) {
      stderr.writeln(
        '$_outputPath is not reproducible from the pinned inputs.',
      );
      exitCode = 1;
    }
    return;
  }

  destination.parent.createSync(recursive: true);
  final temporary = File('$_outputPath.tmp');
  temporary.writeAsStringSync(output, flush: true);
  temporary.renameSync(_outputPath);
}

String _generate() {
  final idiomSource = _readSource('idioms.txt', _idiomsSha256);
  final tableSource = _readSource('table.csv', _tableSha256);
  final idioms = _parseIdioms(idiomSource);
  final tableRules = _parseTable(tableSource);
  if (idioms.length != 355 || tableRules.length != 401) {
    throw StateError(
      'Expected 355 idioms and 401 table rules, got '
      '${idioms.length} and ${tableRules.length}.',
    );
  }

  final output = StringBuffer()
    ..writeln('// GENERATED FILE. DO NOT EDIT.')
    ..writeln('// Generator: tool/generators/generate_korean_g2pkc_data.dart')
    ..writeln('// Upstream: hexgrad/misaki $_upstreamCommit (0.9.4)')
    ..writeln('// Source license/provenance: see THIRD_PARTY_NOTICES.md')
    ..writeln('// idioms.txt SHA-256: $_idiomsSha256')
    ..writeln('// table.csv SHA-256: $_tableSha256')
    ..writeln()
    ..writeln('// dart format off')
    ..writeln('/// Ordered substitutions from pinned `idioms.txt`.')
    ..writeln(
      'const List<(String, String)> koreanG2pkcIdioms = <(String, String)>[',
    );
  for (final (source, replacement) in idioms) {
    output.writeln('  (${_literal(source)}, ${_literal(replacement)}),');
  }
  output
    ..writeln('];')
    ..writeln()
    ..writeln('/// Ordered coda/onset substitutions from pinned `table.csv`.')
    ..writeln(
      'const List<(String, String, String)> koreanG2pkcTableRules = '
      '<(String, String, String)>[',
    );
  for (final (coda, onset, replacement) in tableRules) {
    output.writeln(
      '  (${_literal(coda)}, ${_literal(onset)}, ${_literal(replacement)}),',
    );
  }
  output
    ..writeln('];')
    ..writeln('// dart format on');
  return output.toString();
}

String _readSource(String fileName, String expectedHash) {
  final file = File('$_sourceRoot/$fileName');
  final bytes = file.readAsBytesSync();
  final actualHash = sha256.convert(bytes).toString();
  if (actualHash != expectedHash) {
    throw StateError(
      '$fileName SHA-256 is $actualHash, expected $expectedHash.',
    );
  }
  return utf8.decode(bytes, allowMalformed: false);
}

List<(String, String)> _parseIdioms(String source) {
  final result = <(String, String)>[];
  for (final rawLine in const LineSplitter().convert(source)) {
    final line = rawLine.split('#').first;
    final separator = line.indexOf('===');
    if (separator < 0) {
      continue;
    }
    if (line.indexOf('===', separator + 3) >= 0) {
      throw StateError('Idiom line contains more than one separator: $rawLine');
    }
    result.add((line.substring(0, separator), line.substring(separator + 3)));
  }
  return result;
}

List<(String, String, String)> _parseTable(String source) {
  final lines = const LineSplitter().convert(source);
  if (lines.length != 28) {
    throw StateError('table.csv must contain exactly 28 lines.');
  }
  final onsets = lines.first.split(',');
  if (onsets.length != 20) {
    throw StateError('table.csv must contain exactly 20 onset columns.');
  }
  final result = <(String, String, String)>[];
  for (final line in lines.skip(1)) {
    final columns = line.split(',');
    if (columns.length < onsets.length) {
      throw StateError('Malformed table.csv row: $line');
    }
    final coda = columns.first;
    for (var index = 1; index < columns.length; index++) {
      final cell = columns[index];
      if (cell.isEmpty) {
        continue;
      }
      final ruleSuffix = cell.indexOf('(');
      final replacement = ruleSuffix < 0 ? cell : cell.substring(0, ruleSuffix);
      result.add((coda, onsets[index], replacement));
    }
  }
  return result;
}

String _literal(String value) => jsonEncode(value).replaceAll(r'$', r'\$');
