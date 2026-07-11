import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:misakid_spacy_en/misakid_spacy_en.dart';
import 'package:test/test.dart';

void main() {
  final modelDirectory =
      Platform.environment['MISAKID_SPACY_EN_MODEL_DIR'] ??
      Platform.environment['MISAKID_SPACY_EN_MODEL'];
  final fixtureRoot =
      Platform.environment['MISAKID_SPACY_EN_FIXTURES'] ??
      '../../test/fixtures/upstream/'
          'fba1236595f2d2bf21d414ba6e57d25256afada3';
  final skipReason = modelDirectory == null
      ? 'Set MISAKID_SPACY_EN_MODEL_DIR to en_core_web_sm-3.8.0.'
      : false;

  group(
    'provisioned pure-Dart English small-model backend',
    () {
      late PureDartSpacyEnglishTokenizerBackend backend;
      late PureDartSpacyEnglishTokenizerBackend byteBackend;

      setUpAll(() async {
        backend = await PureDartSpacyEnglishTokenizerBackend.open(
          modelDirectoryPath: modelDirectory!,
        );
        final tokenizer = File('$modelDirectory/tokenizer').readAsBytesSync();
        final lookups = File(
          '$modelDirectory/vocab/lookups.bin',
        ).readAsBytesSync();
        final tok2vec = File('$modelDirectory/tok2vec/model').readAsBytesSync();
        final tagger = File('$modelDirectory/tagger/model').readAsBytesSync();
        byteBackend = PureDartSpacyEnglishTokenizerBackend.fromResources(
          tokenizerBytes: tokenizer,
          vocabLookupsBytes: lookups,
          tok2vecModelBytes: tok2vec,
          taggerModelBytes: tagger,
        );
        for (final bytes in <Uint8List>[tokenizer, lookups, tok2vec, tagger]) {
          bytes.fillRange(0, bytes.length, 0);
        }
      });

      test('reports the exact immutable model identities', () {
        expect(backend.info.name, 'pure-dart-spacy-en-core-web-sm');
        expect(backend.info.version, '3.8.0');
        expect(backend.info.details['implementation'], 'pure-dart');
        expect(
          backend.info.details['tokenizerSha256'],
          spacyEnglishTokenizerSha256,
        );
        expect(
          backend.info.details['tok2vecModelSha256'],
          spacyEnglishTok2vecModelSha256,
        );
      });

      test(
        'byte resources exactly match path loading after source mutation',
        () {
          expect(byteBackend.info.name, backend.info.name);
          expect(byteBackend.info.version, backend.info.version);
          expect(byteBackend.info.details, backend.info.details);
          for (final text in <String>[
            'Hello world.',
            '[hello](/custom/) world',
            '10 buses\tarrived',
          ]) {
            final input = const EnglishInlinePreprocessor().preprocess(text);
            expect(
              _tokenProjection(byteBackend.tokenize(input)),
              _tokenProjection(backend.tokenize(input)),
              reason: text,
            );
          }
        },
      );

      test(
        'tokenizer-only boundary assembles tags and inline controls',
        () async {
          final tokenizer = await PureDartSpacyEnglishTokenizer.open(
            modelDirectoryPath: modelDirectory!,
          );
          final input = const EnglishInlinePreprocessor().preprocess(
            '[hello](/custom/) world',
          );
          final tokenization = tokenizer.tokenize(input);
          expect(
            tokenization.tokens.map(
              (token) => (token.text, token.whitespace, token.isSpace),
            ),
            <(String, String, bool)>[
              ('hello', ' ', false),
              ('world', '', false),
            ],
          );
          final assembled = tokenizer.assembleTagged(
            input: input,
            tokenization: tokenization,
            tags: const <String>['UH', 'NN'],
          );
          expect(assembled.map((token) => token.tag), <String>['UH', 'NN']);
          expect(assembled.first.phonemes, 'custom');
          expect((assembled.first.metadata! as EnglishTokenMetadata).rating, 5);
        },
      );

      test('matches all 146 accepted raw streams and final results', () async {
        var caseCount = 0;
        var rawTokenCount = 0;
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
          final backendInput = fixture['backendInput']! as Map<String, Object?>;
          final replay = mode.endsWith('espeak-fallback')
              ? _FixtureEspeakBackend(
                  backendInput['espeakCalls']! as List<Object?>,
                  dialect,
                )
              : null;
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
            unknownMarker: (options['unk'] as String?) ?? defaultUnknownMarker,
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
          caseCount++;
        }
        expect(caseCount, 146);
        expect(rawTokenCount, 744);
      });
    },
    tags: 'provisioned',
    skip: skipReason,
  );
}

List<Object?> _tokenProjection(List<MisakiToken> tokens) => <Object?>[
  for (final token in tokens)
    (
      token.text,
      token.tag,
      token.whitespace,
      token.phonemes,
      token.startTimeSeconds,
      token.endTimeSeconds,
      switch (token.metadata) {
        EnglishTokenMetadata metadata => (
          metadata.isHead,
          metadata.alias,
          metadata.stress,
          metadata.currency,
          metadata.numberFlags,
          metadata.precededBySpace,
          metadata.rating,
        ),
        _ => null,
      },
    ),
];

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
    'en_american_no_fallback.jsonl',
    'en_american_no_fallback_adversarial.jsonl',
    'en_british_no_fallback.jsonl',
    'en_british_no_fallback_adversarial.jsonl',
    'en_american_espeak_fallback.jsonl',
    'en_british_espeak_fallback.jsonl',
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
