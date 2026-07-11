// Copyright (c) 2021 PaddlePaddle Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Dart adaptation of hexgrad/misaki/misaki/tone_sandhi.py at
// fba1236595f2d2bf21d414ba6e57d25256afada3 (Misaki 0.9.4), itself adapted
// from PaddleSpeech. Modifications: replace jieba and pypinyin with an explicit
// typed backend, use Unicode-scalar-safe word operations, freeze public values,
// validate backend records, and preserve Misaki's mixed-English boundaries.

import '../../core/backend.dart';
import '../../core/errors.dart';

/// One immutable word and part-of-speech pair entering tone sandhi.
final class ChineseSandhiWord {
  /// Creates a sandhi input word.
  const ChineseSandhiWord({required this.word, required this.partOfSpeech});

  /// Surface word, interpreted as Unicode scalar values by sandhi rules.
  final String word;

  /// Jieba-compatible part-of-speech tag.
  final String partOfSpeech;

  @override
  bool operator ==(Object other) =>
      other is ChineseSandhiWord &&
      word == other.word &&
      partOfSpeech == other.partOfSpeech;

  @override
  int get hashCode => Object.hash(word, partOfSpeech);

  @override
  String toString() => 'ChineseSandhiWord($word, $partOfSpeech)';
}

/// Injected lexical capabilities needed by the pure tone-sandhi rules.
///
/// [searchSegments] must match `jieba.cut_for_search`. [tone3Finals] must match
/// `pypinyin.lazy_pinyin` with `Style.FINALS_TONE3` and
/// `neutral_tone_with_five=True`. No jieba or pypinyin adapter is bundled. The
/// pure contract is platform-neutral; concrete adapters must validate their
/// own package and dictionary availability before use.
abstract interface class ChineseToneSandhiBackend implements MisakiBackend {
  /// Returns search-mode segments in backend order for [word].
  ///
  /// The list and every value must be non-empty, and each value must be a
  /// substring of [word].
  List<String> searchSegments(String word);

  /// Returns one pypinyin final per Unicode scalar in [word].
  ///
  /// Pypinyin can return an empty final for an unrecognized scalar and for
  /// `嗯`; the pinned frontend corrects `嗯` to `n2` and otherwise preserves
  /// the empty value until rendering.
  List<String> tone3Finals(String word);
}

/// Ordered Mandarin tone-sandhi and pre-merge stage from pinned Misaki.
final class ChineseToneSandhi {
  /// Creates a sandhi stage with an explicitly configured [backend].
  const ChineseToneSandhi({required this.backend});

  /// Backend used only for search segmentation and original tone-3 finals.
  final ChineseToneSandhiBackend backend;

  /// Applies the pinned pre-merge sequence.
  ///
  /// The order is 不, 一, reduplication, two continuous-third-tone passes,
  /// then 儿. Only lower-case `x` and `eng` are protected boundaries. A
  /// malformed word/POS or backend record throws [BackendFailureException].
  List<ChineseSandhiWord> preMerge(List<ChineseSandhiWord> words) {
    for (var index = 0; index < words.length; index++) {
      _validateWord(words[index], index: index);
    }
    var working = <_MutableSandhiWord>[
      for (final word in words) _MutableSandhiWord.from(word),
    ];
    working = _mergeBu(working);
    working = _mergeYi(working);
    working = _mergeReduplication(working);
    working = _mergeContinuousThreeTones(working);
    working = _mergeContinuousThreeTonesAtBoundary(working);
    working = _mergeEr(working);
    return List<ChineseSandhiWord>.unmodifiable(
      working.map((word) => word.freeze()),
    );
  }

  /// Applies 不, 一, neutral-tone, and third-tone rules in pinned order.
  ///
  /// [finals] must contain one final per Unicode scalar in [word]. Empty
  /// pypinyin finals are preserved unless a matching tone rule needs to
  /// inspect or replace their tone. The source list is not mutated and the
  /// result is immutable. Invalid lengths or search-segmentation records throw
  /// [BackendFailureException].
  List<String> modifyFinals(ChineseSandhiWord word, List<String> finals) {
    _validateWord(word);
    final characters = _scalarCharacters(word.word);
    if (finals.length != characters.length) {
      throw BackendFailureException(
        'Chinese tone-sandhi input `${word.word}` has ${characters.length} '
        'Unicode scalars but ${finals.length} finals.',
      );
    }
    final result = List<String>.of(finals);
    _applyBuSandhi(characters, result);
    _applyYiSandhi(characters, result);
    _applyNeutralSandhi(word, characters, result);
    _applyThreeSandhi(word.word, characters.length, result);
    return List<String>.unmodifiable(result);
  }

