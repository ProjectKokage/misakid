import 'package:misakid/misaki_ja.dart';
import 'package:test/test.dart';

void main() {
  const converter = JapaneseNumberConverter();

  group('JapaneseNumberConverter.convert', () {
    test('defaults to the upstream hiragana representation', () {
      expect(
        converter.convert('123456789'),
        'いちおくにせんさんびゃくよんじゅうごまんろくせんななひゃくはちじゅうきゅう',
      );
    });

    test('selects kanji, hiragana, and romaji output', () {
      expect(
        converter.convert('123456789', format: JapaneseNumberFormat.kanji),
        '一億二千三百四十五万六千七百八十九',
      );
      expect(
        converter.convert('123456789', format: JapaneseNumberFormat.hiragana),
        'いちおくにせんさんびゃくよんじゅうごまんろくせんななひゃくはちじゅうきゅう',
      );
      expect(
        converter.convert('123456789', format: JapaneseNumberFormat.romaji),
        'ichi oku ni sen sanbyaku yon juu go man roku sen nana hyaku '
        'hachi juu kyuu',
      );
    });

    test('preserves irregular hundreds and thousands', () {
      final cases = <(String, String, String)>[
        ('300', 'さんびゃく', 'sanbyaku'),
        ('600', 'ろっぴゃく', 'roppyaku'),
        ('800', 'はっぴゃく', 'happyaku'),
        ('3000', 'さんぜん', 'sanzen'),
        ('8000', 'はっせん', 'hassen'),
        ('11000', 'いちまんいっせん', 'ichi man issen'),
      ];
      for (final (input, hiragana, romaji) in cases) {
        expect(converter.convert(input), hiragana, reason: input);
        expect(
          converter.convert(input, format: JapaneseNumberFormat.romaji),
          romaji,
          reason: input,
        );
      }
    });

    test('removes commas and strips leading zeros after checking length', () {
      expect(converter.convert('1,2,3'), 'ひゃくにじゅうさん');
      expect(converter.convert('000000001'), 'いち');
      expect(
        converter.convert('0000000001'),
        'Number length too long, choose less than 10 digits',
      );
      expect(
        converter.convert('1,000,000,000'),
        'Number length too long, choose less than 10 digits',
      );
    });

    test('supports exactly nine comma-free characters', () {
      expect(
        converter.convert('999999999'),
        'きゅうおくきゅうせんきゅうひゃくきゅうじゅうきゅうまん'
        'きゅうせんきゅうひゃくきゅうじゅうきゅう',
      );
    });

    test('preserves romaji whitespace from empty four-digit groups', () {
      expect(
        converter.convert('10000', format: JapaneseNumberFormat.romaji),
        'ichi man ',
      );
      expect(
        converter.convert('100000000', format: JapaneseNumberFormat.romaji),
        'ichi oku  ',
      );
      expect(
        converter.convert('100000001', format: JapaneseNumberFormat.romaji),
        'ichi oku  ichi',
      );
    });

    test('preserves decimal readings, gemination, and trailing spaces', () {
      expect(converter.convert('12.34'), 'じゅうにてんさんよん');
      expect(converter.convert('20.5'), 'にじゅってんご');
      expect(converter.convert('120.05'), 'ひゃくにじゅってんゼロご');
      expect(
        converter.convert('20.5', format: JapaneseNumberFormat.romaji),
        'ni jutten go ',
      );
      expect(
        converter.convert('12.34', format: JapaneseNumberFormat.kanji),
        '十二点三四',
      );
      expect(
        converter.convert('1.', format: JapaneseNumberFormat.romaji),
        'ichi ten ',
      );
    });

    test('turns upstream incidental failures into typed validation errors', () {
      for (final input in <String>['', ',', '１２', '.5', '1.2.3', '0.5']) {
        expect(
          () => converter.convert(input),
          throwsA(isA<InvalidConfigurationException>()),
          reason: input,
        );
      }
    });
  });

  group('JapaneseNumberConverter.kanjiToArabic', () {
    test('converts canonical kanji number groups', () {
      final cases = <(String, String)>[
        ('零', '0'),
        ('十一', '11'),
        ('百十', '110'),
        ('一千', '1000'),
        ('一万一', '10001'),
        ('一億一万一', '100010001'),
        ('一億二千三百四十五万六千七百八十九', '123456789'),
      ];
      for (final (input, output) in cases) {
        expect(converter.kanjiToArabic(input), output, reason: input);
      }
    });

    test('preserves fractional zeros in Arabic text', () {
      expect(converter.kanjiToArabic('十二点三四'), '12.34');
      expect(converter.kanjiToArabic('零点五'), '0.5');
      expect(converter.kanjiToArabic('二十点零五'), '20.05');
      expect(converter.kanjiToArabic('一点'), '1.');
    });

    test('preserves fractional unit and repeated-point quirks', () {
      expect(converter.kanjiToArabic('一点十'), '1.10');
      expect(converter.kanjiToArabic('一点三百'), '1.3100');
      expect(converter.kanjiToArabic('一点一千'), '1.11000');
      expect(converter.kanjiToArabic('一点五点六'), '1.5.6');
    });

    test('rejects unsupported kanji input with typed errors', () {
      for (final input in <String>['', '〇', '点五', '一点A']) {
        expect(
          () => converter.kanjiToArabic(input),
          throwsA(isA<InvalidConfigurationException>()),
          reason: input,
        );
      }
    });
  });
}
