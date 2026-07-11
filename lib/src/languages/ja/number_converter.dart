// Dart adaptation of hexgrad/misaki/misaki/num2kana.py at
// fba1236595f2d2bf21d414ba6e57d25256afada3 (Misaki 0.9.4).
// The upstream file says it was copied from Greatdane's
// Convert-Numbers-to-Japanese.py and identifies that original as MIT licensed.
// The pinned Misaki snapshot is Apache-2.0 licensed.
//
// Modifications: ported to null-safe, strongly typed Dart; replaced the string
// dictionary selector with an enum; and translated incidental Python failures
// for unsupported input into package validation exceptions. Valid-input output,
// including whitespace and pronunciation quirks, is intentionally preserved.

import '../../core/errors.dart';

/// Output representation used by [JapaneseNumberConverter.convert].
enum JapaneseNumberFormat {
  /// Japanese number characters such as `一万`.
  kanji,

  /// Kana readings such as `いちまん`.
  ///
  /// This name follows upstream even though zero is rendered as katakana
  /// `ゼロ`.
  hiragana,

  /// Space-separated Hepburn-style romanization such as `ichi man`.
  romaji,
}

/// Converts Arabic-number text to Japanese and Japanese kanji to Arabic text.
///
/// The converter is pure Dart and has no backend or runtime-data dependency.
/// It preserves the pinned upstream converter's nine-character limit after
/// commas are removed.
final class JapaneseNumberConverter {
  /// Creates a stateless Japanese number converter.
  const JapaneseNumberConverter();

  /// Converts ASCII [number] text into the selected Japanese [format].
  ///
  /// Commas are discarded wherever they occur, matching upstream. The default
  /// format is [JapaneseNumberFormat.hiragana]. The decimal point counts toward
  /// the nine-character limit, while commas do not.
  ///
  /// Like the pinned converter, input longer than nine characters returns the
  /// literal diagnostic `Number length too long, choose less than 10 digits`.
  ///
  /// Throws [InvalidConfigurationException] when the comma-free input is empty,
  /// contains unsupported characters, or selects a decimal form that the
  /// pinned converter cannot process.
  String convert(
    String number, {
    JapaneseNumberFormat format = JapaneseNumberFormat.hiragana,
  }) {
    var normalized = number.replaceAll(',', '');
    if (_scalarCharacters(normalized).length > 9) {
      return 'Number length too long, choose less than 10 digits';
    }
    _validateArabicInput(normalized);

    while (normalized.startsWith('0') && normalized.length > 1) {
      normalized = normalized.substring(1);
    }
    if (normalized.startsWith('.')) {
      throw const InvalidConfigurationException(
        'The pinned converter cannot process a decimal whose whole part is zero.',
      );
    }

    final dictionary = _dictionaryFor(format);
    final result = normalized.contains('.')
        ? _convertDecimal(normalized, dictionary, format)
        : _convertByLength(normalized, dictionary);
    return _finish(result, format);
  }

  /// Converts Japanese [number] text into an Arabic-number string.
  ///
  /// A string is returned so decimal trailing and leading zeros are retained.
  /// The accepted whole-number symbols are `零一二三四五六七八九十百千万億`;
  /// the fractional tail accepts those same symbols and additional `点`
  /// characters, preserving the pinned converter's literal dictionary-key
  /// concatenation quirks.
  ///
  /// Throws [InvalidConfigurationException] for empty or unsupported input.
  String kanjiToArabic(String number) {
    final characters = _scalarCharacters(number);
    if (characters.isEmpty) {
      throw const InvalidConfigurationException(
        'A Japanese number must not be empty.',
      );
    }

    if (characters.first == '点') {
      throw const InvalidConfigurationException(
        'A Japanese number must not begin with 点.',
      );
    }

    final point = characters.indexOf('点');
    final wholeEnd = point < 0 ? characters.length : point;
    for (var index = 0; index < wholeEnd; index++) {
      if (!_kanjiWholeCharacters.contains(characters[index])) {
        throw InvalidConfigurationException(
          'Unsupported Japanese number character: ${characters[index]}',
        );
      }
    }
    if (point >= 0) {
      for (var index = point + 1; index < characters.length; index++) {
        if (!_kanjiFractionalValues.containsKey(characters[index])) {
          throw InvalidConfigurationException(
            'Unsupported Japanese fractional character: ${characters[index]}',
          );
        }
      }
    }

    final whole = characters.take(wholeEnd).join();
    final wholeNumber = _convertKanjiWhole(whole);
    if (point < 0) {
      return wholeNumber.toString();
    }

    final fraction = StringBuffer();
    for (var index = point + 1; index < characters.length; index++) {
      fraction.write(_kanjiFractionalValues[characters[index]]);
    }
    return '$wholeNumber.$fraction';
  }
}

