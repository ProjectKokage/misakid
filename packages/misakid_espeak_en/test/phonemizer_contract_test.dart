import 'package:misakid/misaki_en.dart';
import 'package:misakid_espeak_en/src/native_bindings.dart';
import 'package:misakid_espeak_en/src/phonemizer_contract.dart';
import 'package:test/test.dart';

void main() {
  group('pinned phonemizer formatting contract', () {
    test('distinguishes an absent empty utterance from whitespace output', () {
      String fake(String text, EnglishDialect dialect) => '';

      expect(
        phonemizeEnglishLikePinnedPhonemizer(
          text: '',
          dialect: EnglishDialect.american,
          phonemizeChunk: fake,
        ),
        isNull,
      );
      expect(
        phonemizeEnglishLikePinnedPhonemizer(
          text: '   ',
          dialect: EnglishDialect.american,
          phonemizeChunk: fake,
        ),
        ' ',
      );
    });

    test('preserves punctuation around separately phonemized chunks', () {
      final calls = <String>[];
      final output = phonemizeEnglishLikePinnedPhonemizer(
        text: '[hello](/custom/',
        dialect: EnglishDialect.american,
        phonemizeChunk: (text, dialect) {
          calls.add(text);
          return switch (text) {
            'hello' => 'həlˈo\u0361ʊ',
            '/custom/' => 'slˈæʃ kˈʌstəm slˈæʃ',
            _ => throw StateError('unexpected chunk'),
          };
        },
      );

      expect(calls, <String>['hello', '/custom/']);
      expect(output, '[həlˈo^ʊ](slˈæʃ kˈʌstəm slˈæʃ ');
    });

    test('ports whitespace, underscore, tie, and word formatting order', () {
      final output = phonemizeEnglishLikePinnedPhonemizer(
        text: 'word',
        dialect: EnglishDialect.british,
        phonemizeChunk: (text, dialect) {
          expect(dialect, EnglishDialect.british);
          return '\u3000a\u0361b___  c\n\u0085';
        },
      );

      expect(output, 'a^b c ');
    });

    test('returns punctuation-only input without a trailing separator', () {
      final output = phonemizeEnglishLikePinnedPhonemizer(
        text: '!?',
        dialect: EnglishDialect.american,
        phonemizeChunk: (text, dialect) => fail('must not invoke eSpeak'),
      );

      expect(output, '!?');
    });

    test('bounds the number of separately phonemized chunks', () {
      final input = List<String>.filled(65537, 'a;').join();
      expect(
        () => phonemizeEnglishLikePinnedPhonemizer(
          text: input,
          dialect: EnglishDialect.american,
          phonemizeChunk: (text, dialect) => fail('must reject before calls'),
        ),
        throwsA(isA<EspeakEnglishNativeLibraryException>()),
      );
    });
  });
}
