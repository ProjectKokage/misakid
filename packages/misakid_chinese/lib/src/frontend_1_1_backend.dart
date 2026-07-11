// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'package:misakid/misaki_zh.dart';

import 'cn2an.dart';
import 'jieba.dart';
import 'pypinyin.dart';
import 'resource_bundle.dart';

/// Complete pure-Dart backend for pinned Misaki's Chinese frontend 1.1 mode.
///
/// [open] validates and loads the exact cn2an 0.5.23, Jieba 0.42.1,
/// pypinyin 0.53.0, and pypinyin-dict 0.9.0 resource tuple documented in
/// `RESOURCE_MANIFEST.md`. Conversion is synchronous, offline, and in-process
/// after initialization. Python, native libraries, resource discovery, and
/// runtime downloads are not used.
///
/// ```dart
/// final backend = await PureDartChineseFrontend11Backend.open(
///   jiebaDictionaryPath: '/resources/jieba/dict.txt',
///   jiebaProbabilityStartPath: '/resources/jieba/finalseg/prob_start.p',
///   jiebaProbabilityTransitionPath: '/resources/jieba/finalseg/prob_trans.p',
///   jiebaProbabilityEmissionPath: '/resources/jieba/finalseg/prob_emit.p',
///   jiebaPartOfSpeechCharacterStatePath:
///       '/resources/jieba/posseg/char_state_tab.p',
///   jiebaPartOfSpeechProbabilityStartPath:
///       '/resources/jieba/posseg/prob_start.p',
///   jiebaPartOfSpeechProbabilityTransitionPath:
///       '/resources/jieba/posseg/prob_trans.p',
///   jiebaPartOfSpeechProbabilityEmissionPath:
///       '/resources/jieba/posseg/prob_emit.p',
///   pypinyinDictionaryPath: '/resources/pypinyin/pinyin_dict.json',
///   pypinyinPhrasesPath: '/resources/pypinyin/phrases_dict.json',
///   pypinyinLargePhrasesPath: '/resources/large_pinyin.txt',
/// );
/// final result = ChineseFrontend11G2pEngine(backend: backend).convert('你好');
/// ```
final class PureDartChineseFrontend11Backend
    implements ChineseFrontend11Backend {
  PureDartChineseFrontend11Backend._({
    required Cn2AnNormalizer normalizer,
    required JiebaSegmenter segmenter,
    required PypinyinTone3Provider pypinyin,
  }) : _normalizer = normalizer,
       _segmenter = segmenter,
       _pypinyin = pypinyin,
       info = BackendInfo(
         name: 'pure-dart-cn2an-jieba-pos-pypinyin-dict',
         version: '0.5.23/0.42.1/0.53.0/0.9.0',
         details: <String, String>{
           'implementation': 'pure-dart',
           'cn2an.mode': 'an2cn',
           for (final entry in segmenter.info.details.entries)
             'jieba.${entry.key}': entry.value,
           for (final entry in pypinyin.info.details.entries)
             'pypinyin.${entry.key}': entry.value,
         },
       );

  final Cn2AnNormalizer _normalizer;
  final JiebaSegmenter _segmenter;
  final PypinyinTone3Provider _pypinyin;

  /// Opens and validates every explicitly supplied frontend-1.1 resource.
  ///
  /// All paths must be absolute paths to exact regular non-link files listed
  /// in `RESOURCE_MANIFEST.md`. Missing files throw
  /// [BackendUnavailableException], invalid path configuration throws
  /// [InvalidConfigurationException], and changed or incompatible data throws
  /// [MalformedDataException].
  static Future<PureDartChineseFrontend11Backend> open({
    required String jiebaDictionaryPath,
    required String jiebaProbabilityStartPath,
    required String jiebaProbabilityTransitionPath,
    required String jiebaProbabilityEmissionPath,
    required String jiebaPartOfSpeechCharacterStatePath,
    required String jiebaPartOfSpeechProbabilityStartPath,
    required String jiebaPartOfSpeechProbabilityTransitionPath,
    required String jiebaPartOfSpeechProbabilityEmissionPath,
    required String pypinyinDictionaryPath,
    required String pypinyinPhrasesPath,
    required String pypinyinLargePhrasesPath,
  }) async {
    final segmenter = await JiebaSegmenter.openWithPartOfSpeech(
      dictionaryPath: jiebaDictionaryPath,
      probabilityStartPath: jiebaProbabilityStartPath,
      probabilityTransitionPath: jiebaProbabilityTransitionPath,
      probabilityEmissionPath: jiebaProbabilityEmissionPath,
      partOfSpeechCharacterStatePath: jiebaPartOfSpeechCharacterStatePath,
      partOfSpeechProbabilityStartPath: jiebaPartOfSpeechProbabilityStartPath,
      partOfSpeechProbabilityTransitionPath:
          jiebaPartOfSpeechProbabilityTransitionPath,
      partOfSpeechProbabilityEmissionPath:
          jiebaPartOfSpeechProbabilityEmissionPath,
    );
    final pypinyin = await PypinyinTone3Provider.openFrontend11(
      pinyinDictionaryPath: pypinyinDictionaryPath,
      phrasesDictionaryPath: pypinyinPhrasesPath,
      largePinyinDictionaryPath: pypinyinLargePhrasesPath,
    );
    return PureDartChineseFrontend11Backend._(
      normalizer: const Cn2AnNormalizer(),
      segmenter: segmenter,
      pypinyin: pypinyin,
    );
  }

  /// Validates and parses an immutable in-memory frontend-1.1 snapshot.
  ///
  /// This synchronous constructor performs the same exact size, SHA-256,
  /// schema, and record-count checks as [open], without filesystem access.
  static PureDartChineseFrontend11Backend fromResources(
    ChineseFrontend11ResourceBundle resources,
  ) {
    final segmenter = createPinnedFrontend11JiebaFromBytes(
      dictionaryBytes: resources.jiebaDictionaryBytes,
      probabilityStartBytes: resources.jiebaProbabilityStartBytes,
      probabilityTransitionBytes: resources.jiebaProbabilityTransitionBytes,
      probabilityEmissionBytes: resources.jiebaProbabilityEmissionBytes,
      partOfSpeechCharacterStateBytes:
          resources.jiebaPartOfSpeechCharacterStatesBytes,
      partOfSpeechProbabilityStartBytes:
          resources.jiebaPartOfSpeechProbabilityStartBytes,
      partOfSpeechProbabilityTransitionBytes:
          resources.jiebaPartOfSpeechProbabilityTransitionBytes,
      partOfSpeechProbabilityEmissionBytes:
          resources.jiebaPartOfSpeechProbabilityEmissionBytes,
    );
    final pypinyin = createPinnedFrontend11PypinyinFromBytes(
      pinyinDictionaryBytes: resources.pypinyinDictionaryBytes,
      phrasesDictionaryBytes: resources.pypinyinPhrasesBytes,
      largePinyinDictionaryBytes: resources.pypinyinLargePhrasesBytes,
    );
    return PureDartChineseFrontend11Backend._(
      normalizer: const Cn2AnNormalizer(),
      segmenter: segmenter,
      pypinyin: pypinyin,
    );
  }

  @override
  final BackendInfo info;

  @override
  String normalizeNumbers(String text) => _normalizer.normalize(text);

  @override
  List<ChineseSandhiWord> segmentWithPartOfSpeech(String text) =>
      _segmenter.segmentWithPartOfSpeech(text);

  @override
  List<String> searchSegments(String word) => _segmenter.searchSegments(word);

  @override
  List<String> initials(String word) => _pypinyin.initials(word);

  @override
  List<String> tone3Finals(String word) => _pypinyin.finalsTone3(word);
}