  List<_MutableSandhiWord> _mergeBu(List<_MutableSandhiWord> words) {
    final result = <_MutableSandhiWord>[];
    for (var index = 0; index < words.length; index++) {
      final current = words[index];
      var word = current.word;
      if (!_englishBoundaries.contains(current.partOfSpeech)) {
        final previousWord = index > 0 ? words[index - 1].word : null;
        if (previousWord == _bu) {
          word = '$previousWord$word';
        }
      }
      final nextPos = index + 1 < words.length
          ? words[index + 1].partOfSpeech
          : null;
      if (word != _bu ||
          nextPos == null ||
          _englishBoundaries.contains(nextPos)) {
        result.add(_MutableSandhiWord(word, current.partOfSpeech));
      }
    }
    return result;
  }

  List<_MutableSandhiWord> _mergeYi(List<_MutableSandhiWord> words) {
    var result = <_MutableSandhiWord>[];
    var skipNext = false;
    for (var index = 0; index < words.length; index++) {
      final current = words[index];
      if (skipNext) {
        skipNext = false;
        continue;
      }
      final isReduplicationBridge =
          index > 0 &&
          current.word == _yi &&
          index + 1 < words.length &&
          words[index - 1].word == words[index + 1].word &&
          words[index - 1].partOfSpeech == 'v' &&
          !_englishBoundaries.contains(words[index + 1].partOfSpeech);
      if (isReduplicationBridge) {
        result.last.word = '${result.last.word}$_yi${words[index + 1].word}';
        skipNext = true;
      } else {
        result.add(_MutableSandhiWord.copy(current));
      }
    }

    words = result;
    result = <_MutableSandhiWord>[];
    for (final current in words) {
      if (result.isNotEmpty &&
          result.last.word == _yi &&
          !_englishBoundaries.contains(current.partOfSpeech)) {
        result.last.word = '${result.last.word}${current.word}';
      } else {
        result.add(_MutableSandhiWord.copy(current));
      }
    }
    return result;
  }

  List<_MutableSandhiWord> _mergeReduplication(List<_MutableSandhiWord> words) {
    final result = <_MutableSandhiWord>[];
    for (final current in words) {
      if (result.isNotEmpty &&
          current.word == result.last.word &&
          !_englishBoundaries.contains(current.partOfSpeech)) {
        result.last.word = '${result.last.word}${current.word}';
      } else {
        result.add(_MutableSandhiWord.copy(current));
      }
    }
    return result;
  }

  List<_MutableSandhiWord> _mergeContinuousThreeTones(
    List<_MutableSandhiWord> words,
  ) {
    final originalFinals = _originalFinalsFor(words);
    final mergedAt = List<bool>.filled(words.length, false);
    final result = <_MutableSandhiWord>[];
    for (var index = 0; index < words.length; index++) {
      final current = words[index];
      final canMerge =
          !_englishBoundaries.contains(current.partOfSpeech) &&
          index > 0 &&
          _allToneThree(originalFinals[index - 1]) &&
          _allToneThree(originalFinals[index]) &&
          !mergedAt[index - 1];
      if (canMerge &&
          !_isReduplication(words[index - 1].word) &&
          _scalarLength(words[index - 1].word) + _scalarLength(current.word) <=
              3) {
        result.last.word = '${result.last.word}${current.word}';
        mergedAt[index] = true;
      } else {
        result.add(_MutableSandhiWord.copy(current));
      }
    }
    return result;
  }

  List<_MutableSandhiWord> _mergeContinuousThreeTonesAtBoundary(
    List<_MutableSandhiWord> words,
  ) {
    final originalFinals = _originalFinalsFor(words);
    final mergedAt = List<bool>.filled(words.length, false);
    final result = <_MutableSandhiWord>[];
    for (var index = 0; index < words.length; index++) {
      final current = words[index];
      final canMerge =
          !_englishBoundaries.contains(current.partOfSpeech) &&
          index > 0 &&
          _lastScalar(originalFinals[index - 1].last) == '3' &&
          _lastScalar(originalFinals[index].first) == '3' &&
          !mergedAt[index - 1];
      if (canMerge &&
          !_isReduplication(words[index - 1].word) &&
          _scalarLength(words[index - 1].word) + _scalarLength(current.word) <=
              3) {
        result.last.word = '${result.last.word}${current.word}';
        mergedAt[index] = true;
      } else {
        result.add(_MutableSandhiWord.copy(current));
      }
    }
    return result;
  }