const Map<String, String> _romaji = <String, String>{
  '.': 'ten',
  '0': 'zero',
  '1': 'ichi',
  '2': 'ni',
  '3': 'san',
  '4': 'yon',
  '5': 'go',
  '6': 'roku',
  '7': 'nana',
  '8': 'hachi',
  '9': 'kyuu',
  '10': 'juu',
  '100': 'hyaku',
  '1000': 'sen',
  '10000': 'man',
  '100000000': 'oku',
  '300': 'sanbyaku',
  '600': 'roppyaku',
  '800': 'happyaku',
  '3000': 'sanzen',
  '8000': 'hassen',
  '01000': 'issen',
};

const Map<String, String> _kanji = <String, String>{
  '.': '点',
  '0': '零',
  '1': '一',
  '2': '二',
  '3': '三',
  '4': '四',
  '5': '五',
  '6': '六',
  '7': '七',
  '8': '八',
  '9': '九',
  '10': '十',
  '100': '百',
  '1000': '千',
  '10000': '万',
  '100000000': '億',
  '300': '三百',
  '600': '六百',
  '800': '八百',
  '3000': '三千',
  '8000': '八千',
  '01000': '一千',
};

const Map<String, String> _hiragana = <String, String>{
  '.': 'てん',
  '0': 'ゼロ',
  '1': 'いち',
  '2': 'に',
  '3': 'さん',
  '4': 'よん',
  '5': 'ご',
  '6': 'ろく',
  '7': 'なな',
  '8': 'はち',
  '9': 'きゅう',
  '10': 'じゅう',
  '100': 'ひゃく',
  '1000': 'せん',
  '10000': 'まん',
  '100000000': 'おく',
  '300': 'さんびゃく',
  '600': 'ろっぴゃく',
  '800': 'はっぴゃく',
  '3000': 'さんぜん',
  '8000': 'はっせん',
  '01000': 'いっせん',
};

const Map<String, int> _kanjiDigitValues = <String, int>{
  '零': 0,
  '一': 1,
  '二': 2,
  '三': 3,
  '四': 4,
  '五': 5,
  '六': 6,
  '七': 7,
  '八': 8,
  '九': 9,
};

const Map<String, int> _kanjiLinkValues = <String, int>{
  '十': 10,
  '百': 100,
  '千': 1000,
  '万': 10000,
  '億': 100000000,
};

const Map<String, String> _kanjiFractionalValues = <String, String>{
  '点': '.',
  '零': '0',
  '一': '1',
  '二': '2',
  '三': '3',
  '四': '4',
  '五': '5',
  '六': '6',
  '七': '7',
  '八': '8',
  '九': '9',
  '十': '10',
  '百': '100',
  '千': '1000',
  '万': '10000',
  '億': '100000000',
};

const Set<String> _kanjiWholeCharacters = <String>{
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
  '十',
  '百',
  '千',
  '万',
  '億',
};

enum _KanjiOperation { times, plus }

Map<String, String> _dictionaryFor(JapaneseNumberFormat format) =>
    switch (format) {
      JapaneseNumberFormat.kanji => _kanji,
      JapaneseNumberFormat.hiragana => _hiragana,
      JapaneseNumberFormat.romaji => _romaji,
    };

void _validateArabicInput(String number) {
  final characters = _scalarCharacters(number);
  if (characters.isEmpty) {
    throw const InvalidConfigurationException('A number must not be empty.');
  }

  var points = 0;
  for (final character in characters) {
    if (character == '.') {
      points++;
    } else if (!_isAsciiDigit(character)) {
      throw InvalidConfigurationException(
        'Unsupported number character: $character',
      );
    }
  }
  if (points > 1 || characters.first == '.') {
    throw const InvalidConfigurationException(
      'A number may contain at most one non-leading decimal point.',
    );
  }
}

bool _isAsciiDigit(String character) {
  final codePoint = character.runes.single;
  return codePoint >= 0x30 && codePoint <= 0x39;
}

