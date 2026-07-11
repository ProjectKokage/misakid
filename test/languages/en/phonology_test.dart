import 'package:misakid/src/languages/en/phonology.dart';
import 'package:test/test.dart';

void main() {
  group('applyEnglishStress', () {
    test('preserves null stress and removes all stress below -1', () {
      expect(applyEnglishStress('ˈabˌA', null), 'ˈabˌA');
      expect(applyEnglishStress('ˈabˌA', -2), 'abA');
    });

    test('demotes primary stress for the upstream negative cases', () {
      expect(applyEnglishStress('həlˈO', -1), 'həlˌO');
      expect(applyEnglishStress('həlˈO', -0.5), 'həlˌO');
      expect(applyEnglishStress('həlˈO', 0), 'həlˌO');
      expect(applyEnglishStress('ˌhɛlO', -1), 'hɛlO');
    });

    test('places new stress immediately before the first vowel', () {
      expect(applyEnglishStress('hɛlO', 0), 'hˌɛlO');
      expect(applyEnglishStress('hɛlO', 0.5), 'hˌɛlO');
      expect(applyEnglishStress('hɛlO', 1), 'hˌɛlO');
      expect(applyEnglishStress('hɛlO', 2), 'hˈɛlO');
      expect(applyEnglishStress('ʤa', 2), 'ʤˈa');
    });

    test('promotes existing secondary stress at one or above', () {
      expect(applyEnglishStress('ˌhɛlO', 1), 'ˈhɛlO');
      expect(applyEnglishStress('ˌhɛlO', 2), 'ˈhɛlO');
    });

    test('does not add stress to consonant-only output', () {
      for (final stress in <num>[0, 0.5, 1, 2]) {
        expect(applyEnglishStress('str', stress), 'str');
      }
    });

    test('preserves an existing stress mark without a vowel', () {
      expect(applyEnglishStress('ˈ', 2), 'ˈ');
    });
  });

  test('stress weight operates on Unicode scalar values', () {
    expect(englishStressWeight('həlˈO'), 6);
    expect(englishStressWeight('AIO'), 6);
    expect(englishStressWeight('ʤa'), 3);
    expect(englishStressWeight('😀A'), 3);
    expect(englishStressWeight(''), 0);
  });
}
