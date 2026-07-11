// Pure-Dart adaptation of cn2an 0.5.23 `Transform.transform(..., "an2cn")`
// and its `An2Cn` low/direct conversion stages.
//
// Upstream: https://github.com/Ailln/cn2an
// Copyright (c) 2017 Ailln
// SPDX-License-Identifier: MIT
//
// Modifications: retain only the an2cn sentence-normalization path used by
// pinned Misaki, replace Python/proces preprocessing with scalar-safe Dart,
// and preserve failed matches without emitting Python warnings.

/// Pure-Dart number normalizer matching cn2an 0.5.23's sentence transform.
///
/// [normalize] implements `cn2an.transform(text, 'an2cn')`, including the
/// upstream date, fraction, percentage, Celsius, and general-number pass
/// order. The normalizer is stateless and performs no I/O.
final class Cn2AnNormalizer {
  /// Creates a reusable cn2an-compatible normalizer.
  const Cn2AnNormalizer();

  static const _numberLow = <String>[
    '零',
    '一',
    '二',
    '三',
    '四',
    '五',
    '六',
    '七',
    '八',
    '九',
  ];

  static const _unitLowOrder = <String>[
    '',
    '十',
    '百',
    '千',
    '万',
    '十',
    '百',
    '千',
    '亿',
    '十',
    '百',
    '千',
    '万',
    '十',
    '百',
    '千',
  ];

  // The pinned CPython 3.12.11 oracle uses its default decimal-int conversion
  // limit. cn2an canonicalizes an integer with `str(int(integer_data))`, so a
  // run with more than 4,300 digits raises before leading zeroes are removed.
  // Transform catches that failure and preserves the complete regex match.
  static const _maximumPythonDecimalIntegerDigits = 4300;

  // Python 3.12's `\d` covers every Unicode 15.0 Nd scalar. Most of those
  // values deliberately fail An2Cn validation and remain unchanged, but they
  // must still participate in a whole regex match; otherwise an adjacent
  // ASCII digit could be converted separately. Full-width digits are the one
  // non-ASCII range accepted after cn2an's full-angle folding stage.
  static const _pythonDecimalDigitClass =
      r'[\u{30}-\u{39}\u{660}-\u{669}\u{6F0}-\u{6F9}'
      r'\u{7C0}-\u{7C9}\u{966}-\u{96F}\u{9E6}-\u{9EF}'
      r'\u{A66}-\u{A6F}\u{AE6}-\u{AEF}\u{B66}-\u{B6F}'
      r'\u{BE6}-\u{BEF}\u{C66}-\u{C6F}\u{CE6}-\u{CEF}'
      r'\u{D66}-\u{D6F}\u{DE6}-\u{DEF}\u{E50}-\u{E59}'
      r'\u{ED0}-\u{ED9}\u{F20}-\u{F29}\u{1040}-\u{1049}'
      r'\u{1090}-\u{1099}\u{17E0}-\u{17E9}\u{1810}-\u{1819}'
      r'\u{1946}-\u{194F}\u{19D0}-\u{19D9}\u{1A80}-\u{1A89}'
      r'\u{1A90}-\u{1A99}\u{1B50}-\u{1B59}\u{1BB0}-\u{1BB9}'
      r'\u{1C40}-\u{1C49}\u{1C50}-\u{1C59}\u{A620}-\u{A629}'
      r'\u{A8D0}-\u{A8D9}\u{A900}-\u{A909}\u{A9D0}-\u{A9D9}'
      r'\u{A9F0}-\u{A9F9}\u{AA50}-\u{AA59}\u{ABF0}-\u{ABF9}'
      r'\u{FF10}-\u{FF19}\u{104A0}-\u{104A9}\u{10D30}-\u{10D39}'
      r'\u{11066}-\u{1106F}\u{110F0}-\u{110F9}\u{11136}-\u{1113F}'
      r'\u{111D0}-\u{111D9}\u{112F0}-\u{112F9}\u{11450}-\u{11459}'
      r'\u{114D0}-\u{114D9}\u{11650}-\u{11659}\u{116C0}-\u{116C9}'
      r'\u{11730}-\u{11739}\u{118E0}-\u{118E9}\u{11950}-\u{11959}'
      r'\u{11C50}-\u{11C59}\u{11D50}-\u{11D59}\u{11DA0}-\u{11DA9}'
      r'\u{11F50}-\u{11F59}\u{16A60}-\u{16A69}\u{16AC0}-\u{16AC9}'
      r'\u{16B50}-\u{16B59}\u{1D7CE}-\u{1D7FF}\u{1E140}-\u{1E149}'
      r'\u{1E2F0}-\u{1E2F9}\u{1E4F0}-\u{1E4F9}\u{1E950}-\u{1E959}'
      r'\u{1FBF0}-\u{1FBF9}]';

