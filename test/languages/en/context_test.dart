import 'package:misakid/misaki.dart';
import 'package:misakid/src/languages/en/context.dart';
import 'package:test/test.dart';

void main() {
  const initial = EnglishTokenContext();

  test('classifies the first significant phoneme scalar', () {
    expect(
      updateEnglishTokenContext(initial, 'ˈɑ', _token('word')).futureVowel,
      isTrue,
    );
    expect(
      updateEnglishTokenContext(initial, 'ˌstr', _token('word')).futureVowel,
      isFalse,
    );
    expect(
      updateEnglishTokenContext(initial, '.ɑ', _token('word')).futureVowel,
      isNull,
    );
  });

  test('ignores quote punctuation while scanning', () {
    expect(
      updateEnglishTokenContext(initial, '“ˈA', _token('word')).futureVowel,
      isTrue,
    );
    expect(
      updateEnglishTokenContext(initial, '”b', _token('word')).futureVowel,
      isFalse,
    );
  });

  test('carries future-vowel context for null or insignificant output', () {
    const context = EnglishTokenContext(futureVowel: true);
    expect(
      updateEnglishTokenContext(context, null, _token('word')).futureVowel,
      isTrue,
    );
    expect(
      updateEnglishTokenContext(context, '', _token('word')).futureVowel,
      isTrue,
    );
    expect(
      updateEnglishTokenContext(context, 'ˈˌ', _token('word')).futureVowel,
      isTrue,
    );
  });

  test('matches exact case and tag rules for future-to', () {
    expect(
      updateEnglishTokenContext(initial, null, _token('to')).futureTo,
      isTrue,
    );
    expect(
      updateEnglishTokenContext(initial, null, _token('To')).futureTo,
      isTrue,
    );
    expect(
      updateEnglishTokenContext(
        initial,
        null,
        _token('TO', tag: 'TO'),
      ).futureTo,
      isTrue,
    );
    expect(
      updateEnglishTokenContext(
        initial,
        null,
        _token('TO', tag: 'IN'),
      ).futureTo,
      isTrue,
    );
    expect(
      updateEnglishTokenContext(
        initial,
        null,
        _token('TO', tag: 'NNP'),
      ).futureTo,
      isFalse,
    );
    expect(
      updateEnglishTokenContext(initial, null, _token('tO')).futureTo,
      isFalse,
    );
  });
}

MisakiToken _token(String text, {String tag = 'X'}) =>
    MisakiToken(text: text, tag: tag, whitespace: '');
