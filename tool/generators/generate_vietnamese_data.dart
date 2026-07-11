// Deterministically embeds the pinned licensed Vietnamese cleaner mappings.
//
// Misaki source: fba1236595f2d2bf21d414ba6e57d25256afada3.
// Mapping source: v-nhandt21/Vinorm
// 577c9cd9bf499e074801b703a5fd1eaad8300d43 (MIT). See
// THIRD_PARTY_NOTICES.md. The unlicensed num2vi.py is deliberately excluded.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _upstreamCommit = 'fba1236595f2d2bf21d414ba6e57d25256afada3';
const _vinormRevision = '577c9cd9bf499e074801b703a5fd1eaad8300d43';
const _sourceRoot = 'tool/upstream_data/$_upstreamCommit/misaki/data';
const _outputPath = 'lib/src/generated/vietnamese_cleaner_json.dart';

const _sources = <_Source>[
  _Source(
    name: 'vietnameseAcronyms',
    fileName: 'vi_acronyms.json',
    sha256: '5da337cdde5231e72680fa4bf29f5dfe906f769492e9ee950ac2d73a28eba529',
    entries: 3098,
  ),
  _Source(
    name: 'vietnameseSymbols',
    fileName: 'vi_symbols.json',
    sha256: 'd963c9261f6ae0211c5941a357dff58f3599b5db98ed38e4cc722bc67ffcb728',
    entries: 62,
  ),
  _Source(
    name: 'vietnameseTeencode',
    fileName: 'vi_teencode.json',
    sha256: 'e35baf886a44a92e08c5d900abbcf921eb69efa198821e2a9de85ca8f5dfa7f3',
    entries: 482,
  ),
];

void main(List<String> arguments) {
  final check = arguments.length == 1 && arguments.single == '--check';
  if (arguments.isNotEmpty && !check) {
    stderr.writeln(
      'Usage: dart run tool/generators/generate_vietnamese_data.dart '
      '[--check]',
    );
    exitCode = 64;
    return;
  }

  final output = _generate();
  final destination = File(_outputPath);
  if (check) {
    if (!destination.existsSync() || destination.readAsStringSync() != output) {
      stderr.writeln('$_outputPath is not reproducible from pinned inputs.');
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
    final bytes = File('$_sourceRoot/${source.fileName}').readAsBytesSync();
    final actualHash = sha256.convert(bytes).toString();
    if (actualHash != source.sha256) {
      throw StateError(
        '${source.fileName} SHA-256 is $actualHash, expected ${source.sha256}.',
      );
    }
    final text = utf8.decode(bytes, allowMalformed: false);
    if (text.contains("'''")) {
      throw StateError('${source.fileName} cannot be embedded as raw text.');
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, Object?> || decoded.length != source.entries) {
      throw StateError(
        '${source.fileName} must contain exactly ${source.entries} entries.',
      );
    }
    if (decoded.entries.any(
      (entry) => entry.key.isEmpty || entry.value is! String,
    )) {
      throw StateError('${source.fileName} must map strings to strings.');
    }
    inputs.add((source, text));
  }

  final output = StringBuffer()
    ..writeln('// GENERATED FILE. DO NOT EDIT.')
    ..writeln('// Generator: tool/generators/generate_vietnamese_data.dart')
    ..writeln('// Upstream: hexgrad/misaki $_upstreamCommit (0.9.4)')
    ..writeln('// Mapping source: Vinorm $_vinormRevision (MIT)');
  for (final (source, _) in inputs) {
    output.writeln('// ${source.fileName} SHA-256: ${source.sha256}');
  }
  output
    ..writeln()
    ..writeln('// dart format off');
  for (final (source, text) in inputs) {
    output
      ..writeln('/// Pinned ${source.fileName} UTF-8 JSON payload.')
      ..writeln('const String ${source.name}Json = r\'\'\'')
      ..write(text);
    if (!text.endsWith('\n')) {
      output.writeln();
    }
    output
      ..writeln("''';")
      ..writeln();
  }
  output.writeln('// dart format on');
  return output.toString();
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
