import 'package:misakid/src/languages/zh/normalization/quantifier_rules.dart';
import 'package:test/test.dart';

void main() {
  group('ChineseQuantifierRules temperatures', () {
    test('renders sign, decimal, and every copied unit spelling', () {
      final cases = <String, String>{
        '-3°C': '零下三度',
        '3℃': '三度',
        '3度': '三度',
        '3摄氏度': '三度',
        '3.20摄氏度': '三点二度',
        '-0度': '零下零度',
      };

      for (final entry in cases.entries) {
        expect(
          ChineseQuantifierRules.replaceTemperatures(entry.key),
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('matches Unicode digits before rejecting the ASCII word table', () {
      expect(
        () => ChineseQuantifierRules.replaceTemperatures('١度'),
        throwsFormatException,
      );
    });
  });

  group('ChineseQuantifierRules measures', () {
    test('maps every unambiguous notation', () {
      expect(
        ChineseQuantifierRules.replaceMeasures(
          '1cm2 2cm² 3cm3 4cm³ 5cm 1db 1ds 1kg 1km '
          '1m2 1m² 1m3 1m³ 1ml 1h 1s',
        ),
        '1平方厘米 2平方厘米 3立方厘米 4立方厘米 5厘米 '
        '1分贝 1毫秒 1千克 1千米 1平方米 1平方米 1立方米 '
        '1立方米 1毫升 1小时 1秒',
      );
    });

    test('preserves insertion-order substring collisions', () {
      expect(
        ChineseQuantifierRules.replaceMeasures('1mm 1mg mml cmml'),
        '1米米 1米g 米毫升 厘米毫升',
      );
    });
  });
}