List<String> _scalarCharacters(String value) =>
    value.runes.map<String>(String.fromCharCode).toList(growable: false);

String _lookup(Map<String, String> dictionary, String key) {
  final result = dictionary[key];
  if (result == null) {
    throw MalformedDataException(
      'Japanese number table has no entry for `$key`.',
    );
  }
  return result;
}

String _finish(String result, JapaneseNumberFormat format) =>
    format == JapaneseNumberFormat.romaji ? result : result.replaceAll(' ', '');

String _convertDecimal(
  String number,
  Map<String, String> dictionary,
  JapaneseNumberFormat format,
) {
  final point = number.indexOf('.');
  final whole = number.substring(0, point);
  final fraction = number.substring(point + 1);
  if (whole == '0') {
    throw const InvalidConfigurationException(
      'The pinned converter cannot process a decimal whose whole part is zero.',
    );
  }

  final fractionalReading = StringBuffer(' ');
  for (final digit in fraction.split('')) {
    fractionalReading
      ..write(_lookup(dictionary, digit))
      ..write(' ');
  }

  final wholeReading = _finish(_convertByLength(whole, dictionary), format);
  if (whole.endsWith('0') && whole[whole.length - 2] != '0') {
    if (format == JapaneseNumberFormat.hiragana) {
      final geminated =
          '${wholeReading.substring(0, wholeReading.length - 1)}っ';
      return _finish(
        '$geminated${_lookup(dictionary, '.')}$fractionalReading',
        format,
      );
    }
    if (format == JapaneseNumberFormat.romaji) {
      final geminated =
          '${wholeReading.substring(0, wholeReading.length - 1)}t';
      return '$geminated${_lookup(dictionary, '.')}$fractionalReading';
    }
  }

  return _finish(
    '$wholeReading ${_lookup(dictionary, '.')}$fractionalReading',
    format,
  );
}

String _convertByLength(String number, Map<String, String> dictionary) {
  return switch (number.length) {
    1 => _convertOne(number, dictionary),
    2 => _convertTwo(number, dictionary),
    3 => _convertThree(number, dictionary),
    4 => _convertFour(number, dictionary, standAlone: true),
    _ => _convertLong(number, dictionary),
  };
}

String _convertOne(String number, Map<String, String> dictionary) =>
    _lookup(dictionary, number);

String _convertTwo(String number, Map<String, String> dictionary) {
  final first = number[0];
  final second = number[1];
  if (first == '0') {
    return _convertOne(second, dictionary);
  }
  if (number == '10') {
    return _lookup(dictionary, '10');
  }
  if (first == '1') {
    return '${_lookup(dictionary, '10')} ${_convertOne(second, dictionary)}';
  }
  if (second == '0') {
    return '${_convertOne(first, dictionary)} ${_lookup(dictionary, '10')}';
  }
  return <String>[
    _lookup(dictionary, first),
    _lookup(dictionary, '10'),
    _lookup(dictionary, second),
  ].join(' ');
}

String _convertThree(String number, Map<String, String> dictionary) {
  final pieces = <String>[];
  switch (number[0]) {
    case '1':
      pieces.add(_lookup(dictionary, '100'));
    case '3':
      pieces.add(_lookup(dictionary, '300'));
    case '6':
      pieces.add(_lookup(dictionary, '600'));
    case '8':
      pieces.add(_lookup(dictionary, '800'));
    default:
      pieces
        ..add(_lookup(dictionary, number[0]))
        ..add(_lookup(dictionary, '100'));
  }

  if (number.substring(1) != '00') {
    pieces.add(
      number[1] == '0'
          ? _lookup(dictionary, number[2])
          : _convertTwo(number.substring(1), dictionary),
    );
  }
  return pieces.join(' ');
}

