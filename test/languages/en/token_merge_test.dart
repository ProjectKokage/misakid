import 'package:misakid/misaki.dart';
import 'package:misakid/src/languages/en/token_merge.dart';
import 'package:test/test.dart';

void main() {
  test('merges exact text, whitespace, timestamps, and dominant tag', () {
    final result = mergeEnglishTokens(<MisakiToken>[
      _token(
        text: 'i',
        tag: 'LOWER',
        whitespace: '-',
        phonemes: 'I',
        start: 1.25,
        rating: 5,
      ),
      _token(
        text: 'PHONE',
        tag: 'UPPER',
        whitespace: '  ',
        phonemes: 'fOn',
        end: 2.5,
        rating: 3,
      ),
    ], unknownMarker: '❓');

    expect(result.text, 'i-PHONE');
    expect(result.tag, 'UPPER');
    expect(result.whitespace, '  ');
    expect(result.phonemes, 'IfOn');
    expect(result.startTimeSeconds, 1.25);
    expect(result.endTimeSeconds, 2.5);
    final metadata = result.metadata as EnglishTokenMetadata;
    expect(metadata.rating, 3);
  });

  test('uses CPython 3.12 lowercase semantics for dominant tags', () {
    final result = mergeEnglishTokens(<MisakiToken>[
      _token(text: 'a', tag: 'DT'),
      _token(text: 'Ꭰ', tag: 'NNP'),
    ]);

    // CPython lowercases Cherokee uppercase U+13A0 to U+AB70, so the second
    // token receives uppercase weight 2 and wins. Dart's host lowercasing
    // leaves U+13A0 unchanged on affected SDKs and incorrectly ties at DT.
    expect(result.tag, 'NNP');
  });

  test('uses null phonemes when no unknown marker is selected', () {
    final result = mergeEnglishTokens(<MisakiToken>[
      _token(text: 'known', phonemes: 'nOn'),
      _token(text: 'unknown', phonemes: null),
    ]);

    expect(result.phonemes, isNull);
  });

  test('renders unknowns and inserts only upstream prespaces', () {
    final result = mergeEnglishTokens(<MisakiToken>[
      _token(text: 'a', phonemes: 'a'),
      _token(text: 'b', phonemes: 'b', precededBySpace: true),
      _token(text: 'c', phonemes: null, precededBySpace: true),
      _token(text: 'd', phonemes: '', precededBySpace: true),
      _token(text: 'e', phonemes: 'e', precededBySpace: true),
    ], unknownMarker: '❓');

    expect(result.phonemes, 'a b❓ e');
  });

  test('does not insert a prespace after Python Unicode whitespace', () {
    final result = mergeEnglishTokens(<MisakiToken>[
      _token(text: 'a', phonemes: 'a\u3000'),
      _token(text: 'b', phonemes: 'b', precededBySpace: true),
    ], unknownMarker: '❓');

    expect(result.phonemes, 'a\u3000b');
  });

  test('combines metadata with upstream set rules', () {
    final result = mergeEnglishTokens(<MisakiToken>[
      _token(
        text: '1',
        isHead: false,
        stress: 0.5,
        currency: r'$',
        numberFlags: 'na',
        precededBySpace: true,
        rating: 4,
      ),
      _token(
        text: '2',
        stress: 0.5,
        currency: '€',
        numberFlags: '&a',
        rating: 2,
      ),
    ], unknownMarker: '❓');

    final metadata = result.metadata as EnglishTokenMetadata;
    expect(metadata.isHead, isFalse);
    expect(metadata.stress, 0.5);
    expect(metadata.currency, '€');
    expect(metadata.numberFlags, r'&an');
    expect(metadata.precededBySpace, isTrue);
    expect(metadata.rating, 2);
    expect(metadata.alias, isNull);
  });

  test('drops ambiguous stress and any rating set containing null', () {
    final result = mergeEnglishTokens(<MisakiToken>[
      _token(text: 'a', stress: -0.5, rating: 4),
      _token(text: 'b', stress: 1, rating: null),
    ], unknownMarker: '❓');

    final metadata = result.metadata as EnglishTokenMetadata;
    expect(metadata.stress, isNull);
    expect(metadata.rating, isNull);
  });

  test('rejects empty input and non-English metadata', () {
    expect(
      () => mergeEnglishTokens(const <MisakiToken>[]),
      throwsA(isA<InvalidConfigurationException>()),
    );
    expect(
      () => mergeEnglishTokens(const <MisakiToken>[
        MisakiToken(text: 'x', tag: 'X', whitespace: ''),
      ]),
      throwsA(isA<MalformedDataException>()),
    );
  });
}

MisakiToken _token({
  required String text,
  String tag = 'X',
  String whitespace = '',
  String? phonemes,
  double? start,
  double? end,
  bool isHead = true,
  num? stress,
  String? currency,
  String numberFlags = '',
  bool precededBySpace = false,
  int? rating,
}) => MisakiToken(
  text: text,
  tag: tag,
  whitespace: whitespace,
  phonemes: phonemes,
  startTimeSeconds: start,
  endTimeSeconds: end,
  metadata: EnglishTokenMetadata(
    isHead: isHead,
    stress: stress,
    currency: currency,
    numberFlags: numberFlags,
    precededBySpace: precededBySpace,
    rating: rating,
  ),
);
