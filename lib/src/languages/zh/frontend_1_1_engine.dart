// Copyright (c) 2021 PaddlePaddle Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Dart adaptation of hexgrad/misaki/misaki/zh.py and zh_frontend.py at
// fba1236595f2d2bf21d414ba6e57d25256afada3 (Misaki 0.9.4), whose frontend
// was adapted from PaddleSpeech. Modifications: replace cn2an, jieba, and
// pypinyin with one typed injected backend; compose the pure tone-sandhi
// stage; use Unicode scalar operations; and expose internal frontend tokens
// separately while retaining the outer ZHG2P null-token contract.

import '../../core/backend.dart';
import '../../core/constants.dart';
import '../../core/engine.dart';
import '../../core/errors.dart';
import '../../core/python_whitespace.dart';
import '../../core/result.dart';
import '../../core/token.dart';
import 'legacy_helpers.dart';
import 'tone_sandhi.dart';

/// External capabilities required by the pinned Chinese frontend 1.1 path.
///
/// Implementations must match `cn2an.transform(..., "an2cn")`,
/// `jieba.posseg.lcut`, `jieba.cut_for_search`, and `pypinyin.lazy_pinyin`
/// with the styles named by each method. No Python or native adapter is
/// bundled with the pure package. The contract itself is platform-neutral;
/// concrete adapters must validate their package, dictionary, and platform
/// requirements before being supplied to an engine.
abstract interface class ChineseFrontend11Backend
    implements ChineseToneSandhiBackend, MisakiBackend {
  /// Performs cn2an-equivalent `an2cn` normalization over the complete input.
  String normalizeNumbers(String text);

  /// Returns the ordered jieba word/POS stream for one frontend segment.
  ///
  /// Words and tags must be non-empty, and the words must concatenate to the
  /// exact input text without deletion or reordering.
  List<ChineseSandhiWord> segmentWithPartOfSpeech(String text);

  /// Returns one pypinyin `Style.INITIALS` value per source scalar.
  ///
  /// Empty initial strings are valid for zero-initial syllables.
  List<String> initials(String word);
}

/// Optional synchronous English callback used at the outer mixed-script
/// boundary.
///
/// The callback receives one CPython-trimmed ASCII-letter/apostrophe/hyphen
/// segment and must return its already-rendered phoneme string.
typedef ChineseEnglishG2p = String Function(String text);

/// Pure implementation of pinned `ZHFrontend` version 1.1.
///
/// [convertSegment] mirrors the internal frontend and therefore returns its
/// raw token list. The outer [ChineseFrontend11G2pEngine] intentionally
/// discards that list because pinned `ZHG2P(version: "1.1")` returns
/// `tokens: null`.
final class ChineseFrontend11 {
  /// Creates a reusable frontend with an explicitly provisioned [backend].
  ChineseFrontend11({
    required this.backend,
    this.unknownMarker = defaultUnknownMarker,
  }) : _sandhi = ChineseToneSandhi(backend: backend);

  /// Backend supplying normalization-independent lexical stages.
  final ChineseFrontend11Backend backend;

  /// Marker rendered for phones and tokens unavailable in the pinned map.
  final String unknownMarker;

  final ChineseToneSandhi _sandhi;

