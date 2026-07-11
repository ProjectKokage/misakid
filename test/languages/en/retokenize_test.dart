import 'package:misakid/misaki.dart';
import 'package:misakid/src/languages/en/retokenize.dart';
import 'package:test/test.dart';

void main() {
  group('foldEnglishTokenHeads', () {
    test(
      'folds inline-control continuations with the selected unknown marker',
      () {
        final result = foldEnglishTokenHeads(<MisakiToken>[
          _token('hello', phonemes: 'hə', rating: 5),
          _token(
            'world',
            phonemes: 'lo',
            whitespace: ' ',
            isHead: false,
            rating: 5,
          ),
        ]);

        expect(result, hasLength(1));
        expect(result.single.text, 'helloworld');
        expect(result.single.whitespace, ' ');
        expect(result.single.phonemes, 'həlo');
        expect(_metadata(result.single).rating, 5);
        expect(() => result.add(_token('x')), throwsUnsupportedError);
      },
    );

    test('preserves an initial non-head token like upstream', () {
      final token = _token('orphan', isHead: false);

      expect(foldEnglishTokenHeads(<MisakiToken>[token]), <MisakiToken>[token]);
    });

    test('rejects non-English metadata', () {
      const token = MisakiToken(text: 'x', tag: 'NN', whitespace: '');

      expect(
        () => foldEnglishTokenHeads(<MisakiToken>[token]),
        throwsA(isA<MalformedDataException>()),
      );
    });
  });

  group('retokenizeEnglishTokens', () {
    test(
      'creates an immutable subtoken group with inherited source fields',
      () {
        final result = retokenizeEnglishTokens(<MisakiToken>[
          _token(
            'abc/def',
            whitespace: ' ',
            stress: 2,
            numberFlags: 'na',
            startTimeSeconds: 1,
            endTimeSeconds: 2,
          ),
        ]);

        expect(result, hasLength(1));
        final group = result.single as EnglishRetokenizedGroup;
        expect(group.tokens.map((token) => token.text), <String>[
          'abc',
          '/',
          'def',
        ]);
        expect(group.tokens.map((token) => token.whitespace), <String>[
          '',
          '',
          ' ',
        ]);
        expect(group.tokens.map((token) => _metadata(token).isHead), <bool>[
          true,
          false,
          false,
        ]);
        for (final token in group.tokens) {
          expect(token.startTimeSeconds, 1);
          expect(token.endTimeSeconds, 2);
          expect(_metadata(token).stress, 2);
          expect(_metadata(token).numberFlags, 'na');
        }
        expect(() => group.tokens.add(_token('x')), throwsUnsupportedError);
        expect(
          () => result.add(EnglishRetokenizedToken(_token('x'))),
          throwsUnsupportedError,
        );
      },
    );

    test('creates the pinned internal 2-to alias', () {
      final result = retokenizeEnglishTokens(<MisakiToken>[
        _token('B2B', whitespace: ' '),
      ]);

      expect(result, hasLength(3));
      final tokens = <MisakiToken>[
        for (final item in result) (item as EnglishRetokenizedToken).token,
      ];
      expect(tokens.map((token) => token.text), <String>['B', '2', 'B']);
      expect(_metadata(tokens[1]).alias, 'to');
      expect(tokens.last.whitespace, ' ');
    });

    test('uses Python 3.12 alphabetic semantics for the internal 2 alias', () {
      final unicode151Letter = String.fromCharCode(0x2ebf0);
      final result = retokenizeEnglishTokens(<MisakiToken>[
        _token('$unicode151Letter${2}$unicode151Letter', whitespace: ' '),
      ]);

      final group = result.single as EnglishRetokenizedGroup;
      expect(group.tokens.map((token) => token.text), <String>[
        unicode151Letter,
        '2',
        unicode151Letter,
      ]);
      expect(_metadata(group.tokens[1]).alias, isNull);
    });

    test('groups unresolved tokens across tokenizer boundaries', () {
      final result = retokenizeEnglishTokens(<MisakiToken>[
        _token('foo'),
        _token('bar', whitespace: ' '),
      ]);

      final group = result.single as EnglishRetokenizedGroup;
      expect(group.tokens.map((token) => token.text), <String>['foo', 'bar']);
      expect(_metadata(group.tokens.first).isHead, isTrue);
      expect(_metadata(group.tokens.last).isHead, isFalse);
    });

    test('tracks currency through adjacent CD tokens', () {
      final result = retokenizeEnglishTokens(<MisakiToken>[
        _token(r'$', tag: r'$'),
        _token('12', tag: 'CD'),
        _token('34', tag: 'CD', whitespace: ' '),
        _token('dogs', tag: 'NNS', whitespace: ' '),
      ]);

      expect(result, hasLength(3));
      final currency = (result[0] as EnglishRetokenizedToken).token;
      expect(currency.phonemes, '');
      expect(_metadata(currency).rating, 4);
      final number = result[1] as EnglishRetokenizedGroup;
      expect(number.tokens.map((token) => token.text), <String>['12', '34']);
      expect(_metadata(number.tokens.last).currency, r'$');
      expect(_metadata(number.tokens.last).isHead, isFalse);
    });

    test('maps dashes and punctuation tags before grouping', () {
      final result = retokenizeEnglishTokens(<MisakiToken>[
        _token('(', tag: '-LRB-'),
        _token('-', tag: ':'),
        _token('!', tag: '.'),
        _token('abc', tag: '.', whitespace: ' '),
        _token('é', tag: '.', whitespace: ' '),
      ]);
      final tokens = <MisakiToken>[
        for (final item in result) (item as EnglishRetokenizedToken).token,
      ];

      expect(tokens.map((token) => token.phonemes), <String?>[
        '(',
        '—',
        '!',
        null,
        '',
      ]);
      expect(tokens.map((token) => _metadata(token).rating), <int?>[
        4,
        3,
        4,
        null,
        4,
      ]);
    });

    test('does not subtokenize an explicitly pronounced token', () {
      final result = retokenizeEnglishTokens(<MisakiToken>[
        _token('hello-world', phonemes: 'CUSTOM', whitespace: ' ', rating: 5),
      ]);

      final token = (result.single as EnglishRetokenizedToken).token;
      expect(token.text, 'hello-world');
      expect(token.phonemes, 'CUSTOM');
    });

    test('reports a typed failure when a token produces no subtokens', () {
      expect(
        () => retokenizeEnglishTokens(<MisakiToken>[_token('')]),
        throwsA(isA<MalformedDataException>()),
      );
    });
  });
}

MisakiToken _token(
  String text, {
  String tag = 'NN',
  String whitespace = '',
  String? phonemes,
  bool isHead = true,
  String? alias,
  num? stress,
  String? currency,
  String numberFlags = '',
  bool precededBySpace = false,
  int? rating,
  double? startTimeSeconds,
  double? endTimeSeconds,
}) => MisakiToken(
  text: text,
  tag: tag,
  whitespace: whitespace,
  phonemes: phonemes,
  startTimeSeconds: startTimeSeconds,
  endTimeSeconds: endTimeSeconds,
  metadata: EnglishTokenMetadata(
    isHead: isHead,
    alias: alias,
    stress: stress,
    currency: currency,
    numberFlags: numberFlags,
    precededBySpace: precededBySpace,
    rating: rating,
  ),
);

EnglishTokenMetadata _metadata(MisakiToken token) =>
    token.metadata! as EnglishTokenMetadata;