  List<_MutableSandhiWord> _mergeEr(List<_MutableSandhiWord> words) {
    final result = <_MutableSandhiWord>[];
    for (var index = 0; index < words.length; index++) {
      final current = words[index];
      if (index > 0 &&
          current.word == '儿' &&
          !_englishBoundaries.contains(result.last.partOfSpeech)) {
        result.last.word = '${result.last.word}${current.word}';
      } else {
        result.add(_MutableSandhiWord.copy(current));
      }
    }
    return result;
  }

  List<List<String>> _originalFinalsFor(List<_MutableSandhiWord> words) =>
      <List<String>>[
        for (final word in words)
          _englishBoundaries.contains(word.partOfSpeech)
              ? <String>['0']
              : _originalFinals(word.word),
      ];

  List<String> _originalFinals(String word) {
    final finals = List<String>.of(
      _callBackend('tone-3 final lookup', () => backend.tone3Finals(word)),
    );
    final characters = _scalarCharacters(word);
    if (finals.length != characters.length) {
      throw BackendFailureException(
        'Chinese tone-sandhi backend ${backend.info} returned '
        '${finals.length} finals for `$word` '
        '(${characters.length} Unicode scalars).',
      );
    }
    for (var index = 0; index < characters.length; index++) {
      if (characters[index] == '嗯') {
        finals[index] = 'n2';
      }
    }
    return finals;
  }

  _WordSplit _splitWord(String word) {
    final segments = List<String>.of(
      _callBackend(
        'jieba search segmentation',
        () => backend.searchSegments(word),
      ),
    );
    if (segments.isEmpty) {
      throw BackendFailureException(
        'Chinese tone-sandhi backend ${backend.info} returned no search '
        'segments for `$word`.',
      );
    }
    if (segments.any((segment) => segment.isEmpty || !word.contains(segment))) {
      throw BackendFailureException(
        'Chinese tone-sandhi backend ${backend.info} returned malformed '
        'search segments for `$word`.',
      );
    }

    var first = segments.first;
    var firstLength = _scalarLength(first);
    for (final segment in segments.skip(1)) {
      final length = _scalarLength(segment);
      if (length < firstLength) {
        first = segment;
        firstLength = length;
      }
    }

    final characters = _scalarCharacters(word);
    if (word.indexOf(first) == 0) {
      final split = firstLength.clamp(0, characters.length);
      return _WordSplit(first, characters.sublist(split).join());
    }
    final end = (characters.length - firstLength).clamp(0, characters.length);
    return _WordSplit(characters.sublist(0, end).join(), first);
  }

  void _applyBuSandhi(List<String> word, List<String> finals) {
    if (word.length == 3 && word[1] == _bu) {
      finals[1] = _withTone(finals[1], '5');
      return;
    }
    for (var index = 0; index < word.length; index++) {
      if (word[index] == _bu &&
          index + 1 < word.length &&
          _lastScalar(finals[index + 1]) == '4') {
        finals[index] = _withTone(finals[index], '2');
      }
    }
  }

  void _applyYiSandhi(List<String> word, List<String> finals) {
    if (word.contains(_yi) &&
        word.where((character) => character != _yi).every(_isPythonNumeric)) {
      return;
    }
    if (word.length == 3 && word[1] == _yi && word.first == word.last) {
      finals[1] = _withTone(finals[1], '5');
      return;
    }
    if (word.length >= 2 && word[0] == '第' && word[1] == _yi) {
      finals[1] = _withTone(finals[1], '1');
      return;
    }
    for (var index = 0; index < word.length; index++) {
      if (word[index] != _yi || index + 1 >= word.length) {
        continue;
      }
      final nextTone = _lastScalar(finals[index + 1]);
      if (nextTone == '4' || nextTone == '5') {
        finals[index] = _withTone(finals[index], '2');
      } else if (!_yiPunctuation.contains(word[index + 1])) {
        finals[index] = _withTone(finals[index], '4');
      }
    }
  }

