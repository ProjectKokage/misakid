// Copyright (c) 2021 PaddlePaddle Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Dart adaptation of misaki/zh_normalization/phonecode.py from hexgrad/misaki
// at fba1236595f2d2bf21d414ba6e57d25256afada3 (Misaki 0.9.4). The pinned file
// was copied from PaddleSpeech. Modifications: use scalar-safe CPython
// whitespace splitting and boundary captures instead of regex lookbehind.

import '../../../core/python312_unicode.dart';
import '../../../core/python_whitespace.dart';
import 'number_rules.dart';

/// Pure mobile, landline, and national-number stages for Chinese text.
final class ChinesePhoneRules {
  ChinesePhoneRules._();

  static const String _digitPattern = python312DecimalRegExpPattern;
  static final String _nonDigitPattern =
      '[^${_digitPattern.substring(1, _digitPattern.length - 1)}]';

  // The leading non-digit capture is retained in replacement output. It is
  // equivalent to upstream's negative lookbehind while remaining usable on
  // Dart runtimes without lookbehind support.
  static final RegExp _mobilePattern = RegExp(
    '(^|$_nonDigitPattern)'
    '((?:\\+?86 ?)?1(?:[38]$_digitPattern|5[0-35-9]|7[678]|9[89])'
    '$_digitPattern{8})(?!$_digitPattern)',
    unicode: true,
  );
  static final RegExp _telephonePattern = RegExp(
    '(^|$_nonDigitPattern)'
    '((?:0(?:10|2[1-3]|[3-9]$_digitPattern{2})-?)?'
    '[1-9]$_digitPattern{6,7})(?!$_digitPattern)',
    unicode: true,
  );
  static final RegExp _nationalUniformPattern = RegExp(
    '400-?$_digitPattern{3}-?$_digitPattern{4}',
    unicode: true,
  );

  /// Reads a phone number digit-by-digit with 幺 for one.
  ///
  /// Mobile mode strips any number of leading/trailing plus signs and joins
  /// CPython-whitespace-delimited parts with `，`. Landline mode splits only
  /// on ASCII hyphens.
  static String phoneToChinese(String phone, {bool mobile = true}) {
    final List<String> parts;
    if (mobile) {
      var start = 0;
      var end = phone.length;
      while (start < end && phone.codeUnitAt(start) == 0x2b) {
        start++;
      }
      while (end > start && phone.codeUnitAt(end - 1) == 0x2b) {
        end--;
      }
      parts = _splitPythonWhitespace(phone.substring(start, end));
    } else {
      parts = phone.split('-');
    }

    return parts
        .map(
          (part) =>
              ChineseNumberRules.verbalizeDigits(part, alternateOne: true),
        )
        .join('，');
  }

  /// Replaces supported mainland mobile-number expressions.
  static String replaceMobilePhones(String text) =>
      text.replaceAllMapped(_mobilePattern, (match) {
        return '${match[1]}${phoneToChinese(match[2]!)}';
      });

  /// Replaces supported landline expressions.
  static String replaceTelephones(String text) =>
      text.replaceAllMapped(_telephonePattern, (match) {
        return '${match[1]}${phoneToChinese(match[2]!, mobile: false)}';
      });

  /// Replaces 400 national uniform numbers without digit boundaries.
  static String replaceNationalUniformNumbers(String text) =>
      text.replaceAllMapped(_nationalUniformPattern, (match) {
        return phoneToChinese(match[0]!, mobile: false);
      });

  static List<String> _splitPythonWhitespace(String value) {
    final result = <String>[];
    var part = StringBuffer();
    for (final scalar in value.runes) {
      if (isPythonWhitespace(scalar)) {
        if (part.isNotEmpty) {
          result.add(part.toString());
          part = StringBuffer();
        }
      } else {
        part.writeCharCode(scalar);
      }
    }
    if (part.isNotEmpty) {
      result.add(part.toString());
    }
    return result;
  }
}