  /// Converts one non-English frontend segment and retains internal tokens.
  ///
  /// This method does not run cn2an normalization or mixed-English splitting;
  /// use [ChineseFrontend11G2pEngine.convert] for the outer contract. It throws
  /// [BackendFailureException] for malformed provider records and preserves a
  /// typed [MisakiException] raised directly by an adapter.
  G2pResult convertSegment(String text, {bool withErhua = true}) {
    final segmented = List<ChineseSandhiWord>.of(
      _callBackend(
        'jieba POS segmentation',
        () => backend.segmentWithPartOfSpeech(text),
      ),
    );
    if ((text.isNotEmpty && segmented.isEmpty) ||
        segmented.map((segment) => segment.word).join() != text) {
      throw BackendFailureException(
        'Chinese frontend backend ${backend.info} returned segmentation that '
        'does not preserve the non-empty input segment.',
      );
    }
    final words = _sandhi.preMerge(segmented);
    final tokens = <MisakiToken>[];

    for (final input in words) {
      final word = input.word;
      var partOfSpeech = input.partOfSpeech;
      if (partOfSpeech == 'x' && _isAllBasicCjk(word)) {
        partOfSpeech = 'X';
      } else if (partOfSpeech != 'x' && _punctuation.contains(word)) {
        partOfSpeech = 'x';
      }

      if (partOfSpeech == 'x' || partOfSpeech == 'eng') {
        if (!_isPythonWhitespaceOnly(word)) {
          tokens.add(
            MisakiToken(
              text: word,
              tag: partOfSpeech,
              whitespace: '',
              phonemes: partOfSpeech == 'x' && _punctuation.contains(word)
                  ? word
                  : null,
            ),
          );
        } else if (tokens.isNotEmpty) {
          tokens[tokens.length - 1] = _copyToken(
            tokens.last,
            whitespace: '${tokens.last.whitespace}$word',
          );
        }
        continue;
      }

      if (tokens.isNotEmpty &&
          tokens.last.tag != 'x' &&
          tokens.last.tag != 'eng' &&
          tokens.last.whitespace.isEmpty) {
        tokens[tokens.length - 1] = _copyToken(tokens.last, whitespace: '/');
      }

      final values = _initialsAndFinals(word);
      var initials = values.initials;
      var finals = _sandhi.modifyFinals(
        ChineseSandhiWord(word: word, partOfSpeech: partOfSpeech),
        values.finals,
      );
      if (withErhua) {
        final merged = _mergeErhua(initials, finals, word, partOfSpeech);
        initials = merged.initials;
        finals = merged.finals;
      }

      tokens.add(
        MisakiToken(
          text: word,
          tag: partOfSpeech,
          whitespace: '',
          phonemes: _renderPhones(initials, finals),
        ),
      );
    }

    return G2pResult(
      phonemes: tokens
          .map((token) => token.render(unknownMarker: unknownMarker))
          .join(),
      tokens: tokens,
    );
  }

  _InitialsFinals _initialsAndFinals(String word) {
    final initials = List<String>.of(
      _callBackend('pinyin initial lookup', () => backend.initials(word)),
    );
    final finals = List<String>.of(
      _callBackend('pinyin final lookup', () => backend.tone3Finals(word)),
    );
    final characters = _scalarCharacters(word);
    if (initials.length != characters.length ||
        finals.length != characters.length) {
      throw BackendFailureException(
        'Chinese frontend backend ${backend.info} returned malformed pinyin '
        'for `$word`; expected one initial and one final per Unicode scalar.',
      );
    }
    for (var index = 0; index < characters.length; index++) {
      if (characters[index] == '嗯') {
        if (index >= finals.length) {
          throw BackendFailureException(
            'Chinese frontend backend ${backend.info} returned too few '
            'finals to apply the pinned 嗯 correction.',
          );
        }
        finals[index] = 'n2';
      }
    }

    final pairedInitials = <String>[];
    final pairedFinals = <String>[];
    for (var index = 0; index < characters.length; index++) {
      final initial = initials[index];
      var finalValue = finals[index];
      if (_plainIWithTone.hasMatch(finalValue)) {
        if (_alveolarInitials.contains(initial)) {
          finalValue = finalValue.replaceAll('i', 'ii');
        } else if (_retroflexInitials.contains(initial)) {
          finalValue = finalValue.replaceAll('i', 'iii');
        }
      }
      pairedInitials.add(initial);
      pairedFinals.add(finalValue);
    }
    return _InitialsFinals(pairedInitials, pairedFinals);
  }

