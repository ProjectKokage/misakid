import 'package:misakid/misaki.dart';
import 'package:misakid/src/languages/en/resolve.dart';
import 'package:test/test.dart';

void main() {
  test('resolves final punctuation and junk tokens exactly', () {
    final resolved = resolveEnglishTokens(<MisakiToken>[
      _token("'", phonemes: null),
      _token('.', phonemes: null),
    ]);

    expect(resolved.map((token) => token.phonemes), <String>['', '.']);
    expect(
      resolved.map((token) => (token.metadata as EnglishTokenMetadata).rating),
      <int>[3, 3],
    );
  });

  test('marks later resolved tokens when a separator is required', () {
    final resolved = resolveEnglishTokens(<MisakiToken>[
      _token('abc', phonemes: 'ˈab', whitespace: ' '),
      _token('123', phonemes: 'wˈʌn'),
      _token('-', phonemes: ''),
    ]);

    expect(
      (resolved[0].metadata as EnglishTokenMetadata).precededBySpace,
      isFalse,
    );
    expect(
      (resolved[1].metadata as EnglishTokenMetadata).precededBySpace,
      isTrue,
    );
    expect(
      (resolved[2].metadata as EnglishTokenMetadata).precededBySpace,
      isTrue,
    );
  });

  test('uses Unicode letters and excludes junk from kind detection', () {
    final onlyLetters = resolveEnglishTokens(<MisakiToken>[
      _token('漢-𐐀', phonemes: 'ˈA'),
      _token('字', phonemes: 'ˈI'),
    ]);
    expect(
      (onlyLetters[1].metadata as EnglishTokenMetadata).precededBySpace,
      isFalse,
    );

    final mixed = resolveEnglishTokens(<MisakiToken>[
      _token('漢1', phonemes: 'ˈA'),
      _token('字', phonemes: 'ˈI'),
    ]);
    expect((mixed[1].metadata as EnglishTokenMetadata).precededBySpace, isTrue);

    final unicode151Letter = String.fromCharCode(0x2ebf0);
    final pythonMixed = resolveEnglishTokens(<MisakiToken>[
      _token('A$unicode151Letter', phonemes: 'ˈA'),
      _token('B', phonemes: 'ˈI'),
    ]);
    expect(
      (pythonMixed[1].metadata as EnglishTokenMetadata).precededBySpace,
      isTrue,
    );
  });

  test('demotes the second of two joined tokens after a one-scalar head', () {
    final resolved = resolveEnglishTokens(<MisakiToken>[
      _token('A', phonemes: 'ˈA'),
      _token('word', phonemes: 'wˈɜɹd'),
    ]);

    expect(resolved.map((token) => token.phonemes), <String>['ˈA', 'wˌɜɹd']);
  });

  test('demotes the sorted lower half when primary stress is a majority', () {
    final resolved = resolveEnglishTokens(<MisakiToken>[
      _token('aa', phonemes: 'ˈA'),
      _token('bb', phonemes: 'bˈI'),
      _token('cc', phonemes: 'kˈɑt'),
      _token('dd', phonemes: 'str'),
    ]);

    expect(resolved.map((token) => token.phonemes), <String>[
      'ˌA',
      'bˈI',
      'kˈɑt',
      'str',
    ]);
  });

  test('does not demote at or below the primary-stress threshold', () {
    final resolved = resolveEnglishTokens(<MisakiToken>[
      _token('aa', phonemes: 'ˈA'),
      _token('bb', phonemes: 'bI'),
      _token('cc', phonemes: 'kɑt'),
    ]);

    expect(resolved.map((token) => token.phonemes), <String>[
      'ˈA',
      'bI',
      'kɑt',
    ]);
  });

  test('returns an immutable list and validates English metadata', () {
    final resolved = resolveEnglishTokens(<MisakiToken>[
      _token('word', phonemes: 'wˈɜɹd'),
    ]);
    expect(() => resolved.add(_token('x')), throwsUnsupportedError);
    expect(
      () => resolveEnglishTokens(const <MisakiToken>[]),
      throwsA(isA<InvalidConfigurationException>()),
    );
    expect(
      () => resolveEnglishTokens(const <MisakiToken>[
        MisakiToken(text: 'x', tag: 'X', whitespace: '', phonemes: 'x'),
      ]),
      throwsA(isA<MalformedDataException>()),
    );
  });
}

MisakiToken _token(
  String text, {
  String whitespace = '',
  String? phonemes = 'x',
}) => MisakiToken(
  text: text,
  tag: 'X',
  whitespace: whitespace,
  phonemes: phonemes,
  metadata: const EnglishTokenMetadata(isHead: true),
);
