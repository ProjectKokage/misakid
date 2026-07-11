import 'dart:convert';
import 'dart:io';

import 'package:misakid_espeak_en/misakid_espeak_en.dart';
import 'package:misakid_spacy_en/misakid_spacy_en.dart';
import 'package:test/test.dart';

void main() {
  final adapterPath = Platform.environment['MISAKID_ESPEAK_EN_ADAPTER_LIBRARY'];
  final runtimePath = Platform.environment['MISAKID_ESPEAK_EN_LIBRARY'];
  final dataPath = Platform.environment['MISAKID_ESPEAK_EN_DATA'];
  final modelPath = Platform.environment['MISAKID_SPACY_EN_MODEL_DIR'];
  final skipReason =
      adapterPath == null ||
          runtimePath == null ||
          dataPath == null ||
          modelPath == null
      ? 'Set MISAKID_ESPEAK_EN_ADAPTER_LIBRARY, '
            'MISAKID_ESPEAK_EN_LIBRARY, MISAKID_ESPEAK_EN_DATA, and '
            'MISAKID_SPACY_EN_MODEL_DIR.'
      : false;

  test(
    'real small-model tokenizer and eSpeak match all 40 accepted cases',
    () async {
      final fixtures = await _readFixtures();
      final tokenizer = await PureDartSpacyEnglishTokenizerBackend.open(
        modelDirectoryPath: modelPath!,
      );
      final native = await EspeakEnglishBackend.open(
        adapterLibraryPath: adapterPath!,
        espeakLibraryPath: runtimePath!,
        dataPath: dataPath!,
      );
      final recording = _RecordingEspeakBackend(native);
      try {
        var expectedCallCount = 0;
        for (final fixture in fixtures) {
          recording.calls.clear();
          final dialect = fixture['mode'] == 'american-espeak-fallback'
              ? EnglishDialect.american
              : EnglishDialect.british;
          final options = fixture['options']! as Map<String, Object?>;
          final version = options['version'] == '2.0'
              ? EnglishPhonemeVersion.v2
              : EnglishPhonemeVersion.legacy;
          final engine = EnglishG2pEngine(
            tokenizer: tokenizer,
            pronunciation: PinnedEnglishLexicon(dialect: dialect),
            fallback: EnglishEspeakFallback(
              backend: recording,
              dialect: dialect,
              phonemeVersion: version,
            ),
            phonemeVersion: version,
            unknownMarker: options['unk'] as String? ?? '❓',
            preprocessInput: options['preprocess'] as bool? ?? true,
          );
          final result = engine.convert(fixture['input']! as String);
          final reason = '${fixture['mode']}/${fixture['caseId']}';
          expect(result.phonemes, fixture['phonemes'], reason: reason);
          _expectTokens(result.tokens, fixture['tokens'], reason);

          final backendInput = fixture['backendInput']! as Map<String, Object?>;
          final expectedCalls = backendInput['espeakCalls']! as List<Object?>;
          expectedCallCount += expectedCalls.length;
          expect(
            recording.calls,
            hasLength(expectedCalls.length),
            reason: reason,
          );
          for (var index = 0; index < expectedCalls.length; index++) {
            final expected = expectedCalls[index]! as Map<String, Object?>;
            final actual = recording.calls[index];
            final callReason = '$reason eSpeak call $index';
            expect(actual.text, expected['text'], reason: callReason);
            expect(actual.dialect, dialect, reason: callReason);
            expect(actual.phones, expected['rawPhones'], reason: callReason);
          }
        }
        expect(expectedCallCount, 58);
      } finally {
        native.close();
      }
    },
    tags: 'native',
    skip: skipReason,
  );
}

final class _RecordedEspeakCall {
  const _RecordedEspeakCall({
    required this.text,
    required this.dialect,
    required this.phones,
  });

  final String text;
  final EnglishDialect dialect;
  final String? phones;
}

final class _RecordingEspeakBackend implements EnglishEspeakBackend {
  _RecordingEspeakBackend(this._delegate);

  final EspeakEnglishBackend _delegate;
  final List<_RecordedEspeakCall> calls = <_RecordedEspeakCall>[];

  @override
  BackendInfo get info => _delegate.info;

  @override
  String? phonemize(String text, {required EnglishDialect dialect}) {
    final phones = _delegate.phonemize(text, dialect: dialect);
    calls.add(
      _RecordedEspeakCall(text: text, dialect: dialect, phones: phones),
    );
    return phones;
  }
}

void _expectTokens(List<MisakiToken>? actual, Object? raw, String reason) {
  final expected = raw! as List<Object?>;
  expect(actual, isNotNull, reason: reason);
  expect(actual, hasLength(expected.length), reason: reason);
  for (var index = 0; index < expected.length; index++) {
    final expectedToken = expected[index]! as Map<String, Object?>;
    final expectedMetadata = expectedToken['_']! as Map<String, Object?>;
    final token = actual![index];
    final metadata = token.metadata! as EnglishTokenMetadata;
    final tokenReason = '$reason token $index';
    expect(token.text, expectedToken['text'], reason: tokenReason);
    expect(token.tag, expectedToken['tag'], reason: tokenReason);
    expect(token.whitespace, expectedToken['whitespace'], reason: tokenReason);
    expect(token.phonemes, expectedToken['phonemes'], reason: tokenReason);
    expect(
      token.startTimeSeconds,
      expectedToken['start_ts'],
      reason: tokenReason,
    );
    expect(token.endTimeSeconds, expectedToken['end_ts'], reason: tokenReason);
    expect(metadata.isHead, expectedMetadata['is_head'], reason: tokenReason);
    expect(metadata.alias, expectedMetadata['alias'], reason: tokenReason);
    expect(metadata.stress, expectedMetadata['stress'], reason: tokenReason);
    expect(
      metadata.currency,
      expectedMetadata['currency'],
      reason: tokenReason,
    );
    expect(
      metadata.numberFlags,
      expectedMetadata['num_flags'],
      reason: tokenReason,
    );
    expect(
      metadata.precededBySpace,
      expectedMetadata['prespace'],
      reason: tokenReason,
    );
    expect(
      metadata.rating,
      expectedToken['rating'] ?? expectedMetadata['rating'],
      reason: tokenReason,
    );
  }
}

Future<List<Map<String, Object?>>> _readFixtures() async {
  final directory = Directory(
    '../../test/fixtures/upstream/'
    'fba1236595f2d2bf21d414ba6e57d25256afada3',
  );
  final rows = <Map<String, Object?>>[];
  for (final name in <String>[
    'en_american_espeak_fallback.jsonl',
    'en_british_espeak_fallback.jsonl',
  ]) {
    await for (final line in File(
      '${directory.path}/$name',
    ).openRead().transform(utf8.decoder).transform(const LineSplitter())) {
      rows.add(jsonDecode(line) as Map<String, Object?>);
    }
  }
  return rows;
}