  static final _datePattern = RegExp(
    '(?:$_pythonDecimalDigitClass{2,4}年)?'
    '(?:$_pythonDecimalDigitClass{1,2}月)?'
    '(?:$_pythonDecimalDigitClass{1,2}日)?',
    unicode: true,
  );
  static final _fractionPattern = RegExp(
    '$_pythonDecimalDigitClass+/$_pythonDecimalDigitClass+',
    unicode: true,
  );
  static final _percentPattern = RegExp(
    '-?(?:$_pythonDecimalDigitClass+\\.)?'
    '$_pythonDecimalDigitClass+%',
    unicode: true,
  );
  static final _celsiusPattern = RegExp(
    '$_pythonDecimalDigitClass+℃',
    unicode: true,
  );
  static final _numberPattern = RegExp(
    '-?(?:$_pythonDecimalDigitClass+\\.)?'
    '$_pythonDecimalDigitClass+',
    unicode: true,
  );
  static final _digitsPattern = RegExp(
    '$_pythonDecimalDigitClass+',
    unicode: true,
  );
  static final _yearDigitsPattern = RegExp(
    '$_pythonDecimalDigitClass+(?=年)',
    unicode: true,
  );

  /// Normalizes Arabic-number expressions in [text] to Chinese numerals.
  String normalize(String text) {
    var output = text.replaceAllMapped(
      _datePattern,
      (match) => _convertDate(match.group(0)!),
    );
    output = output.replaceAllMapped(
      _fractionPattern,
      (match) => _convertFraction(match.group(0)!),
    );
    output = output.replaceAllMapped(
      _percentPattern,
      (match) => _convertPercent(match.group(0)!),
    );
    output = output.replaceAllMapped(
      _celsiusPattern,
      (match) => _convertCelsius(match.group(0)!),
    );
    return output.replaceAllMapped(
      _numberPattern,
      (match) => _an2Cn(match.group(0)!, direct: false) ?? match.group(0)!,
    );
  }

  static String _convertDate(String input) {
    if (input.isEmpty) {
      return input;
    }

    var failed = false;
    var output = input.replaceAllMapped(_yearDigitsPattern, (match) {
      final original = match.group(0)!;
      final converted = _an2Cn(original, direct: true);
      if (converted == null) {
        failed = true;
        return original;
      }
      return converted;
    });
    if (failed) {
      return input;
    }

    final outputAfterYearPass = output;
    output = output.replaceAllMapped(_digitsPattern, (match) {
      final original = match.group(0)!;
      final converted = _an2Cn(original, direct: false);
      if (converted == null) {
        failed = true;
        return original;
      }
      return converted;
    });
    // Python assigns the second re.sub result only after every callback has
    // succeeded. On a later invalid Unicode digit, its exception handler sees
    // the already-assigned year pass but none of this pass's partial output.
    return failed ? outputAfterYearPass : output;
  }

  static String _convertFraction(String input) {
    final separator = input.indexOf('/');
    final numerator = input.substring(0, separator);
    final denominator = input.substring(separator + 1);
    final convertedNumerator = _an2Cn(numerator, direct: false);
    final convertedDenominator = _an2Cn(denominator, direct: false);
    if (convertedNumerator == null || convertedDenominator == null) {
      return input;
    }
    return '$convertedDenominator分之$convertedNumerator';
  }

  static String _convertPercent(String input) {
    final number = input.substring(0, input.length - 1);
    final converted = _an2Cn(number, direct: false);
    return converted == null ? input : '百分之$converted';
  }

