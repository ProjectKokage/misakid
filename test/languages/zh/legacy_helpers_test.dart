import 'package:misakid/src/core/errors.dart';
import 'package:misakid/src/languages/zh/legacy_helpers.dart';
import 'package:test/test.dart';

void main() {
  group('retoneLegacyChinese', () {
    test('maps contours in the pinned replacement order', () {
      expect(retoneLegacyChinese('a˧˩˧ b˧˥ c˥˩ d˥'), 'a↓ b↗ c↘ d→');
    });

    test('folds the two supported syllabic-r variants to ɨ', () {
      expect(retoneLegacyChinese('ɻ̩ɹ̩'), 'ɨɨ');
    });

    test('reports an unhandled syllabic mark as malformed data', () {
      expect(
        () => retoneLegacyChinese('m̩'),
        throwsA(isA<MalformedDataException>()),
      );
    });
  });

  group('mapLegacyChinesePunctuation', () {
    test('maps full-width stops and preserves inserted spacing', () {
      expect(mapLegacyChinesePunctuation('你好，世界。真的？'), '你好, 世界. 真的?');
    });

    test('maps paired quotes and brackets', () {
      expect(mapLegacyChinesePunctuation('《你好》【世界】（测试）'), '“你好”  “世界”  (测试)');
    });

    test(
      'uses CPython whitespace trimming including information separators',
      () {
        expect(mapLegacyChinesePunctuation('\u001c　你好　\u001f'), '你好');
      },
    );

    test('does not collapse existing or inserted interior whitespace', () {
      expect(mapLegacyChinesePunctuation('甲，  乙'), '甲,   乙');
    });
  });
}
