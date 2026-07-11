import 'package:misakid/misaki_ja.dart';

void main() {
  const numbers = JapaneseNumberConverter();

  print(numbers.convert('12345'));
  print(numbers.convert('20.5', format: JapaneseNumberFormat.romaji));
  print(numbers.kanjiToArabic('一億一万一'));
}
