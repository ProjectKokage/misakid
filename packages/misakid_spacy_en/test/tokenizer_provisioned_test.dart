import 'dart:convert';
import 'dart:io';

import 'package:misakid_spacy_en/src/tokenizer/config.dart';
import 'package:misakid_spacy_en/src/tokenizer/tokenizer.dart';
import 'package:test/test.dart';

void main() {
  final modelRoot =
      Platform.environment['MISAKID_SPACY_EN_MODEL_DIR'] ??
      Platform.environment['MISAKID_SPACY_EN_MODEL'];
  final fixtureRoot =
      Platform.environment['MISAKID_SPACY_EN_FIXTURES'] ??
      '../../test/fixtures/upstream/'
          'fba1236595f2d2bf21d414ba6e57d25256afada3';
  final auditPath =
      Platform.environment['MISAKID_SPACY_EN_TOKENIZER_AUDIT_JSONL'];
  final skipReason = modelRoot == null
      ? 'Set MISAKID_SPACY_EN_MODEL_DIR to en_core_web_sm-3.8.0.'
      : false;

  group('provisioned en_core_web_sm 3.8.0 tokenizer', () {
    late SpacyTokenizerConfig config;
    late SpacyTokenizer tokenizer;

    setUpAll(() {
      final root = Directory(modelRoot!);
      config = SpacyTokenizerConfig.decode(
        tokenizerBytes: File('${root.path}/tokenizer').readAsBytesSync(),
        vocabLookupsBytes: File(
          '${root.path}/vocab/lookups.bin',
        ).readAsBytesSync(),
      );
      tokenizer = SpacyTokenizer(config);
    });

    test('loads the exact reviewed resource cardinalities', () {
      expect(config.exceptions, hasLength(1347));
      expect(config.lexemeNorms, hasLength(3510));
      expect(config.tokenMatchPattern, isNull);
      expect(config.fasterHeuristics, isTrue);
    });

    test('all 146 accepted streams and 744 tokens match exactly', () {
      var caseCount = 0;
      var tokenCount = 0;
      final names = <String>[
        'en_american_espeak_fallback.jsonl',
        'en_american_no_fallback.jsonl',
        'en_american_no_fallback_adversarial.jsonl',
        'en_british_espeak_fallback.jsonl',
        'en_british_no_fallback.jsonl',
        'en_british_no_fallback_adversarial.jsonl',
      ];
      for (final name in names) {
        final lines = File('$fixtureRoot/$name').readAsLinesSync();
        for (final line in lines) {
          final fixture = jsonDecode(line) as Map<String, Object?>;
          final backend = fixture['backendInput']! as Map<String, Object?>;
          if (backend['kind'] != 'misaki.en.G2P.preprocess-tokenize') {
            continue;
          }
          final preprocess = backend['preprocess']! as Map<String, Object?>;
          final text = preprocess['text']! as String;
          final expected = backend['tokens']! as List<Object?>;
          final actual = tokenizer.tokenize(text);
          final reason = '${fixture['caseId']} in $name';
          expect(actual, hasLength(expected.length), reason: reason);
          tokenCount += actual.length;
          caseCount++;
          final reconstructed = StringBuffer();
          for (var index = 0; index < actual.length; index++) {
            final token = expected[index]! as Map<String, Object?>;
            expect(actual[index].text, token['text'], reason: reason);
            expect(
              actual[index].whitespace,
              token['whitespace'],
              reason: reason,
            );
            reconstructed
              ..write(actual[index].text)
              ..write(actual[index].whitespace);
          }
          expect(reconstructed.toString(), text, reason: reason);
        }
      }
      expect(caseCount, 146);
      expect(tokenCount, 744);
    });

    test('non-ASCII URL, norm, symbol, and shape adversaries match spaCy', () {
      for (final value in <String>[
        'αβ://例え.テスト',
        '例え.テスト/path',
        'café@example.com',
        'http://x.example/é?q=λ',
        '١٢٣.٤٥',
        '½.example',
      ]) {
        expect(tokenizer.tokenize(value).single.text, value, reason: value);
      }
      final specials = tokenizer.tokenize("can't 10a.m. °C.");
      expect(
        specials.map((token) => (token.text, token.norm)),
        <(String, String)>[
          ('ca', 'can'),
          ("n't", 'not'),
          ('10', '10'),
          ('a.m.', 'a.m.'),
          ('°', '°'),
          ('C', 'c'),
          ('.', '.'),
        ],
      );
      final symbols = tokenizer.tokenize('X aux _ ① ½');
      expect(symbols.map((token) => token.orthId), <int>[
        101,
        405,
        456,
        5711679940398778098,
        -1382962432747454302,
      ]);
      expect(symbols.map((token) => token.shapeId), <int>[
        101,
        4088098365541558500,
        456,
        8148669997605808657,
        -1382962432747454302,
      ]);
      final punctuation = tokenizer.tokenize('“Hello…” ‘Really?’');
      expect(punctuation.map((token) => token.norm), <String>[
        '"',
        'hello',
        '...',
        '"',
        "'",
        'really',
        '?',
        "'",
      ]);
    });

    test(
      'optional extended spaCy differential matches every token field',
      () {
        var caseCount = 0;
        var tokenCount = 0;
        for (final line in File(auditPath!).readAsLinesSync()) {
          if (line.isEmpty) {
            continue;
          }
          final record = jsonDecode(line) as Map<String, Object?>;
          final input = record['input']! as String;
          final expected = record['tokens']! as List<Object?>;
          final actual = tokenizer.tokenize(input);
          expect(actual, hasLength(expected.length), reason: input);
          for (var index = 0; index < actual.length; index++) {
            final token = expected[index]! as Map<String, Object?>;
            final reason = 'case $caseCount token $index for `$input`';
            expect(actual[index].text, token['text'], reason: reason);
            expect(
              actual[index].whitespace,
              token['whitespace'],
              reason: reason,
            );
            expect(actual[index].norm, token['norm'], reason: reason);
            expect(actual[index].orthId, token['orthId'], reason: reason);
            expect(actual[index].normId, token['normId'], reason: reason);
            expect(actual[index].prefixId, token['prefixId'], reason: reason);
            expect(actual[index].suffixId, token['suffixId'], reason: reason);
            expect(actual[index].shapeId, token['shapeId'], reason: reason);
            expect(actual[index].spacy, token['spacy'], reason: reason);
            expect(actual[index].isSpace, token['isSpace'], reason: reason);
            expect(
              actual[index].startOffsetUtf16,
              token['startOffsetUtf16'],
              reason: reason,
            );
            expect(
              actual[index].endOffsetUtf16,
              token['endOffsetUtf16'],
              reason: reason,
            );
          }
          caseCount++;
          tokenCount += actual.length;
        }
        expect(caseCount, greaterThan(0));
        expect(tokenCount, greaterThan(0));
      },
      skip: auditPath == null
          ? 'Set MISAKID_SPACY_EN_TOKENIZER_AUDIT_JSONL.'
          : false,
    );
  }, skip: skipReason);
}
