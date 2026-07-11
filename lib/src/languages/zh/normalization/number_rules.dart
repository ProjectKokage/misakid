// Copyright (c) 2021 PaddlePaddle Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Dart adaptation of misaki/zh_normalization/num.py from hexgrad/misaki at
// fba1236595f2d2bf21d414ba6e57d25256afada3 (Misaki 0.9.4). The pinned file
// was copied from PaddleSpeech. Modifications: use Unicode-scalar-safe digit
// handling and expose sentence-rule stages without Python regular expressions.

import '../../../core/python312_unicode.dart';

/// Pure number-verbalization rules used by the pinned Chinese normalizer.
///
/// These methods intentionally preserve upstream replacement order and quirks.
/// Unicode decimal characters match the upstream regular expressions, but the
/// copied word table only accepts ASCII digits and reports the mismatch as a
/// [FormatException], corresponding to upstream's `KeyError`.
final class ChineseNumberRules {
  ChineseNumberRules._();

  static const String _digitPattern = python312DecimalRegExpPattern;

  static final RegExp _fractionPattern = RegExp(
    '(-?)($_digitPattern+)/($_digitPattern+)',
    unicode: true,
  );
  static final RegExp _percentagePattern = RegExp(
    '(-?)($_digitPattern+(?:\\.$_digitPattern+)?)%',
    unicode: true,
  );
  static final RegExp _negativeIntegerPattern = RegExp(
    '(-)($_digitPattern+)',
    unicode: true,
  );
  static final RegExp _defaultNumberPattern = RegExp(
    '$_digitPattern{3}$_digitPattern*',
    unicode: true,
  );

  // The top-level alternation is deliberate: in Python the optional minus is
  // part of the integer branch, not the leading-dot branch.
  static final RegExp _decimalPattern = RegExp(
    '(-?)(($_digitPattern+)(\\.$_digitPattern+))|(\\.($_digitPattern+))',
    unicode: true,
  );
  static final RegExp _numberPattern = RegExp(
    '(-?)(($_digitPattern+)(\\.$_digitPattern+)?)|(\\.($_digitPattern+))',
    unicode: true,
  );

  static final String _rangeNumberPattern =
      '(?:-?$_digitPattern+(?:\\.$_digitPattern+)?|\\.$_digitPattern+)';
  static final RegExp _rangePattern = RegExp(
    '($_rangeNumberPattern)[-~]($_rangeNumberPattern)',
    unicode: true,
  );

  static final RegExp _positiveQuantifierPattern = RegExp(
    '($_digitPattern+)([多余几+])?($_commonQuantifiers)',
    unicode: true,
  );

  /// Verbalizes an unsigned cardinal using the copied 万/亿 recursion.
  static String verbalizeCardinal(String value) {
    if (value.isEmpty) {
      return '';
    }

    final scalars = _scalarCharacters(value);
    var start = 0;
    while (start < scalars.length && scalars[start] == '0') {
      start++;
    }
    if (start == scalars.length) {
      return '零';
    }

    var symbols = _getValue(scalars.sublist(start));
    if (symbols.length >= 2 && symbols[0] == '一' && symbols[1] == '十') {
      symbols = symbols.sublist(1);
    }
    return symbols.join();
  }

  /// Verbalizes each digit independently, optionally reading 一 as 幺.
  static String verbalizeDigits(String value, {bool alternateOne = false}) {
    final result = StringBuffer();
    for (final digit in _scalarCharacters(value)) {
      final word = _digitWord(digit);
      result.write(alternateOne && word == '一' ? '幺' : word);
    }
    return result.toString();
  }

  /// Verbalizes one unsigned integer or decimal string.
  static String numberToChinese(String value) {
    final parts = value.split('.');
    if (parts.length > 2) {
      throw FormatException(
        "The value string: '\$$value' has more than one point in it.",
      );
    }

    var result = verbalizeCardinal(parts.first);
    var decimal = parts.length == 2 ? parts[1] : '';
    while (decimal.endsWith('0')) {
      decimal = decimal.substring(0, decimal.length - 1);
    }
    if (decimal.isNotEmpty) {
      if (result.isEmpty) {
        result = '零';
      }
      result += '点${verbalizeDigits(decimal)}';
    }
    return result;
  }

  /// Replaces fraction expressions such as `-7/12`.
  static String replaceFractions(String text) =>
      text.replaceAllMapped(_fractionPattern, (match) {
        final sign = match[1]!.isEmpty ? '' : '负';
        final numerator = numberToChinese(match[2]!);
        final denominator = numberToChinese(match[3]!);
        return '$sign$denominator分之$numerator';
      });

  /// Replaces ASCII-percent expressions such as `-3.20%`.
  static String replacePercentages(String text) =>
      text.replaceAllMapped(_percentagePattern, (match) {
        final sign = match[1]!.isEmpty ? '' : '负';
        return '$sign百分之${numberToChinese(match[2]!)}';
      });

