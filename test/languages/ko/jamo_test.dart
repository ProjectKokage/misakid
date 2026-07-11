import 'package:misakid/misaki_ko.dart';
import 'package:test/test.dart';

void main() {
  test('decomposes the modern Hangul range by Unicode scalar', () {
    expect(decomposeKoreanHangul('가각힣'), '가각힣');
    expect(decomposeKoreanHangul('A😀ㄱᄀ️'), 'A😀ㄱᄀ️');
  });

  test('round-trips every modern precomposed Hangul syllable', () {
    final syllables = String.fromCharCodes(
      List<int>.generate(0xd7a3 - 0xac00 + 1, (index) => 0xac00 + index),
    );

    expect(composeKoreanJamo(decomposeKoreanHangul(syllables)), syllables);
  });

  test('composition supplies a silent onset for a standalone modern vowel', () {
    expect(composeKoreanJamo('ᅡ'), '아');
    expect(composeKoreanJamo('Aᅡ'), 'A아');
    expect(composeKoreanJamo('한글'), '한글');
    expect(composeKoreanJamo('ㄱ😀'), 'ㄱ😀');
  });

  test('preserves upstream non-overlap for consecutive vowels', () {
    expect(composeKoreanJamo('ᅡᅥ'), '아ᅥ');
    expect(composeKoreanJamo('ᅡᅥᅩᅮ'), '아ᅥ오ᅮ');
    expect(composeKoreanJamo('가ᅥ'), '가어');
    expect(composeKoreanJamo('Aᅡᅥ'), 'A아ᅥ');
  });
}
