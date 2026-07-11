import 'package:misakid/misaki.dart';
import 'package:misakid/src/languages/ja/cutlet_normalizer.dart';
import 'package:test/test.dart';

void main() {
  group('normalizeJapaneseCutletText', () {
    test('preserves empty text', () {
      expect(normalizeJapaneseCutletText(''), '');
    });

    test('normalizes width and katakana phonetic extensions', () {
      expect(
        normalizeJapaneseCutletText('ＡＢＣ１２３ ｶﾀｶﾅ ㇰ'),
        'ABC ひゃくにじゅうさん カタカナ ク',
      );
      expect(normalizeJapaneseCutletText('￥ ＂ ﾊﾟ ｳﾞ'), '¥ " パ ヴ');
    });

    test('expands a wave-dash range only before a decimal digit', () {
      expect(normalizeJapaneseCutletText('1～3匹'), ' いちから さん匹');
      expect(normalizeJapaneseCutletText('～３匹'), 'から さん匹');
      expect(normalizeJapaneseCutletText('～猫'), '~猫');
      expect(normalizeJapaneseCutletText('〜猫'), '〜猫');
    });

    test('converts every separate ASCII digit run with a leading space', () {
      expect(normalizeJapaneseCutletText('第12回と3個'), '第 じゅうに回と さん個');
    });

    test('preserves the upstream long-number diagnostic as text', () {
      expect(
        normalizeJapaneseCutletText('1234567890'),
        ' Number length too long, choose less than 10 digits',
      );
    });

    test('distinguishes Python re decimal runs from str.isdigit', () {
      // U+1369 is a Python digit but not a decimal scalar. As an isolated
      // regex non-digit run, upstream still sends it to Convert and fails.
      expect(
        () => normalizeJapaneseCutletText('፩'),
        throwsA(isA<InvalidConfigurationException>()),
      );
      // A mixed non-decimal run does not satisfy str.isdigit and is retained.
      expect(normalizeJapaneseCutletText('A፩'), 'A፩');
    });
  });
}
