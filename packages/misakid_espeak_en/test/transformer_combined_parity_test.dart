import 'dart:convert';
import 'dart:io';

import 'package:misakid_espeak_en/misakid_espeak_en.dart';
import 'package:misakid_spacy_trf_en/misakid_spacy_trf_en.dart'
    show NativeSpacyTransformerEnglishTokenizerBackend;
import 'package:test/test.dart';

void main() {
  final espeakAdapterPath =
      Platform.environment['MISAKID_ESPEAK_EN_ADAPTER_LIBRARY'];
  final espeakRuntimePath = Platform.environment['MISAKID_ESPEAK_EN_LIBRARY'];
  final espeakDataPath = Platform.environment['MISAKID_ESPEAK_EN_DATA'];
  final transformerLibraryPath =
      Platform.environment['MISAKID_SPACY_TRF_EN_LIBRARY'];
  final transformerModelPath =
      Platform.environment['MISAKID_SPACY_TRF_EN_MODEL_DIR'];
  final skipReason =
      espeakAdapterPath == null ||
          espeakRuntimePath == null ||
          espeakDataPath == null ||
          transformerLibraryPath == null ||
          transformerModelPath == null
      ? 'Set MISAKID_ESPEAK_EN_ADAPTER_LIBRARY, '
            'MISAKID_ESPEAK_EN_LIBRARY, MISAKID_ESPEAK_EN_DATA, '
            'MISAKID_SPACY_TRF_EN_LIBRARY, and '
            'MISAKID_SPACY_TRF_EN_MODEL_DIR.'
      : false;

  test(
    'real transformer tokenizer and eSpeak match all 40 accepted cases',
    () async {
      final transformer =
          await NativeSpacyTransformerEnglishTokenizerBackend.open(
            modelDirectoryPath: transformerModelPath!,
            nativeLibraryPath: transformerLibraryPath!,
          );
      try {
        final espeak = await EspeakEnglishBackend.open(
          adapterLibraryPath: espeakAdapterPath!,
          espeakLibraryPath: espeakRuntimePath!,
          dataPath: espeakDataPath!,
        );
        try {
          final capturing = _CapturingTokenizerBackend(transformer);
          final recording = _RecordingEspeakBackend(espeak);
          var caseCount = 0;
          var rawTokenCount = 0;
          var expectedCallCount = 0;

          for (final fixture in await _readFixtures()) {
            recording.calls.clear();
            final mode = fixture['mode']! as String;
            final caseId = fixture['caseId']! as String;
            final reason = '$mode/$caseId';
            final dialect = mode.startsWith('british-')
                ? EnglishDialect.british
                : EnglishDialect.american;
            final options = fixture['options']! as Map<String, Object?>;
            final version = options['version'] == '2.0'
                ? EnglishPhonemeVersion.v2
                : EnglishPhonemeVersion.legacy;
            final engine = EnglishG2pEngine(
              tokenizer: capturing,
              pronunciation: PinnedEnglishLexicon(dialect: dialect),
              fallback: EnglishEspeakFallback(
                backend: recording,
                dialect: dialect,
                phonemeVersion: version,
              ),
              phonemeVersion: version,
              unknownMarker:
                  (options['unk'] as String?) ?? defaultUnknownMarker,
              preprocessInput: options['preprocess'] != false,
            );

            final result = engine.convert(fixture['input']! as String);
            final backendInput =
                fixture['backendInput']! as Map<String, Object?>;
            final expectedRawTokens = backendInput['tokens']! as List<Object?>;
            _expectTokens(
              capturing.lastTokens,
              expectedRawTokens,
              '$reason raw',
            );
            rawTokenCount += expectedRawTokens.length;

            expect(result.phonemes, fixture['phonemes'], reason: reason);
            _expectTokens(
              result.tokens,
              fixture['tokens']! as List<Object?>,
              '$reason final',
            );

            final expectedCalls = backendInput['espeakCalls']! as List<Object?>;
            expectedCallCount += expectedCalls.length;
            expect(
              recording.calls,
              hasLength(expectedCalls.length),
              reason: '$reason eSpeak calls',
            );
            for (var index = 0; index < expectedCalls.length; index++) {
              final expected = expectedCalls[index]! as Map<String, Object?>;
              final actual = recording.calls[index];
              final callReason = '$reason eSpeak call $index';
              expect(actual.text, expected['text'], reason: callReason);
              expect(actual.dialect, dialect, reason: callReason);
              expect(
                actual.rawPhones,
                expected['rawPhones'],
                reason: callReason,
              );
            }
            caseCount++;
          }

          expect(caseCount, 40);
          expect(rawTokenCount, 86);
          expect(expectedCallCount, 50);
        } finally {
          espeak.close();
        }
      } finally {
        transformer.close();
      }
    },
    tags: <String>['native', 'provisioned'],
    skip: skipReason,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

final class _CapturingTokenizerBackend implements EnglishTokenizerBackend {
  _CapturingTokenizerBackend(this._delegate);

  final EnglishTokenizerBackend _delegate;
  List<MisakiToken> lastTokens = const <MisakiToken>[];

  @override
  BackendInfo get info => _delegate.info;

  @override
  List<MisakiToken> tokenize(EnglishPreprocessResult input) {
    lastTokens = _delegate.tokenize(input);
    return lastTokens;
  }
}

final class _RecordedEspeakCall {
  const _RecordedEspeakCall({
    required this.text,
    required this.dialect,
    required this.rawPhones,
  });

  final String text;
  final EnglishDialect dialect;
  final String? rawPhones;
}

final class _RecordingEspeakBackend implements EnglishEspeakBackend {
  _RecordingEspeakBackend(this._delegate);

  final EspeakEnglishBackend _delegate;
  final List<_RecordedEspeakCall> calls = <_RecordedEspeakCall>[];

  @override
  BackendInfo get info => _delegate.info;

  @override
  String? phonemize(String text, {required EnglishDialect dialect}) {
    final rawPhones = _delegate.phonemize(text, dialect: dialect);
    calls.add(
      _RecordedEspeakCall(text: text, dialect: dialect, rawPhones: rawPhones),
    );
    return rawPhones;
  }
}

void _expectTokens(
  List<MisakiToken>? actual,
  List<Object?> expected,
  String reason,
) {
  expect(actual, isNotNull, reason: reason);
  expect(actual, hasLength(expected.length), reason: reason);
  for (var index = 0; index < expected.length; index++) {
    final record = expected[index]! as Map<String, Object?>;
    final metadata = record['_']! as Map<String, Object?>;
    final token = actual![index];
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

Future<List<Map<String, Object?>>> _readFixtures() async {
  final root = Directory(
    '../../test/fixtures/upstream/'
    'fba1236595f2d2bf21d414ba6e57d25256afada3',
  );
  final rows = <Map<String, Object?>>[];
  for (final name in <String>[
    'en_american_trf_espeak_fallback.jsonl',
    'en_british_trf_espeak_fallback.jsonl',
  ]) {
    await for (final line in File(
      '${root.path}/$name',
    ).openRead().transform(utf8.decoder).transform(const LineSplitter())) {
      rows.add(jsonDecode(line) as Map<String, Object?>);
    }
  }
  return List<Map<String, Object?>>.unmodifiable(rows);
}