  _InitialsFinals _mergeErhua(
    List<String> inputInitials,
    List<String> inputFinals,
    String word,
    String partOfSpeech,
  ) {
    final initials = List<String>.of(inputInitials);
    final finals = List<String>.of(inputFinals);
    final characters = _scalarCharacters(word);

    if (finals.isNotEmpty &&
        characters.isNotEmpty &&
        characters.last == '儿' &&
        finals.last == 'er1') {
      finals[finals.length - 1] = 'er2';
    }

    if (!_mustErhua.contains(word) &&
        (_notErhua.contains(word) ||
            partOfSpeech == 'a' ||
            partOfSpeech == 'j' ||
            partOfSpeech == 'nr')) {
      return _InitialsFinals(initials, finals);
    }
    if (finals.length != characters.length) {
      return _InitialsFinals(initials, finals);
    }

    final newInitials = <String>[];
    final newFinals = <String>[];
    for (var index = 0; index < finals.length; index++) {
      final finalValue = finals[index];
      final merge =
          index == finals.length - 1 &&
          characters[index] == '儿' &&
          (finalValue == 'er2' || finalValue == 'er5') &&
          !_notErhua.contains(_lastScalars(word, 2)) &&
          newFinals.isNotEmpty;
      if (merge) {
        newFinals[newFinals.length - 1] = _insertErhuaMarker(newFinals.last);
      } else {
        newInitials.add(initials[index]);
        newFinals.add(finalValue);
      }
    }
    return _InitialsFinals(newInitials, newFinals);
  }

  String _renderPhones(List<String> initials, List<String> finals) {
    final phones = <String>[];
    final pairedLength = initials.length < finals.length
        ? initials.length
        : finals.length;
    for (var index = 0; index < pairedLength; index++) {
      final initial = initials[index];
      final finalValue = finals[index];
      if (initial.isNotEmpty) {
        phones.add(initial);
      }
      if (finalValue.isNotEmpty &&
          (!_punctuation.contains(finalValue) || finalValue != initial)) {
        phones.add(finalValue);
      }
    }

    final expanded = phones
        .join('_')
        .replaceAll('_eR', '_er')
        .replaceAll('R', '_R')
        .replaceAllMapped(_beforeAsciiDigit, (_) => '_');
    return expanded
        .split('_')
        .map((phone) => _phoneMap[phone] ?? unknownMarker)
        .join();
  }

  T _callBackend<T>(String operation, T Function() call) {
    try {
      return call();
    } on MisakiException {
      rethrow;
    } on Exception catch (error) {
      throw BackendFailureException(
        'Chinese frontend backend ${backend.info} failed during $operation.',
        cause: error,
      );
    }
  }
}

/// Pinned outer `ZHG2P(version: "1.1")` mixed-script contract.
///
/// The engine is pure Dart and platform-neutral after callers provide a
/// synchronous [ChineseFrontend11Backend]. It performs no package discovery,
/// model loading, subprocess invocation, or runtime download. Every successful
/// outer result has `tokens == null`, matching pinned upstream behavior.
final class ChineseFrontend11G2pEngine implements G2pEngine {
  /// Creates the 1.1 engine with explicit Chinese and optional English stages.
  ChineseFrontend11G2pEngine({
    required this.backend,
    this.unknownMarker = defaultUnknownMarker,
    this.englishG2p,
  }) : _frontend = ChineseFrontend11(
         backend: backend,
         unknownMarker: unknownMarker,
       );

  /// Backend supplying cn2an, jieba, and pypinyin-equivalent values.
  final ChineseFrontend11Backend backend;

  /// Marker used when English conversion or a phone mapping is unavailable.
  final String unknownMarker;

  /// Optional equivalent of pinned `en_callable`.
  final ChineseEnglishG2p? englishG2p;

  final ChineseFrontend11 _frontend;