  void _applyNeutralSandhi(
    ChineseSandhiWord input,
    List<String> word,
    List<String> finals,
  ) {
    final surface = input.word;
    final pos = input.partOfSpeech;
    if (_mustNotNeutralToneWords.contains(surface)) {
      return;
    }

    final posInitial = _scalarCharacters(pos).first;
    for (var index = 1; index < word.length; index++) {
      if (word[index] == word[index - 1] &&
          _neutralReduplicationPos.contains(posInitial)) {
        finals[index] = _withTone(finals[index], '5');
      }
    }

    final geIndex = word.indexOf('个');
    if (word.isNotEmpty && _sentenceFinalParticles.contains(word.last)) {
      finals[finals.length - 1] = _withTone(finals.last, '5');
    } else if (word.isNotEmpty && _structuralParticles.contains(word.last)) {
      finals[finals.length - 1] = _withTone(finals.last, '5');
    } else if (word.length == 1 &&
        _aspectParticles.contains(word.single) &&
        _aspectPos.contains(pos)) {
      finals[finals.length - 1] = _withTone(finals.last, '5');
    } else if (word.length > 1 &&
        _pluralOrNominalSuffixes.contains(word.last) &&
        _pluralOrNominalPos.contains(pos)) {
      finals[finals.length - 1] = _withTone(finals.last, '5');
    } else if (word.length > 1 &&
        _locationSuffixes.contains(word.last) &&
        _locationPos.contains(pos)) {
      finals[finals.length - 1] = _withTone(finals.last, '5');
    } else if (word.length > 1 &&
        _directionComplements.contains(word.last) &&
        _directionLeads.contains(word[word.length - 2])) {
      finals[finals.length - 1] = _withTone(finals.last, '5');
    } else if ((geIndex >= 1 &&
            (_isPythonNumeric(word[geIndex - 1]) ||
                _gePredecessors.contains(word[geIndex - 1]))) ||
        surface == '个') {
      finals[geIndex] = _withTone(finals[geIndex], '5');
    } else if (_mustBeNeutral(surface)) {
      finals[finals.length - 1] = _withTone(finals.last, '5');
    }

    final split = _splitWord(surface);
    final splitIndex = _scalarLength(split.first).clamp(0, finals.length);
    final splitFinals = <List<String>>[
      finals.sublist(0, splitIndex),
      finals.sublist(splitIndex),
    ];
    final splitWords = <String>[split.first, split.second];
    for (var index = 0; index < splitWords.length; index++) {
      if (_mustBeNeutral(splitWords[index])) {
        if (splitFinals[index].isEmpty) {
          throw BackendFailureException(
            'Chinese tone-sandhi backend ${backend.info} returned search '
            'segments incompatible with `$surface`.',
          );
        }
        final last = splitFinals[index].length - 1;
        splitFinals[index][last] = _withTone(splitFinals[index][last], '5');
      }
    }
    finals
      ..clear()
      ..addAll(splitFinals.expand((sublist) => sublist));
  }

  void _applyThreeSandhi(String word, int wordLength, List<String> finals) {
    if (wordLength == 2 && _allToneThree(finals)) {
      finals[0] = _withTone(finals[0], '2');
      return;
    }
    if (wordLength == 3) {
      final split = _splitWord(word);
      final firstLength = _scalarLength(split.first).clamp(0, finals.length);
      if (_allToneThree(finals)) {
        if (firstLength == 2) {
          finals[0] = _withTone(finals[0], '2');
          finals[1] = _withTone(finals[1], '2');
        } else if (firstLength == 1) {
          finals[1] = _withTone(finals[1], '2');
        }
        return;
      }

      final splitFinals = <List<String>>[
        finals.sublist(0, firstLength),
        finals.sublist(firstLength),
      ];
      for (var index = 0; index < splitFinals.length; index++) {
        final sub = splitFinals[index];
        if (_allToneThree(sub) && sub.length == 2) {
          sub[0] = _withTone(sub[0], '2');
        } else if (index == 1 &&
            !_allToneThree(sub) &&
            sub.isNotEmpty &&
            splitFinals[0].isNotEmpty &&
            _lastScalar(sub[0]) == '3' &&
            _lastScalar(splitFinals[0].last) == '3') {
          final previousLast = splitFinals[0].length - 1;
          splitFinals[0][previousLast] = _withTone(
            splitFinals[0][previousLast],
            '2',
          );
        }
      }
      finals
        ..clear()
        ..addAll(splitFinals.expand((sublist) => sublist));
      return;
    }
    if (wordLength == 4) {
      final splitFinals = <List<String>>[
        finals.sublist(0, 2),
        finals.sublist(2),
      ];
      finals.clear();
      for (final sub in splitFinals) {
        if (_allToneThree(sub)) {
          sub[0] = _withTone(sub[0], '2');
        }
        finals.addAll(sub);
      }
    }
  }

