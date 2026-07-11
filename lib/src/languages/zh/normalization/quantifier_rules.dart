// Copyright (c) 2021 PaddlePaddle Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Dart adaptation of misaki/zh_normalization/quantifier.py from
// hexgrad/misaki at fba1236595f2d2bf21d414ba6e57d25256afada3
// (Misaki 0.9.4). The pinned file was copied from PaddleSpeech.
// Modifications: use typed ordered replacement records and preserve the
// upstream temperature capture-group and measure-order quirks.

import '../../../core/python312_unicode.dart';
import 'number_rules.dart';

/// Pure temperature and measurement stages for the Chinese normalizer.
final class ChineseQuantifierRules {
  ChineseQuantifierRules._();

  static const String _digitPattern = python312DecimalRegExpPattern;
  static final RegExp _temperaturePattern = RegExp(
    '(-?)($_digitPattern+(?:\\.$_digitPattern+)?)(°C|℃|度|摄氏度)',
    unicode: true,
  );

  /// Replaces supported temperature expressions.
  ///
  /// The pinned callback reads the decimal subgroup instead of the unit
  /// subgroup, so even an input ending in `摄氏度` is rendered with `度`.
  static String replaceTemperatures(String text) =>
      text.replaceAllMapped(_temperaturePattern, (match) {
        final sign = match[1]!.isEmpty ? '' : '零下';
        return '$sign${ChineseNumberRules.numberToChinese(match[2]!)}度';
      });

  /// Applies the copied measurement substitutions in insertion order.
  static String replaceMeasures(String text) {
    var result = text;
    for (final replacement in _measureReplacements) {
      if (result.contains(replacement.$1)) {
        result = result.replaceAll(replacement.$1, replacement.$2);
      }
    }
    return result;
  }

  static const List<(String, String)> _measureReplacements = <(String, String)>[
    ('cm2', '平方厘米'),
    ('cm²', '平方厘米'),
    ('cm3', '立方厘米'),
    ('cm³', '立方厘米'),
    ('cm', '厘米'),
    ('db', '分贝'),
    ('ds', '毫秒'),
    ('kg', '千克'),
    ('km', '千米'),
    ('m2', '平方米'),
    ('m²', '平方米'),
    ('m³', '立方米'),
    ('m3', '立方米'),
    ('ml', '毫升'),
    ('m', '米'),
    ('mm', '毫米'),
    ('s', '秒'),
    ('h', '小时'),
    ('mg', '毫克'),
  ];
}
