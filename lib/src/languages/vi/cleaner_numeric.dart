// Numeric/date/unit stages adapted from licensed Vietnamese cleaner modules
// in pinned Misaki fba1236595f2d2bf21d414ba6e57d25256afada3.
// CodeLinkIO/Vinorm MIT notices are in THIRD_PARTY_NOTICES.md. Number words
// come from the independent clean-room VietnameseNumberSpeller.

import '../../generated/vietnamese_cleaner_tables.dart';
import '../../core/python311_case.dart';
import 'data.dart';
import 'number_speller.dart';

/// Normalizes dates then times in pinned order.
String normalizeVietnameseDateTime(
  String text,
  VietnameseNumberSpeller speller,
) {
  var output = text.replaceAllMapped(
    _quarterMonthYear,
    (match) => _expandQuarterMonthYear(match, speller),
  );
  output = output.replaceAllMapped(
    _rangeMonthYear,
    (match) => _expandRangeMonthYear(match, speller),
  );
  output = output.replaceAllMapped(
    _fullRangeDate,
    (match) => _expandFullRangeDate(match, speller),
  );
  output = output.replaceAllMapped(
    _fullDate,
    (match) => _expandFullDate(match, speller),
  );
  output = output.replaceAllMapped(
    _monthYear,
    (match) => _expandMonthYear(match, speller),
  );
  output = output.replaceAllMapped(
    _rangeDayMonth,
    (match) => _expandRangeDayMonth(match, speller),
  );
  output = output.replaceAllMapped(
    _dayMonth,
    (match) => _expandDayMonth(match, speller),
  );
  output = output.replaceAllMapped(
    _fullTime,
    (match) => _expandFullTime(match, speller),
  );
  return output.replaceAllMapped(_time, (match) => _expandTime(match, speller));
}

/// Normalizes licensed measurement-unit mappings.
String normalizeVietnameseMeasurements(String text) {
  var output = text.replaceAllMapped(_measurementWithSlash, (match) {
    final first = vietnameseMeasurements[match.group(2)!]!;
    final second = vietnameseMeasurements[match.group(4)!]!;
    return '${match.group(1)} $first trên $second${match.group(5)}';
  });
  return output.replaceAllMapped(_measurement, (match) {
    final prefix = match.group(1)!;
    final source = match.group(2)!;
    if (source.runes.length == 1 && int.tryParse(prefix) == null) {
      return match.group(0)!;
    }
    return '$prefix ${vietnameseMeasurements[source]} ${match.group(3)}';
  });
}

/// Normalizes licensed currency and general symbol mappings.
String normalizeVietnameseCurrencies(String text) =>
    text.replaceAllMapped(_currency, (match) {
      final prefix = match.group(1) ?? '';
      final source = match.group(2)!;
      final suffix = match.group(3) ?? '';
      if (source == 'Đ' && suffix == '.') {
        return match.group(0)!;
      }
      if (suffix == source || prefix == source) {
        return match.group(0)!;
      }
      final replacement = source == r'$'
          ? vietnameseBaseCurrencies[r'\$']
          : _currencies[python311Lower(source)];
      return '$prefix${replacement ?? source}$suffix';
    });

/// Normalizes ordinals, multiplication, ranges, phones, and general numbers.
String normalizeVietnameseNumbers(
  String text,
  VietnameseNumberSpeller speller,
) {
  var output = text.replaceAllMapped(_specialOrdinal, (match) {
    final number = match.group(3)!;
    final spoken = switch (number) {
      '1' => 'nhất',
      '4' => 'tư',
      _ => speller.spell(number),
    };
    return '${match.group(1)}${match.group(2)}$spoken';
  });
  output = output.replaceAllMapped(
    _multiplyNumber,
    (match) =>
        '${speller.spell(match.group(1)!)} nhân '
        '${speller.spell(match.group(3)!)}',
  );
  output = output.replaceAllMapped(_rangeNumber, (match) {
    final prefix = match.group(2) ?? '';
    if (prefix.isNotEmpty && vietnameseCharacterSet.contains(prefix)) {
      return match.group(0)!;
    }
    final start = match.group(3) == '-'
        ? '-${match.group(4)}'
        : match.group(4)!;
    final end = match.group(6) == '-' ? '-${match.group(7)}' : match.group(7)!;
    return '${match.group(1)}$prefix${speller.spell(start)} đến '
        '${speller.spell(end)}${match.group(8)}';
  });
  output = output.replaceAllMapped(
    _phone,
    (match) => speller.spellDigits(stripPython311Whitespace(match.group(0)!)),
  );
  return output.replaceAllMapped(_number, (match) {
    final prefix = match.group(1)!;
    final negative = match.group(2) ?? '';
    final number = _removePrefixZero(match.group(3)!);
    if (vietnameseCharacterSet.contains(prefix)) {
      return '$prefix $negative${speller.spell(number)} ';
    }
    return '$prefix ${speller.spell(negative == '-' ? '-$number' : number)} ';
  });
}