  bool _mustBeNeutral(String word) =>
      _mustNeutralToneWords.contains(word) ||
      _mustNeutralToneWords.contains(_lastScalars(word, 2));

  bool _isPythonNumeric(String character) {
    if (_unicodeNumber.hasMatch(character)) {
      return true;
    }
    final scalar = character.runes.single;
    return _python15NumericLetters.contains(scalar);
  }

  bool _allToneThree(List<String> finals) =>
      finals.every((finalValue) => _lastScalar(finalValue) == '3');

  bool _isReduplication(String word) {
    final characters = _scalarCharacters(word);
    return characters.length == 2 && characters[0] == characters[1];
  }

  void _validateWord(ChineseSandhiWord word, {int? index}) {
    final location = index == null ? '' : ' at index $index';
    if (word.word.isEmpty) {
      throw BackendFailureException(
        'Chinese tone-sandhi word$location is empty.',
      );
    }
    if (word.partOfSpeech.isEmpty) {
      throw BackendFailureException(
        'Chinese tone-sandhi word `${word.word}`$location has an empty '
        'part-of-speech tag.',
      );
    }
  }

  T _callBackend<T>(String operation, T Function() call) {
    try {
      return call();
    } on MisakiException {
      rethrow;
    } on Exception catch (error) {
      throw BackendFailureException(
        'Chinese tone-sandhi backend ${backend.info} failed during '
        '$operation.',
        cause: error,
      );
    }
  }

  static String _withTone(String finalValue, String tone) {
    final scalars = finalValue.runes.toList(growable: false);
    if (scalars.isEmpty) {
      throw const BackendFailureException(
        'Chinese tone-sandhi cannot retone an empty final.',
      );
    }
    return '${String.fromCharCodes(scalars.sublist(0, scalars.length - 1))}'
        '$tone';
  }

  static String _lastScalar(String value) {
    final iterator = value.runes.iterator;
    if (!iterator.moveNext()) {
      throw const BackendFailureException(
        'Chinese tone-sandhi encountered an empty final.',
      );
    }
    var last = iterator.current;
    while (iterator.moveNext()) {
      last = iterator.current;
    }
    return String.fromCharCode(last);
  }

  static String _lastScalars(String value, int count) {
    final scalars = value.runes.toList(growable: false);
    final start = (scalars.length - count).clamp(0, scalars.length);
    return String.fromCharCodes(scalars.sublist(start));
  }

  static int _scalarLength(String value) => value.runes.length;

  static List<String> _scalarCharacters(String value) => <String>[
    for (final scalar in value.runes) String.fromCharCode(scalar),
  ];

  static const String _bu = '不';
  static const String _yi = '一';
  static const Set<String> _englishBoundaries = <String>{'x', 'eng'};
  static const Set<String> _neutralReduplicationPos = <String>{'n', 'v', 'a'};
  static const Set<String> _sentenceFinalParticles = <String>{
    '吧',
    '呢',
    '啊',
    '呐',
    '噻',
    '嘛',
    '吖',
    '嗨',
    '哦',
    '哒',
    '滴',
    '哩',
    '哟',
    '喽',
    '啰',
    '耶',
    '喔',
    '诶',
  };
  static const Set<String> _structuralParticles = <String>{'的', '地', '得'};
  static const Set<String> _aspectParticles = <String>{'了', '着', '过'};
  static const Set<String> _aspectPos = <String>{'ul', 'uz', 'ug'};
  static const Set<String> _pluralOrNominalSuffixes = <String>{'们', '子'};
  static const Set<String> _pluralOrNominalPos = <String>{'r', 'n'};
  static const Set<String> _locationSuffixes = <String>{'上', '下'};
  static const Set<String> _locationPos = <String>{'s', 'l', 'f'};
  static const Set<String> _directionComplements = <String>{'来', '去'};
  static const Set<String> _directionLeads = <String>{
    '上',
    '下',
    '进',
    '出',
    '回',
    '过',
    '起',
    '开',
  };
  static const Set<String> _gePredecessors = <String>{
    '几',
    '有',
    '两',
    '半',
    '多',
    '各',
    '整',
    '每',
    '做',
    '是',
  };
  static const Set<String> _yiPunctuation = <String>{
    '、',
    '：',
    '，',
    '；',
    '。',
    '？',
    '！',
    '“',
    '”',
    '‘',
    '’',
    "'",
    ':',
    ',',
    ';',
    '.',
    '?',
    '!',
  };

