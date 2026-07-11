import 'dart:convert';
import 'dart:io';

import 'package:misakid_chinese/misakid_chinese.dart';
import 'package:misakid_spacy_en/misakid_spacy_en.dart';
import 'package:test/test.dart';

const _chineseEnvironmentNames = <String>[
  'MISAKID_CHINESE_JIEBA_DICTIONARY',
  'MISAKID_CHINESE_JIEBA_PROB_START',
  'MISAKID_CHINESE_JIEBA_PROB_TRANSITION',
  'MISAKID_CHINESE_JIEBA_PROB_EMISSION',
  'MISAKID_CHINESE_JIEBA_POS_CHAR_STATE',
  'MISAKID_CHINESE_JIEBA_POS_PROB_START',
  'MISAKID_CHINESE_JIEBA_POS_PROB_TRANSITION',
  'MISAKID_CHINESE_JIEBA_POS_PROB_EMISSION',
  'MISAKID_CHINESE_PYPINYIN_DICT',
  'MISAKID_CHINESE_PYPINYIN_PHRASES',
  'MISAKID_CHINESE_LARGE_PINYIN',
];

void main() {
  final paths = <String, String?>{
    for (final name in _chineseEnvironmentNames)
      name: Platform.environment[name],
  };
  final modelDirectory = Platform.environment['MISAKID_SPACY_EN_MODEL_DIR'];
  final missing = <String>[
    for (final entry in paths.entries)
      if (entry.value == null) entry.key,
    if (modelDirectory == null) 'MISAKID_SPACY_EN_MODEL_DIR',
  ];
  final skipReason = missing.isEmpty
      ? false
      : 'Set provisioned resource paths: ${missing.join(', ')}.';

  group(
    'Chinese frontend 1.1 with pure-Dart English small model',
    () {
      late PureDartChineseFrontend11Backend chinese;
      late PureDartSpacyEnglishTokenizerBackend english;
      late List<Map<String, Object?>> fixtures;

      setUpAll(() async {
        fixtures = await _readFixtures();
        chinese = await PureDartChineseFrontend11Backend.open(
          jiebaDictionaryPath: paths['MISAKID_CHINESE_JIEBA_DICTIONARY']!,
          jiebaProbabilityStartPath: paths['MISAKID_CHINESE_JIEBA_PROB_START']!,
          jiebaProbabilityTransitionPath:
              paths['MISAKID_CHINESE_JIEBA_PROB_TRANSITION']!,
          jiebaProbabilityEmissionPath:
              paths['MISAKID_CHINESE_JIEBA_PROB_EMISSION']!,
          jiebaPartOfSpeechCharacterStatePath:
              paths['MISAKID_CHINESE_JIEBA_POS_CHAR_STATE']!,
          jiebaPartOfSpeechProbabilityStartPath:
              paths['MISAKID_CHINESE_JIEBA_POS_PROB_START']!,
          jiebaPartOfSpeechProbabilityTransitionPath:
              paths['MISAKID_CHINESE_JIEBA_POS_PROB_TRANSITION']!,
          jiebaPartOfSpeechProbabilityEmissionPath:
              paths['MISAKID_CHINESE_JIEBA_POS_PROB_EMISSION']!,
          pypinyinDictionaryPath: paths['MISAKID_CHINESE_PYPINYIN_DICT']!,
          pypinyinPhrasesPath: paths['MISAKID_CHINESE_PYPINYIN_PHRASES']!,
          pypinyinLargePhrasesPath: paths['MISAKID_CHINESE_LARGE_PINYIN']!,
        );
        english = await PureDartSpacyEnglishTokenizerBackend.open(
          modelDirectoryPath: modelDirectory!,
        );
      });

      test('exhausts every recorded callback and matches outer output', () {
        var caseCount = 0;
        var callbackCount = 0;
        var rawTokenCount = 0;
        var finalTokenCount = 0;

        for (final fixture in fixtures) {
          final caseId = _string(fixture, 'caseId');
          final reason = 'frontend-1.1-en-small-no-fallback/$caseId';
          final options = _map(fixture['options'], '$reason options');
          final dialect = _string(options, 'englishDialect') == 'british'
              ? EnglishDialect.british
              : EnglishDialect.american;
          final version = options['englishVersion'] == '2.0'
              ? EnglishPhonemeVersion.v2
              : EnglishPhonemeVersion.legacy;
          final unknown = (options['unk'] as String?) ?? defaultUnknownMarker;
          final backendInput = _map(
            fixture['backendInput'],
            '$reason backendInput',
          );
          expect(
            backendInput['kind'],
            'misaki.zh.frontend-1.1-en-small-no-fallback.external-stages',
            reason: reason,
          );
          expect(backendInput['schemaVersion'], 2, reason: reason);
          final englishInput = _map(
            backendInput['english'],
            '$reason English input',
          );
          expect(englishInput['dialect'], dialect.name, reason: reason);
          expect(
            englishInput['version'],
            options['englishVersion'],
            reason: reason,
          );
          expect(englishInput['model'], 'en_core_web_sm', reason: reason);
          expect(englishInput['fallback'], 'none', reason: reason);
          expect(englishInput['preprocess'], true, reason: reason);
          final expectedCalls = _list(
            englishInput['calls'],
            '$reason English calls',
          );

          final directCapture = _CapturingTokenizerBackend(english);
          final directEnglish = EnglishG2pEngine(
            tokenizer: directCapture,
            pronunciation: PinnedEnglishLexicon(dialect: dialect),
            phonemeVersion: version,
            unknownMarker: unknown,
            preprocessInput: true,
          );
          for (var index = 0; index < expectedCalls.length; index++) {
            final expectedCall = _map(
              expectedCalls[index],
              '$reason callback $index',
            );
            directCapture.calls.clear();
            final result = directEnglish.convert(
              _string(expectedCall, 'input'),
            );
            expect(directCapture.calls, hasLength(1), reason: reason);
            _expectTokenizerCall(
              directCapture.calls.single,
              _map(expectedCall['backendInput'], '$reason callback backend'),
              '$reason callback $index',
            );
            expect(
              result.phonemes,
              expectedCall['phonemes'],
              reason: '$reason callback $index',
            );
            _expectTokens(
              result.tokens!,
              _list(expectedCall['tokens'], '$reason final tokens'),
              '$reason callback $index final',
            );
            rawTokenCount += directCapture.calls.single.tokens.length;
            finalTokenCount += result.tokens!.length;
            callbackCount++;
          }

          final composedCapture = _CapturingTokenizerBackend(english);
          final engine = ChineseFrontend11EnglishG2pEngine(
            chineseBackend: chinese,
            englishTokenizer: composedCapture,
            englishDialect: dialect,
            englishPhonemeVersion: version,
            unknownMarker: unknown,
          );
          final actual = engine.convert(_string(fixture, 'input'));
          expect(
            composedCapture.calls,
            hasLength(expectedCalls.length),
            reason: '$reason callback count',
          );
          for (var index = 0; index < expectedCalls.length; index++) {
            final expectedCall = _map(
              expectedCalls[index],
              '$reason composed callback $index',
            );
            _expectTokenizerCall(
              composedCapture.calls[index],
              _map(expectedCall['backendInput'], '$reason composed backend'),
              '$reason composed callback $index',
            );
          }
          expect(actual.phonemes, fixture['phonemes'], reason: reason);
          expect(actual.tokens, isNull, reason: reason);
          caseCount++;
        }

        expect(caseCount, 14);
        expect(callbackCount, 14);
        expect(rawTokenCount, 40);
        expect(finalTokenCount, 33);
      });
    },
    tags: 'provisioned',
    skip: skipReason,
  );
}