String _expandFullDate(Match match, VietnameseNumberSpeller speller) {
  final prefix = match.group(1) ?? '';
  final space = match.group(2) ?? '';
  final day = _removePrefixZero(match.group(3)!);
  final separator = match.group(4)!;
  final month = _removePrefixZero(match.group(5)!);
  final year = _removePrefixZero(match.group(7)!);
  if (!_validDate(int.parse(day), int.parse(month)) || prefix == separator) {
    return match.group(0)!;
  }
  return '$space ngày ${speller.spell(day)} tháng ${speller.spell(month)} '
      'năm ${speller.spell(year)}${match.group(8)} ';
}

String _expandFullRangeDate(Match match, VietnameseNumberSpeller speller) {
  final space = match.group(2) ?? '';
  final start = _removePrefixZero(match.group(3)!);
  final end = _removePrefixZero(match.group(5)!);
  final month = _removePrefixZero(match.group(7)!);
  final year = _removePrefixZero(match.group(9)!);
  if (!_validDate(int.parse(start), int.parse(month)) ||
      !_validDate(int.parse(end), int.parse(month))) {
    return match.group(0)!;
  }
  return '$space ngày ${speller.spell(start)} đến ngày ${speller.spell(end)} '
      'tháng ${speller.spell(month)} năm ${speller.spell(year)}'
      '${match.group(10)} ';
}

String _expandDayMonth(Match match, VietnameseNumberSpeller speller) {
  var prefix = match.group(1)!;
  final space = match.group(2) ?? '';
  final day = _removePrefixZero(match.group(3)!);
  final separator = match.group(4)!;
  final month = _removePrefixZero(match.group(5)!);
  prefix = prefix == 'ngày' ? prefix : '$prefix ngày';
  if (!_validDate(int.parse(day), int.parse(month)) || space == separator) {
    return match.group(0)!;
  }
  return '$space$prefix$space${speller.spell(day)} tháng '
      '${speller.spell(month)}${match.group(6)} ';
}

String _expandRangeDayMonth(Match match, VietnameseNumberSpeller speller) {
  final space = match.group(2) ?? '';
  final start = _removePrefixZero(match.group(3)!);
  final end = _removePrefixZero(match.group(5)!);
  final month = _removePrefixZero(match.group(7)!);
  if (!_validDate(int.parse(start), int.parse(month)) ||
      !_validDate(int.parse(end), int.parse(month))) {
    return match.group(0)!;
  }
  return '$space ngày ${speller.spell(start)} đến ngày ${speller.spell(end)} '
      'tháng ${speller.spell(month)}${match.group(8)} ';
}

String _expandMonthYear(Match match, VietnameseNumberSpeller speller) {
  final space = match.group(2) ?? '';
  final month = _removePrefixZero(match.group(3)!);
  final separator = match.group(4)!;
  final year = _removePrefixZero(match.group(5)!);
  if (!_validDate(1, int.parse(month)) || space == separator) {
    return match.group(0)!;
  }
  return '$space tháng ${speller.spell(month)} năm ${speller.spell(year)}'
      '${match.group(6)} ';
}

String _expandQuarterMonthYear(Match match, VietnameseNumberSpeller speller) {
  final space = match.group(2) ?? '';
  final quarter = _removePrefixZero(match.group(3)!);
  final separator = match.group(5)!;
  final year = _removePrefixZero(match.group(6)!);
  final roman = const <String, String>{
    'I': '1',
    'II': '2',
    'III': '3',
    'IV': '4',
  }[quarter];
  if (roman == null &&
      (!_validQuarter(int.parse(quarter)) || space == separator)) {
    return match.group(0)!;
  }
  return '$space quý ${speller.spell(roman ?? quarter)} năm '
      '${speller.spell(year)}${match.group(7)} ';
}

