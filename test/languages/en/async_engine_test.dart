import 'package:misakid/misaki_en.dart';
import 'package:test/test.dart';

void main() {
  group('AsyncEnglishG2pEngine', () {
    test(
      'awaits fallback before resolving left-hand lexical context',
      () async {
        final pronunciation = _FakePronunciation((token, context) {
          if (token.text == 'known') {
            expect(context.futureVowel, isTrue);
            return const EnglishPronunciation(phonemes: 'nOn', rating: 4);
          }
          return null;
        });
        final fallback = _FakeAsyncFallback((token) async {
          await Future<void>.delayed(Duration.zero);
          return token.text == 'oov'
              ? const EnglishPronunciation(phonemes: 'it', rating: 1)
              : null;
        });
        final engine = AsyncEnglishG2pEngine(
          tokenizer: _FakeTokenizer(
            (_) => <MisakiToken>[
              _token('known', whitespace: ' '),
              _token('oov'),
            ],
          ),
          pronunciation: pronunciation,
          fallback: fallback,
        );

        final result = await engine.convert('known oov');

        expect(result.phonemes, 'nOn it');
        expect(pronunciation.calls.map((call) => call.token.text), <String>[
          'oov',
          'known',
        ]);
        expect(fallback.calls.map((token) => token.text), <String>['oov']);
        expect(_metadata(result.tokens![1]).rating, 1);
      },
    );

    test('falls back once on a whole unresolved subtoken group', () async {
      final fallback = _FakeAsyncFallback(
        (_) async => const EnglishPronunciation(phonemes: 'FB', rating: 2),
      );
      final result = await AsyncEnglishG2pEngine(
        tokenizer: _FakeTokenizer(
          (_) => <MisakiToken>[_token('foo-bar', whitespace: ' ')],
        ),
        pronunciation: _FakePronunciation((_, _) => null),
        fallback: fallback,
      ).convert('foo-bar ');

      expect(result.phonemes, 'FB ');
      expect(fallback.calls.map((token) => token.text), <String>['foo-bar']);
      expect(result.tokens!.single.phonemes, 'FB');
      expect(_metadata(result.tokens!.single).rating, 2);
    });

    test('matches synchronous fallback resolution and rendering', () async {
      final tokens = <MisakiToken>[
        _token('silent', whitespace: ' '),
        _token('unknown'),
      ];
      EnglishPronunciation? pronounce(MisakiToken token) =>
          token.text == 'silent'
          ? const EnglishPronunciation(phonemes: '', rating: 1)
          : null;
      final synchronous = EnglishG2pEngine(
        tokenizer: _FakeTokenizer((_) => tokens),
        pronunciation: _FakePronunciation((_, _) => null),
        fallback: _FakeFallback(pronounce),
        unknownMarker: '?',
      ).convert('silent unknown');
      final asynchronous = await AsyncEnglishG2pEngine(
        tokenizer: _FakeTokenizer((_) => tokens),
        pronunciation: _FakePronunciation((_, _) => null),
        fallback: _FakeAsyncFallback((token) async => pronounce(token)),
        unknownMarker: '?',
      ).convert('silent unknown');

      expect(asynchronous.phonemes, synchronous.phonemes);
      expect(
        asynchronous.tokens!.map((token) => token.phonemes),
        synchronous.tokens!.map((token) => token.phonemes),
      );
    });

    test('wraps asynchronous fallback failures with backend identity', () {
      final cause = Exception('model failed');
      final engine = AsyncEnglishG2pEngine(
        tokenizer: _FakeTokenizer((_) => <MisakiToken>[_token('oov')]),
        pronunciation: _FakePronunciation((_, _) => null),
        fallback: _FakeAsyncFallback((_) async => throw cause),
      );

      expect(
        engine.convert('oov'),
        throwsA(
          isA<BackendFailureException>()
              .having(
                (error) => error.message,
                'message',
                contains('fake-async-fallback 4.0'),
              )
              .having((error) => error.cause, 'cause', same(cause)),
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

final class _FakeTokenizer implements EnglishTokenizerBackend {
  _FakeTokenizer(this._tokenize);

  final _Tokenize _tokenize;

  @override
  BackendInfo get info => BackendInfo(name: 'fake-tokenizer', version: '1.0');

  @override
  List<MisakiToken> tokenize(EnglishPreprocessResult input) => _tokenize(input);
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

  final EnglishPronunciation? Function(MisakiToken token) _pronounce;

  @override
  BackendInfo get info => BackendInfo(name: 'fake-fallback', version: '3.0');

  @override
  EnglishPronunciation? pronounce(MisakiToken token) => _pronounce(token);
}

final class _FakeAsyncFallback implements AsyncEnglishFallbackBackend {
  _FakeAsyncFallback(this._pronounce);

  final Future<EnglishPronunciation?> Function(MisakiToken token) _pronounce;
  final List<MisakiToken> calls = <MisakiToken>[];

  @override
  BackendInfo get info =>
      BackendInfo(name: 'fake-async-fallback', version: '4.0');

  @override
  Future<EnglishPronunciation?> pronounce(MisakiToken token) {
    calls.add(token);
    return _pronounce(token);
  }
}

MisakiToken _token(String text, {String whitespace = ''}) => MisakiToken(
  text: text,
  tag: 'NN',
  whitespace: whitespace,
  metadata: const EnglishTokenMetadata(isHead: true),
);

EnglishTokenMetadata _metadata(MisakiToken token) =>
    token.metadata! as EnglishTokenMetadata;
