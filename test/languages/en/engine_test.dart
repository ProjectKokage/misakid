import 'package:misakid/misaki_en.dart';
import 'package:test/test.dart';

void main() {
  group('EnglishG2pEngine', () {
    test('returns a non-null empty token list when tokenization is empty', () {
      final tokenizer = _FakeTokenizer((_) => const <MisakiToken>[]);
      final pronunciation = _FakePronunciation((_, _) => null);
      final result = EnglishG2pEngine(
        tokenizer: tokenizer,
        pronunciation: pronunciation,
      ).convert('');

      expect(result.phonemes, '');
      expect(result.tokens, isNotNull);
      expect(result.tokens, isEmpty);
      expect(pronunciation.calls, isEmpty);
    });

    test('preprocesses and folds inline controls applied by the tokenizer', () {
      final tokenizer = _FakeTokenizer((input) {
        expect(input.text, 'hello world');
        expect(input.sourceWords, <String>['hello world']);
        expect(input.controls.keys, <int>[0]);
        final control = input.controls[0];
        expect(control, isA<EnglishPronunciationControl>());
        expect((control! as EnglishPronunciationControl).phonemes, 'həlo');
        return <MisakiToken>[
          _token('hello', phonemes: 'həlo', whitespace: ' '),
          _token('world', phonemes: '', isHead: false),
        ];
      });
      final pronunciation = _FakePronunciation((_, _) => null);

      final result = EnglishG2pEngine(
        tokenizer: tokenizer,
        pronunciation: pronunciation,
      ).convert('[hello world](/həlo/)');

      expect(result.phonemes, 'həlo');
      expect(result.tokens, hasLength(1));
      expect(result.tokens!.single.text, 'hello world');
      expect(result.tokens!.single.phonemes, 'həlo');
      expect(pronunciation.calls, isEmpty);
    });

    test('resolves standalone tokens right-to-left with exact context', () {
      final tokenizer = _FakeTokenizer(
        (_) => <MisakiToken>[
          _token('used', tag: 'VBD', whitespace: ' '),
          _token('to', tag: 'TO', whitespace: ' '),
          _token('eat', tag: 'VB'),
        ],
      );
      final pronunciation = _FakePronunciation((token, context) {
        return switch (token.text) {
          'eat' => const EnglishPronunciation(phonemes: 'it', rating: 4),
          'to' => const EnglishPronunciation(phonemes: 'tu', rating: 4),
          'used' => const EnglishPronunciation(phonemes: 'juzd', rating: 4),
          _ => null,
        };
      });

      final result = EnglishG2pEngine(
        tokenizer: tokenizer,
        pronunciation: pronunciation,
      ).convert('used to eat');

      expect(result.phonemes, 'juzd tu it');
      expect(pronunciation.calls.map((call) => call.token.text), <String>[
        'eat',
        'to',
        'used',
      ]);
      expect(
        pronunciation.calls.map(
          (call) => (call.context.futureVowel, call.context.futureTo),
        ),
        <(bool?, bool)>[(null, false), (true, false), (false, true)],
      );
    });

    test('searches a group by longest right suffix before its prefix', () {
      final tokenizer = _FakeTokenizer(
        (_) => <MisakiToken>[_token('foobarBaz', whitespace: ' ')],
      );
      final pronunciation = _FakePronunciation((token, _) {
        return switch (token.text) {
          'Baz' => const EnglishPronunciation(phonemes: 'baz', rating: 4),
          'foobar' => const EnglishPronunciation(phonemes: 'fu', rating: 3),
          _ => null,
        };
      });

      final result = EnglishG2pEngine(
        tokenizer: tokenizer,
        pronunciation: pronunciation,
      ).convert('foobarBaz ');

      expect(result.phonemes, 'fubaz ');
      expect(pronunciation.calls.map((call) => call.token.text), <String>[
        'foobarBaz',
        'Baz',
        'foobar',
      ]);
      expect(pronunciation.calls.last.context.futureVowel, isFalse);
      expect(result.tokens, hasLength(1));
      expect(result.tokens!.single.text, 'foobarBaz');
      expect(result.tokens!.single.phonemes, 'fubaz');
      expect(_metadata(result.tokens!.single).rating, 3);
    });

    test('falls back once on the whole unresolved group', () {
      final tokenizer = _FakeTokenizer(
        (_) => <MisakiToken>[_token('foo-bar', whitespace: ' ')],
      );
      final pronunciation = _FakePronunciation((_, _) => null);
      final fallback = _FakeFallback(
        (token) => const EnglishPronunciation(phonemes: 'FB', rating: 2),
      );

      final result = EnglishG2pEngine(
        tokenizer: tokenizer,
        pronunciation: pronunciation,
        fallback: fallback,
      ).convert('foo-bar ');

      expect(result.phonemes, 'FB ');
      expect(pronunciation.calls.map((call) => call.token.text), <String>[
        'foo-bar',
        '-bar',
        'bar',
      ]);
      expect(fallback.calls.map((token) => token.text), <String>['foo-bar']);
      expect(result.tokens!.single.phonemes, 'FB');
      expect(_metadata(result.tokens!.single).rating, 2);
    });

    test(
      'keeps a multi-subtoken lexicon match quality unset like upstream',
      () {
        final tokenizer = _FakeTokenizer(
          (_) => <MisakiToken>[_token('foo-bar', whitespace: ' ')],
        );
        final pronunciation = _FakePronunciation((token, _) {
          if (token.text == 'foo-bar') {
            return const EnglishPronunciation(phonemes: 'WHOLE', rating: 4);
          }
          return null;
        });

        final result = EnglishG2pEngine(
          tokenizer: tokenizer,
          pronunciation: pronunciation,
        ).convert('foo-bar ');

        expect(result.phonemes, 'WHOLE ');
        expect(result.tokens!.single.phonemes, 'WHOLE');
        expect(_metadata(result.tokens!.single).rating, isNull);
      },
    );

    test('collapses a null whole-group fallback to one unresolved token', () {
      final tokenizer = _FakeTokenizer(
        (_) => <MisakiToken>[_token('foo-bar', whitespace: ' ')],
      );

      final result = EnglishG2pEngine(
        tokenizer: tokenizer,
        pronunciation: _FakePronunciation((_, _) => null),
        fallback: _FakeFallback((_) => null),
        unknownMarker: '?',
      ).convert('foo-bar ');

      expect(result.phonemes, '? ');
      expect(result.tokens!.single.phonemes, '?');
      expect(_metadata(result.tokens!.single).rating, isNull);
    });

    test('preserves unresolved null and successful empty fallback results', () {
      final tokenizer = _FakeTokenizer(
        (_) => <MisakiToken>[
          _token('unknown', whitespace: ' '),
          _token('silent'),
        ],
      );
      final pronunciation = _FakePronunciation((_, _) => null);
      final fallback = _FakeFallback((token) {
        if (token.text == 'silent') {
          return const EnglishPronunciation(phonemes: '', rating: 1);
        }
        return null;
      });

      final result = EnglishG2pEngine(
        tokenizer: tokenizer,
        pronunciation: pronunciation,
        fallback: fallback,
      ).convert('unknown silent');

      expect(result.phonemes, '❓ ');
      expect(result.tokens, hasLength(2));
      expect(result.tokens![0].phonemes, isNull);
      expect(result.tokens![1].phonemes, '');
      expect(_metadata(result.tokens![1]).rating, 1);
    });

    test('uses the selected unknown marker for an unresolved group', () {
      final tokenizer = _FakeTokenizer(
        (_) => <MisakiToken>[_token('foo-bar', whitespace: ' ')],
      );

      final result = EnglishG2pEngine(
        tokenizer: tokenizer,
        pronunciation: _FakePronunciation((_, _) => null),
        unknownMarker: '?',
      ).convert('foo-bar ');

      expect(result.phonemes, '?? ');
      expect(result.tokens!.single.phonemes, '??');
    });

    test('preserves currency metadata through the lookup boundary', () {
      final tokenizer = _FakeTokenizer(
        (_) => <MisakiToken>[
          _token(r'$', tag: r'$'),
          _token('12', tag: 'CD'),
          _token('34', tag: 'CD', whitespace: ' '),
          _token('!', tag: '.'),
        ],
      );
      final pronunciation = _FakePronunciation((token, _) {
        if (token.text == '1234') {
          expect(_metadata(token).currency, r'$');
          return const EnglishPronunciation(phonemes: 'money', rating: 4);
        }
        return null;
      });

      final result = EnglishG2pEngine(
        tokenizer: tokenizer,
        pronunciation: pronunciation,
      ).convert(r'$1234 !');

      expect(result.phonemes, 'money !');
      expect(result.tokens!.map((token) => token.text), <String>[
        r'$',
        '1234',
        '!',
      ]);
      expect(pronunciation.calls, hasLength(1));
    });

    test('applies legacy and version 2 rendering after resolution', () {
      EnglishG2pEngine engine(EnglishPhonemeVersion version) =>
          EnglishG2pEngine(
            tokenizer: _FakeTokenizer((_) => <MisakiToken>[_token('x')]),
            pronunciation: _FakePronunciation(
              (_, _) => const EnglishPronunciation(phonemes: 'ɾʔ'),
            ),
            phonemeVersion: version,
          );

      expect(engine(EnglishPhonemeVersion.legacy).convert('x').phonemes, 'Tt');
      expect(engine(EnglishPhonemeVersion.v2).convert('x').phonemes, 'ɾʔ');
    });

    test('can pass literal input through without inline preprocessing', () {
      final tokenizer = _FakeTokenizer((input) {
        expect(input.text, '  [x](/p/)');
        expect(input.sourceWords, isEmpty);
        expect(input.controls, isEmpty);
        return <MisakiToken>[_token(input.text, phonemes: '')];
      });

      EnglishG2pEngine(
        tokenizer: tokenizer,
        pronunciation: _FakePronunciation((_, _) => null),
        preprocessInput: false,
      ).convert('  [x](/p/)');

      expect(tokenizer.inputs, hasLength(1));
    });

    test('rejects tokenizer records without English metadata', () {
      final engine = EnglishG2pEngine(
        tokenizer: _FakeTokenizer(
          (_) => const <MisakiToken>[
            MisakiToken(text: 'x', tag: 'NN', whitespace: ''),
          ],
        ),
        pronunciation: _FakePronunciation((_, _) => null),
      );

      expect(
        () => engine.convert('x'),
        throwsA(
          isA<BackendFailureException>()
              .having(
                (error) => error.message,
                'message',
                contains('fake-tokenizer 1.0'),
              )
              .having((error) => error.cause, 'cause', isNull),
        ),
      );
    });

    test('rejects malformed or source-deleting tokenizer records', () {
      EnglishG2pEngine engine(List<MisakiToken> tokens) => EnglishG2pEngine(
        tokenizer: _FakeTokenizer((_) => tokens),
        pronunciation: _FakePronunciation((_, _) => null),
      );

      for (final tokens in <List<MisakiToken>>[
        <MisakiToken>[_token('', tag: 'NN')],
        <MisakiToken>[_token('x', tag: '')],
        <MisakiToken>[_token('x', isHead: false)],
        <MisakiToken>[_token('x', stress: 0.25)],
        <MisakiToken>[_token('x', rating: 0)],
        <MisakiToken>[_token('y')],
      ]) {
        expect(
          () => engine(tokens).convert('x'),
          throwsA(isA<BackendFailureException>()),
        );
      }
    });

    test('rejects out-of-range pronunciation and fallback ratings', () {
      final pronunciationEngine = EnglishG2pEngine(
        tokenizer: _FakeTokenizer((_) => <MisakiToken>[_token('x')]),
        pronunciation: _FakePronunciation(
          (_, _) => const EnglishPronunciation(phonemes: 'x', rating: 6),
        ),
      );
      expect(
        () => pronunciationEngine.convert('x'),
        throwsA(
          isA<BackendFailureException>().having(
            (error) => error.message,
            'message',
            allOf(contains('fake-pronunciation 2.0'), contains('outside 1..5')),
          ),
        ),
      );

      final fallbackEngine = EnglishG2pEngine(
        tokenizer: _FakeTokenizer((_) => <MisakiToken>[_token('x')]),
        pronunciation: _FakePronunciation((_, _) => null),
        fallback: _FakeFallback(
          (_) => const EnglishPronunciation(phonemes: 'x', rating: 0),
        ),
      );
      expect(
        () => fallbackEngine.convert('x'),
        throwsA(
          isA<BackendFailureException>().having(
            (error) => error.message,
            'message',
            allOf(contains('fake-fallback 3.0'), contains('outside 1..5')),
          ),
        ),
      );
    });

    test('wraps tokenizer, pronunciation, and fallback exceptions', () {
      final tokenizerError = Exception('tokenizer exploded');
      final tokenizerEngine = EnglishG2pEngine(
        tokenizer: _FakeTokenizer((_) => throw tokenizerError),
        pronunciation: _FakePronunciation((_, _) => null),
      );
      expect(
        () => tokenizerEngine.convert('x'),
        throwsA(
          isA<BackendFailureException>()
              .having(
                (error) => error.message,
                'message',
                contains('fake-tokenizer 1.0'),
              )
              .having((error) => error.cause, 'cause', same(tokenizerError)),
        ),
      );

      final pronunciationError = Exception('pronunciation exploded');
      final pronunciationEngine = EnglishG2pEngine(
        tokenizer: _FakeTokenizer((_) => <MisakiToken>[_token('x')]),
        pronunciation: _FakePronunciation((_, _) => throw pronunciationError),
      );
      expect(
        () => pronunciationEngine.convert('x'),
        throwsA(
          isA<BackendFailureException>()
              .having(
                (error) => error.message,
                'message',
                contains('fake-pronunciation 2.0'),
              )
              .having(
                (error) => error.cause,
                'cause',
                same(pronunciationError),
              ),
        ),
      );

      final fallbackError = Exception('fallback exploded');
      final fallbackEngine = EnglishG2pEngine(
        tokenizer: _FakeTokenizer((_) => <MisakiToken>[_token('x')]),
        pronunciation: _FakePronunciation((_, _) => null),
        fallback: _FakeFallback((_) => throw fallbackError),
      );
      expect(
        () => fallbackEngine.convert('x'),
        throwsA(
          isA<BackendFailureException>()
              .having(
                (error) => error.message,
                'message',
                contains('fake-fallback 3.0'),
              )
              .having((error) => error.cause, 'cause', same(fallbackError)),
        ),
      );
    });
  });
}

