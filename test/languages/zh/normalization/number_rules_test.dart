import 'package:misakid/src/languages/zh/normalization/number_rules.dart';
import 'package:test/test.dart';

void main() {
  group('ChineseNumberRules cardinal and digit verbalization', () {
    test(
      'preserves zero elision, internal zeroes, and large-unit recursion',
      () {
        final cases = <String, String>{
          '': '',
          '000': '零',
          '01': '一',
          '10': '十',
          '101': '一百零一',
          '10001': '一万零一',
          '10010': '一万零一十',
          '123456789': '一亿二千三百四十五万六千七百八十九',
          '10000000000000000': '一亿亿',
        };

        for (final entry in cases.entries) {
          expect(
            ChineseNumberRules.verbalizeCardinal(entry.key),
            entry.value,
            reason: entry.key,
          );
        }
      },
    );

    test('preserves decimal trimming and alternate serial one', () {
      expect(ChineseNumberRules.numberToChinese('3.20'), '三点二');
      expect(ChineseNumberRules.numberToChinese('.22'), '零点二二');
      expect(ChineseNumberRules.numberToChinese('.00'), '');
      expect(ChineseNumberRules.numberToChinese('000.0200'), '零点零二');
      expect(
        ChineseNumberRules.verbalizeDigits('001', alternateOne: true),
        '零零幺',
      );
      expect(
        () => ChineseNumberRules.numberToChinese('1.2.3'),
        throwsFormatException,
      );
    });
  });

  group('ChineseNumberRules expression replacement', () {
    test('replaces fractions, percentages, and negative integers', () {
      expect(ChineseNumberRules.replaceFractions('--1/2 7/12'), '-负二分之一 十二分之七');
      expect(
        ChineseNumberRules.replacePercentages('--2% -3.20%'),
        '-负百分之二 负百分之三点二',
      );
      expect(
        ChineseNumberRules.replaceNegativeIntegers('-1.20 1-10'),
        '负一.20 1负十',
      );
    });

    test('preserves top-level alternation quirks for leading-dot decimals', () {
      expect(ChineseNumberRules.replaceNumbers('-.22'), '-零点二二');
      expect(ChineseNumberRules.replaceDecimals('-.22'), '-零点二二');
      expect(ChineseNumberRules.replaceRanges('-.5-.2'), '-零点五到零点二');
      expect(ChineseNumberRules.replaceRanges('.5~-.2'), '.5~-.2');
      expect(ChineseNumberRules.replaceRanges('1-2-3'), '一到二-3');
    });

    test('reads serials and ordered quantifiers exactly', () {
      expect(
        ChineseNumberRules.replaceDefaultNumbers('00078 123a4567'),
        '零零零七八 幺二三a四五六七',
      );
      expect(
        ChineseNumberRules.replacePositiveQuantifiers(
          '3个 3+个 12小时 5厘米 100万元 12美元',
        ),
        '三个 三多个 十二小时 五厘米 一百万元 十二美元',
      );
    });

    test('matches Unicode decimals before rejecting the ASCII-only table', () {
      expect(
        () => ChineseNumberRules.replaceDefaultNumbers('１２３'),
        throwsFormatException,
      );
    });
  });
}
