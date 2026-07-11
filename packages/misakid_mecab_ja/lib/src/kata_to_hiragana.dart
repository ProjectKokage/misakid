// Dart adaptation of jaconv 0.4.0's K2H_TABLE (MIT).
//
// Modifications: represents the table as its equivalent Unicode-scalar ranges
// and iterates Dart strings by scalar rather than UTF-16 code unit.

/// Converts the exact full-width Katakana set used by jaconv 0.4.0 to
/// Hiragana.
///
/// No normalization or half-width conversion is performed. Katakana outside
/// jaconv's table, including `ヷ` through `ヺ`, are intentionally unchanged.
String cutletKataToHiragana(String text) {
  if (text.isEmpty) return text;
  final output = StringBuffer();
  for (final scalar in text.runes) {
    if ((scalar >= 0x30A1 && scalar <= 0x30F6) ||
        scalar == 0x30FD ||
        scalar == 0x30FE) {
      output.writeCharCode(scalar - 0x60);
    } else {
      output.writeCharCode(scalar);
    }
  }
  return output.toString();
}
