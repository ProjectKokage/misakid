// Clean-room English number spelling for the observable surface consumed by
// pinned Misaki. The behavior was derived from num2words 0.5.14 oracle outputs;
// no num2words source code is copied or used at runtime.

import '../../core/errors.dart';

/// Pure English word sequences matching pinned `num2words==0.5.14`.
final class EnglishNumberSpeller {
  /// Creates the stateless pinned number speller.
  const EnglishNumberSpeller();

  /// Spells a cardinal integer.
  List<String> cardinal(BigInt value) {
    if (value == BigInt.zero) {
      return const <String>['zero'];
    }
    final result = <String>[];
    var remaining = value;
    if (remaining.isNegative) {
      result.add('minus');
      remaining = -remaining;
    }

    final groups = <int>[];
    final thousand = BigInt.from(1000);
    while (remaining > BigInt.zero) {
      groups.add((remaining % thousand).toInt());
      remaining ~/= thousand;
    }
    if (groups.length > _scaleNames.length) {
      throw const InvalidConfigurationException(
        'English number magnitude must be less than 10^306.',
      );
    }

    final nonzeroIndices = <int>[
      for (var index = groups.length - 1; index >= 0; index--)
        if (groups[index] != 0) index,
    ];
    for (var position = 0; position < nonzeroIndices.length; position++) {
      final index = nonzeroIndices[position];
      final group = groups[index];
      final isFinal = position + 1 == nonzeroIndices.length;
      if (isFinal && index == 0 && group < 100 && position > 0) {
        result.add('and');
      }
      result.addAll(_underThousand(group));
      if (index > 0) {
        result.add(_scaleNames[index]);
      }
    }
    return List<String>.unmodifiable(result);
  }

  /// Spells an ordinal integer.
  List<String> ordinal(BigInt value) {
    final words = List<String>.of(cardinal(value));
    if (value.isNegative) {
      throw const InvalidConfigurationException(
        'English ordinal numbers must not be negative.',
      );
    }
    words[words.length - 1] = _ordinalWord(words.last);
    return List<String>.unmodifiable(words);
  }

  /// Spells the pinned special year form.
  List<String> year(BigInt value) {
    if (value.isNegative ||
        value < BigInt.from(100) ||
        value > BigInt.from(9999)) {
      return cardinal(value);
    }
    final number = value.toInt();
    final high = number ~/ 100;
    final low = number % 100;
    if (low == 0) {
      if (number % 1000 == 0) {
        return cardinal(value);
      }
      return List<String>.unmodifiable(<String>[
        ...cardinal(BigInt.from(high)),
        'hundred',
      ]);
    }
    if (high % 10 == 0 && low < 10) {
      return cardinal(value);
    }
    return List<String>.unmodifiable(<String>[
      ...cardinal(BigInt.from(high)),
      if (low < 10) 'oh',
      ...cardinal(BigInt.from(low)),
    ]);
  }

  /// Spells the observable float path used for decimal number tokens.
  List<String> decimal(String source) {
    final value = double.parse(source);
    if (!value.isFinite) {
      throw const InvalidConfigurationException(
        'English decimal numbers must be finite.',
      );
    }
    final absolute = value.abs();
    final integer = absolute.truncate();
    if (absolute == integer.toDouble()) {
      return cardinal(BigInt.from(integer));
    }
    final precision = _decimalPrecision(absolute.toString());
    if (precision == 0) {
      return cardinal(BigInt.from(integer));
    }
    final factor = _pow10Double(precision);
    final scaledFraction = (absolute - integer) * factor;
    final nearestInteger = scaledFraction.round();
    // num2words 0.5.14 normally floors the binary-float remainder, but first
    // snaps values within 0.01 of an integer. Without this observable guard,
    // inputs such as 0.29 become `zero point two eight` because their IEEE-754
    // remainder is 28.999999999999996 after scaling.
    final fraction = (nearestInteger - scaledFraction).abs() < 0.01
        ? nearestInteger
        : scaledFraction.floor();
    final digits = fraction.toString().padLeft(precision, '0');
    return List<String>.unmodifiable(<String>[
      ...cardinal(BigInt.from(integer)),
      'point',
      for (final codePoint in digits.runes) _smallNumbers[codePoint - 0x30],
    ]);
  }
}

List<String> _underThousand(int value) {
  if (value <= 0 || value >= 1000) {
    throw StateError('Internal English number group must be in 1..999.');
  }
  final result = <String>[];
  var remaining = value;
  if (remaining >= 100) {
    result
      ..add(_smallNumbers[remaining ~/ 100])
      ..add('hundred');
    remaining %= 100;
    if (remaining != 0) {
      result.add('and');
    }
  }
  if (remaining >= 20) {
    result.add(_tens[remaining ~/ 10]);
    remaining %= 10;
  }
  if (remaining != 0) {
    result.add(_smallNumbers[remaining]);
  }
  return result;
}

