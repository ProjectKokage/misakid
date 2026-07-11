import 'package:misakid/misaki_zh.dart';
import 'package:test/test.dart';

void main() {
  group('ChineseTextNormalizer normalizeSentence', () {
    test('runs the converter before width and numeric stages', () {
      final converter = _FakeChineseCharacterConverter();
      final normalizer = ChineseTextNormalizer(converter: converter);

      final result = normalizer.normalizeSentence('傳統Ａ１２３');

      expect(result, '传统A幺二三');
      expect(converter.inputs, <String>['傳統Ａ１２３']);
    });

    test('matches representative pinned NSW outputs', () {
      final normalizer = ChineseTextNormalizer(
        converter: _FakeChineseCharacterConverter(),
      );
      final cases = <String, String>{
        '她出生于86年8月18日，她弟弟出生于1995年3月1日': '她出生于八六年八月十八日，她弟弟出生于一九九五年三月一日',
        '等会请在12:05请通知我': '等会请在十二点零五分请通知我',
        '今天的最低气温达到-10°C': '今天的最低气温达到零下十度',
        '现场有7/12的观众投出了赞成票': '现场有十二分之七的观众投出了赞成票',
        '明天有62%的概率降雨': '明天有百分之六十二的概率降雨',
        '这是固话0421-33441122': '这是固话零四二幺，三三四四幺幺二二',
        '这是手机+86 18544139121': '这是手机八六，幺八五四四幺三九幺二幺',
        '12~23 -1.5~2': '十二到二十三 负一点五到二',
        '编号27149': '编号二七幺四九',
        '3个 3+个 12小时': '三个 三多个 十二小时',
        '2024-01-02': '二零二四年一月二日',
        '400-123-4567': '四零零，幺二三，四五六七',
      };

      for (final entry in cases.entries) {
        expect(
          normalizer.normalizeSentence(entry.key),
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('preserves ordered rule and copied-table quirks', () {
      final normalizer = ChineseTextNormalizer(
        converter: _FakeChineseCharacterConverter(),
      );

      expect(normalizer.normalizeSentence('8:30-12:20'), '八点半至十二点半');
      expect(normalizer.normalizeSentence('-1.5 -.5'), '负一零点五 零点五');
      expect(normalizer.normalizeSentence('3摄氏度'), '三度');
      expect(
        normalizer.normalizeSentence('1mm 1m 1cm2 1mg'),
        '一米米 一米 一平方厘米 一米g',
      );
      expect(normalizer.normalizeSentence('3％ 1～2 A/B a-b'), '三％ 一至二 A每B ab');
    });

    test('converts fullwidth letters/digits but retains U+3000', () {
      final normalizer = ChineseTextNormalizer(
        converter: _FakeChineseCharacterConverter(),
      );

      expect(normalizer.normalizeSentence('ＡＢｃ１２３　'), 'ABc幺二三　');
      expect(normalizer.normalizeSentence('１ｍｍ'), '一米米');
    });

    test('applies circled-number, Greek, and special-character post rules', () {
      final normalizer = ChineseTextNormalizer(
        converter: _FakeChineseCharacterConverter(),
      );

      expect(
        normalizer.normalizeSentence('①②⑩ αβΓΔΣσςΩ 《a》#'),
        '一二十 阿尔法贝塔伽玛德尔塔西格玛西格玛西格玛欧米伽 a',
      );
    });
  });

  group('ChineseTextNormalizer normalize', () {
    test(
      'splits punctuation, removes copied special characters and spaces',
      () {
        final converter = _FakeChineseCharacterConverter();
        final normalizer = ChineseTextNormalizer(converter: converter);

        final result = normalizer.normalize(' 甲，乙！“丙？” 丁');

        expect(result, <String>['甲，', '乙！', '丙？', '丁']);
        expect(converter.inputs, <String>['甲，', '乙！', '丙？', '丁']);
        expect(() => result.add('戊'), throwsUnsupportedError);
      },
    );

    test('retains the upstream one-empty-sentence contract', () {
      final normalizer = ChineseTextNormalizer(
        converter: _FakeChineseCharacterConverter(),
      );

      expect(normalizer.normalize(''), <String>['']);
      expect(normalizer.normalize('   '), <String>['']);
      expect(normalizer.normalize('甲……乙'), <String>['甲乙']);
    });

    test('space removal changes mobile pause behavior before conversion', () {
      final normalizer = ChineseTextNormalizer(
        converter: _FakeChineseCharacterConverter(),
      );

      expect(normalizer.normalize('+86 18544139121'), <String>[
        '八六幺八五四四幺三九幺二幺',
      ]);
      expect(normalizer.normalize('ＡＢｃ１２３　'), <String>['ABc幺二三']);
    });
  });
}

final class _FakeChineseCharacterConverter
    implements ChineseCharacterConverter {
  final List<String> inputs = <String>[];

  @override
  String traditionalToSimplified(String text) {
    inputs.add(text);
    return text.replaceAll('傳統', '传统');
  }
}
