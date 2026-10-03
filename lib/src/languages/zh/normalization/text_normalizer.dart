// Copyright (c) 2021 PaddlePaddle Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Dart adaptation of misaki/zh_normalization/text_normalization.py and its
// directly used width constants from hexgrad/misaki at
// fba1236595f2d2bf21d414ba6e57d25256afada3 (Misaki 0.9.4). The pinned files
// were copied from PaddleSpeech. Modifications: inject traditional-character
// conversion instead of embedding char_convert.py, use scalar-safe width and
// whitespace handling, and return an immutable sentence list.

import '../../../core/python_whitespace.dart';
import 'character_converter.dart';
import 'chronology_rules.dart';
import 'number_rules.dart';
import 'phone_rules.dart';
import 'quantifier_rules.dart';

/// Ordered pure-text pipeline copied from the pinned Chinese NSW normalizer.
///
/// Number, date/time, phone, temperature, measure, width, sentence splitting,
/// and post-replacement behavior is implemented in Dart. Traditional-character
/// conversion remains explicit through [converter]. The pipeline is
/// synchronous and platform-neutral and performs no file or network access.
final class ChineseTextNormalizer {
  /// Creates a normalizer with an explicitly supplied character [converter].
  const ChineseTextNormalizer({required this.converter});

  /// Traditional-to-simplified converter used before every sentence pipeline.
  final ChineseCharacterConverter converter;

  /// Splits and normalizes [text], preserving the pinned sentence order.
  ///
  /// The returned list is immutable. As upstream, empty input yields one empty
  /// sentence rather than an empty list.
  List<String> normalize(String text) =>
      List<String>.unmodifiable(_split(text).map(normalizeSentence));

  /// Normalizes one sentence with the exact pinned stage order.
  String normalizeSentence(String text) {
    var sentence = converter.traditionalToSimplified(text);
    sentence = _fullwidthLettersAndDigitsToHalfwidth(sentence);

    sentence = ChineseChronologyRules.replaceDates(sentence);
    sentence = ChineseChronologyRules.replaceSeparatedDates(sentence);

    sentence = ChineseChronologyRules.replaceTimeRanges(sentence);
    sentence = ChineseChronologyRules.replaceTimes(sentence);

    sentence = ChineseQuantifierRules.replaceTemperatures(sentence);
    sentence = ChineseQuantifierRules.replaceMeasures(sentence);
    sentence = ChineseNumberRules.replaceFractions(sentence);
    sentence = ChineseNumberRules.replacePercentages(sentence);
    sentence = ChinesePhoneRules.replaceMobilePhones(sentence);

    sentence = ChinesePhoneRules.replaceTelephones(sentence);
    sentence = ChinesePhoneRules.replaceNationalUniformNumbers(sentence);

    sentence = ChineseNumberRules.replaceRanges(sentence);
    sentence = ChineseNumberRules.replaceNegativeIntegers(sentence);
    sentence = ChineseNumberRules.replaceDecimals(sentence);
    sentence = ChineseNumberRules.replacePositiveQuantifiers(sentence);
    sentence = ChineseNumberRules.replaceDefaultNumbers(sentence);
    sentence = ChineseNumberRules.replaceNumbers(sentence);
    return _postReplace(sentence);
  }

  static List<String> _split(String text) {
    var value = text.replaceAll(' ', '');
    value = value.replaceAll(_splitSpecialCharacters, '');
    value = value.replaceAllMapped(
      _sentenceSplitter,
      (match) => '${match[1]}\n',
    );
    value = _pythonTrim(value);
    return <String>[
      for (final sentence in value.split(_newlineRuns)) _pythonTrim(sentence),
    ];
  }

  static String _fullwidthLettersAndDigitsToHalfwidth(String value) {
    final result = StringBuffer();
    for (final scalar in value.runes) {
      final isFullwidthLetter =
          (scalar >= 0xff21 && scalar <= 0xff3a) ||
          (scalar >= 0xff41 && scalar <= 0xff5a);
      final isFullwidthDigit = scalar >= 0xff10 && scalar <= 0xff19;
      result.writeCharCode(
        isFullwidthLetter || isFullwidthDigit ? scalar - 0xfee0 : scalar,
      );
    }
    // The upstream F2H_SPACE map has String rather than integer keys, so
    // Python str.translate ignores it. U+3000 intentionally remains unchanged.
    return result.toString();
  }

  static String _postReplace(String sentence) {
    var result = sentence;
    for (final replacement in _postReplacements) {
      result = result.replaceAll(replacement.$1, replacement.$2);
    }
    return result.replaceAll(_postSpecialCharacters, '');
  }

  static String _pythonTrim(String value) {
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

  static final RegExp _sentenceSplitter = RegExp(r'([：、，；。？！,;?!][”’]?)');
  static final RegExp _splitSpecialCharacters = RegExp(
    r'[——《》【】<=>{}()（）#&@“”^_|…\\]',
  );
  static final RegExp _postSpecialCharacters = RegExp(
    r'[-——《》【】<=>{}()（）#&@“”^_|…\\]',
  );
  static final RegExp _newlineRuns = RegExp(r'\n+');

  static const List<(String, String)> _postReplacements = <(String, String)>[
    ('/', '每'),
    ('~', '至'),
    ('～', '至'),
    ('①', '一'),
    ('②', '二'),
    ('③', '三'),
    ('④', '四'),
    ('⑤', '五'),
    ('⑥', '六'),
    ('⑦', '七'),
    ('⑧', '八'),
    ('⑨', '九'),
    ('⑩', '十'),
    ('α', '阿尔法'),
    ('β', '贝塔'),
    ('γ', '伽玛'),
    ('Γ', '伽玛'),
    ('δ', '德尔塔'),
    ('Δ', '德尔塔'),
    ('ε', '艾普西龙'),
    ('ζ', '捷塔'),
    ('η', '依塔'),
    ('θ', '西塔'),
    ('Θ', '西塔'),
    ('ι', '艾欧塔'),
    ('κ', '喀帕'),
    ('λ', '拉姆达'),
    ('Λ', '拉姆达'),
    ('μ', '缪'),
    ('ν', '拗'),
    ('ξ', '克西'),
    ('Ξ', '克西'),
    ('ο', '欧米克伦'),
    ('π', '派'),
    ('Π', '派'),
    ('ρ', '肉'),
    ('ς', '西格玛'),
    ('Σ', '西格玛'),
    ('σ', '西格玛'),
    ('τ', '套'),
    ('υ', '宇普西龙'),
    ('φ', '服艾'),
    ('Φ', '服艾'),
    ('χ', '器'),
    ('ψ', '普赛'),
    ('Ψ', '普赛'),
    ('ω', '欧米伽'),
    ('Ω', '欧米伽'),
  ];
}