  /// Replaces a minus immediately followed by an integer.
  static String replaceNegativeIntegers(String text) =>
      text.replaceAllMapped(_negativeIntegerPattern, (match) {
        return '负${numberToChinese(match[2]!)}';
      });

  /// Reads every run of at least three digits as a serial number.
  static String replaceDefaultNumbers(String text) =>
      text.replaceAllMapped(_defaultNumberPattern, (match) {
        return verbalizeDigits(match[0]!, alternateOne: true);
      });

  /// Replaces decimal expressions, retaining the pinned leading-dot quirk.
  static String replaceDecimals(String text) =>
      text.replaceAllMapped(_decimalPattern, _replaceNumberMatch);

  /// Replaces remaining integer/decimal expressions.
  static String replaceNumbers(String text) =>
      text.replaceAllMapped(_numberPattern, _replaceNumberMatch);

  /// Replaces numeric ranges separated by ASCII `-` or `~`.
  static String replaceRanges(String text) =>
      text.replaceAllMapped(_rangePattern, (match) {
        final first = replaceNumbers(match[1]!);
        final second = replaceNumbers(match[2]!);
        return '$first到$second';
      });

  /// Replaces positive numbers followed by the copied quantifier inventory.
  static String replacePositiveQuantifiers(String text) =>
      text.replaceAllMapped(_positiveQuantifierPattern, (match) {
        final modifier = switch (match[2]) {
          '+' => '多',
          final String value => value,
          null => '',
        };
        return '${numberToChinese(match[1]!)}$modifier${match[3]!}';
      });

  static String _replaceNumberMatch(Match match) {
    final pureDecimal = match[5];
    if (pureDecimal != null) {
      return numberToChinese(pureDecimal);
    }
    final sign = match[1]!.isEmpty ? '' : '负';
    return '$sign${numberToChinese(match[2]!)}';
  }

  static List<String> _getValue(List<String> value, {bool useZero = true}) {
    var start = 0;
    while (start < value.length && value[start] == '0') {
      start++;
    }
    final stripped = value.sublist(start);
    if (stripped.isEmpty) {
      return <String>[];
    }
    if (stripped.length == 1) {
      final digit = _digitWord(stripped.single);
      if (useZero && stripped.length < value.length) {
        return <String>['零', digit];
      }
      return <String>[digit];
    }

    final largestUnit = switch (stripped.length) {
      > 8 => 8,
      > 4 => 4,
      > 3 => 3,
      > 2 => 2,
      _ => 1,
    };
    final split = value.length - largestUnit;
    return <String>[
      ..._getValue(value.sublist(0, split)),
      _unitWords[largestUnit]!,
      ..._getValue(value.sublist(split)),
    ];
  }

  static String _digitWord(String digit) => switch (digit) {
    '0' => '零',
    '1' => '一',
    '2' => '二',
    '3' => '三',
    '4' => '四',
    '5' => '五',
    '6' => '六',
    '7' => '七',
    '8' => '八',
    '9' => '九',
    _ => throw FormatException('Unsupported decimal digit `$digit`.'),
  };

  static List<String> _scalarCharacters(String value) => <String>[
    for (final scalar in value.runes) String.fromCharCode(scalar),
  ];

  static const Map<int, String> _unitWords = <int, String>{
    1: '十',
    2: '百',
    3: '千',
    4: '万',
    8: '亿',
  };

  static const String _commonQuantifiers =
      r'(?:封|艘|把|目|套|段|人|所|朵|匹|张|座|回|场|尾|条|个|首|阙|阵|网|炮|顶|丘|棵|只|支|袭|辆|挑|担|颗|壳|窠|曲|墙|群|腔|砣|座|客|贯|扎|捆|刀|令|打|手|罗|坡|山|岭|江|溪|钟|队|单|双|对|出|口|头|脚|板|跳|枝|件|贴|针|线|管|名|位|身|堂|课|本|页|家|户|层|丝|毫|厘|分|钱|两|斤|担|铢|石|钧|锱|忽|(?:千|毫|微)克|毫|厘|(?:公)分|分|寸|尺|丈|里|寻|常|铺|程|(?:千|分|厘|毫|微)米|米|撮|勺|合|升|斗|石|盘|碗|碟|叠|桶|笼|盆|盒|杯|钟|斛|锅|簋|篮|盘|桶|罐|瓶|壶|卮|盏|箩|箱|煲|啖|袋|钵|年|月|日|季|刻|时|周|天|秒|分|小时|旬|纪|岁|世|更|夜|春|夏|秋|冬|代|伏|辈|丸|泡|粒|颗|幢|堆|条|根|支|道|面|片|张|颗|块|元|(?:亿|千万|百万|万|千|百)|(?:亿|千万|百万|万|千|百|美|)元|(?:亿|千万|百万|万|千|百|十|)吨|(?:亿|千万|百万|万|千|百|)块|角|毛|分|(?:公(?:里|引|丈|尺|寸|分|釐)))';
}
