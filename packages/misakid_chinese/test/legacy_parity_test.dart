import 'dart:convert';
import 'dart:io';

import 'package:misakid_chinese/misakid_chinese.dart';
import 'package:test/test.dart';

const _environmentNames = <String>[
  'MISAKID_CHINESE_JIEBA_DICTIONARY',
  'MISAKID_CHINESE_JIEBA_PROB_START',
  'MISAKID_CHINESE_JIEBA_PROB_TRANSITION',
  'MISAKID_CHINESE_JIEBA_PROB_EMISSION',
  'MISAKID_CHINESE_PYPINYIN_DICT',
  'MISAKID_CHINESE_PYPINYIN_PHRASES',
];

void main() {
  final paths = <String, String?>{
    for (final name in _environmentNames) name: Platform.environment[name],
  };
  final missing = paths.entries
      .where((entry) => entry.value == null)
      .map((entry) => entry.key)
      .toList(growable: false);
  final skipReason = missing.isEmpty
      ? false
      : 'Set provisioned resource paths: ${missing.join(', ')}.';

  group(
    'provisioned pure-Dart Chinese legacy backend',
    () {
      late List<Map<String, Object?>> fixtures;
      late PureDartChineseLegacyBackend backend;

      setUpAll(() async {
        fixtures = await _readFixtures();
        backend = await PureDartChineseLegacyBackend.open(
          jiebaDictionaryPath: paths['MISAKID_CHINESE_JIEBA_DICTIONARY']!,
          jiebaProbabilityStartPath: paths['MISAKID_CHINESE_JIEBA_PROB_START']!,
          jiebaProbabilityTransitionPath:
              paths['MISAKID_CHINESE_JIEBA_PROB_TRANSITION']!,
          jiebaProbabilityEmissionPath:
              paths['MISAKID_CHINESE_JIEBA_PROB_EMISSION']!,
          pypinyinDictionaryPath: paths['MISAKID_CHINESE_PYPINYIN_DICT']!,
          pypinyinPhrasesPath: paths['MISAKID_CHINESE_PYPINYIN_PHRASES']!,
        );
      });

      test('reports the exact immutable implementation identities', () {
        expect(backend.info.name, 'pure-dart-cn2an-jieba-pypinyin');
        expect(backend.info.version, '0.5.23/0.42.1/0.53.0');
        expect(backend.info.details['implementation'], 'pure-dart');
        expect(
          backend.info.details['jieba.dictionarySha256'],
          '7197c3211ddd98962b036cdf40324d1ea2bfaa12bd028e68faa70111a88e12a8',
        );
        expect(
          backend.info.details['pypinyin.pinyinDictSha256'],
          '19ac93a11b0cf2d1b42741c2956dcb8632944e87d2ebcd1ba7cc4d3a936b9fb5',
        );
        expect(
          () => backend.info.details['mutable'] = 'no',
          throwsUnsupportedError,
        );
      });

      test('matches every captured external-stage call exactly', () {
        var normalizations = 0;
        var runs = 0;
        var words = 0;
        var syllables = 0;
        for (final fixture in fixtures) {
          final caseId = _string(fixture, 'caseId');
          final backendInput = _map(
            fixture['backendInput'],
            '$caseId backendInput',
          );
          final normalization = backendInput['normalization'];
          if (normalization != null) {
            final record = _map(normalization, '$caseId normalization');
            expect(
              backend.normalizeNumbers(_string(record, 'input')),
              _string(record, 'output'),
              reason: caseId,
            );
            normalizations++;
          }
          for (final rawRun in _list(backendInput['runs'], '$caseId runs')) {
            final run = _map(rawRun, '$caseId run');
            final expectedWords = _list(run['words'], '$caseId words');
            final input = _string(run, 'input');
            expect(backend.segmentChinese(input), <String>[
              for (final rawWord in expectedWords)
                _string(_map(rawWord, '$caseId word'), 'word'),
            ], reason: caseId);
            runs++;
            for (final rawWord in expectedWords) {
              final word = _map(rawWord, '$caseId word');
              final pinyin = _map(word['pinyin'], '$caseId pinyin');
              final expected = <String>[
                for (final value in _list(pinyin['output'], '$caseId output'))
                  _stringValue(value, '$caseId pinyin value'),
              ];
              expect(
                backend.tone3Pinyin(_string(word, 'word')),
                expected,
                reason: caseId,
              );
              words++;
              syllables += expected.length;
            }
          }
        }
        expect(normalizations, 22);
        expect(runs, 41);
        expect(words, 82);
        expect(syllables, 152);
      });

      test('matches all 24 original Misaki outputs and failures', () {
        final engine = ChineseLegacyG2pEngine(backend: backend);
        var successes = 0;
        var failures = 0;
        for (final fixture in fixtures) {
          final caseId = _string(fixture, 'caseId');
          final input = _string(fixture, 'input');
          final error = fixture['error'];
          if (error != null) {
            final errorRecord = _map(error, '$caseId error');
            expect(errorRecord['category'], 'upstreamFailure');
            expect(
              () => engine.convert(input),
              throwsA(
                isA<BackendFailureException>()
                    .having(
                      (value) => value.message,
                      'message',
                      contains('invalid tone-3 Pinyin'),
                    )
                    .having(
                      (value) => value.cause,
                      'cause',
                      isA<FormatException>(),
                    ),
              ),
              reason: caseId,
            );
            failures++;
            continue;
          }

          final actual = engine.convert(input);
          expect(actual.phonemes, fixture['phonemes'], reason: caseId);
          expect(actual.tokens, isNull, reason: caseId);
          successes++;
        }
        expect(successes, 22);
        expect(failures, 2);
      });
    },
    tags: 'provisioned',
    skip: skipReason,
  );
}

Future<List<Map<String, Object?>>> _readFixtures() async {
  final file = File(
    '../../test/fixtures/upstream/'
    'fba1236595f2d2bf21d414ba6e57d25256afada3/'
    'zh_legacy.jsonl',
  );
  final rows = <Map<String, Object?>>[];
  await for (final line
      in file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    rows.add(_map(jsonDecode(line), 'fixture row'));
  }
  expect(rows, hasLength(24));
  return rows;
}

Map<String, Object?> _map(Object? value, String location) {
  if (value is! Map<String, Object?>) fail('$location is not an object.');
  return value;
}

List<Object?> _list(Object? value, String location) {
  if (value is! List<Object?>) fail('$location is not a list.');
  return value;
}

String _string(Map<String, Object?> map, String key) =>
    _stringValue(map[key], key);

String _stringValue(Object? value, String location) {
  if (value is! String) fail('$location is not a string.');
  return value;
}
