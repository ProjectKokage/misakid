// Deterministically extracts the pinned PaddleSpeech/Misaki Chinese character
// mapping into a pure-Dart scalar table.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _upstreamCommit = 'fba1236595f2d2bf21d414ba6e57d25256afada3';
const _paddleSpeechCommit = 'd7bf91561d5a8a025f3cfc4bd7b28368fd98d102';
const _sourcePath =
    'tool/upstream_data/$_upstreamCommit/misaki/zh_normalization/'
    'char_convert.py';
const _sourceHash =
    '84341ec93b420a28467ccfee223d23e262f7ee0a4da00402f662c656b119e190';
const _outputPath = 'lib/src/generated/chinese_character_map.dart';

void main(List<String> arguments) {
  final check = arguments.length == 1 && arguments.single == '--check';
  if (arguments.isNotEmpty && !check) {
    stderr.writeln(
      'Usage: dart run tool/generators/generate_chinese_character_map.dart '
      '[--check]',
    );
    exitCode = 64;
    return;
  }

  final output = _generate();
  final destination = File(_outputPath);
  if (check) {
    if (!destination.existsSync() || destination.readAsStringSync() != output) {
      stderr.writeln('$_outputPath is not reproducible from the pinned input.');
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
  final bytes = File(_sourcePath).readAsBytesSync();
  final actualHash = sha256.convert(bytes).toString();
  if (actualHash != _sourceHash) {
    throw StateError(
      'char_convert.py SHA-256 is $actualHash, expected $_sourceHash.',
    );
  }
  final source = utf8.decode(bytes, allowMalformed: false);
  final simplified = _extractLiteral(source, 'simplified_charcters');
  final traditional = _extractLiteral(source, 'traditional_characters');
  if (simplified.runes.length != traditional.runes.length) {
    throw StateError('Pinned Chinese character strings have unequal lengths.');
  }
  if (simplified.contains("'''") || traditional.contains("'''")) {
    throw StateError('Pinned Chinese mappings cannot use Dart raw literals.');
  }

  final output = StringBuffer()
    ..writeAll(<String>[
      '// GENERATED FILE. DO NOT EDIT.\n',
      '// Generator: tool/generators/generate_chinese_character_map.dart\n',
      '// Upstream: hexgrad/misaki $_upstreamCommit (0.9.4)\n',
      '// Source: PaddlePaddle/PaddleSpeech $_paddleSpeechCommit (Apache-2.0)\n',
      '// char_convert.py SHA-256: $_sourceHash\n\n',
      '// dart format off\n',
      '/// Parallel simplified-character scalars from the pinned table.\n',
      "const String simplifiedChineseCharacters = r'''$simplified''';\n\n",
      '/// Parallel traditional-character scalars from the pinned table.\n',
      "const String traditionalChineseCharacters = r'''$traditional''';\n",
      '// dart format on\n',
    ]);
  return output.toString();
}

String _extractLiteral(String source, String name) {
  final prefix = "$name = '";
  final line = source
      .split('\n')
      .singleWhere(
        (candidate) => candidate.startsWith(prefix),
        orElse: () => throw StateError('Missing $name literal.'),
      );
  final body = line.substring(prefix.length, line.length - 1);
  if (!line.endsWith("'") || body.contains(r'\')) {
    throw StateError('$name is not the expected unescaped one-line literal.');
  }
  return body;
}