  @override
  G2pResult convert(String text) {
    if (_isPythonWhitespaceOnly(text)) {
      return G2pResult(phonemes: '', tokens: null);
    }
    final normalized = _callBackend(
      'cn2an-equivalent number normalization',
      () => backend.normalizeNumbers(text),
    );
    final mapped = mapLegacyChinesePunctuation(normalized);
    final rendered = <String>[];
    for (final match in _mixedScriptSegments.allMatches(mapped)) {
      final english = _pythonTrim(match.group(1) ?? '');
      final chinese = _pythonTrim(match.group(2) ?? '');
      if (chinese.isNotEmpty) {
        rendered.add(_frontend.convertSegment(chinese).phonemes);
      } else if (englishG2p == null) {
        rendered.add(unknownMarker);
      } else {
        try {
          rendered.add(englishG2p!(english));
        } on MisakiException {
          rethrow;
        } on Exception catch (error) {
          throw BackendFailureException(
            'Chinese frontend English callback failed.',
            cause: error,
          );
        }
      }
    }
    return G2pResult(phonemes: rendered.join(' '), tokens: null);
  }

  T _callBackend<T>(String operation, T Function() call) {
    try {
      return call();
    } on MisakiException {
      rethrow;
    } on Exception catch (error) {
      throw BackendFailureException(
        'Chinese frontend backend ${backend.info} failed during $operation.',
        cause: error,
      );
    }
  }
}

MisakiToken _copyToken(MisakiToken token, {required String whitespace}) =>
    MisakiToken(
      text: token.text,
      tag: token.tag,
      whitespace: whitespace,
      phonemes: token.phonemes,
      startTimeSeconds: token.startTimeSeconds,
      endTimeSeconds: token.endTimeSeconds,
      metadata: token.metadata,
    );

bool _isAllBasicCjk(String word) =>
    word.isNotEmpty &&
    word.runes.every((rune) => rune >= 0x4e00 && rune <= 0x9fff);

bool _isPythonWhitespaceOnly(String text) =>
    text.runes.every(isPythonWhitespace);

String _pythonTrim(String value) {
  final scalars = value.runes.toList(growable: false);
  var start = 0;
  while (start < scalars.length && isPythonWhitespace(scalars[start])) {
    start++;
  }
  var end = scalars.length;
  while (end > start && isPythonWhitespace(scalars[end - 1])) {
    end--;
  }
  return String.fromCharCodes(scalars.sublist(start, end));
}

List<String> _scalarCharacters(String value) => <String>[
  for (final scalar in value.runes) String.fromCharCode(scalar),
];

String _lastScalars(String value, int count) {
  final scalars = value.runes.toList(growable: false);
  final start = (scalars.length - count).clamp(0, scalars.length);
  return String.fromCharCodes(scalars.sublist(start));
}

String _insertErhuaMarker(String finalValue) {
  final scalars = finalValue.runes.toList(growable: false);
  if (scalars.isEmpty) {
    throw const BackendFailureException(
      'Chinese frontend cannot merge erhua into an empty final.',
    );
  }
  return '${String.fromCharCodes(scalars.sublist(0, scalars.length - 1))}'
      'R${String.fromCharCode(scalars.last)}';
}

final class _InitialsFinals {
  _InitialsFinals(Iterable<String> initials, Iterable<String> finals)
    : initials = List<String>.of(initials),
      finals = List<String>.of(finals);

  final List<String> initials;
  final List<String> finals;
}

final RegExp _plainIWithTone = RegExp(r'^i\d');
final RegExp _beforeAsciiDigit = RegExp(r'(?=\d)');
final RegExp _mixedScriptSegments = RegExp(
  r"([A-Za-z \-']*[A-Za-z][A-Za-z \-']*)|([^A-Za-z]+)",
);

const Set<String> _alveolarInitials = <String>{'z', 'c', 's'};
const Set<String> _retroflexInitials = <String>{'zh', 'ch', 'sh', 'r'};
const Set<String> _punctuation = <String>{
  ';',
  ':',
  ',',
  '.',
  '!',
  '?',
  '—',
  '…',
  '"',
  '(',
  ')',
  '“',
  '”',
};

