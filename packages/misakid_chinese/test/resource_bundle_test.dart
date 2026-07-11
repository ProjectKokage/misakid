import 'dart:io';
import 'dart:typed_data';

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
  test('legacy bundle owns immutable typed byte snapshots', () {
    final source = Uint8List.fromList(<int>[1, 2, 3]);
    final bundle = ChineseLegacyResourceBundle(
      jiebaDictionaryBytes: source,
      jiebaProbabilityStartBytes: source,
      jiebaProbabilityTransitionBytes: source,
      jiebaProbabilityEmissionBytes: source,
      pypinyinDictionaryBytes: source,
      pypinyinPhrasesBytes: source,
    );

    source[0] = 9;
    expect(bundle.jiebaDictionaryBytes, <int>[1, 2, 3]);
    expect(bundle.pypinyinPhrasesBytes, <int>[1, 2, 3]);
    expect(() => bundle.jiebaDictionaryBytes[0] = 7, throwsUnsupportedError);
  });

  test('frontend-1.1 bundle owns every POS and large-phrase snapshot', () {
    final source = Uint8List.fromList(<int>[4, 5, 6]);
    final bundle = ChineseFrontend11ResourceBundle(
      jiebaDictionaryBytes: source,
      jiebaProbabilityStartBytes: source,
      jiebaProbabilityTransitionBytes: source,
      jiebaProbabilityEmissionBytes: source,
      jiebaPartOfSpeechCharacterStatesBytes: source,
      jiebaPartOfSpeechProbabilityStartBytes: source,
      jiebaPartOfSpeechProbabilityTransitionBytes: source,
      jiebaPartOfSpeechProbabilityEmissionBytes: source,
      pypinyinDictionaryBytes: source,
      pypinyinPhrasesBytes: source,
      pypinyinLargePhrasesBytes: source,
    );

    source[1] = 0;
    expect(bundle.jiebaPartOfSpeechCharacterStatesBytes, <int>[4, 5, 6]);
    expect(bundle.pypinyinLargePhrasesBytes, <int>[4, 5, 6]);
    expect(
      () => bundle.pypinyinLargePhrasesBytes[0] = 7,
      throwsUnsupportedError,
    );
  });

  test('byte-backed backends reject malformed resource identities', () {
    final bytes = Uint8List.fromList(<int>[0]);
    expect(
      () => PureDartChineseLegacyBackend.fromResources(
        ChineseLegacyResourceBundle(
          jiebaDictionaryBytes: bytes,
          jiebaProbabilityStartBytes: bytes,
          jiebaProbabilityTransitionBytes: bytes,
          jiebaProbabilityEmissionBytes: bytes,
          pypinyinDictionaryBytes: bytes,
          pypinyinPhrasesBytes: bytes,
        ),
      ),
      throwsA(isA<MalformedDataException>()),
    );
    expect(
      () => PureDartChineseFrontend11Backend.fromResources(
        ChineseFrontend11ResourceBundle(
          jiebaDictionaryBytes: bytes,
          jiebaProbabilityStartBytes: bytes,
          jiebaProbabilityTransitionBytes: bytes,
          jiebaProbabilityEmissionBytes: bytes,
          jiebaPartOfSpeechCharacterStatesBytes: bytes,
          jiebaPartOfSpeechProbabilityStartBytes: bytes,
          jiebaPartOfSpeechProbabilityTransitionBytes: bytes,
          jiebaPartOfSpeechProbabilityEmissionBytes: bytes,
          pypinyinDictionaryBytes: bytes,
          pypinyinPhrasesBytes: bytes,
          pypinyinLargePhrasesBytes: bytes,
        ),
      ),
      throwsA(isA<MalformedDataException>()),
    );
  });

  test('byte-backed parser and backend libraries do not import dart:io', () {
    for (final path in <String>[
      'lib/src/resource_bundle.dart',
      'lib/src/legacy_backend.dart',
      'lib/src/frontend_1_1_backend.dart',
      'lib/src/jieba.dart',
      'lib/src/pypinyin.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        isNot(contains("import 'dart:io';")),
        reason: path,
      );
    }
  });

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
    'provisioned path and byte resource equivalence',
    () {
      late PureDartChineseLegacyBackend legacyPath;
      late PureDartChineseLegacyBackend legacyBytes;
      late PureDartChineseFrontend11Backend frontendPath;
      late PureDartChineseFrontend11Backend frontendBytes;
      late Map<String, Uint8List> sourceBytes;

      setUpAll(() async {
        sourceBytes = <String, Uint8List>{
          for (final entry in paths.entries)
            entry.key: await File(entry.value!).readAsBytes(),
        };
        final legacyBundle = ChineseLegacyResourceBundle(
          jiebaDictionaryBytes:
              sourceBytes['MISAKID_CHINESE_JIEBA_DICTIONARY']!,
          jiebaProbabilityStartBytes:
              sourceBytes['MISAKID_CHINESE_JIEBA_PROB_START']!,
          jiebaProbabilityTransitionBytes:
              sourceBytes['MISAKID_CHINESE_JIEBA_PROB_TRANSITION']!,
          jiebaProbabilityEmissionBytes:
              sourceBytes['MISAKID_CHINESE_JIEBA_PROB_EMISSION']!,
          pypinyinDictionaryBytes:
              sourceBytes['MISAKID_CHINESE_PYPINYIN_DICT']!,
          pypinyinPhrasesBytes:
              sourceBytes['MISAKID_CHINESE_PYPINYIN_PHRASES']!,
        );
        final frontendBundle = ChineseFrontend11ResourceBundle(
          jiebaDictionaryBytes:
              sourceBytes['MISAKID_CHINESE_JIEBA_DICTIONARY']!,
          jiebaProbabilityStartBytes:
              sourceBytes['MISAKID_CHINESE_JIEBA_PROB_START']!,
          jiebaProbabilityTransitionBytes:
              sourceBytes['MISAKID_CHINESE_JIEBA_PROB_TRANSITION']!,
          jiebaProbabilityEmissionBytes:
              sourceBytes['MISAKID_CHINESE_JIEBA_PROB_EMISSION']!,
          jiebaPartOfSpeechCharacterStatesBytes:
              sourceBytes['MISAKID_CHINESE_JIEBA_POS_CHAR_STATE']!,
          jiebaPartOfSpeechProbabilityStartBytes:
              sourceBytes['MISAKID_CHINESE_JIEBA_POS_PROB_START']!,
          jiebaPartOfSpeechProbabilityTransitionBytes:
              sourceBytes['MISAKID_CHINESE_JIEBA_POS_PROB_TRANSITION']!,
          jiebaPartOfSpeechProbabilityEmissionBytes:
              sourceBytes['MISAKID_CHINESE_JIEBA_POS_PROB_EMISSION']!,
          pypinyinDictionaryBytes:
              sourceBytes['MISAKID_CHINESE_PYPINYIN_DICT']!,
          pypinyinPhrasesBytes:
              sourceBytes['MISAKID_CHINESE_PYPINYIN_PHRASES']!,
          pypinyinLargePhrasesBytes:
              sourceBytes['MISAKID_CHINESE_LARGE_PINYIN']!,
        );

        sourceBytes['MISAKID_CHINESE_JIEBA_DICTIONARY']![0] ^= 0xff;
        legacyBytes = PureDartChineseLegacyBackend.fromResources(legacyBundle);
        frontendBytes = PureDartChineseFrontend11Backend.fromResources(
          frontendBundle,
        );
        legacyPath = await PureDartChineseLegacyBackend.open(
          jiebaDictionaryPath: paths['MISAKID_CHINESE_JIEBA_DICTIONARY']!,
          jiebaProbabilityStartPath: paths['MISAKID_CHINESE_JIEBA_PROB_START']!,
          jiebaProbabilityTransitionPath:
              paths['MISAKID_CHINESE_JIEBA_PROB_TRANSITION']!,
          jiebaProbabilityEmissionPath:
              paths['MISAKID_CHINESE_JIEBA_PROB_EMISSION']!,
          pypinyinDictionaryPath: paths['MISAKID_CHINESE_PYPINYIN_DICT']!,
          pypinyinPhrasesPath: paths['MISAKID_CHINESE_PYPINYIN_PHRASES']!,
        );
        frontendPath = await PureDartChineseFrontend11Backend.open(
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

      test('legacy backend metadata, stages, and output are identical', () {
        _expectSameInfo(legacyBytes.info, legacyPath.info);
        expect(
          legacyBytes.segmentChinese('南京市长江大桥'),
          legacyPath.segmentChinese('南京市长江大桥'),
        );
        expect(legacyBytes.tone3Pinyin('重庆'), legacyPath.tone3Pinyin('重庆'));
        for (final input in <String>['你好，世界！', '重庆银行', '2025年']) {
          expect(
            ChineseLegacyG2pEngine(
              backend: legacyBytes,
            ).convert(input).phonemes,
            ChineseLegacyG2pEngine(backend: legacyPath).convert(input).phonemes,
            reason: input,
          );
        }
      });

      test('frontend-1.1 metadata, stages, and output are identical', () {
        _expectSameInfo(frontendBytes.info, frontendPath.info);
        expect(
          frontendBytes.segmentWithPartOfSpeech('重庆银行'),
          frontendPath.segmentWithPartOfSpeech('重庆银行'),
        );
        expect(frontendBytes.initials('重庆'), frontendPath.initials('重庆'));
        expect(frontendBytes.tone3Finals('重庆'), frontendPath.tone3Finals('重庆'));
        for (final input in <String>['你好，世界！', '重庆银行', '2025年']) {
          expect(
            ChineseFrontend11G2pEngine(
              backend: frontendBytes,
            ).convert(input).phonemes,
            ChineseFrontend11G2pEngine(
              backend: frontendPath,
            ).convert(input).phonemes,
            reason: input,
          );
        }
      });

      test('one-byte identity drift is rejected before parsing', () {
        final tampered = Uint8List.fromList(
          File(paths['MISAKID_CHINESE_JIEBA_DICTIONARY']!).readAsBytesSync(),
        )..[0] ^= 0xff;
        expect(
          () => PureDartChineseLegacyBackend.fromResources(
            ChineseLegacyResourceBundle(
              jiebaDictionaryBytes: tampered,
              jiebaProbabilityStartBytes:
                  sourceBytes['MISAKID_CHINESE_JIEBA_PROB_START']!,
              jiebaProbabilityTransitionBytes:
                  sourceBytes['MISAKID_CHINESE_JIEBA_PROB_TRANSITION']!,
              jiebaProbabilityEmissionBytes:
                  sourceBytes['MISAKID_CHINESE_JIEBA_PROB_EMISSION']!,
              pypinyinDictionaryBytes:
                  sourceBytes['MISAKID_CHINESE_PYPINYIN_DICT']!,
              pypinyinPhrasesBytes:
                  sourceBytes['MISAKID_CHINESE_PYPINYIN_PHRASES']!,
            ),
          ),
          throwsA(isA<MalformedDataException>()),
        );
      });
    },
    tags: 'provisioned',
    skip: skipReason,
  );
}

void _expectSameInfo(BackendInfo actual, BackendInfo expected) {
  expect(actual.name, expected.name);
  expect(actual.version, expected.version);
  expect(actual.details, expected.details);
}
