// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

/// Immutable in-memory resources for pinned Misaki legacy Chinese G2P.
///
/// The constructor defensively copies every byte list. Getters return
/// unmodifiable defensive copies, so neither later caller mutations nor a
/// retained view can change the resource snapshot.
final class ChineseLegacyResourceBundle {
  /// Creates an immutable snapshot of all six legacy resources.
  ChineseLegacyResourceBundle({
    required Uint8List jiebaDictionaryBytes,
    required Uint8List jiebaProbabilityStartBytes,
    required Uint8List jiebaProbabilityTransitionBytes,
    required Uint8List jiebaProbabilityEmissionBytes,
    required Uint8List pypinyinDictionaryBytes,
    required Uint8List pypinyinPhrasesBytes,
  }) : _jiebaDictionaryBytes = Uint8List.fromList(jiebaDictionaryBytes),
       _jiebaProbabilityStartBytes = Uint8List.fromList(
         jiebaProbabilityStartBytes,
       ),
       _jiebaProbabilityTransitionBytes = Uint8List.fromList(
         jiebaProbabilityTransitionBytes,
       ),
       _jiebaProbabilityEmissionBytes = Uint8List.fromList(
         jiebaProbabilityEmissionBytes,
       ),
       _pypinyinDictionaryBytes = Uint8List.fromList(pypinyinDictionaryBytes),
       _pypinyinPhrasesBytes = Uint8List.fromList(pypinyinPhrasesBytes);

  final Uint8List _jiebaDictionaryBytes;
  final Uint8List _jiebaProbabilityStartBytes;
  final Uint8List _jiebaProbabilityTransitionBytes;
  final Uint8List _jiebaProbabilityEmissionBytes;
  final Uint8List _pypinyinDictionaryBytes;
  final Uint8List _pypinyinPhrasesBytes;

  /// Exact Jieba 0.42.1 `dict.txt` bytes.
  Uint8List get jiebaDictionaryBytes => _copy(_jiebaDictionaryBytes);

  /// Exact Jieba finalseg `prob_start.p` bytes.
  Uint8List get jiebaProbabilityStartBytes =>
      _copy(_jiebaProbabilityStartBytes);

  /// Exact Jieba finalseg `prob_trans.p` bytes.
  Uint8List get jiebaProbabilityTransitionBytes =>
      _copy(_jiebaProbabilityTransitionBytes);

  /// Exact Jieba finalseg `prob_emit.p` bytes.
  Uint8List get jiebaProbabilityEmissionBytes =>
      _copy(_jiebaProbabilityEmissionBytes);

  /// Exact pypinyin 0.53.0 `pinyin_dict.json` bytes.
  Uint8List get pypinyinDictionaryBytes => _copy(_pypinyinDictionaryBytes);

  /// Exact pypinyin 0.53.0 `phrases_dict.json` bytes.
  Uint8List get pypinyinPhrasesBytes => _copy(_pypinyinPhrasesBytes);
}

/// Immutable in-memory resources for pinned Misaki Chinese frontend 1.1.
///
/// This includes the legacy Jieba and pypinyin resources, Jieba's POS HMM,
/// and the pypinyin-dict 0.9.0 large phrase overlay. Every input is copied.
final class ChineseFrontend11ResourceBundle {
  /// Creates an immutable snapshot of all eleven frontend-1.1 resources.
  ChineseFrontend11ResourceBundle({
    required Uint8List jiebaDictionaryBytes,
    required Uint8List jiebaProbabilityStartBytes,
    required Uint8List jiebaProbabilityTransitionBytes,
    required Uint8List jiebaProbabilityEmissionBytes,
    required Uint8List jiebaPartOfSpeechCharacterStatesBytes,
    required Uint8List jiebaPartOfSpeechProbabilityStartBytes,
    required Uint8List jiebaPartOfSpeechProbabilityTransitionBytes,
    required Uint8List jiebaPartOfSpeechProbabilityEmissionBytes,
    required Uint8List pypinyinDictionaryBytes,
    required Uint8List pypinyinPhrasesBytes,
    required Uint8List pypinyinLargePhrasesBytes,
  }) : _jiebaDictionaryBytes = Uint8List.fromList(jiebaDictionaryBytes),
       _jiebaProbabilityStartBytes = Uint8List.fromList(
         jiebaProbabilityStartBytes,
       ),
       _jiebaProbabilityTransitionBytes = Uint8List.fromList(
         jiebaProbabilityTransitionBytes,
       ),
       _jiebaProbabilityEmissionBytes = Uint8List.fromList(
         jiebaProbabilityEmissionBytes,
       ),
       _jiebaPartOfSpeechCharacterStatesBytes = Uint8List.fromList(
         jiebaPartOfSpeechCharacterStatesBytes,
       ),
       _jiebaPartOfSpeechProbabilityStartBytes = Uint8List.fromList(
         jiebaPartOfSpeechProbabilityStartBytes,
       ),
       _jiebaPartOfSpeechProbabilityTransitionBytes = Uint8List.fromList(
         jiebaPartOfSpeechProbabilityTransitionBytes,
       ),
       _jiebaPartOfSpeechProbabilityEmissionBytes = Uint8List.fromList(
         jiebaPartOfSpeechProbabilityEmissionBytes,
       ),
       _pypinyinDictionaryBytes = Uint8List.fromList(pypinyinDictionaryBytes),
       _pypinyinPhrasesBytes = Uint8List.fromList(pypinyinPhrasesBytes),
       _pypinyinLargePhrasesBytes = Uint8List.fromList(
         pypinyinLargePhrasesBytes,
       );

