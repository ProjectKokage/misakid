import 'package:misakid/src/languages/zh/normalization/chronology_rules.dart';
import 'package:test/test.dart';

void main() {
  group('ChineseChronologyRules clocks', () {
    test('renders zero, half, leading-zero, and second fields exactly', () {
      final cases = <String, String>{
        '0:00': '零点',
        '00:00': '零点',
        '8:05': '八点零五分',
        '08:30': '八点半',
        '12:05:06': '十二点零五分零六秒',
        '23:59:59': '二十三点五十九分五十九秒',
        '24:00': '2四点',
      };

      for (final entry in cases.entries) {
        expect(
          ChineseChronologyRules.replaceTimes(entry.key),
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('preserves the pinned second-minute range bug', () {
      expect(
        ChineseChronologyRules.replaceTimeRanges('08:30-12:20'),
        '八点半至十二点半',
      );
      expect(
        ChineseChronologyRules.replaceTimeRanges('08:20-12:30'),
        '八点二十分至十二点三十分',
      );
      expect(
        ChineseChronologyRules.replaceTimeRanges('08:00~09:05:06'),
        '八点至九点零五分零六秒',
      );
    });
  });

  group('ChineseChronologyRules dates', () {
    test('renders Chinese-delimited dates and retains unmatched suffixes', () {
      final cases = <String, String>{
        '86年8月18日': '八六年八月十八日',
        '1995年3月1日': '一九九五年三月一日',
        '2024年': '二零二四年',
        '2024年00月': '二零二四年00月',
        '2024年02月30号': '二零二四年二月三十号',
      };

      for (final entry in cases.entries) {
        expect(
          ChineseChronologyRules.replaceDates(entry.key),
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('requires a repeated separator and two-digit month/day', () {
      final cases = <String, String>{
        '2024-01-02': '二零二四年一月二日',
        '2024/12/31': '二零二四年十二月三十一日',
        '2024 03 09': '二零二四年三月九日',
        '2024.03.09': '二零二四年三月九日',
        '2024-1-02': '2024-1-02',
        '2024-02/03': '2024-02/03',
      };

      for (final entry in cases.entries) {
        expect(
          ChineseChronologyRules.replaceSeparatedDates(entry.key),
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('matches Unicode year digits before the ASCII word-table failure', () {
      expect(
        () => ChineseChronologyRules.replaceDates('２０２４年'),
        throwsFormatException,
      );
    });
  });
}
