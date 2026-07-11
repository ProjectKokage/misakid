import 'package:misakid/src/languages/ko/backends.dart';
import 'package:misakid/src/languages/ko/idioms.dart';
import 'package:misakid/src/languages/ko/jamo.dart';
import 'package:misakid/src/languages/ko/morphology.dart';
import 'package:misakid/src/languages/ko/rules.dart';
import 'package:test/test.dart';

void main() {
  test('applies generated idioms in pinned source order', () {
    expect(
      applyKoreanG2pkcIdioms('갇혀 의견란 문고리 꽃잎 3연대 119'),
      '가쳐 의견난 문꼬리 꼰닙 삼년대 일릴구',
    );
  });

  test('annotates particles, predicate endings, and bound nouns', () {
    expect(
      annotateKoreanMorphology('나의 갈 읽 곳', const <KoreanMorphologyToken>[
        KoreanMorphologyToken(surface: '나', tag: 'NP'),
        KoreanMorphologyToken(surface: '의', tag: 'JKG'),
        KoreanMorphologyToken(surface: '갈', tag: 'ETM'),
        KoreanMorphologyToken(surface: '읽', tag: 'VV'),
        KoreanMorphologyToken(surface: '곳', tag: 'NNG'),
      ]),
      '나의/J 갈/E 읽/P 곳/B',
    );
  });

  test('returns input unchanged when morphology surfaces do not align', () {
    expect(
      annotateKoreanMorphology('한국어', const <KoreanMorphologyToken>[
        KoreanMorphologyToken(surface: '한글', tag: 'NNG'),
      ]),
      '한국어',
    );
  });

  test('preserves ordered table, palatalization, and caret blocking rules', () {
    expect(
      applyKoreanG2pkcRules(decomposeKoreanHangul('국밥 같이 국^밥')),
      '국빱 가치 국밥',
    );
  });

  test('uses Python Unicode word boundaries rather than Dart ASCII words', () {
    expect(applyKoreanG2pkcRules('ᆺα'), 'ᆺα');
    expect(applyKoreanG2pkcRules('ᆺ!'), 'ᆮ!');
  });
}