  static final RegExp _unicodeNumber = RegExp(r'^\p{N}$', unicode: true);

  // Unicode 15 code points outside general category N for which CPython 3.12
  // str.isnumeric() returns true. This covers the Han-number behavior used by
  // the pinned 一 rule without treating simplified 两 as numeric.
  static const Set<int> _python15NumericLetters = <int>{
    0x3405,
    0x3483,
    0x382a,
    0x3b4d,
    0x4e00,
    0x4e03,
    0x4e07,
    0x4e09,
    0x4e5d,
    0x4e8c,
    0x4e94,
    0x4e96,
    0x4ebf,
    0x4ec0,
    0x4edf,
    0x4ee8,
    0x4f0d,
    0x4f70,
    0x5104,
    0x5146,
    0x5169,
    0x516b,
    0x516d,
    0x5341,
    0x5343,
    0x5344,
    0x5345,
    0x534c,
    0x53c1,
    0x53c2,
    0x53c3,
    0x53c4,
    0x56db,
    0x58f1,
    0x58f9,
    0x5e7a,
    0x5efe,
    0x5eff,
    0x5f0c,
    0x5f0d,
    0x5f0e,
    0x5f10,
    0x62fe,
    0x634c,
    0x67d2,
    0x6f06,
    0x7396,
    0x767e,
    0x8086,
    0x842c,
    0x8cae,
    0x8cb3,
    0x8d30,
    0x9621,
    0x9646,
    0x964c,
    0x9678,
    0x96f6,
    0xf96b,
    0xf973,
    0xf978,
    0xf9b2,
    0xf9d1,
    0xf9d3,
    0xf9fd,
    0x20001,
    0x20064,
    0x200e2,
    0x20121,
    0x2092a,
    0x20983,
    0x2098c,
    0x2099c,
    0x20aea,
    0x20afd,
    0x20b19,
    0x22390,
    0x22998,
    0x23b1b,
    0x2626d,
    0x2f890,
  };

  static final Set<String> _mustNeutralToneWords = Set<String>.unmodifiable(
    _mustNeutralToneWordData.split(' '),
  );
  static final Set<String> _mustNotNeutralToneWords = Set<String>.unmodifiable(
    _mustNotNeutralToneWordData.split(' '),
  );

