import 'dart:convert';
import 'dart:io';

import 'package:misakid_chinese/misakid_chinese.dart';
import 'package:test/test.dart';

const _environmentNames = <String>[
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
    'provisioned pure-Dart Chinese frontend 1.1 backend',
    () {
      late List<Map<String, Object?>> fixtures;
      late PureDartChineseFrontend11Backend backend;

      setUpAll(() async {
        fixtures = await _readFixtures();
        backend = await PureDartChineseFrontend11Backend.open(
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
      });

      test('reports the exact immutable implementation identities', () {
        expect(backend.info.name, 'pure-dart-cn2an-jieba-pos-pypinyin-dict');
        expect(backend.info.version, '0.5.23/0.42.1/0.53.0/0.9.0');
        expect(backend.info.details['implementation'], 'pure-dart');
        expect(
          backend.info.details['jieba.partOfSpeechCharacterStatesSha256'],
          'c0ef4bb3d698eed188225d430ac291000b30c3d6e253a538d26b7ac9687424b1',
        );
        expect(
          backend.info.details['pypinyin.largePinyinSha256'],
          'f1f00a0682120f4052eb9ab03c632b040677dd9675bade5b8cb6a3bb7c0b8fd3',
        );
        expect(
          () => backend.info.details['mutable'] = 'no',
          throwsUnsupportedError,
        );
      });

      test('matches every captured external-stage call exactly', () {
        var normalizations = 0;
        var frontendCalls = 0;
        var posSegments = 0;
        var pinyinCalls = 0;
        var pinyinSyllables = 0;
        var searchCalls = 0;
        var searchSegments = 0;

        for (final fixture in fixtures) {
          final caseId = _string(fixture, 'caseId');
          final input = _map(fixture['backendInput'], '$caseId backendInput');
          final normalization = input['normalization'];
          if (normalization != null) {
            final record = _map(normalization, '$caseId normalization');
            expect(
              backend.normalizeNumbers(_string(record, 'input')),
              _string(record, 'output'),
              reason: caseId,
            );
            normalizations++;
          }

          for (final rawCall in _list(
            input['frontendCalls'],
            '$caseId frontendCalls',
          )) {
            final call = _map(rawCall, '$caseId frontend call');
            final expectedSegments = <ChineseSandhiWord>[
              for (final rawSegment in _list(
                call['segmentation'],
                '$caseId segmentation',
              ))
                ChineseSandhiWord(
                  word: _string(_map(rawSegment, '$caseId segment'), 'word'),
                  partOfSpeech: _string(
                    _map(rawSegment, '$caseId segment'),
                    'pos',
                  ),
                ),
            ];
            expect(
              backend.segmentWithPartOfSpeech(_string(call, 'input')),
              expectedSegments,
              reason: caseId,
            );
            frontendCalls++;
            posSegments += expectedSegments.length;

            for (final rawExternal in _list(
              call['externalCalls'],
              '$caseId externalCalls',
            )) {
              final external = _map(rawExternal, '$caseId external call');
              final externalInput = _string(external, 'input');
              final expected = <String>[
                for (final value in _list(
                  external['output'],
                  '$caseId external output',
                ))
                  _stringValue(value, '$caseId external value'),
              ];
              switch (_string(external, 'kind')) {
                case 'pypinyin.lazy_pinyin':
                  final style = _string(external, 'style');
                  final actual = switch (style) {
                    'initials' => backend.initials(externalInput),
                    'finals-tone3' => backend.tone3Finals(externalInput),
                    _ => throw StateError('Unexpected pypinyin style $style.'),
                  };
                  expect(actual, expected, reason: '$caseId $style');
                  pinyinCalls++;
                  pinyinSyllables += expected.length;
                case 'jieba.cut_for_search':
                  expect(
                    backend.searchSegments(externalInput),
                    expected,
                    reason: '$caseId search $externalInput',
                  );
                  searchCalls++;
                  searchSegments += expected.length;
                default:
                  throw StateError(
                    'Unexpected external call kind ${external['kind']}.',
                  );
              }
            }
          }
        }

        expect(normalizations, 24);
        expect(frontendCalls, 25);
        expect(posSegments, 131);
        expect(pinyinCalls, 365);
        expect(pinyinSyllables, 746);
        expect(searchCalls, 107);
        expect(searchSegments, 164);
      });

      test('matches all 26 original Misaki outputs exactly', () {
        var successes = 0;
        for (final fixture in fixtures) {
          final caseId = _string(fixture, 'caseId');
          final options = _map(fixture['options'], '$caseId options');
          final unknown = options['unk'];
          final engine = ChineseFrontend11G2pEngine(
            backend: backend,
            unknownMarker: unknown == null
                ? defaultUnknownMarker
                : _stringValue(unknown, '$caseId unknown marker'),
          );
          final actual = engine.convert(_string(fixture, 'input'));
          expect(actual.phonemes, fixture['phonemes'], reason: caseId);
          expect(actual.tokens, isNull, reason: caseId);
          successes++;
        }
        expect(successes, 26);
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
    'zh_frontend_1_1.jsonl',
  );
  final rows = <Map<String, Object?>>[];
  await for (final line
      in file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    rows.add(_map(jsonDecode(line), 'fixture row'));
  }
  expect(rows, hasLength(26));
  return rows;
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

String _string(Map<String, Object?> value, String key) =>
    _stringValue(value[key], key);

String _stringValue(Object? value, String label) {
  if (value is! String) throw FormatException('$label must be a string.');
  return value;
}
