import 'package:misakid/src/languages/ko/backends.dart';
import 'package:misakid/src/languages/ko/english.dart';
import 'package:test/test.dart';

void main() {
  test('drops the uncomposed vowel from adjacent ARPABET monophthongs', () {
    final result = convertKoreanEnglish(
      'test',
      (_) => KoreanCmuPronunciation(const <String>['EH', 'AE']),
    );

    expect(result, '에');
  });

  test('retains adjacent vowels when an onset separates their Jamo', () {
    final result = convertKoreanEnglish(
      'test',
      (_) => KoreanCmuPronunciation(const <String>['AY2', 'IY1']),
    );

    expect(result, '아이이');
  });
}
