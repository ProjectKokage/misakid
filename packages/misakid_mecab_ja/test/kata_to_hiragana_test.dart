import 'package:misakid_mecab_ja/misakid_mecab_ja.dart';
import 'package:test/test.dart';

void main() {
  test('matches every entry in jaconv 0.4.0 K2H_TABLE', () {
    const katakana =
        'ァアィイゥウェエォオカガキギクグケゲコゴサザシジスズ'
        'セゼソゾタダチヂッツヅテデトドナニヌネノハバパヒビピ'
        'フブプヘベペホボポマミムメモャヤュユョヨラリルレロワ'
        'ヲンーヮヰヱヵヶヴヽヾ・「」。、';
    const hiragana =
        'ぁあぃいぅうぇえぉおかがきぎくぐけげこごさざしじすず'
        'せぜそぞただちぢっつづてでとどなにぬねのはばぱひびぴ'
        'ふぶぷへべぺほぼぽまみむめもゃやゅゆょよらりるれろわ'
        'をんーゎゐゑゕゖゔゝゞ・「」。、';
    final from = katakana.runes.toList(growable: false);
    final to = hiragana.runes.toList(growable: false);
    expect(from, hasLength(to.length));
    for (var index = 0; index < from.length; index++) {
      expect(
        cutletKataToHiragana(String.fromCharCode(from[index])),
        String.fromCharCode(to[index]),
        reason: 'jaconv table index $index',
      );
    }
    expect(cutletKataToHiragana(katakana), hiragana);
  });

  test('leaves scalars outside the exact table unchanged', () {
    const input = 'ヷヸヹヺㇰｶﾞA😀が';
    expect(cutletKataToHiragana(input), input);
  });

  test('handles empty and mixed strings by Unicode scalar', () {
    expect(cutletKataToHiragana(''), '');
    expect(cutletKataToHiragana('巴マミ・スーパー𠮷'), '巴まみ・すーぱー𠮷');
  });
}
