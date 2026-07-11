import 'package:misakid/misaki_zh.dart';
import 'package:test/test.dart';

void main() {
  group('ChineseFrontend11 internal frontend', () {
    test('renders exact internal tokens and slash separators', () {
      final backend = _FakeFrontendBackend(
        segments: <String, List<ChineseSandhiWord>>{
          '你好': const <ChineseSandhiWord>[
            ChineseSandhiWord(word: '你', partOfSpeech: 'r'),
            ChineseSandhiWord(word: '好', partOfSpeech: 'a'),
          ],
        },
        initialsByWord: <String, List<String>>{
          '你': <String>['n'],
          '好': <String>['h'],
        },
        finalsByWord: <String, List<String>>{
          '你': <String>['i2'],
          '好': <String>['ao4'],
        },
        searchByWord: <String, List<String>>{
          '你': <String>['你'],
          '好': <String>['好'],
        },
      );

      final result = ChineseFrontend11(backend: backend).convertSegment('你好');

      expect(result.phonemes, 'ㄋㄧ2/ㄏㄠ4');
      expect(result.tokens, hasLength(2));
      final first = result.tokens!.first;
      expect(first.text, '你');
      expect(first.tag, 'r');
      expect(first.whitespace, '/');
      expect(first.phonemes, 'ㄋㄧ2');
      expect(first.startTimeSeconds, isNull);
      expect(first.endTimeSeconds, isNull);
      expect(first.metadata, isNull);
      final second = result.tokens![1];
      expect(second.text, '好');
      expect(second.tag, 'a');
      expect(second.whitespace, isEmpty);
      expect(second.phonemes, 'ㄏㄠ4');
      expect(backend.calls, <String>[
        'segment:你好',
        'finals:你',
        'finals:好',
        'finals:你',
        'finals:好',
        'initials:你',
        'finals:你',
        'search:你',
        'initials:好',
        'finals:好',
        'search:好',
      ]);
      expect(() => result.tokens!.add(second), throwsUnsupportedError);
    });

    test('folds whitespace, punctuation, and unknown eng tokens exactly', () {
      final backend = _FakeFrontendBackend(
        segments: <String, List<ChineseSandhiWord>>{
          '你  ,English': const <ChineseSandhiWord>[
            ChineseSandhiWord(word: '你', partOfSpeech: 'r'),
            ChineseSandhiWord(word: '  ', partOfSpeech: 'x'),
            ChineseSandhiWord(word: ',', partOfSpeech: 'x'),
            ChineseSandhiWord(word: 'English', partOfSpeech: 'eng'),
          ],
        },
        initialsByWord: <String, List<String>>{
          '你': <String>['n'],
        },
        finalsByWord: <String, List<String>>{
          '你': <String>['i2'],
        },
      );

      final result = ChineseFrontend11(
        backend: backend,
      ).convertSegment('你  ,English');

      expect(result.phonemes, 'ㄋㄧ2  ,❓');
      expect(result.tokens, hasLength(3));
      expect(result.tokens!.first.whitespace, '  ');
      expect(result.tokens![1].phonemes, ',');
      expect(result.tokens![2].text, 'English');
      expect(result.tokens![2].tag, 'eng');
      expect(result.tokens![2].phonemes, isNull);
    });

    test('corrects backend POS around Han and punctuation', () {
      final backend = _FakeFrontendBackend(
        segments: <String, List<ChineseSandhiWord>>{
          '甲,': const <ChineseSandhiWord>[
            ChineseSandhiWord(word: '甲', partOfSpeech: 'x'),
            ChineseSandhiWord(word: ',', partOfSpeech: 'n'),
          ],
        },
        initialsByWord: <String, List<String>>{
          '甲': <String>['j'],
        },
        finalsByWord: <String, List<String>>{
          '甲': <String>['ia3'],
          ',': <String>[','],
        },
      );

      final result = ChineseFrontend11(backend: backend).convertSegment('甲,');

      expect(result.phonemes, 'ㄐ压3,');
      expect(result.tokens!.map((token) => token.tag), <String>['X', 'x']);
      expect(backend.initialInputs, <String>['甲']);
    });

    test('integrates ordered 不 sandhi before phone rendering', () {
      final backend = _FakeFrontendBackend(
        segments: <String, List<ChineseSandhiWord>>{
          '不怕': const <ChineseSandhiWord>[
            ChineseSandhiWord(word: '不怕', partOfSpeech: 'v'),
          ],
        },
        initialsByWord: <String, List<String>>{
          '不怕': <String>['b', 'p'],
        },
        finalsByWord: <String, List<String>>{
          '不怕': <String>['u4', 'a4'],
        },
      );

      final result = ChineseFrontend11(backend: backend).convertSegment('不怕');

      expect(result.phonemes, 'ㄅㄨ2ㄆㄚ4');
      expect(result.tokens!.single.phonemes, result.phonemes);
    });

    test('preserves must-erhua and not-erhua contracts', () {
      final backend = _FakeFrontendBackend(
        segments: <String, List<ChineseSandhiWord>>{
          '小院儿': const <ChineseSandhiWord>[
            ChineseSandhiWord(word: '小院儿', partOfSpeech: 'n'),
          ],
          '女儿': const <ChineseSandhiWord>[
            ChineseSandhiWord(word: '女儿', partOfSpeech: 'n'),
          ],
        },
        initialsByWord: <String, List<String>>{
          '小院儿': <String>['x', '', ''],
          '女儿': <String>['n', ''],
        },
        finalsByWord: <String, List<String>>{
          '小院儿': <String>['iao3', 'van4', 'er2'],
          '女儿': <String>['v3', 'er2'],
        },
      );
      final frontend = ChineseFrontend11(backend: backend);

      expect(frontend.convertSegment('小院儿').phonemes, 'ㄒ要3元R4');
      expect(frontend.convertSegment('女儿').phonemes, 'ㄋㄩ3ㄦ2');
      expect(
        frontend.convertSegment('小院儿', withErhua: false).phonemes,
        'ㄒ要3元4ㄦ2',
      );
    });

    test('applies i-family and 嗯 postprocessing from pinned frontend', () {
      final backend = _FakeFrontendBackend(
        segments: <String, List<ChineseSandhiWord>>{
          '词时嗯在': const <ChineseSandhiWord>[
            ChineseSandhiWord(word: '词', partOfSpeech: 'n'),
            ChineseSandhiWord(word: '时', partOfSpeech: 'n'),
            ChineseSandhiWord(word: '嗯', partOfSpeech: 'e'),
            ChineseSandhiWord(word: '在', partOfSpeech: 'v'),
          ],
        },
        initialsByWord: <String, List<String>>{
          '词': <String>['c'],
          '时': <String>['sh'],
          '嗯': <String>[''],
          '在': <String>['z'],
        },
        finalsByWord: <String, List<String>>{
          '词': <String>['i2'],
          '时': <String>['i2'],
          '嗯': <String>[''],
          '在': <String>['ai4'],
        },
      );

      final result = ChineseFrontend11(backend: backend).convertSegment('词时嗯在');

      expect(result.phonemes, 'ㄘㄭ2/ㄕ十2/ㄋ2/ㄗㄞ4');
    });

    test('renders unmapped phone components with the selected marker', () {
      final backend = _FakeFrontendBackend(
        segments: <String, List<ChineseSandhiWord>>{
          '甲': const <ChineseSandhiWord>[
            ChineseSandhiWord(word: '甲', partOfSpeech: 'n'),
          ],
        },
        initialsByWord: <String, List<String>>{
          '甲': <String>['unknown'],
        },
        finalsByWord: <String, List<String>>{
          '甲': <String>['a1'],
        },
      );

      final result = ChineseFrontend11(
        backend: backend,
        unknownMarker: '<?>',
      ).convertSegment('甲');

      expect(result.phonemes, '<?>ㄚ1');
    });

    test('renders an empty pypinyin pair as the selected unknown marker', () {
      final backend = _FakeFrontendBackend(
        segments: <String, List<ChineseSandhiWord>>{
          '鿿': const <ChineseSandhiWord>[
            ChineseSandhiWord(word: '鿿', partOfSpeech: 'x'),
          ],
        },
        initialsByWord: <String, List<String>>{
          '鿿': <String>[''],
        },
        finalsByWord: <String, List<String>>{
          '鿿': <String>[''],
        },
      );

      final result = ChineseFrontend11(
        backend: backend,
        unknownMarker: '<?>',
      ).convertSegment('鿿');

      expect(result.phonemes, '<?>');
      expect(result.tokens!.single.tag, 'X');
      expect(result.tokens!.single.phonemes, '<?>');
    });

    test('returns an available-but-empty internal token list', () {
      final result = ChineseFrontend11(
        backend: _FakeFrontendBackend(),
      ).convertSegment('');

      expect(result.phonemes, isEmpty);
      expect(result.tokens, isEmpty);
    });

    test('rejects provider segmentation that does not preserve input', () {
      for (final segments in <List<ChineseSandhiWord>>[
        const <ChineseSandhiWord>[],
        const <ChineseSandhiWord>[
          ChineseSandhiWord(word: '乙', partOfSpeech: 'n'),
        ],
        const <ChineseSandhiWord>[
          ChineseSandhiWord(word: '甲', partOfSpeech: ''),
        ],
      ]) {
        final backend = _FakeFrontendBackend(
          segments: <String, List<ChineseSandhiWord>>{'甲': segments},
          finalsByWord: <String, List<String>>{
            '甲': <String>['ia3'],
          },
        );
        expect(
          () => ChineseFrontend11(backend: backend).convertSegment('甲'),
          throwsA(isA<BackendFailureException>()),
          reason: segments.toString(),
        );
      }
    });

    test('rejects mismatched pinyin arrays with backend identity', () {
      final backend = _FakeFrontendBackend(
        segments: <String, List<ChineseSandhiWord>>{
          '甲': const <ChineseSandhiWord>[
            ChineseSandhiWord(word: '甲', partOfSpeech: 'n'),
          ],
        },
        initialsByWord: <String, List<String>>{'甲': <String>[]},
        finalsByWord: <String, List<String>>{
          '甲': <String>['ia3'],
        },
      );

      expect(
        () => ChineseFrontend11(backend: backend).convertSegment('甲'),
        throwsA(
          isA<BackendFailureException>()
              .having(
                (error) => error.message,
                'message',
                contains('fake-frontend 1.1'),
              )
              .having(
                (error) => error.message,
                'message',
                contains('one initial'),
              ),
        ),
      );
    });

    test('wraps provider errors and preserves typed adapter failures', () {
      final providerError = FormatException('initials');
      final failing = _FakeFrontendBackend(
        segments: <String, List<ChineseSandhiWord>>{
          '甲': const <ChineseSandhiWord>[
            ChineseSandhiWord(word: '甲', partOfSpeech: 'n'),
          ],
        },
        finalsByWord: <String, List<String>>{
          '甲': <String>['ia3'],
        },
        initialError: providerError,
      );
      expect(
        () => ChineseFrontend11(backend: failing).convertSegment('甲'),
        throwsA(
          isA<BackendFailureException>().having(
            (error) => error.cause,
            'cause',
            same(providerError),
          ),
        ),
      );

      const unavailable = BackendUnavailableException('pypinyin unavailable');
      final unavailableBackend = _FakeFrontendBackend(
        segments: <String, List<ChineseSandhiWord>>{
          '甲': const <ChineseSandhiWord>[
            ChineseSandhiWord(word: '甲', partOfSpeech: 'n'),
          ],
        },
        finalsByWord: <String, List<String>>{
          '甲': <String>['ia3'],
        },
        initialError: unavailable,
      );
      expect(
        () =>
            ChineseFrontend11(backend: unavailableBackend).convertSegment('甲'),
        throwsA(same(unavailable)),
      );
    });
  });

  group('ChineseFrontend11G2pEngine outer contract', () {
    test('short-circuits CPython whitespace with null tokens', () {
      final backend = _FakeFrontendBackend();
      final engine = ChineseFrontend11G2pEngine(backend: backend);

      for (final text in <String>['', '\t\r\n', '\u001c　\u001f', '\u0085']) {
        final result = engine.convert(text);
        expect(result.phonemes, isEmpty);
        expect(result.tokens, isNull);
      }
      expect(backend.calls, isEmpty);
    });

    test('normalizes, maps punctuation, and splits mixed English exactly', () {
      final backend = _FakeFrontendBackend(
        normalized: '二，Hello 你好 world',
        segments: <String, List<ChineseSandhiWord>>{
          '二,': const <ChineseSandhiWord>[
            ChineseSandhiWord(word: '二', partOfSpeech: 'm'),
            ChineseSandhiWord(word: ',', partOfSpeech: 'x'),
          ],
          '你好': const <ChineseSandhiWord>[
            ChineseSandhiWord(word: '你', partOfSpeech: 'r'),
            ChineseSandhiWord(word: '好', partOfSpeech: 'a'),
          ],
        },
        initialsByWord: <String, List<String>>{
          '二': <String>[''],
          '你': <String>['n'],
          '好': <String>['h'],
        },
        finalsByWord: <String, List<String>>{
          '二': <String>['er4'],
          '你': <String>['i2'],
          '好': <String>['ao4'],
        },
      );
      final englishInputs = <String>[];
      final engine = ChineseFrontend11G2pEngine(
        backend: backend,
        englishG2p: (text) {
          englishInputs.add(text);
          return '[en:$text]';
        },
      );

      final result = engine.convert('2，ignored');

      expect(result.phonemes, 'ㄦ4, [en:Hello] ㄋㄧ2/ㄏㄠ4 [en:world]');
      expect(result.tokens, isNull);
      expect(backend.normalizationInputs, <String>['2，ignored']);
      expect(backend.segmentationInputs, <String>['二,', '你好']);
      expect(englishInputs, <String>['Hello', 'world']);
    });

    test('uses one unknown marker for an English segment without callback', () {
      final backend = _FakeFrontendBackend(normalized: 'Hello world');

      final result = ChineseFrontend11G2pEngine(
        backend: backend,
        unknownMarker: '<?>',
      ).convert('ignored');

      expect(result.phonemes, '<?>');
      expect(result.tokens, isNull);
      expect(backend.segmentationInputs, isEmpty);
    });

    test('allows normalized non-whitespace input to become empty', () {
      final result = ChineseFrontend11G2pEngine(
        backend: _FakeFrontendBackend(normalized: '　'),
      ).convert('甲');

      expect(result.phonemes, isEmpty);
      expect(result.tokens, isNull);
    });

    test('wraps backend and English callback failures with their causes', () {
      final backendError = FormatException('normalize');
      final failingBackend = _FakeFrontendBackend(normalizeError: backendError);
      expect(
        () => ChineseFrontend11G2pEngine(backend: failingBackend).convert('甲'),
        throwsA(
          isA<BackendFailureException>()
              .having(
                (error) => error.message,
                'message',
                contains('fake-frontend 1.1'),
              )
              .having((error) => error.cause, 'cause', same(backendError)),
        ),
      );

      final englishError = FormatException('english');
      expect(
        () => ChineseFrontend11G2pEngine(
          backend: _FakeFrontendBackend(normalized: 'English'),
          englishG2p: (_) => throw englishError,
        ).convert('ignored'),
        throwsA(
          isA<BackendFailureException>().having(
            (error) => error.cause,
            'cause',
            same(englishError),
          ),
        ),
      );
    });
  });
}