String _ordinalWord(String word) =>
    _irregularOrdinals[word] ??
    (word.endsWith('y')
        ? '${word.substring(0, word.length - 1)}ieth'
        : '${word}th');

int _decimalPrecision(String representation) {
  final exponentIndex = representation.indexOf(RegExp('[eE]'));
  final mantissa = exponentIndex < 0
      ? representation
      : representation.substring(0, exponentIndex);
  final exponent = exponentIndex < 0
      ? 0
      : int.parse(representation.substring(exponentIndex + 1));
  final decimalIndex = mantissa.indexOf('.');
  final mantissaDigits = decimalIndex < 0
      ? 0
      : mantissa.length - decimalIndex - 1;
  final precision = mantissaDigits - exponent;
  return precision < 0 ? 0 : precision;
}

double _pow10Double(int exponent) {
  var result = 1.0;
  for (var index = 0; index < exponent; index++) {
    result *= 10;
  }
  return result;
}

const List<String> _smallNumbers = <String>[
  'zero',
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
  'ten',
  'eleven',
  'twelve',
  'thirteen',
  'fourteen',
  'fifteen',
  'sixteen',
  'seventeen',
  'eighteen',
  'nineteen',
];

const List<String> _tens = <String>[
  '',
  '',
  'twenty',
  'thirty',
  'forty',
  'fifty',
  'sixty',
  'seventy',
  'eighty',
  'ninety',
];

const Map<String, String> _irregularOrdinals = <String, String>{
  'zero': 'zeroth',
  'one': 'first',
  'two': 'second',
  'three': 'third',
  'four': 'fourth',
  'five': 'fifth',
  'eight': 'eighth',
  'nine': 'ninth',
  'twelve': 'twelfth',
};

// Index is the power-of-1000 group. These are the complete scale names
// accepted by the pinned oracle; the next group raises OverflowError there.
const List<String> _scaleNames = <String>[
  '',
  'thousand',
  'million',
  'billion',
  'trillion',
  'quadrillion',
  'quintillion',
  'sextillion',
  'septillion',
  'octillion',
  'nonillion',
  'decillion',
  'undecillion',
  'duodecillion',
  'tredecillion',
  'quattuordecillion',
  'quindecillion',
  'sexdecillion',
  'septdecillion',
  'octodecillion',
  'novemdecillion',
  'vigintillion',
  'unvigintillion',
  'duovigintillion',
  'trevigintillion',
  'quattuorvigintillion',
  'quinvigintillion',
  'sexvigintillion',
  'septvigintillion',
  'octovigintillion',
  'novemvigintillion',
  'trigintillion',
  'untrigintillion',
  'duotrigintillion',
  'tretrigintillion',
  'quattuortrigintillion',
  'quintrigintillion',
  'sextrigintillion',
  'septtrigintillion',
  'octotrigintillion',
  'novemtrigintillion',
  'quadragintillion',
  'unquadragintillion',
  'duoquadragintillion',
  'trequadragintillion',
  'quattuorquadragintillion',
  'quinquadragintillion',
  'sexquadragintillion',
  'septquadragintillion',
  'octoquadragintillion',
  'novemquadragintillion',
  'quinquagintillion',
  'unquinquagintillion',
  'duoquinquagintillion',
  'trequinquagintillion',
  'quattuorquinquagintillion',
  'quinquinquagintillion',
  'sexquinquagintillion',
  'septquinquagintillion',
  'octoquinquagintillion',
  'novemquinquagintillion',
  'sexagintillion',
  'unsexagintillion',
  'duosexagintillion',
  'tresexagintillion',
  'quattuorsexagintillion',
  'quinsexagintillion',
  'sexsexagintillion',
  'septsexagintillion',
  'octosexagintillion',
  'novemsexagintillion',
  'septuagintillion',
  'unseptuagintillion',
  'duoseptuagintillion',
  'treseptuagintillion',
  'quattuorseptuagintillion',
  'quinseptuagintillion',
  'sexseptuagintillion',
  'septseptuagintillion',
  'octoseptuagintillion',
  'novemseptuagintillion',
  'octogintillion',
  'unoctogintillion',
  'duooctogintillion',
  'treoctogintillion',
  'quattuoroctogintillion',
  'quinoctogintillion',
  'sexoctogintillion',
  'septoctogintillion',
  'octooctogintillion',
  'novemoctogintillion',
  'nonagintillion',
  'unnonagintillion',
  'duononagintillion',
  'trenonagintillion',
  'quattuornonagintillion',
  'quinnonagintillion',
  'sexnonagintillion',
  'septnonagintillion',
  'octononagintillion',
  'novemnonagintillion',
  'centillion',
];
