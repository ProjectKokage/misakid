import 'package:misakid/src/languages/zh/normalization/phone_rules.dart';
import 'package:test/test.dart';

void main() {
  group('ChinesePhoneRules phoneToChinese', () {
    test('preserves mobile plus stripping, spacing, and alternate one', () {
      final cases = <String, String>{
        '+86 18544139121': '八六，幺八五四四幺三九幺二幺',
        '18544139121': '幺八五四四幺三九幺二幺',
        '+8618544139121': '八六幺八五四四幺三九幺二幺',
        '++86\u30001++': '八六，幺',
      };

      for (final entry in cases.entries) {
        expect(
          ChinesePhoneRules.phoneToChinese(entry.key),
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('preserves hyphen-delimited landline pauses', () {
      expect(
        ChinesePhoneRules.phoneToChinese('0421-33441122', mobile: false),
        '零四二幺，三三四四幺幺二二',
      );
      expect(
        ChinesePhoneRules.phoneToChinese('400-123-4567', mobile: false),
        '四零零，幺二三，四五六七',
      );
    });
  });

  group('ChinesePhoneRules expression replacement', () {
    test('matches exact mobile prefixes and Unicode digit boundaries', () {
      expect(
        ChinesePhoneRules.replaceMobilePhones('+86 18544139121'),
        '八六，幺八五四四幺三九幺二幺',
      );
      expect(
        ChinesePhoneRules.replaceMobilePhones('x18544139121y'),
        'x幺八五四四幺三九幺二幺y',
      );
      expect(
        ChinesePhoneRules.replaceMobilePhones('218544139121'),
        '218544139121',
      );
      expect(
        ChinesePhoneRules.replaceMobilePhones('+86 15412345678'),
        '+86 15412345678',
      );
    });

    test('matches exact supported landline shapes', () {
      final cases = <String, String>{
        '0421-33441122': '零四二幺，三三四四幺幺二二',
        '010-12345678': '零幺零，幺二三四五六七八',
        '02112345678': '零二幺幺二三四五六七八',
        '1234567': '幺二三四五六七',
        '01234567': '01234567',
        '1123456789': '1123456789',
      };

      for (final entry in cases.entries) {
        expect(
          ChinesePhoneRules.replaceTelephones(entry.key),
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('keeps national-number lack of boundaries', () {
      expect(
        ChinesePhoneRules.replaceNationalUniformNumbers('400-123-4567'),
        '四零零，幺二三，四五六七',
      );
      expect(
        ChinesePhoneRules.replaceNationalUniformNumbers('1400-123-4567'),
        '1四零零，幺二三，四五六七',
      );
    });
  });
}
