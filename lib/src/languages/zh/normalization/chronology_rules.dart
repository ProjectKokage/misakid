// Copyright (c) 2021 PaddlePaddle Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Dart adaptation of misaki/zh_normalization/chronology.py from
// hexgrad/misaki at fba1236595f2d2bf21d414ba6e57d25256afada3
// (Misaki 0.9.4). The pinned file was copied from PaddleSpeech.
// Modifications: use typed, precompiled Dart expressions and preserve the
// upstream second-range-minute condition exactly.

import '../../../core/python312_unicode.dart';
import 'number_rules.dart';

/// Pure date and clock-expression stages for the pinned Chinese normalizer.
final class ChineseChronologyRules {
  ChineseChronologyRules._();

  static const String _digitPattern = python312DecimalRegExpPattern;

  static final RegExp _timePattern = RegExp(
    r'([0-1]?[0-9]|2[0-3]):([0-5][0-9])(?::([0-5][0-9]))?',
  );
  static final RegExp _timeRangePattern = RegExp(
    r'([0-1]?[0-9]|2[0-3]):([0-5][0-9])(?::([0-5][0-9]))?'
    r'(~|-)([0-1]?[0-9]|2[0-3]):([0-5][0-9])'
    r'(?::([0-5][0-9]))?',
  );
  static final RegExp _datePattern = RegExp(
    '($_digitPattern{4}|$_digitPattern{2})年'
    '(?:(0?[1-9]|1[0-2])月)?'
    '(?:(0?[1-9]|[12][0-9]|30|31)([日号]))?',
    unicode: true,
  );
  static final RegExp _separatedDatePattern = RegExp(
    '($_digitPattern{4})([- /.])(0[1-9]|1[012])\\2'
    '(0[1-9]|[12][0-9]|3[01])',
    unicode: true,
  );

  /// Replaces `HH:MM[:SS]-HH:MM[:SS]` and `~` clock ranges.
  static String replaceTimeRanges(String text) =>
      text.replaceAllMapped(_timeRangePattern, (match) {
        final hour = match[1]!;
        final minute = match[2]!;
        final second = match[3];
        final hour2 = match[5]!;
        final minute2 = match[6]!;
        final second2 = match[7];

        final result = StringBuffer()
          ..write('${ChineseNumberRules.numberToChinese(hour)}点')
          ..write(_minuteText(minute))
          ..write(_secondText(second))
          ..write('至')
          ..write('${ChineseNumberRules.numberToChinese(hour2)}点');

        if (_hasNonzeroDigit(minute2)) {
          // Pinned quirk: the first minute controls whether the second time is
          // rendered as 半; minute2 is intentionally not checked here.
          if (int.parse(minute) == 30) {
            result.write('半');
          } else {
            result.write('${_timeNumberToChinese(minute2)}分');
          }
        }
        result.write(_secondText(second2));
        return result.toString();
      });

  /// Replaces remaining 24-hour clock expressions.
  static String replaceTimes(String text) =>
      text.replaceAllMapped(_timePattern, (match) {
        final result = StringBuffer()
          ..write('${ChineseNumberRules.numberToChinese(match[1]!)}点')
          ..write(_minuteText(match[2]!))
          ..write(_secondText(match[3]));
        return result.toString();
      });

  /// Replaces `YY年...` and `YYYY年...` date expressions.
  static String replaceDates(String text) => text.replaceAllMapped(
    _datePattern,
    (match) {
      final result = StringBuffer()
        ..write('${ChineseNumberRules.verbalizeDigits(match[1]!)}年');
      final month = match[2];
      if (month != null) {
        result.write('${ChineseNumberRules.verbalizeCardinal(month)}月');
      }
      final day = match[3];
      if (day != null) {
        result.write('${ChineseNumberRules.verbalizeCardinal(day)}${match[4]}');
      }
      return result.toString();
    },
  );

  /// Replaces `YYYY-MM-DD` and the pinned same-separator variants.
  static String replaceSeparatedDates(String text) =>
      text.replaceAllMapped(_separatedDatePattern, (match) {
        return '${ChineseNumberRules.verbalizeDigits(match[1]!)}年'
            '${ChineseNumberRules.verbalizeCardinal(match[3]!)}月'
            '${ChineseNumberRules.verbalizeCardinal(match[4]!)}日';
      });

  static String _minuteText(String minute) {
    if (!_hasNonzeroDigit(minute)) {
      return '';
    }
    return int.parse(minute) == 30 ? '半' : '${_timeNumberToChinese(minute)}分';
  }

  static String _secondText(String? second) {
    if (second == null || !_hasNonzeroDigit(second)) {
      return '';
    }
    return '${_timeNumberToChinese(second)}秒';
  }

  static String _timeNumberToChinese(String value) {
    var start = 0;
    while (start < value.length && value.codeUnitAt(start) == 0x30) {
      start++;
    }
    final result = ChineseNumberRules.numberToChinese(value.substring(start));
    return value.startsWith('0') ? '零$result' : result;
  }

  static bool _hasNonzeroDigit(String value) =>
      value.codeUnits.any((codeUnit) => codeUnit != 0x30);
}