typedef _Tokenize = List<MisakiToken> Function(EnglishPreprocessResult input);
typedef _Lookup =
    EnglishPronunciation? Function(
      MisakiToken token,
      EnglishTokenContext context,
    );
typedef _Pronounce = EnglishPronunciation? Function(MisakiToken token);

final class _FakeTokenizer implements EnglishTokenizerBackend {
  _FakeTokenizer(this._tokenize);

  final _Tokenize _tokenize;
  final List<EnglishPreprocessResult> inputs = <EnglishPreprocessResult>[];

  @override
  BackendInfo get info => BackendInfo(name: 'fake-tokenizer', version: '1.0');

  @override
  List<MisakiToken> tokenize(EnglishPreprocessResult input) {
    inputs.add(input);
    return _tokenize(input);
  }
}

final class _PronunciationCall {
  const _PronunciationCall(this.token, this.context);

  final MisakiToken token;
  final EnglishTokenContext context;
}

final class _FakePronunciation implements EnglishPronunciationBackend {
  _FakePronunciation(this._lookup);

  final _Lookup _lookup;
  final List<_PronunciationCall> calls = <_PronunciationCall>[];

  @override
  BackendInfo get info =>
      BackendInfo(name: 'fake-pronunciation', version: '2.0');

  @override
  EnglishPronunciation? lookup(MisakiToken token, EnglishTokenContext context) {
    calls.add(_PronunciationCall(token, context));
    return _lookup(token, context);
  }
}

final class _FakeFallback implements EnglishFallbackBackend {
  _FakeFallback(this._pronounce);

  final _Pronounce _pronounce;
  final List<MisakiToken> calls = <MisakiToken>[];

  @override
  BackendInfo get info => BackendInfo(name: 'fake-fallback', version: '3.0');

  @override
  EnglishPronunciation? pronounce(MisakiToken token) {
    calls.add(token);
    return _pronounce(token);
  }
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
}) => MisakiToken(
  text: text,
  tag: tag,
  whitespace: whitespace,
  phonemes: phonemes,
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