  final Uint8List _jiebaDictionaryBytes;
  final Uint8List _jiebaProbabilityStartBytes;
  final Uint8List _jiebaProbabilityTransitionBytes;
  final Uint8List _jiebaProbabilityEmissionBytes;
  final Uint8List _jiebaPartOfSpeechCharacterStatesBytes;
  final Uint8List _jiebaPartOfSpeechProbabilityStartBytes;
  final Uint8List _jiebaPartOfSpeechProbabilityTransitionBytes;
  final Uint8List _jiebaPartOfSpeechProbabilityEmissionBytes;
  final Uint8List _pypinyinDictionaryBytes;
  final Uint8List _pypinyinPhrasesBytes;
  final Uint8List _pypinyinLargePhrasesBytes;

  /// Exact Jieba 0.42.1 `dict.txt` bytes.
  Uint8List get jiebaDictionaryBytes => _copy(_jiebaDictionaryBytes);

  /// Exact Jieba finalseg `prob_start.p` bytes.
  Uint8List get jiebaProbabilityStartBytes =>
      _copy(_jiebaProbabilityStartBytes);

  /// Exact Jieba finalseg `prob_trans.p` bytes.
  Uint8List get jiebaProbabilityTransitionBytes =>
      _copy(_jiebaProbabilityTransitionBytes);

  /// Exact Jieba finalseg `prob_emit.p` bytes.
  Uint8List get jiebaProbabilityEmissionBytes =>
      _copy(_jiebaProbabilityEmissionBytes);

  /// Exact Jieba POS `char_state_tab.p` bytes.
  Uint8List get jiebaPartOfSpeechCharacterStatesBytes =>
      _copy(_jiebaPartOfSpeechCharacterStatesBytes);

  /// Exact Jieba POS `prob_start.p` bytes.
  Uint8List get jiebaPartOfSpeechProbabilityStartBytes =>
      _copy(_jiebaPartOfSpeechProbabilityStartBytes);

  /// Exact Jieba POS `prob_trans.p` bytes.
  Uint8List get jiebaPartOfSpeechProbabilityTransitionBytes =>
      _copy(_jiebaPartOfSpeechProbabilityTransitionBytes);

  /// Exact Jieba POS `prob_emit.p` bytes.
  Uint8List get jiebaPartOfSpeechProbabilityEmissionBytes =>
      _copy(_jiebaPartOfSpeechProbabilityEmissionBytes);

  /// Exact pypinyin 0.53.0 `pinyin_dict.json` bytes.
  Uint8List get pypinyinDictionaryBytes => _copy(_pypinyinDictionaryBytes);

  /// Exact pypinyin 0.53.0 `phrases_dict.json` bytes.
  Uint8List get pypinyinPhrasesBytes => _copy(_pypinyinPhrasesBytes);

  /// Exact pypinyin-dict 0.9.0 `large_pinyin.txt` bytes.
  Uint8List get pypinyinLargePhrasesBytes => _copy(_pypinyinLargePhrasesBytes);
}

Uint8List _copy(Uint8List bytes) =>
    Uint8List.fromList(bytes).asUnmodifiableView();
