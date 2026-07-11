import 'package:misakid/src/languages/en/lexicon_data.dart';
import 'package:misakid/src/languages/en/morphology.dart';
import 'package:test/test.dart';

void main() {
  group('generated English lexicons', () {
    test('load exact American entry counts and values', () {
      final data = loadEnglishLexiconData(EnglishDialect.american);

      expect(data.goldEntries, hasLength(90201));
      expect(data.silverEntries, hasLength(93361));
      expect(
        data.gold('hello'),
        isA<EnglishSimpleLexiconEntry>().having(
          (entry) => entry.phonemes,
          'phonemes',
          'həlˈO',
        ),
      );
      expect(
        data.gold('used'),
        isA<EnglishContextualLexiconEntry>()
            .having((entry) => entry.variants['DEFAULT'], 'default', 'jˈuzd')
            .having((entry) => entry.variants['VBD'], 'past', 'jˈust'),
      );
    });

    test('load exact British entry counts and values', () {
      final data = loadEnglishLexiconData(EnglishDialect.british);

      expect(data.goldEntries, hasLength(87352));
      expect(data.silverEntries, hasLength(109766));
      expect(
        data.gold('hello'),
        isA<EnglishSimpleLexiconEntry>().having(
          (entry) => entry.phonemes,
          'phonemes',
          'həlˈQ',
        ),
      );
    });

    test('emulates grow_dictionary without duplicating stored maps', () {
      final data = loadEnglishLexiconData(EnglishDialect.american);

      expect(data.goldEntries.containsKey('Hello'), isFalse);
      expect(
        data.gold('Hello'),
        isA<EnglishSimpleLexiconEntry>().having(
          (entry) => entry.phonemes,
          'phonemes',
          'həlˈO',
        ),
      );
      expect(data.gold('A'), isA<EnglishSimpleLexiconEntry>());
      expect(data.gold('a'), isA<EnglishSimpleLexiconEntry>());
      expect(data.gold('HELLO'), isNull);
    });

    test('returns the same isolate-local cache instance', () {
      expect(
        identical(
          loadEnglishLexiconData(EnglishDialect.american),
          loadEnglishLexiconData(EnglishDialect.american),
        ),
        isTrue,
      );
    });
  });
}
