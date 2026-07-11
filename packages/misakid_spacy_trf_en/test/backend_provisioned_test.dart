import 'dart:convert';
import 'dart:io';

import 'package:misakid_spacy_trf_en/misakid_spacy_trf_en.dart';
import 'package:test/test.dart';

void main() {
  final libraryPath = Platform.environment['MISAKID_SPACY_TRF_EN_LIBRARY'];
  final modelDirectory = Platform.environment['MISAKID_SPACY_TRF_EN_MODEL_DIR'];
  final fixtureRoot =
      Platform.environment['MISAKID_SPACY_TRF_EN_FIXTURES'] ??
      '../../test/fixtures/upstream/'
          'fba1236595f2d2bf21d414ba6e57d25256afada3';
  final skipReason = libraryPath == null || modelDirectory == null
      ? 'Set MISAKID_SPACY_TRF_EN_LIBRARY and '
            'MISAKID_SPACY_TRF_EN_MODEL_DIR.'
      : false;

  group(
    'provisioned native English transformer backend',
    () {
      late NativeSpacyTransformerEnglishTokenizerBackend backend;

      setUpAll(() async {
        backend = await NativeSpacyTransformerEnglishTokenizerBackend.open(
          modelDirectoryPath: modelDirectory!,
          nativeLibraryPath: libraryPath!,
        );
      });

      tearDownAll(() => backend.close());

      test('reports exact model, graph, and native identities', () {
        expect(backend.info.name, 'native-accelerate-spacy-en-core-web-trf');
        expect(backend.info.version, '3.8.0');
        expect(
          backend.info.details['implementation'],
          'dart-byte-bpe+native-accelerate',
        );
        expect(backend.info.details['platform'], 'macos-arm64');
        expect(
          backend.info.details['modelSha256'],
          '2b7061c623f424486e5dddcff79276927127cee339cc6a9d26d87837c3e6074a',
        );
        expect(spacyTransformerTagLabels, hasLength(49));
        expect(spacyTransformerTagLabels[23], 'NNP');
      });

      test(
        'matches all 116 transformer streams, results, and fallback calls',
        () async {
          var caseCount = 0;
          var rawTokenCount = 0;
          var fallbackCallCount = 0;
          for (final fixture in await _readFixtures(fixtureRoot)) {
            final caseId = fixture['caseId']! as String;
            final mode = fixture['mode']! as String;
            final reason = '$mode/$caseId';
            final options = fixture['options']! as Map<String, Object?>;
            final dialect = mode.startsWith('british-')
                ? EnglishDialect.british
                : EnglishDialect.american;
            final version = options['version'] == '2.0'
                ? EnglishPhonemeVersion.v2
                : EnglishPhonemeVersion.legacy;
            final backendInput =
                fixture['backendInput']! as Map<String, Object?>;
            final calls = backendInput['espeakCalls'] as List<Object?>?;
            final replay = calls == null
                ? null
                : _FixtureEspeakBackend(calls, dialect);
            final capturing = _CapturingTokenizerBackend(backend);
            final engine = EnglishG2pEngine(
              tokenizer: capturing,
              pronunciation: PinnedEnglishLexicon(dialect: dialect),
              fallback: replay == null
                  ? null
                  : EnglishEspeakFallback(
                      backend: replay,
                      dialect: dialect,
                      phonemeVersion: version,
                    ),
              phonemeVersion: version,
              unknownMarker:
                  (options['unk'] as String?) ?? defaultUnknownMarker,
              preprocessInput: options['preprocess'] != false,
            );

            final actual = engine.convert(fixture['input']! as String);
            final expectedRaw = backendInput['tokens']! as List<Object?>;
            _expectTokens(capturing.lastTokens, expectedRaw, '$reason raw');
            rawTokenCount += expectedRaw.length;
            expect(actual.phonemes, fixture['phonemes'], reason: reason);
            _expectTokens(
              actual.tokens!,
              fixture['tokens']! as List<Object?>,
              '$reason final',
            );
            replay?.expectComplete(reason);
            fallbackCallCount += calls?.length ?? 0;
            caseCount++;
          }
          expect(caseCount, 116);
          expect(rawTokenCount, 2278);
          expect(fallbackCallCount, 50);
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    },
    tags: 'provisioned',
    skip: skipReason,
  );
}

final class _CapturingTokenizerBackend implements EnglishTokenizerBackend {
  _CapturingTokenizerBackend(this.delegate);

  final EnglishTokenizerBackend delegate;
  List<MisakiToken> lastTokens = const <MisakiToken>[];

  @override
  BackendInfo get info => delegate.info;

  @override
  List<MisakiToken> tokenize(EnglishPreprocessResult input) {
    lastTokens = delegate.tokenize(input);
    return lastTokens;
  }
}

final class _FixtureEspeakBackend implements EnglishEspeakBackend {
  _FixtureEspeakBackend(this.calls, this.dialect);

  final List<Object?> calls;
  final EnglishDialect dialect;
  var _index = 0;

  @override
  BackendInfo get info =>
      BackendInfo(name: 'accepted-espeak-call-replay', version: '1.52.0');

  @override
  String? phonemize(String text, {required EnglishDialect dialect}) {
    expect(dialect, this.dialect);
    expect(_index, lessThan(calls.length), reason: 'unexpected eSpeak call');
    final call = calls[_index++]! as Map<String, Object?>;
    expect(text, call['text'], reason: 'eSpeak call ${_index - 1}');
    return call['rawPhones'] as String?;
  }

  void expectComplete(String reason) {
    expect(_index, calls.length, reason: '$reason eSpeak calls');
  }
}

Future<List<Map<String, Object?>>> _readFixtures(String root) async {
  final rows = <Map<String, Object?>>[];
  for (final name in <String>[
    'en_american_trf_no_fallback.jsonl',
    'en_british_trf_no_fallback.jsonl',
    'en_american_trf_espeak_fallback.jsonl',
    'en_british_trf_espeak_fallback.jsonl',
  ]) {
    await for (final line in File(
      '$root/$name',
    ).openRead().transform(utf8.decoder).transform(const LineSplitter())) {
      rows.add(jsonDecode(line) as Map<String, Object?>);
    }
  }
  return List<Map<String, Object?>>.unmodifiable(rows);
}

void _expectTokens(
  List<MisakiToken> actual,
  List<Object?> expected,
  String reason,
) {
  expect(actual, hasLength(expected.length), reason: reason);
  for (var index = 0; index < expected.length; index++) {
    final record = expected[index]! as Map<String, Object?>;
    final metadata = record['_']! as Map<String, Object?>;
    final token = actual[index];
    final details = token.metadata! as EnglishTokenMetadata;
    final tokenReason = '$reason token $index';
    expect(token.text, record['text'], reason: tokenReason);
    expect(token.tag, record['tag'], reason: tokenReason);
    expect(token.whitespace, record['whitespace'], reason: tokenReason);
    expect(token.phonemes, record['phonemes'], reason: tokenReason);
    expect(token.startTimeSeconds, record['start_ts'], reason: tokenReason);
    expect(token.endTimeSeconds, record['end_ts'], reason: tokenReason);
    expect(details.isHead, metadata['is_head'], reason: tokenReason);
    expect(details.alias, metadata['alias'], reason: tokenReason);
    expect(details.stress, metadata['stress'], reason: tokenReason);
    expect(details.currency, metadata['currency'], reason: tokenReason);
    expect(details.numberFlags, metadata['num_flags'], reason: tokenReason);
    expect(details.precededBySpace, metadata['prespace'], reason: tokenReason);
    expect(
      details.rating,
      record['rating'] ?? metadata['rating'],
      reason: tokenReason,
    );
  }
}