String _expandRangeMonthYear(Match match, VietnameseNumberSpeller speller) {
  final space = match.group(2) ?? '';
  final start = _removePrefixZero(match.group(3)!);
  final separator = match.group(4)!;
  final end = _removePrefixZero(match.group(5)!);
  final yearSeparator = match.group(6)!;
  final year = _removePrefixZero(match.group(7)!);
  if (!_validDate(1, int.parse(start)) ||
      !_validDate(1, int.parse(end)) ||
      separator == yearSeparator) {
    return match.group(0)!;
  }
  return '$space tháng ${speller.spell(start)} đến tháng ${speller.spell(end)} '
      'năm ${speller.spell(year)}${match.group(8)} ';
}

String _expandTime(Match match, VietnameseNumberSpeller speller) {
  final prefix = match.group(1) ?? '';
  final hour = _removePrefixZero(match.group(2)!);
  final minute = _removePrefixZero(match.group(4)!);
  if (!_validTime(int.parse(hour), int.parse(minute))) {
    return match.group(0)!;
  }
  return '$prefix ${speller.spell(hour)} giờ ${speller.spell(minute)} phút'
      '${match.group(6)} ';
}

String _expandFullTime(Match match, VietnameseNumberSpeller speller) {
  final prefix = match.group(1) ?? '';
  final hour = _removePrefixZero(match.group(2)!);
  final minute = _removePrefixZero(match.group(4)!);
  final second = _removePrefixZero(match.group(6)!);
  if (!_validTime(int.parse(hour), int.parse(minute), int.parse(second))) {
    return match.group(0)!;
  }
  return '$prefix ${speller.spell(hour)} giờ ${speller.spell(minute)} phút '
      '${speller.spell(second)} giây${match.group(8)} ';
}

String _removePrefixZero(String text) {
  var result = stripRightPython311Whitespace(text);
  while (result.length > 1 && result.startsWith('0') && result[1] != ',') {
    result = result.substring(1);
  }
  return result.isEmpty ? '0' : result;
}

bool _validQuarter(int quarter) => quarter >= 1 && quarter <= 4;

bool _validDate(int day, int month) =>
    month >= 1 && month <= 12 && day >= 1 && day <= _daysInMonth[month - 1];

bool _validTime(int hour, int minute, [int second = 0]) =>
    hour >= 0 &&
    hour < 24 &&
    minute >= 0 &&
    minute < 60 &&
    second >= 0 &&
    second < 60;

const List<int> _daysInMonth = <int>[
  31,
  29,
  31,
  30,
  31,
  30,
  31,
  31,
  30,
  31,
  30,
  31,
];

final String _letters = vietnameseCharacterSet.replaceAll(RegExp('[0-9]'), '');
final String _vietnameseBoundary =
    '([^${RegExp.escape(vietnameseCharacterSet)}])';
final String _dateWordCharacters = '$vietnameseCharacterSet%\$';
final String _dateBoundary =
    '([^${RegExp.escape(_dateWordCharacters).replaceAll(r'\$', r'$')}])';
final String _withoutNumberBoundary = '([^${RegExp.escape(_letters)}])';
const String _separator = r'(/|-|\.)';
const String _dayPeriods = r'(ngày|hôm|sáng|trưa|chiều|tối|đêm|khuya)';
const String _quarter = r'([\p{Nd}]{1,2}|(I|II|III|IV))';