  static const String _mustNeutralToneWordData =
      '一辈 丈人 丈夫 上司 上头 下巴 下水 不由 世故 东家 东西 两口 丧气 丫头 主意 买卖 事情 云彩 交情 亲家 亲戚 人家 什么 介绍 休息 伙计 似的 位置 体面 作坊 佩服 使唤 '
      '便宜 倒腾 兄弟 先生 关系 养活 冒失 冤家 冤枉 冷战 凉快 凑合 凤凰 出息 分析 利害 利索 利落 别人 别扭 刺激 刺猬 前头 力气 功夫 动弹 动静 勤快 匀称 包涵 包袱 千斤 '
      '厉害 厚道 口袋 叫唤 吆喝 合同 吉他 名堂 名字 后头 吓唬 含糊 告示 告诉 和尚 咕噜 咖喱 咳嗽 哆嗦 哈欠 哑巴 唾沫 商量 喇叭 喇嘛 喉咙 喜欢 喽啰 嘀咕 嘟囔 嘱咐 嘴巴 '
      '困难 在乎 地方 地道 壮实 外甥 多么 多少 大人 大夫 大意 大方 大爷 太阳 头发 女婿 奴才 妖精 妥当 妯娌 姐夫 姑娘 委屈 姥爷 娘家 婆家 媒人 媳妇 嫁妆 字号 学问 官司 '
      '实在 客气 家伙 寒碜 寡妇 对付 对头 将军 将就 小伙 小气 少爷 尾巴 屁股 岁数 工夫 差事 巴掌 巴结 师傅 师父 希罕 帐篷 帮手 干事 幸福 庄稼 应酬 开通 弄堂 弟兄 张罗 '
      '得罪 心思 志气 忙活 快活 念叨 念头 怎么 思量 怪物 悟性 惦记 意思 意识 懒得 戏弄 戒指 扁担 扎实 扑腾 打发 打听 打扮 打算 打量 扫帚 扫把 折腾 护士 报复 抬举 拖沓 '
      '招呼 招牌 拨弄 拳头 拾掇 指头 指甲 挑剔 挖苦 提防 收成 收拾 故事 新鲜 时候 明白 暖和 月亮 月饼 朋友 木匠 木头 本事 机灵 枇杷 枕头 架势 柴火 栅栏 核桃 棉花 棒槌 '
      '棺材 槟榔 模糊 欺负 正经 母亲 比方 泥鳅 活泼 浪头 消息 清楚 温和 溜达 滑溜 漂亮 火候 灯笼 炊帚 点心 烂糊 烟筒 烧饼 热闹 照顾 熟悉 爱人 父亲 爽快 牌楼 牙碜 牢骚 '
      '牲口 特务 状元 狐狸 玄乎 玫瑰 玻璃 琉璃 琢磨 琵琶 甘蔗 甜头 生意 畜生 疏忽 疙瘩 疟疾 痛快 痢疾 白净 盘算 盘缠 相声 眉毛 眨巴 眯缝 眼睛 知识 石匠 石头 石榴 码头 '
      '砚台 祖宗 福气 秀才 秀气 秧歌 称呼 稀罕 稳当 窗户 窝囊 窟窿 笑话 笑语 笤帚 答应 算盘 算计 篱笆 簸箕 粮食 精神 糊涂 糟蹋 糨糊 累赘 红火 结实 编辑 罐头 罗嗦 翻腾 '
      '老婆 老实 老爷 耳朵 耷拉 耽搁 耽误 聪明 胡同 胡琴 胡萝 胭脂 胳膊 能耐 脊梁 脑袋 脾气 膏药 自在 舌头 舒坦 舒服 芝麻 苍蝇 苗头 苗条 荒唐 荸荠 菩萨 萝卜 葡萄 葫芦 '
      '薄荷 蘑菇 蚂蚱 蛤蟆 蜡烛 行当 行李 街坊 衙门 衣服 衣裳 补丁 裁缝 见识 规矩 计划 认识 记号 记性 讲究 豆腐 财主 费用 趔趄 跟头 跳蚤 踏实 转悠 软和 过去 运气 这个 '
      '这么 连累 迷糊 造化 逻辑 道士 邋遢 那个 那么 部分 里头 里脊 钥匙 铁匠 铃铛 铺盖 锄头 门道 闺女 阔气 队伍 难为 风筝 馄饨 馒头 首饰 马虎 骆驼 骨头 高粱 鸳鸯 麻利 '
      '麻烦';

  static const String _mustNotNeutralToneWordData =
      '人人 以下 佼佼 冉冉 分子 卵子 原子 吵吵 哈哈 女子 娃哈哈 学子 家家户户 局地 干嘛 幺幺 恳恳 想想 打打 攘攘 数数 整整 死死 熙熙 瓜子 电子 男子 留得 石子 算子 考考 '
      '耕地 花花草草 莘莘 莲子 落地 虎虎 袅袅 量子 青青';
}

final class _MutableSandhiWord {
  _MutableSandhiWord(this.word, this.partOfSpeech);

  factory _MutableSandhiWord.from(ChineseSandhiWord word) =>
      _MutableSandhiWord(word.word, word.partOfSpeech);

  factory _MutableSandhiWord.copy(_MutableSandhiWord word) =>
      _MutableSandhiWord(word.word, word.partOfSpeech);

  String word;
  final String partOfSpeech;

  ChineseSandhiWord freeze() =>
      ChineseSandhiWord(word: word, partOfSpeech: partOfSpeech);
}

final class _WordSplit {
  const _WordSplit(this.first, this.second);

  final String first;
  final String second;
}
