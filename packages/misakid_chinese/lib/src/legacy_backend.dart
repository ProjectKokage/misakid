// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'package:misakid/misaki_zh.dart';

import 'cn2an.dart';
import 'jieba.dart';
import 'pypinyin.dart';
import 'resource_bundle.dart';

/// Complete pure-Dart backend for pinned Misaki's legacy Chinese mode.
///
/// [open] validates and loads the exact Jieba 0.42.1 and pypinyin 0.53.0
/// resources supplied by the caller. Conversion is synchronous, offline, and
/// in-process after initialization. Python, native libraries, package
/// discovery, and runtime downloads are not used.
///
/// ```dart
/// final backend = await PureDartChineseLegacyBackend.open(
///   jiebaDictionaryPath: '/absolute/path/jieba/dict.txt',
///   jiebaProbabilityStartPath:
///       '/absolute/path/jieba/finalseg/prob_start.p',
///   jiebaProbabilityTransitionPath:
///       '/absolute/path/jieba/finalseg/prob_trans.p',
///   jiebaProbabilityEmissionPath:
///       '/absolute/path/jieba/finalseg/prob_emit.p',
///   pypinyinDictionaryPath: '/absolute/path/pypinyin/pinyin_dict.json',
///   pypinyinPhrasesPath: '/absolute/path/pypinyin/phrases_dict.json',
/// );
/// final result = ChineseLegacyG2pEngine(backend: backend).convert('你好');
/// ```
final class PureDartChineseLegacyBackend implements ChineseLegacyBackend {
  PureDartChineseLegacyBackend._({
    required Cn2AnNormalizer normalizer,
    required JiebaSegmenter segmenter,
    required PypinyinTone3Provider pypinyin,
  }) : _normalizer = normalizer,
       _segmenter = segmenter,
       _pypinyin = pypinyin,
       info = BackendInfo(
         name: 'pure-dart-cn2an-jieba-pypinyin',
         version: '0.5.23/0.42.1/0.53.0',
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

  /// Opens and validates every explicitly supplied legacy Chinese resource.
  ///
  /// All paths must be absolute paths to the exact regular non-link files
  /// listed in `RESOURCE_MANIFEST.md`. Missing files throw
  /// [BackendUnavailableException], invalid path configuration throws
  /// [InvalidConfigurationException], and changed or incompatible data throws
  /// [MalformedDataException].
  static Future<PureDartChineseLegacyBackend> open({
    required String jiebaDictionaryPath,
    required String jiebaProbabilityStartPath,
    required String jiebaProbabilityTransitionPath,
    required String jiebaProbabilityEmissionPath,
    required String pypinyinDictionaryPath,
    required String pypinyinPhrasesPath,
  }) async {
    final segmenter = await JiebaSegmenter.open(
      dictionaryPath: jiebaDictionaryPath,
      probabilityStartPath: jiebaProbabilityStartPath,
      probabilityTransitionPath: jiebaProbabilityTransitionPath,
      probabilityEmissionPath: jiebaProbabilityEmissionPath,
    );
    final pypinyin = await PypinyinTone3Provider.open(
      pinyinDictionaryPath: pypinyinDictionaryPath,
      phrasesDictionaryPath: pypinyinPhrasesPath,
    );
    return PureDartChineseLegacyBackend._(
      normalizer: const Cn2AnNormalizer(),
      segmenter: segmenter,
      pypinyin: pypinyin,
    );
  }

  /// Validates and parses an immutable in-memory resource snapshot.
  ///
  /// This synchronous constructor performs the same exact size, SHA-256,
  /// schema, and record-count checks as [open], without filesystem access.
  /// It is suitable for resources supplied by Flutter assets, embedded hosts,
  /// or another caller-controlled byte source.
  static PureDartChineseLegacyBackend fromResources(
    ChineseLegacyResourceBundle resources,
  ) {
    final segmenter = createPinnedLegacyJiebaFromBytes(
      dictionaryBytes: resources.jiebaDictionaryBytes,
      probabilityStartBytes: resources.jiebaProbabilityStartBytes,
      probabilityTransitionBytes: resources.jiebaProbabilityTransitionBytes,
      probabilityEmissionBytes: resources.jiebaProbabilityEmissionBytes,
    );
    final pypinyin = createPinnedLegacyPypinyinFromBytes(
      pinyinDictionaryBytes: resources.pypinyinDictionaryBytes,
      phrasesDictionaryBytes: resources.pypinyinPhrasesBytes,
    );
    return PureDartChineseLegacyBackend._(
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
  List<String> segmentChinese(String text) => _segmenter.segment(text);

  @override
  List<String> tone3Pinyin(String word) => _pypinyin.tone3(word);
}
