// Python 3.12.11 (Unicode 15.0) `str.isdigit` bridge.

import '../../core/python312_unicode.dart';

/// Maps pinned Python integral digit scalars to ASCII and preserves all else.
String mapPython312DigitsToAscii(String input) {
  final result = StringBuffer();
  for (final scalar in input.runes) {
    final digit = python312DigitValue(scalar);
    result.writeCharCode(digit == null ? scalar : 0x30 + digit);
  }
  return result.toString();
}