final class _TokenizerCall {
  const _TokenizerCall(this.input, this.tokens);

  final EnglishPreprocessResult input;
  final List<MisakiToken> tokens;
}

final class _CapturingTokenizerBackend implements EnglishTokenizerBackend {
  _CapturingTokenizerBackend(this.delegate);

  final EnglishTokenizerBackend delegate;
  final List<_TokenizerCall> calls = <_TokenizerCall>[];

  @override
  BackendInfo get info => delegate.info;

  @override
  List<MisakiToken> tokenize(EnglishPreprocessResult input) {
    final tokens = delegate.tokenize(input);
    calls.add(_TokenizerCall(input, tokens));
    return tokens;
  }
}

void _expectTokenizerCall(
  _TokenizerCall actual,
  Map<String, Object?> expected,
  String reason,
) {
  expect(expected['kind'], 'misaki.en.G2P.preprocess-tokenize', reason: reason);
  expect(expected['schemaVersion'], 1, reason: reason);
  final preprocess = _map(expected['preprocess'], '$reason preprocess');
  expect(preprocess['applied'], true, reason: reason);
  expect(actual.input.text, preprocess['text'], reason: reason);
  expect(actual.input.sourceWords, preprocess['sourceWords'], reason: reason);
  expect(actual.input.controls, isEmpty, reason: reason);
  expect(preprocess['features'], isEmpty, reason: reason);
  _expectTokens(
    actual.tokens,
    _list(expected['tokens'], '$reason raw tokens'),
    '$reason raw',
  );
}

void _expectTokens(
  List<MisakiToken> actual,
  List<Object?> expected,
  String reason,
) {
  expect(actual, hasLength(expected.length), reason: reason);
  for (var index = 0; index < expected.length; index++) {
    final record = _map(expected[index], '$reason token $index');
    final metadata = _map(record['_'], '$reason token $index metadata');
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

Future<List<Map<String, Object?>>> _readFixtures() async {
  final file = File(
    '../../test/fixtures/upstream/'
    'fba1236595f2d2bf21d414ba6e57d25256afada3/'
    'zh_frontend_1_1_en_small_no_fallback.jsonl',
  );
  final rows = <Map<String, Object?>>[];
  await for (final line
      in file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    rows.add(_map(jsonDecode(line), 'fixture row'));
  }
  return List<Map<String, Object?>>.unmodifiable(rows);
}

Map<String, Object?> _map(Object? value, String label) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$label must be a string-keyed object.');
  }
  return value;
}

List<Object?> _list(Object? value, String label) {
  if (value is! List<Object?>) {
    throw FormatException('$label must be an array.');
  }
  return value;
}

String _string(Map<String, Object?> value, String key) {
  final result = value[key];
  if (result is! String) throw FormatException('$key must be a string.');
  return result;
}
