import 'package:misakid_spacy_en/src/tokenizer/python_unicode.dart';
import 'package:test/test.dart';

void main() {
  group('CPython 3.12 / Unicode 15 tables', () {
    test('alphabetic and uppercase properties are host-independent', () {
      expect(isPython312AlphabeticScalar(0x41), isTrue);
      expect(isPython312UppercaseScalar(0x41), isTrue);
      expect(isPython312UppercaseScalar(0x61), isFalse);
      expect(isPython312AlphabeticScalar(0x10400), isTrue); // Deseret.
      expect(isPython312UppercaseScalar(0x10400), isTrue);
      expect(isPython312AlphabeticScalar(0x11f02), isTrue); // Unicode 15 Kawi.
      expect(isPython312UppercaseScalar(0x11f02), isFalse);
      expect(isPython312AlphabeticScalar(0x1c89), isFalse); // Unicode 16.
    });

    test('digit and whitespace properties preserve Python distinctions', () {
      expect(isPython312DigitScalar(0x31), isTrue);
      expect(isPython312DigitScalar(0x2460), isTrue); // Circled digit one.
      expect(isPython312DigitScalar(0x00bd), isFalse); // Numeric, not digit.
      expect(isPython312DigitScalar(0x1e4f0), isTrue); // Unicode 15 digit.
      expect(isPython312WhitespaceScalar(0x1c), isTrue);
      expect(isPython312WhitespaceScalar(0x2007), isTrue);
      expect(isPython312WhitespaceScalar(0x200b), isFalse);
    });

    test('lowercase mappings include expansion and final sigma context', () {
      expect(python312Lower('Hello'), 'hello');
      expect(python312Lower('İ'), 'i\u0307');
      expect(python312Lower('𐐀'), '𐐨');
      expect(python312Lower('ΟΣ'), 'ος');
      expect(python312Lower('ΟΣΑ'), 'οσα');
      expect(python312Lower('AΣ\u0301'), 'aς\u0301');
      expect(python312Lower('AΣ\u0301B'), 'aσ\u0301b');
      expect(python312Lower('\u{1c89}'), '\u{1c89}');
    });

    test('URL word class contains exact Python alphanumeric semantics', () {
      final word = RegExp(
        '^[$python312WordRegExpClassContents]\$',
        unicode: true,
      );
      expect(word.hasMatch('A'), isTrue);
      expect(word.hasMatch('λ'), isTrue);
      expect(word.hasMatch('𐐀'), isTrue);
      expect(word.hasMatch('①'), isTrue);
      expect(word.hasMatch('½'), isTrue);
      expect(word.hasMatch('_'), isTrue);
      expect(word.hasMatch('-'), isFalse);
      expect(word.hasMatch('\u{1c89}'), isFalse);
    });
  });
}
