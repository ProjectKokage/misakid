import 'package:misakid/misaki.dart';
import 'package:test/test.dart';

void main() {
  group('KokoroEnglishG2pFrontend', () {
    test(
      'reconstructs exact chunks from tokens and ignores aggregate output',
      () {
        final chunks = KokoroEnglishG2pFrontend.chunkResult(
          G2pResult(
            phonemes: 'this aggregate is intentionally ignored',
            tokens: <MisakiToken>[
              _englishToken('Alpha', phonemes: 'A', whitespace: '\t'),
              _englishToken('unknown', whitespace: '  '),
              _englishToken('Beta', phonemes: 'B'),
            ],
          ),
        );

        expect(chunks, hasLength(1));
        expect(chunks.single.graphemes, 'Alpha\tunknown  Beta');
        expect(chunks.single.phonemes, 'A  B');
        expect(chunks.single.textIndex, isNull);
        expect(chunks.single.tokens, hasLength(3));
        expect(chunks.single.tokens![1].phonemes, '');
        expect(() => chunks.clear(), throwsUnsupportedError);
        expect(
          () => chunks.single.tokens!.add(_englishToken('extra')),
          throwsUnsupportedError,
        );
      },
    );

    test('uses Kokoro punctuation waterfall and includes one closing bump', () {
      final chunks = KokoroEnglishG2pFrontend.chunkResult(
        G2pResult(
          phonemes: '',
          tokens: <MisakiToken>[
            _englishToken('lead', phonemes: _repeat('a', 300)),
            _englishToken('.', phonemes: '.', whitespace: ' '),
            _englishToken(')', phonemes: ')', whitespace: ' '),
            _englishToken('tail', phonemes: _repeat('b', 205)),
            _englishToken('end', phonemes: _repeat('c', 10)),
          ],
        ),
      );

      expect(chunks, hasLength(2));
      expect(chunks.first.tokens!.map((token) => token.text), <String>[
        'lead',
        '.',
        ')',
      ]);
      expect(chunks.first.phonemes, '${_repeat('a', 300)}. )');
      expect(chunks.last.phonemes, '${_repeat('b', 205)}${_repeat('c', 10)}');
    });

    test('counts and truncates Python code points instead of UTF-16 units', () {
      final source = _repeat('😀', 511);
      final chunks = KokoroEnglishG2pFrontend.chunkResult(
        G2pResult(
          phonemes: '',
          tokens: <MisakiToken>[_englishToken('emoji', phonemes: source)],
        ),
      );

      expect(chunks, hasLength(1));
      expect(chunks.single.phonemes.runes, hasLength(510));
      expect(chunks.single.phonemes.length, 1020);
      expect(chunks.single.tokens!.single.phonemes!.runes, hasLength(511));
    });

    test('reproduces default line-feed segmentation before English G2P', () {
      final engine = _RecordingEngine((text) {
        return G2pResult(
          phonemes: 'ignored',
          tokens: <MisakiToken>[_englishToken(text, phonemes: 'p')],
        );
      });
      final frontend = KokoroEnglishG2pFrontend(engine: engine);

      final chunks = frontend.convert(' \n  one \n\n two  \n ');

      expect(engine.inputs, <String>['one ', ' two']);
      expect(chunks.map((chunk) => chunk.graphemes), <String>['one', 'two']);
      expect(chunks.map((chunk) => chunk.phonemes), <String>['p', 'p']);
      expect(chunks.map((chunk) => chunk.textIndex), <int>[0, 1]);
    });

    test('requires exact token details but accepts upstream token fields', () {
      expect(
        () => KokoroEnglishG2pFrontend.chunkResult(
          G2pResult(phonemes: 'x', tokens: null),
        ),
        throwsA(isA<BackendFailureException>()),
      );

      final chunks = KokoroEnglishG2pFrontend.chunkResult(
        G2pResult(
          phonemes: 'ignored',
          tokens: const <MisakiToken>[
            MisakiToken(text: '', tag: '', whitespace: '', phonemes: 'x'),
          ],
        ),
      );
      expect(chunks.single.graphemes, isEmpty);
      expect(chunks.single.phonemes, 'x');
    });

    test('rejects an engine whose real unknown marker is non-empty', () {
      final engine = _RecordingEngine(
        (_) => G2pResult(phonemes: '', tokens: const <MisakiToken>[]),
        unknownMarker: '❓',
      );

      expect(
        () => KokoroEnglishG2pFrontend(engine: engine),
        throwsA(isA<InvalidConfigurationException>()),
      );
    });
  });

  group('KokoroNonEnglishG2pFrontend', () {
    test('packs sentence units to a 400-code-point pre-G2P target', () {
      final first = '${_repeat('😀', 199)}.';
      final second = '${_repeat('😀', 199)}!';
      final engine = _RecordingEngine(
        (text) => G2pResult(
          phonemes: text,
          tokens: <MisakiToken>[_englishToken('discarded', phonemes: 'x')],
        ),
      );
      final frontend = KokoroNonEnglishG2pFrontend(engine: engine);

      final chunks = frontend.convert('$first${second}b');

      expect(engine.inputs, <String>['$first$second', 'b']);
      expect(chunks, hasLength(2));
      expect(chunks.first.graphemes.runes, hasLength(400));
      expect(chunks.first.tokens, isNull);
      expect(chunks.first.textIndex, 0);
      expect(chunks.last.graphemes, 'b');
    });

    test('preserves Kokoro overlong single-sentence behavior', () {
      final sentence = _repeat('a', 401);
      final engine = _RecordingEngine(
        (text) => G2pResult(phonemes: 'p', tokens: null),
      );

      final chunks = KokoroNonEnglishG2pFrontend(
        engine: engine,
      ).convert(sentence);

      expect(engine.inputs, <String>[sentence]);
      expect(chunks.single.graphemes.runes, hasLength(401));
      expect(chunks.single.phonemes, 'p');
    });

    test('truncates backend phonemes at 510 Python code points', () {
      final engine = _RecordingEngine(
        (_) => G2pResult(
          phonemes: _repeat('😀', 511),
          tokens: const <MisakiToken>[],
        ),
      );

      final chunk = KokoroNonEnglishG2pFrontend(
        engine: engine,
      ).convert('source').single;

      expect(chunk.phonemes.runes, hasLength(510));
      expect(chunk.phonemes.length, 1020);
      expect(chunk.tokens, isNull);
      expect(chunk.textIndex, 0);
    });

    test('uses only ASCII sentence punctuation and skips empty G2P output', () {
      final engine = _RecordingEngine((text) {
        return G2pResult(phonemes: text == 'skip' ? '' : 'p', tokens: null);
      });
      final longJapaneseSentence = '${_repeat('あ', 400)}。x';
      final frontend = KokoroNonEnglishG2pFrontend(engine: engine);

      final longChunks = frontend.convert(longJapaneseSentence);
      final emptyChunks = frontend.convert('skip');

      expect(longChunks, hasLength(1));
      expect(longChunks.single.graphemes, longJapaneseSentence);
      expect(emptyChunks, isEmpty);
    });
  });
}

MisakiToken _englishToken(
  String text, {
  String tag = 'X',
  String whitespace = '',
  String? phonemes,
  TokenMetadata metadata = const EnglishTokenMetadata(isHead: true),
}) => MisakiToken(
  text: text,
  tag: tag,
  whitespace: whitespace,
  phonemes: phonemes,
  metadata: metadata,
);

String _repeat(String value, int count) =>
    List<String>.filled(count, value).join();

final class _RecordingEngine implements UnknownMarkerG2pEngine {
  _RecordingEngine(this.callback, {this.unknownMarker = ''});

  final G2pResult Function(String text) callback;
  final List<String> inputs = <String>[];

  @override
  final String unknownMarker;

  @override
  G2pResult convert(String text) {
    inputs.add(text);
    return callback(text);
  }
}