final class _FakeFrontendBackend implements ChineseFrontend11Backend {
  _FakeFrontendBackend({
    this.normalized,
    this.segments = const <String, List<ChineseSandhiWord>>{},
    this.initialsByWord = const <String, List<String>>{},
    this.finalsByWord = const <String, List<String>>{},
    this.searchByWord = const <String, List<String>>{},
    this.normalizeError,
    this.initialError,
  });

  final String? normalized;
  final Map<String, List<ChineseSandhiWord>> segments;
  final Map<String, List<String>> initialsByWord;
  final Map<String, List<String>> finalsByWord;
  final Map<String, List<String>> searchByWord;
  final Exception? normalizeError;
  final Exception? initialError;

  final List<String> calls = <String>[];
  final List<String> normalizationInputs = <String>[];
  final List<String> segmentationInputs = <String>[];
  final List<String> initialInputs = <String>[];
  final List<String> finalInputs = <String>[];
  final List<String> searchInputs = <String>[];

  @override
  BackendInfo get info => BackendInfo(name: 'fake-frontend', version: '1.1');

  @override
  String normalizeNumbers(String text) {
    calls.add('normalize');
    normalizationInputs.add(text);
    if (normalizeError != null) {
      throw normalizeError!;
    }
    return normalized ?? text;
  }

  @override
  List<ChineseSandhiWord> segmentWithPartOfSpeech(String text) {
    calls.add('segment:$text');
    segmentationInputs.add(text);
    return List<ChineseSandhiWord>.of(
      segments[text] ?? const <ChineseSandhiWord>[],
    );
  }

  @override
  List<String> initials(String word) {
    calls.add('initials:$word');
    initialInputs.add(word);
    final error = initialError;
    if (error != null) {
      throw error;
    }
    return List<String>.of(initialsByWord[word] ?? const <String>[]);
  }

  @override
  List<String> tone3Finals(String word) {
    calls.add('finals:$word');
    finalInputs.add(word);
    return List<String>.of(finalsByWord[word] ?? const <String>['0']);
  }

  @override
  List<String> searchSegments(String word) {
    calls.add('search:$word');
    searchInputs.add(word);
    return List<String>.of(searchByWord[word] ?? <String>[word]);
  }
}