const Map<String, String> _phoneMap = <String, String>{
  'b': 'ㄅ',
  'p': 'ㄆ',
  'm': 'ㄇ',
  'f': 'ㄈ',
  'd': 'ㄉ',
  't': 'ㄊ',
  'n': 'ㄋ',
  'l': 'ㄌ',
  'g': 'ㄍ',
  'k': 'ㄎ',
  'h': 'ㄏ',
  'j': 'ㄐ',
  'q': 'ㄑ',
  'x': 'ㄒ',
  'zh': 'ㄓ',
  'ch': 'ㄔ',
  'sh': 'ㄕ',
  'r': 'ㄖ',
  'z': 'ㄗ',
  'c': 'ㄘ',
  's': 'ㄙ',
  'a': 'ㄚ',
  'o': 'ㄛ',
  'e': 'ㄜ',
  'ie': 'ㄝ',
  'ai': 'ㄞ',
  'ei': 'ㄟ',
  'ao': 'ㄠ',
  'ou': 'ㄡ',
  'an': 'ㄢ',
  'en': 'ㄣ',
  'ang': 'ㄤ',
  'eng': 'ㄥ',
  'er': 'ㄦ',
  'i': 'ㄧ',
  'u': 'ㄨ',
  'v': 'ㄩ',
  'ii': 'ㄭ',
  'iii': '十',
  've': '月',
  'ia': '压',
  'ian': '言',
  'iang': '阳',
  'iao': '要',
  'in': '阴',
  'ing': '应',
  'iong': '用',
  'iou': '又',
  'ong': '中',
  'ua': '穵',
  'uai': '外',
  'uan': '万',
  'uang': '王',
  'uei': '为',
  'uen': '文',
  'ueng': '瓮',
  'uo': '我',
  'van': '元',
  'vn': '云',
  ' ': ' ',
  ';': ';',
  ':': ':',
  ',': ',',
  '.': '.',
  '!': '!',
  '?': '?',
  '/': '/',
  '—': '—',
  '…': '…',
  '"': '"',
  '(': '(',
  ')': ')',
  '“': '“',
  '”': '”',
  '1': '1',
  '2': '2',
  '3': '3',
  '4': '4',
  '5': '5',
  'R': 'R',
};

/// Builds the render-scalar inventory from the pinned frontend 1.1 phone map.
///
/// This is an internal source-table bridge for `inventory.dart`. It includes
/// mapped tone digits and structural punctuation/spacing entries because they
/// are explicit phone-map values, but cannot include configurable unknown or
/// injected English output.
Set<String> frontend11ChineseRenderedScalars() => Set<String>.unmodifiable(
  _phoneMap.values.expand(
    (value) => value.runes.map<String>(String.fromCharCode),
  ),
);

const Set<String> _mustErhua = <String>{
  '小院儿',
  '胡同儿',
  '范儿',
  '老汉儿',
  '撒欢儿',
  '寻老礼儿',
  '妥妥儿',
  '媳妇儿',
};

const Set<String> _notErhua = <String>{
  '虐儿',
  '为儿',
  '护儿',
  '瞒儿',
  '救儿',
  '替儿',
  '有儿',
  '一儿',
  '我儿',
  '俺儿',
  '妻儿',
  '拐儿',
  '聋儿',
  '乞儿',
  '患儿',
  '幼儿',
  '孤儿',
  '婴儿',
  '婴幼儿',
  '连体儿',
  '脑瘫儿',
  '流浪儿',
  '体弱儿',
  '混血儿',
  '蜜雪儿',
  '舫儿',
  '祖儿',
  '美儿',
  '应采儿',
  '可儿',
  '侄儿',
  '孙儿',
  '侄孙儿',
  '女儿',
  '男儿',
  '红孩儿',
  '花儿',
  '虫儿',
  '马儿',
  '鸟儿',
  '猪儿',
  '猫儿',
  '狗儿',
  '少儿',
};
