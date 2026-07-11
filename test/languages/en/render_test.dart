import 'package:misakid/misaki.dart';
import 'package:misakid/src/languages/en/render.dart';
import 'package:test/test.dart';

void main() {
  final tokens = <MisakiToken>[
    const MisakiToken(
      text: 'water',
      tag: 'NN',
      whitespace: ' ',
      phonemes: 'wˈɔɾɚ',
      metadata: EnglishTokenMetadata(isHead: true, rating: 4),
    ),
    const MisakiToken(
      text: 'button',
      tag: 'NN',
      whitespace: '\n',
      phonemes: 'bˈʌʔn',
      metadata: EnglishTokenMetadata(isHead: true, rating: 4),
    ),
    const MisakiToken(
      text: 'unknown',
      tag: 'NN',
      whitespace: '',
      metadata: EnglishTokenMetadata(isHead: true),
    ),
  ];

  test('legacy rendering folds flap and glottal-stop symbols', () {
    final result = renderEnglishTokens(tokens);

    expect(result.phonemes, 'wˈɔTɚ bˈʌtn\n❓');
    expect(result.tokens![0].phonemes, 'wˈɔTɚ');
    expect(result.tokens![1].phonemes, 'bˈʌtn');
    expect(result.tokens![2].phonemes, isNull);
  });

  test('version 2.0 preserves the exact symbols', () {
    final result = renderEnglishTokens(
      tokens,
      version: EnglishPhonemeVersion.v2,
    );

    expect(result.phonemes, 'wˈɔɾɚ bˈʌʔn\n❓');
    expect(result.tokens![0], same(tokens[0]));
  });

  test('uses the selected unknown marker and preserves null tokens', () {
    final result = renderEnglishTokens(tokens, unknownMarker: '□');

    expect(result.phonemes.endsWith('□'), isTrue);
    expect(result.tokens![2].phonemes, isNull);
  });

  test('returns an available empty token list for empty input', () {
    final result = renderEnglishTokens(const <MisakiToken>[]);

    expect(result.phonemes, '');
    expect(result.tokens, isNotNull);
    expect(result.tokens, isEmpty);
  });
}
