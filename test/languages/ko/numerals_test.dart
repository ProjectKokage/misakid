import 'package:misakid/misaki_ko.dart';
import 'package:misakid/src/languages/ko/numerals.dart' as internal;
import 'package:test/test.dart';

void main() {
  group('CPython 3.12 seed-zero compatibility', () {
    test('matches fixed ASCII, UCS-2, and UCS-4 string hash vectors', () {
      expect(
        internal.koreanNumeralPython312Seed0StringHash('measure'),
        BigInt.parse('-8980130084555996632'),
      );
      expect(
        internal.koreanNumeralPython312Seed0StringHash('개'),
        BigInt.parse('-2950668263717473879'),
      );
      expect(
        internal.koreanNumeralPython312Seed0StringHash('𝟙'),
        BigInt.parse('1021053864345214522'),
      );
      expect(
        internal.koreanNumeralPython312Seed0StringHash('１２３'),
        BigInt.parse('7237364759803222486'),
      );
      expect(internal.koreanNumeralPython312Seed0StringHash(''), BigInt.zero);
    });

    test('matches fixed numeral and Korean-bound-noun tuple hashes', () {
      expect(
        internal.koreanNumeralPython312Seed0TupleHash(('1', '')),
        BigInt.parse('1659685661504581852'),
      );
      expect(
        internal.koreanNumeralPython312Seed0TupleHash(('1', '개')),
        BigInt.parse('-6417099183924321603'),
      );
      expect(
        internal.koreanNumeralPython312Seed0TupleHash(('1', ' 개')),
        BigInt.parse('-4051891192338571189'),
      );
      expect(
        internal.koreanNumeralPython312Seed0TupleHash(('21', '시간')),
        BigInt.parse('-431371819027856709'),
      );
    });

    test('matches the first set-table resize threshold at five entries', () {
      final values = <(String, String)>[
        ('1', ''),
        ('10', ''),
        ('100', ''),
        ('1000', ''),
        ('1', '개'),
      ];
      expect(
        internal.koreanNumeralPython312Seed0SetOrder(values.take(4)),
        <(String, String)>[('10', ''), ('1', ''), ('100', ''), ('1000', '')],
      );
      expect(
        internal.koreanNumeralPython312Seed0SetOrder(values),
        <(String, String)>[
          ('10', ''),
          ('1000', ''),
          ('100', ''),
          ('1', ''),
          ('1', '개'),
        ],
      );
    });
  });

  group('spellKoreanNumber', () {
    test('preserves Sino and native counter forms', () {
      expect(spellKoreanNumber('0'), '영');
      expect(spellKoreanNumber('20', sino: false), '스무');
      expect(spellKoreanNumber('21', sino: false), '스물한');
      expect(spellKoreanNumber('123,456'), '^십^이만^삼천^사백^오십^육');
    });

    test('preserves the Unicode-digit versus ASCII-table mismatch', () {
      expect(spellKoreanNumber('１２３'), '백십');
      expect(spellKoreanNumber('١٢٣'), '백십');
      expect(spellKoreanNumber('𝟙𝟚𝟛'), '백십');
      expect(spellKoreanNumber('０'), '');
      expect(
        () => spellKoreanNumber('12a'),
        throwsA(isA<InvalidConfigurationException>()),
      );
      expect(
        () => spellKoreanNumber(''),
        throwsA(isA<InvalidConfigurationException>()),
      );
    });

    test(
      'turns the pinned undefined seventeenth position into a typed error',
      () {
        expect(
          () => spellKoreanNumber('10,000,000,000,000,000'),
          throwsA(
            isA<InvalidConfigurationException>().having(
              (error) => error.message,
              'message',
              contains('positions above 15'),
            ),
          ),
        );
      },
    );
  });

  group('convertKoreanNumerals', () {
    test('replays seeded overlap behavior deterministically', () {
      expect(
        convertKoreanNumerals('0 7 10 16 106 123,456'),
        '영 ^칠 ^십 ^심뉵 ^심뉵 ^십^이만^삼천^사백^오심뉵',
      );
    });

    test('uses morphology markers for native bound nouns', () {
      expect(
        convertKoreanNumerals('1개/B 20살/B 21시/B 10분/B'),
        '한개/B 스무살/B 스물한시/B ^십분/B',
      );
    });

    test('replays CPython 3.12 seed-zero tuple-set iteration order', () {
      expect(convertKoreanNumerals('1개/B 1'), '^일개/B ^일');
      expect(convertKoreanNumerals('3개/B 30개/B 3 30'), '^삼개/B ^삼^영개/B ^삼 ^삼^영');
      expect(convertKoreanNumerals('3 개/B 3개/B 3'), '세개/B ^삼개/B ^삼');
      expect(convertKoreanNumerals('10 100 106 1006'), '^십 ^십^영 ^심뉵 ^십^영^육');
    });

    test('matches non-ASCII Unicode decimal behavior', () {
      expect(convertKoreanNumerals('１２３ ١٢٣ 𝟙𝟚𝟛 １０ ０'), '백십 백십 백십 １ ');
    });
  });
}
