// Independent clean-room implementation of Vietnamese number spelling.
//
// This file was written from black-box outputs of the pinned Misaki oracle.
// It does not copy or translate misaki/vi_cleaner/num2vi.py, whose named source
// has no license. See THIRD_PARTY_NOTICES.md and PORTING_NOTES.md.

import '../../core/errors.dart';

/// Clean-room number spelling used by the Vietnamese cleaner.
final class VietnameseNumberSpeller {
  /// Creates a stateless speller.
  const VietnameseNumberSpeller();

  /// Spells an upstream-formatted number as grouped Vietnamese words.
  String spell(String number) {
    final digits = _normalize(number);
    if (digits == '0') {
      return 'không';
    }
    final groups = <String>[];
    for (var end = digits.length; end > 0; end -= 3) {
      final start = end < 3 ? 0 : end - 3;
      groups.insert(0, digits.substring(start, end));
    }
    final retained = groups.length > _scales.length
        ? groups.sublist(groups.length - _scales.length)
        : groups;
    final scaleOffset = _scales.length - retained.length;
    final words = <String>[];
    for (var index = 0; index < retained.length; index++) {
      final groupWords = _spellGroup(retained[index]);
      final scale = _scales[scaleOffset + index];
      if (groupWords.isNotEmpty) {
        words.add(groupWords);
      }
      if (scale.isNotEmpty) {
        words.add(scale);
      }
    }
    return words.join(' ');
  }

  /// Spells each digit independently, including the pinned `+84` phone rule.
  String spellDigits(String number) {
    var normalized = number.startsWith('+84')
        ? '0${number.substring(3)}'
        : number;
    normalized = _normalize(normalized);
    return <String>[
      for (final codeUnit in normalized.codeUnits) _digitNames[codeUnit - 0x30],
    ].join(' ');
  }

  String _normalize(String number) {
    final normalized = number.replaceAll(_ignoredNumberCharacters, '');
    if (normalized.isEmpty ||
        normalized.codeUnits.any((unit) => unit < 0x30 || unit > 0x39)) {
      throw InvalidConfigurationException(
        'Vietnamese number input must contain ASCII digits and supported '
        'separators only.',
      );
    }
    return normalized;
  }

  String _spellGroup(String digits) {
    if (digits.length == 1) {
      return _digitNames[int.parse(digits)];
    }
    final output = <String>[];
    final hundred = digits.length == 3 ? int.parse(digits[0]) : null;
    final tensIndex = digits.length - 2;
    final tens = int.parse(digits[tensIndex]);
    final ones = int.parse(digits[tensIndex + 1]);
    if (hundred != null) {
      output
        ..add(_digitNames[hundred])
        ..add('trăm');
    }
    if (tens == 0) {
      if (ones != 0) {
        output
          ..add('lẻ')
          ..add(_digitNames[ones]);
      }
      return output.join(' ');
    }
    if (tens == 1) {
      output.add('mười');
    } else {
      output
        ..add(_digitNames[tens])
        ..add('mươi');
    }
    if (ones != 0) {
      if (ones == 1 && tens > 1) {
        output.add('mốt');
      } else if (ones == 5) {
        output.add('lăm');
      } else {
        output.add(_digitNames[ones]);
      }
    }
    return output.join(' ');
  }
}

final RegExp _ignoredNumberCharacters = RegExp(r'[-., ]');

const List<String> _digitNames = <String>[
  'không',
  'một',
  'hai',
  'ba',
  'bốn',
  'năm',
  'sáu',
  'bảy',
  'tám',
  'chín',
];

const List<String> _scales = <String>['tỷ', 'triệu', 'nghìn', ''];