String _convertFour(
  String number,
  Map<String, String> dictionary, {
  required bool standAlone,
}) {
  if (number == '0000') {
    return '';
  }

  var normalized = number;
  while (normalized.startsWith('0')) {
    normalized = normalized.substring(1);
  }
  switch (normalized.length) {
    case 1:
      return _convertOne(normalized, dictionary);
    case 2:
      return _convertTwo(normalized, dictionary);
    case 3:
      return _convertThree(normalized, dictionary);
  }

  final pieces = <String>[];
  switch (normalized[0]) {
    case '1' when standAlone:
      pieces.add(_lookup(dictionary, '1000'));
    case '1':
      pieces.add(_lookup(dictionary, '01000'));
    case '3':
      pieces.add(_lookup(dictionary, '3000'));
    case '8':
      pieces.add(_lookup(dictionary, '8000'));
    default:
      pieces
        ..add(_lookup(dictionary, normalized[0]))
        ..add(_lookup(dictionary, '1000'));
  }

  if (normalized.substring(1) != '000') {
    pieces.add(
      normalized[1] == '0'
          ? _convertTwo(normalized.substring(2), dictionary)
          : _convertThree(normalized.substring(1), dictionary),
    );
  }
  return pieces.join(' ');
}

String _convertLong(String number, Map<String, String> dictionary) {
  final pieces = <String>[];
  final prefixLength = number.length - 4;
  switch (prefixLength) {
    case 1:
      pieces
        ..add(_lookup(dictionary, number.substring(0, 1)))
        ..add(_lookup(dictionary, '10000'));
    case 2:
      pieces
        ..add(_convertTwo(number.substring(0, 2), dictionary))
        ..add(_lookup(dictionary, '10000'));
    case 3:
      pieces
        ..add(_convertThree(number.substring(0, 3), dictionary))
        ..add(_lookup(dictionary, '10000'));
    case 4:
      pieces
        ..add(
          _convertFour(number.substring(0, 4), dictionary, standAlone: false),
        )
        ..add(_lookup(dictionary, '10000'));
    case 5:
      pieces
        ..add(_lookup(dictionary, number[0]))
        ..add(_lookup(dictionary, '100000000'));
      final myriadGroup = number.substring(1, 5);
      pieces.add(_convertFour(myriadGroup, dictionary, standAlone: false));
      if (myriadGroup != '0000') {
        pieces.add(_lookup(dictionary, '10000'));
      }
    default:
      throw const MalformedDataException(
        'Japanese number conversion supports at most nine digits.',
      );
  }

  pieces.add(
    _convertFour(
      number.substring(number.length - 4),
      dictionary,
      standAlone: false,
    ),
  );
  return pieces.join(' ');
}

int _convertKanjiWhole(String number) {
  if (number == '零') {
    return 0;
  }

  final operations = <_KanjiOperation>[];
  final numberParts = <String>[];
  var current = '';
  for (final character in _scalarCharacters(number)) {
    if (character == '万' || character == '億') {
      numberParts
        ..add(current)
        ..add(character);
      operations
        ..add(_KanjiOperation.times)
        ..add(_KanjiOperation.plus);
      current = '';
    } else {
      current += character;
    }
  }
  if (current.isNotEmpty) {
    numberParts.add(current);
  }

  final convertedParts = <int>[
    for (final part in numberParts) _convertKanjiPart(part),
  ];
  if (convertedParts.isEmpty) {
    throw const InvalidConfigurationException(
      'A Japanese whole number must not be empty.',
    );
  }

  var result = convertedParts.first;
  var operationIndex = 0;
  for (var partIndex = 1; partIndex < convertedParts.length; partIndex++) {
    if (operations[operationIndex] == _KanjiOperation.plus) {
      if (operationIndex + 1 >= operations.length) {
        result += convertedParts.last;
        break;
      }
      if (operations[operationIndex + 1] == _KanjiOperation.times) {
        result += convertedParts[partIndex] * convertedParts[partIndex + 1];
        operationIndex++;
      } else {
        result += convertedParts[partIndex];
      }
    } else {
      result *= convertedParts[partIndex];
    }
    operationIndex++;
  }
  return result;
}

int _convertKanjiPart(String part) {
  final characters = _scalarCharacters(part);
  var result = 0;
  var skip = 1;
  var count = characters.length;
  for (var index = characters.length - 1; index >= 0; index--) {
    final character = characters[index];
    skip--;
    count--;
    if (skip == 1) {
      continue;
    }

    final digit = _kanjiDigitValues[character];
    if (digit != null && character != '零') {
      result += digit;
      continue;
    }

    final link = _kanjiLinkValues[character];
    if (link == null) {
      continue;
    }
    if (count > 0) {
      final precedingDigit = _kanjiDigitValues[characters[count - 1]];
      if (precedingDigit != null && precedingDigit != 0) {
        result += precedingDigit * link;
        skip = 2;
        continue;
      }
    }
    result += link;
  }
  return result;
}
