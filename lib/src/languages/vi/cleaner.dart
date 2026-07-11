// Dart adaptation of licensed Vietnamese cleaner stages in pinned Misaki
// fba1236595f2d2bf21d414ba6e57d25256afada3. CodeLinkIO and Vinorm source
// revisions and MIT notices are recorded in THIRD_PARTY_NOTICES.md.
// Modifications: immutable generated mappings, precompiled expressions, and a
// separately documented clean-room number speller. No num2vi.py code is used.

import '../../core/python312_nfkc.dart';
import '../../core/python311_case.dart';
import '../../generated/vietnamese_cleaner_tables.dart';
import 'cleaner_numeric.dart';
import 'data.dart';
import 'number_speller.dart';
import 'options.dart';

/// Pure pinned Vietnamese text-normalization pipeline.
final class VietnameseCleaner {
  /// Creates a cleaner for [options].
  const VietnameseCleaner({
    required this.options,
    this.numberSpeller = const VietnameseNumberSpeller(),
  });

  /// Cleaning toggles shared with the engine.
  final VietnameseOptions options;

  /// Independently implemented number behavior.
  final VietnameseNumberSpeller numberSpeller;

  /// Applies every cleaner stage in pinned order.
  String clean(String text) {
    var output = collapseWhitespace(text);
    output = ' $output ';
    output = normalizePython311Nfc(output);
    if (options.cleanAbbreviations) {
      output = normalizeAbbreviations(output);
    }
    output = normalizeRomanNumbers(output);
    if (options.cleanAcronyms) {
      output = normalizeAcronyms(output);
    }
    output = normalizeVietnameseDateTime(output, numberSpeller);
    output = normalizeVietnameseMeasurements(output);
    output = normalizeVietnameseCurrencies(output);
    output = normalizeVietnameseNumbers(output, numberSpeller);
    output = normalizeLetters(output);
    output = output.replaceAll('/', ' trên ');
    output = output.replaceAllMapped(
      _internalHyphen,
      (match) => '${match.group(1)} ${match.group(3)}',
    );
    output = collapseWhitespace(output);
    output = output.replaceAllMapped(_monthFour, (_) => 'tháng tư');
    return python311Lower(output);
  }

  /// Collapses whitespace with pinned punctuation/bracket ordering.
  String collapseWhitespace(String text) {
    var output = text.replaceAllMapped(
      _repeatedIdenticalWhitespace,
      (match) => match.group(1)!,
    );
    output = output.replaceAllMapped(
      _whitespaceBeforePunctuation,
      (match) => match.group(2)!,
    );
    output = output.replaceAllMapped(
      _openingBracketWhitespace,
      (match) => '${match.group(2)}${match.group(1)}',
    );
    output = output.replaceAllMapped(
      _repeatedIdenticalWhitespace,
      (match) => match.group(1)!,
    );
    return stripPython311Whitespace(output.replaceAll(_tabs, ' '));
  }

  /// Applies special-symbol, URL, base abbreviation, and teencode mappings.
  String normalizeAbbreviations(String text) {
    var output = text
        .replaceAllMapped(_percent, (_) => ' phần trăm')
        .replaceAll('&', ' và ')
        .replaceAll('@', ' a còng ')
        .replaceAll('+', ' cộng ')
        .replaceAll('//', ' xuyệt ');
    output = output.replaceAllMapped(
      _url,
      (match) => '${match.group(1)} chấm ${match.group(2)}',
    );
    return output.replaceAllMapped(_abbreviationPattern, (match) {
      final key = python311Lower(match.group(1)!.replaceAll('.', r'\.'));
      return _abbreviations[key]!;
    });
  }

  /// Applies pinned Roman-number behavior up to 39.
  String normalizeRomanNumbers(String text) {
    var output = text.replaceAllMapped(
      _trueLetterPattern,
      (match) => python311Lower(match.group(0)!),
    );
    output = output.replaceAllMapped(_romanCandidate, (match) {
      final roman = match.group(1)!;
      if (roman.startsWith('LLC') || !_canonicalRoman.hasMatch(roman)) {
        return roman;
      }
      var value = 0;
      final scalars = roman.codeUnits;
      for (var index = 0; index < scalars.length; index++) {
        final current = _romanValues[String.fromCharCode(scalars[index])]!;
        final next = index + 1 == scalars.length
            ? null
            : _romanValues[String.fromCharCode(scalars[index + 1])]!;
        value += next == null || current >= next ? current : -current;
      }
      return value > 39 ? roman : ' ${numberSpeller.spell('$value')} ';
    });
    return output;
  }

