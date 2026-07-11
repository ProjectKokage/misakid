// Dart adaptation of Cutlet._normalize_text in hexgrad/misaki/misaki/cutlet.py
// at fba1236595f2d2bf21d414ba6e57d25256afada3 (Misaki 0.9.4,
// Apache-2.0), itself adapted from polm/cutlet under the MIT notice retained in
// THIRD_PARTY_NOTICES.md.

import '../../core/python312_nfkc.dart';
import '../../core/python312_unicode.dart';
import 'number_converter.dart';

/// Normalizes text before an injected Cutlet morphology backend sees it.
String normalizeJapaneseCutletText(String input) {
  final source = input.runes.toList(growable: false);
  final ranged = StringBuffer();
  for (var index = 0; index < source.length; index++) {
    final scalar = source[index];
    if ((scalar == 0x301c || scalar == 0xff5e) &&
        index + 1 < source.length &&
        isPython312DecimalScalar(source[index + 1])) {
      ranged.write('から');
    } else {
      ranged.writeCharCode(scalar);
    }
  }

  var normalized = ranged.toString();
  for (final entry in _katakanaPhoneticExtensions.entries) {
    normalized = normalized.replaceAll(entry.key, entry.value);
  }
  normalized = normalizePython312Nfkc(normalized);

  final output = StringBuffer();
  final current = StringBuffer();
  bool? currentIsDigit;
  void flush() {
    if (currentIsDigit == null) {
      return;
    }
    final value = current.toString();
    // Pinned Cutlet segments with `re \d` (the decimal property), then calls
    // str.isdigit on each complete segment. A non-decimal digit such as ፩ can
    // therefore still enter Convert when it forms a segment by itself.
    final segmentIsDigit = value.runes.every(isPython312DigitScalar);
    output.write(
      segmentIsDigit
          ? ' ${const JapaneseNumberConverter().convert(value)}'
          : value,
    );
    current.clear();
  }

  for (final scalar in normalized.runes) {
    final isDigit = isPython312DecimalScalar(scalar);
    if (currentIsDigit != null && currentIsDigit != isDigit) {
      flush();
    }
    currentIsDigit = isDigit;
    current.writeCharCode(scalar);
  }
  flush();
  return output.toString();
}

const Map<String, String> _katakanaPhoneticExtensions = <String, String>{
  'ㇰ': 'ク',
  'ㇱ': 'シ',
  'ㇲ': 'ス',
  'ㇳ': 'ト',
  'ㇴ': 'ヌ',
  'ㇵ': 'ハ',
  'ㇶ': 'ヒ',
  'ㇷ': 'フ',
  'ㇸ': 'ヘ',
  'ㇹ': 'ホ',
  'ㇺ': 'ム',
  'ㇻ': 'ラ',
  'ㇼ': 'リ',
  'ㇽ': 'ル',
  'ㇾ': 'レ',
  'ㇿ': 'ロ',
};
