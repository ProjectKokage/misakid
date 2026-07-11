// Deterministically embeds the pinned English lexicons for pure-Dart loading.
//
// Source: hexgrad/misaki fba1236595f2d2bf21d414ba6e57d25256afada3.
// Author-published dataset: hexgrad/misaki
// b65a6b4398e053983b9c360f0682b720e362859d (Apache-2.0).

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _upstreamCommit = 'fba1236595f2d2bf21d414ba6e57d25256afada3';
const _datasetRevision = 'b65a6b4398e053983b9c360f0682b720e362859d';
const _outputPath = 'lib/src/generated/english_lexicon_json.dart';
const _sourceRoot = 'tool/upstream_data/$_upstreamCommit/misaki/data';

const _sources = <_Source>[
  _Source(
    name: 'gbGold',
    fileName: 'gb_gold.json',
    sha256: '29e62f4b60261c88f7f3c2c7811ca3825978948090b72d2b27d565b729282f71',
    entries: 87352,
  ),
  _Source(
    name: 'gbSilver',
    fileName: 'gb_silver.json',
    sha256: '48131e2d92ccc41655f4543e87e0f938e71463eb5a54be7f0693bb712ebb6bce',
    entries: 109766,
  ),
  _Source(
    name: 'usGold',
    fileName: 'us_gold.json',
    sha256: 'dc414872a49a28ae6c141463d502fd945f3b2fde040484fdc47d00cc4612686f',
    entries: 90201,
  ),
  _Source(
    name: 'usSilver',
    fileName: 'us_silver.json',
    sha256: 'de8f67be911bb6c659187b4a65fd966b6a30e56350e0f790d763210b053ac475',
    entries: 93361,
  ),
];

void main(List<String> arguments) {
  final check = arguments.length == 1 && arguments.single == '--check';
  if (arguments.isNotEmpty && !check) {
    stderr.writeln(
      'Usage: dart run tool/generators/generate_english_lexicons.dart '
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
  final inputs = <(_Source, String)>[];
  for (final source in _sources) {
    final file = File('$_sourceRoot/${source.fileName}');
    final bytes = file.readAsBytesSync();
    final actualHash = sha256.convert(bytes).toString();
    if (actualHash != source.sha256) {
      throw StateError(
        '${source.fileName} SHA-256 is $actualHash, expected ${source.sha256}.',
      );
    }
    final text = utf8.decode(bytes, allowMalformed: false);
    if (text.contains("'''")) {
      throw StateError(
        '${source.fileName} cannot be embedded as a raw string.',
      );
    }
    _validateJson(source, text);
    inputs.add((source, text));
  }

  final output = StringBuffer()
    ..writeln('// GENERATED FILE. DO NOT EDIT.')
    ..writeln('// Generator: tool/generators/generate_english_lexicons.dart')
    ..writeln('// Upstream: hexgrad/misaki $_upstreamCommit (0.9.4)')
    ..writeln('// Dataset: hexgrad/misaki $_datasetRevision (Apache-2.0)');
  for (final (source, _) in inputs) {
    output.writeln('// ${source.fileName} SHA-256: ${source.sha256}');
  }
  output
    ..writeln()
    ..writeln('// dart format off');
  for (final (source, text) in inputs) {
    output
      ..writeln('/// Pinned ${source.fileName} UTF-8 JSON payload.')
      ..writeln('const String ${source.name}LexiconJson = r\'\'\'')
      ..write(text);
    if (!text.endsWith('\n')) {
      output.writeln();
    }
    output.writeln("''';");
    output.writeln();
  }
  output.writeln('// dart format on');
  return output.toString();
}

void _validateJson(_Source source, String text) {
  final decoded = jsonDecode(text);
  if (decoded is! Map<String, Object?> || decoded.length != source.entries) {
    throw StateError(
      '${source.fileName} must contain exactly ${source.entries} entries.',
    );
  }
  for (final MapEntry(key: key, value: value) in decoded.entries) {
    if (value is String) {
      continue;
    }
    if (value is! Map<String, Object?> || !value.containsKey('DEFAULT')) {
      throw StateError('${source.fileName} has malformed entry $key.');
    }
    if (value.values.any((item) => item != null && item is! String)) {
      throw StateError('${source.fileName} has a non-string value at $key.');
    }
  }
}

final class _Source {
  const _Source({
    required this.name,
    required this.fileName,
    required this.sha256,
    required this.entries,
  });

  final String name;
  final String fileName;
  final String sha256;
  final int entries;
}