  /// Applies ordered acronym dictionary replacements and spelling behavior.
  String normalizeAcronyms(String text) {
    var output = text.replaceAllMapped(
      _acronymDictionaryPattern,
      (match) => _acronymsByLowercase[python311Lower(match.group(1)!)]!,
    );
    return output.replaceAllMapped(_acronymPattern, (match) {
      final acronym = match.group(1)!;
      if (!vietnameseSpelledAcronyms.contains(acronym)) {
        return acronym;
      }
      return <String>[
        for (final scalar in match.group(0)!.runes) String.fromCharCode(scalar),
      ].join('  ');
    });
  }

  /// Expands standalone letter names with pinned surrounding-character rules.
  String normalizeLetters(String text) =>
      text.replaceAllMapped(_letterPattern, (match) {
        final leading = match.group(1) ?? '';
        final quote = match.group(3) ?? '';
        final character = match.group(4)!;
        var trailing = match.group(5) ?? '';
        if (trailing.isNotEmpty && vietnameseCharacterSet.contains(trailing)) {
          return match.group(0)!;
        }
        if (trailing == '.') {
          trailing = '';
        }
        final name = vietnameseCleanerLetterNames[python311Lower(character)];
        if (name == null) {
          return match.group(0)!;
        }
        return '$leading $quote$name$trailing ';
      });
}

final Map<String, String> _abbreviations = <String, String>{
  ...vietnameseBaseAbbreviations,
  ...loadVietnameseCleanerData().teencode,
};

final Map<String, String> _acronyms = <String, String>{
  ...vietnameseBaseAcronyms,
  ...loadVietnameseCleanerData().acronyms,
};

final Map<String, String> _acronymsByLowercase = <String, String>{
  for (final entry in _acronyms.entries) python311Lower(entry.key): entry.value,
};

final RegExp _acronymDictionaryPattern = _unicodeWordPattern(
  '(${_acronyms.keys.map(RegExp.escape).join('|')})',
  captureAlreadyPresent: true,
);

final String _abbreviationAlternation = <String>[
  for (final key in vietnameseBaseAbbreviations.keys) key,
  for (final key in loadVietnameseCleanerData().teencode.keys)
    RegExp.escape(key),
].join('|');

final RegExp _abbreviationPattern = _unicodeWordPattern(
  '($_abbreviationAlternation)',
  captureAlreadyPresent: true,
);

RegExp _unicodeWordPattern(String body, {bool captureAlreadyPresent = false}) =>
    RegExp(
      '(?<![_\\p{L}\\p{N}])${captureAlreadyPresent ? body : '($body)'}'
      '(?![_\\p{L}\\p{N}])',
      caseSensitive: false,
      unicode: true,
    );

final RegExp _repeatedIdenticalWhitespace = RegExp(r'(\s)\1{1,}');
final RegExp _whitespaceBeforePunctuation = RegExp(r'(\s)([.,?!:;)}\]])');
final RegExp _openingBracketWhitespace = RegExp(r'([(\[{])(\s)');
final RegExp _tabs = RegExp(r'\t+');
final RegExp _percent = RegExp(r' ?%');
final RegExp _url = RegExp(r'([a-zA-Z])\.(com|gov|org|vn|com\.vn|edu\.vn)');
final RegExp _internalHyphen = RegExp(r'([^\s])(-)([^\s])');
final RegExp _monthFour = RegExp(
  'tháng bốn',
  caseSensitive: false,
  unicode: true,
);

final String _vietnameseBoundary =
    '([^${RegExp.escape(vietnameseCharacterSet)}])';
final RegExp _trueLetterPattern = RegExp(
  '(chữ|chữ cái|kí tự|ký tự)(\\s)("|\')?([A-Z]+)("|\')?'
  '$_vietnameseBoundary',
  unicode: true,
);
final RegExp _romanCandidate = RegExp(
  r'(?<![_\p{L}\p{N}])([MDCLXVI]+)(?![_\p{L}\p{N}])',
  unicode: true,
);
final RegExp _canonicalRoman = RegExp(
  r'^M{0,4}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3})$',
);
const Map<String, int> _romanValues = <String, int>{
  'I': 1,
  'V': 5,
  'X': 10,
  'L': 50,
  'C': 100,
  'D': 500,
  'M': 1000,
};

final RegExp _acronymPattern = RegExp(r'([a-z]*[A-Z][A-Z]+)s?\.?');

final String _letterAlternation = vietnameseCleanerLetterNames.keys
    .map(RegExp.escape)
    .join('|');
final RegExp _letterPattern = RegExp(
  '(chữ|chữ cái|kí tự|ký tự)?(\\s)("|\')?'
  '($_letterAlternation)(.)?',
  caseSensitive: false,
  unicode: true,
);
