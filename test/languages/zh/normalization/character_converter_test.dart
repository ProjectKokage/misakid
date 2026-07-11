import 'package:misakid/misaki_zh.dart';
import 'package:test/test.dart';

void main() {
  const converter = PinnedChineseCharacterConverter();

  test('converts the pinned traditional example exactly', () {
    const source = '一般是指存取一個應用程式啟動時始終顯示在網站或網頁瀏覽器中的一個或多個初始網頁等畫面存在的站點';
    expect(
      converter.traditionalToSimplified(source),
      '一般是指存取一个应用程式启动时始终显示在网站或网页浏览器中的一个或多个初始网页等画面存在的站点',
    );
  });

  test('preserves unmapped scalars and supplementary characters', () {
    expect(converter.traditionalToSimplified('ABC🙂カナ'), 'ABC🙂カナ');
  });

  test('supports upstream simplified-to-traditional last-value mapping', () {
    expect(converter.simplifiedToTraditional('网页浏览器'), '網頁瀏覽器');
  });

  test('drives the public normalizer without an external converter', () {
    const normalizer = ChineseTextNormalizer(converter: converter);
    // Pinned normalization converts fullwidth digits but leaves fullwidth
    // punctuation unchanged, so the percentage rule intentionally misses.
    expect(normalizer.normalizeSentence('網站１２％'), '网站十二％');
  });
}