  static String _convertCelsius(String input) {
    final number = input.substring(0, input.length - 1);
    final converted = _an2Cn(number, direct: false);
    return converted == null ? input : '$converted摄氏度';
  }

  static String? _an2Cn(String input, {required bool direct}) {
    final folded = _foldFullWidth(input);
    for (final codeUnit in folded.codeUnits) {
      if ((codeUnit < 0x30 || codeUnit > 0x39) &&
          codeUnit != 0x2e &&
          codeUnit != 0x2d) {
        return null;
      }
    }

    var unsigned = folded;
    var sign = '';
    if (unsigned.startsWith('-')) {
      sign = '负';
      unsigned = unsigned.substring(1);
    }

    if (direct) {
      final output = StringBuffer(sign);
      for (final codeUnit in unsigned.codeUnits) {
        if (codeUnit == 0x2e) {
          output.write('点');
        } else if (codeUnit >= 0x30 && codeUnit <= 0x39) {
          output.write(_numberLow[codeUnit - 0x30]);
        } else {
          return null;
        }
      }
      return output.toString();
    }

    final decimalPoint = unsigned.indexOf('.');
    if (decimalPoint != unsigned.lastIndexOf('.')) {
      return null;
    }
    final integer = decimalPoint < 0
        ? unsigned
        : unsigned.substring(0, decimalPoint);
    final decimal = decimalPoint < 0
        ? null
        : unsigned.substring(decimalPoint + 1);
    final convertedInteger = _convertInteger(integer);
    if (convertedInteger == null) {
      return null;
    }
    return sign + convertedInteger + _convertDecimal(decimal);
  }

  static String? _convertInteger(String input) {
    if (input.length > _maximumPythonDecimalIntegerDigits) {
      return null;
    }
    var firstSignificant = 0;
    while (firstSignificant < input.length - 1 &&
        input.codeUnitAt(firstSignificant) == 0x30) {
      firstSignificant++;
    }
    final canonical = input.substring(firstSignificant);
    if (canonical.isEmpty || canonical.length > _unitLowOrder.length) {
      return null;
    }

    final output = StringBuffer();
    for (var index = 0; index < canonical.length; index++) {
      final digit = canonical.codeUnitAt(index) - 0x30;
      final unitIndex = canonical.length - index - 1;
      if (digit != 0) {
        output
          ..write(_numberLow[digit])
          ..write(_unitLowOrder[unitIndex]);
      } else {
        if (unitIndex % 4 == 0) {
          output
            ..write(_numberLow[0])
            ..write(_unitLowOrder[unitIndex]);
        }
        if (index > 0 && !output.toString().endsWith(_numberLow[0])) {
          output.write(_numberLow[0]);
        }
      }
    }

    var converted = output
        .toString()
        .replaceAll('零零', '零')
        .replaceAll('零万', '万')
        .replaceAll('零亿', '亿')
        .replaceAll('亿万', '亿');
    while (converted.startsWith('零')) {
      converted = converted.substring(1);
    }
    while (converted.endsWith('零')) {
      converted = converted.substring(0, converted.length - 1);
    }
    if (converted.startsWith('一十')) {
      converted = converted.substring(1);
    }
    return converted.isEmpty ? '零' : converted;
  }

  static String _convertDecimal(String? input) {
    if (input == null) {
      return '';
    }
    final effective = input.length > 16 ? input.substring(0, 16) : input;
    final output = StringBuffer();
    if (effective.isNotEmpty) {
      output.write('点');
    }
    for (final codeUnit in effective.codeUnits) {
      output.write(_numberLow[codeUnit - 0x30]);
    }
    return output.toString();
  }

  static String _foldFullWidth(String input) {
    final output = StringBuffer();
    for (final scalar in input.runes) {
      if (scalar == 0x3000) {
        output.writeCharCode(0x20);
      } else if (scalar >= 0xff01 && scalar <= 0xff5e) {
        output.writeCharCode(scalar - 0xfee0);
      } else {
        output.writeCharCode(scalar);
      }
    }
    return output.toString();
  }
}
