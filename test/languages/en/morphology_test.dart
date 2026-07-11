import 'package:misakid/src/languages/en/morphology.dart';
import 'package:test/test.dart';

void main() {
  const american = EnglishInflectionRules(EnglishDialect.american);
  const british = EnglishInflectionRules(EnglishDialect.british);

  group('appendS', () {
    test('returns null for an unavailable or empty stem', () {
      expect(american.appendS(null), isNull);
      expect(american.appendS(''), isNull);
    });

    test('selects voiceless, sibilant, and voiced endings', () {
      expect(american.appendS('kæt'), 'kæts');
      expect(american.appendS('bʌz'), 'bʌzᵻz');
      expect(british.appendS('bʌz'), 'bʌzɪz');
      expect(american.appendS('dɑg'), 'dɑgz');
    });
  });

  group('appendEd', () {
    test('returns null for an unavailable or empty stem', () {
      expect(american.appendEd(null), isNull);
      expect(american.appendEd(''), isNull);
    });

    test('preserves dialect-specific suffix vowels', () {
      expect(american.appendEd('nˈid'), 'nˈidᵻd');
      expect(british.appendEd('nˈid'), 'nˈidɪd');
      expect(american.appendEd('wɑʃ'), 'wɑʃt');
      expect(american.appendEd('kˈɔl'), 'kˈɔld');
    });

    test('flaps eligible American final t', () {
      expect(american.appendEd('wˈeɪt'), 'wˈeɪɾᵻd');
      expect(american.appendEd('ækt'), 'æktᵻd');
      expect(british.appendEd('wˈeɪt'), 'wˈeɪtɪd');
      expect(american.appendEd('t'), 'tɪd');
    });
  });

  group('appendIng', () {
    test('returns null for an unavailable or empty stem', () {
      expect(american.appendIng(null), isNull);
      expect(american.appendIng(''), isNull);
    });

    test('flaps eligible American final t', () {
      expect(american.appendIng('wˈeɪt'), 'wˈeɪɾɪŋ');
      expect(american.appendIng('ækt'), 'æktɪŋ');
      expect(british.appendIng('wˈeɪt'), 'wˈeɪtɪŋ');
    });

    test('preserves the British schwa and length-mark failure quirk', () {
      expect(british.appendIng('fɑː'), isNull);
      expect(british.appendIng('ə'), isNull);
      expect(american.appendIng('ə'), 'əɪŋ');
    });
  });
}
