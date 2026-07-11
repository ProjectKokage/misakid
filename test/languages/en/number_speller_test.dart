import 'package:misakid/misaki.dart';
import 'package:misakid/src/languages/en/number_speller.dart';
import 'package:test/test.dart';

void main() {
  const speller = EnglishNumberSpeller();

  group('cardinal', () {
    const cases = <int, String>{
      0: 'zero',
      7: 'seven',
      19: 'nineteen',
      21: 'twenty one',
      105: 'one hundred and five',
      999: 'nine hundred and ninety nine',
      1000: 'one thousand',
      1001: 'one thousand and one',
      1100: 'one thousand one hundred',
      1234: 'one thousand two hundred and thirty four',
      1000001: 'one million and one',
      1234567:
          'one million two hundred and thirty four thousand five hundred and sixty seven',
    };

    for (final entry in cases.entries) {
      test('${entry.key}', () {
        expect(speller.cardinal(BigInt.from(entry.key)).join(' '), entry.value);
      });
    }

    test('negative and complete scale boundary', () {
      expect(
        speller.cardinal(BigInt.from(-105)).join(' '),
        'minus one hundred and five',
      );
      expect(
        speller.cardinal(BigInt.from(10).pow(303)).join(' '),
        'one centillion',
      );
      expect(
        () => speller.cardinal(BigInt.from(10).pow(306)),
        throwsA(isA<InvalidConfigurationException>()),
      );
    });
  });

  group('ordinal', () {
    const cases = <int, String>{
      0: 'zeroth',
      1: 'first',
      2: 'second',
      3: 'third',
      4: 'fourth',
      5: 'fifth',
      8: 'eighth',
      9: 'ninth',
      12: 'twelfth',
      20: 'twentieth',
      21: 'twenty first',
      100: 'one hundredth',
      102: 'one hundred and second',
      1000: 'one thousandth',
      1100: 'one thousand one hundredth',
      1000000: 'one millionth',
    };

    for (final entry in cases.entries) {
      test('${entry.key}', () {
        expect(speller.ordinal(BigInt.from(entry.key)).join(' '), entry.value);
      });
    }
  });

  group('year', () {
    const cases = <int, String>{
      99: 'ninety nine',
      100: 'one hundred',
      101: 'one oh one',
      999: 'nine ninety nine',
      1000: 'one thousand',
      1001: 'one thousand and one',
      1100: 'eleven hundred',
      1905: 'nineteen oh five',
      2000: 'two thousand',
      2005: 'two thousand and five',
      2010: 'twenty ten',
      2024: 'twenty twenty four',
      2100: 'twenty one hundred',
      9999: 'ninety nine ninety nine',
      10000: 'ten thousand',
    };

    for (final entry in cases.entries) {
      test('${entry.key}', () {
        expect(speller.year(BigInt.from(entry.key)).join(' '), entry.value);
      });
    }
  });

  group('decimal', () {
    const cases = <String, String>{
      '0.0': 'zero',
      '0.01': 'zero point zero one',
      '0.0000001': 'zero point zero zero zero zero zero zero one',
      '0.29': 'zero point two nine',
      '0.58': 'zero point five eight',
      '1.2300': 'one point two three',
      '2.675': 'two point six seven five',
      '3.14': 'three point one four',
      '10.01': 'ten point zero one',
      '12.345': 'twelve point three four five',
      '100.01': 'one hundred point zero one',
    };

    for (final entry in cases.entries) {
      test(entry.key, () {
        expect(speller.decimal(entry.key).join(' '), entry.value);
      });
    }
  });
}