final RegExp _quarterMonthYear = RegExp(
  '(quý)$_vietnameseBoundary$_quarter$_separator'
  r'([\p{Nd}]{4})'
  '$_dateBoundary',
  caseSensitive: false,
  unicode: true,
);
final RegExp _fullDate = RegExp(
  '(ngày)?$_vietnameseBoundary'
  r'([\p{Nd}]{1,2})'
  '$_separator'
  r'([\p{Nd}]{1,2})'
  '$_separator'
  r'([\p{Nd}]{4})'
  '$_dateBoundary',
  caseSensitive: false,
  unicode: true,
);
final RegExp _fullRangeDate = RegExp(
  '(ngày)?$_vietnameseBoundary'
  r'([\p{Nd}]{1,2})(-)([\p{Nd}]{1,2})'
  '$_separator'
  r'([\p{Nd}]{1,2})'
  '$_separator'
  r'([\p{Nd}]{4})'
  '$_dateBoundary',
  caseSensitive: false,
  unicode: true,
);
final RegExp _dayMonth = RegExp(
  '$_dayPeriods$_vietnameseBoundary'
  r'([\p{Nd}]{1,2})'
  '$_separator'
  r'([\p{Nd}]{1,2})'
  '$_dateBoundary',
  caseSensitive: false,
  unicode: true,
);
final RegExp _rangeDayMonth = RegExp(
  '(ngày)?$_vietnameseBoundary'
  r'([\p{Nd}]{1,2})(-)([\p{Nd}]{1,2})'
  '$_separator'
  r'([\p{Nd}]{1,2})'
  '$_dateBoundary',
  caseSensitive: false,
  unicode: true,
);
final RegExp _monthYear = RegExp(
  '(tháng)?$_vietnameseBoundary'
  r'([\p{Nd}]{1,2})'
  '$_separator'
  r'([\p{Nd}]{4})'
  '$_dateBoundary',
  caseSensitive: false,
  unicode: true,
);
final RegExp _rangeMonthYear = RegExp(
  '(tháng)?$_vietnameseBoundary'
  r'([\p{Nd}]{1,2})(-)([\p{Nd}]{1,2})'
  '$_separator'
  r'([\p{Nd}]{4})'
  '$_dateBoundary',
  caseSensitive: false,
  unicode: true,
);
final RegExp _fullTime = RegExp(
  '$_vietnameseBoundary'
  r'([\p{Nd}]{1,2})(g|:|h)([\p{Nd}]{1,2})(p|:|m)'
  r'([\p{Nd}]{1,2})(s|g)?'
  '$_dateBoundary',
  caseSensitive: false,
  unicode: true,
);
final RegExp _time = RegExp(
  '$_vietnameseBoundary'
  r'([\p{Nd}]{1,2})(g|:|h)([\p{Nd}]{1,2})(p|m)?'
  '$_dateBoundary',
  caseSensitive: false,
  unicode: true,
);

final String _measurementAlternation = vietnameseMeasurements.keys.join('|');
final RegExp _measurement = RegExp(
  '$_withoutNumberBoundary($_measurementAlternation)$_vietnameseBoundary',
  unicode: true,
);
final RegExp _measurementWithSlash = RegExp(
  '$_withoutNumberBoundary($_measurementAlternation)(/)'
  '($_measurementAlternation)$_vietnameseBoundary',
  unicode: true,
);

final Map<String, String> _currencies = <String, String>{
  ...vietnameseBaseCurrencies,
  ...loadVietnameseCleanerData().symbols,
};
final String _currencyAlternation = _currencies.keys
    .map(RegExp.escape)
    .join('|');
final RegExp _currency = RegExp(
  '$_withoutNumberBoundary($_currencyAlternation)$_withoutNumberBoundary',
  caseSensitive: false,
  unicode: true,
);

const String _digits = r'[\p{Nd}]+';
const String _normalNumber = _digits;
const String _oneSpace = r'[\p{Nd}]+\s{1}[\p{Nd}]{3}';
const String _twoSpaces = r'[\p{Nd}]+\s{1}[\p{Nd}]{3}\s{1}[\p{Nd}]{3}';
const String _threeSpaces =
    r'[\p{Nd}]+\s{1}[\p{Nd}]{3}\s{1}[\p{Nd}]{3}\s{1}[\p{Nd}]{3}';
const String _oneDot = r'[\p{Nd}]+\.[\p{Nd}]{3}';
const String _twoDots = r'[\p{Nd}]+\.[\p{Nd}]{3}\.[\p{Nd}]{3}';
const String _threeDots = r'[\p{Nd}]+\.[\p{Nd}]{3}\.[\p{Nd}]{3}\.[\p{Nd}]{3}';
const String _floatNumber = r'[\p{Nd}]+,[\p{Nd}]+';
const String _numberValue =
    '(?:$_floatNumber|$_threeDots|$_twoDots|$_oneDot|'
    '$_threeSpaces|$_twoSpaces|$_oneSpace|$_normalNumber)';
const String _numberPattern = '(.)(-)?($_numberValue)';
const String _endNumberPattern = '(-)?($_numberValue)';

final RegExp _specialOrdinal = RegExp(r'(thứ|hạng)(\s)(1|4)', unicode: true);
final RegExp _multiplyNumber = RegExp(
  '($_normalNumber)(x|\\sx\\s)($_normalNumber)',
  unicode: true,
);
final RegExp _rangeNumber = RegExp(
  '(từ|tới|còn|đến|khoảng|sau)$_numberPattern'
  r'(-|\s-\s)'
  '$_endNumberPattern$_withoutNumberBoundary',
  caseSensitive: false,
  unicode: true,
);
final RegExp _phone = RegExp(
  r'(?:(?:(?:\+84|84|0|0084))(?:3|5|7|8|9))+(?:[0-9]{8})',
);
final RegExp _number = RegExp(_numberPattern, unicode: true);
