import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:misakid/misaki_ja.dart';
import 'package:misakid/src/languages/ja/pyopenjtalk_engine.dart' as internal;
import 'package:test/test.dart';

void main() {
  group('JapanesePyopenjtalkEngine frontend contract', () {
    test('forwards input and preserves an available empty token list', () {
      final backend = _FakeJapaneseFrontend(const <JapaneseFrontendWord>[]);
      final result = JapanesePyopenjtalkEngine(backend: backend).convert('入力');

      expect(backend.inputs, <String>['入力']);
      expect(result.phonemes, '');
      expect(result.tokens, isNotNull);
      expect(result.tokens, isEmpty);
    });

    test('wraps backend exceptions with stable backend identity', () {
      final failure = Exception('frontend broke');
      final backend = _ThrowingJapaneseFrontend(failure);
      final engine = JapanesePyopenjtalkEngine(backend: backend);

      expect(
        () => engine.convert('秘密の入力'),
        throwsA(
          isA<BackendFailureException>()
              .having(
                (error) => error.message,
                'message',
                allOf(contains('fake-pyopenjtalk'), contains('9.9.0')),
              )
              .having((error) => error.cause, 'cause', same(failure)),
        ),
      );
    });

    test('preserves typed backend exceptions without wrapping', () {
      const failure = BackendUnavailableException(
        'pyopenjtalk dictionary is unavailable.',
      );
      final engine = JapanesePyopenjtalkEngine(
        backend: _ThrowingJapaneseFrontend(failure),
      );

      expect(() => engine.convert('入力'), throwsA(same(failure)));
    });

    test('turns invalid frontend invariants into typed failures', () {
      final invalidWords = <JapaneseFrontendWord>[
        _word(surface: '不正', pronunciation: 'カ', moraSize: 2),
        _word(surface: '不正', pronunciation: 'カ', moraSize: 1, accent: -1),
        _word(surface: ' ', pronunciation: '', moraSize: 0),
      ];

      for (final word in invalidWords) {
        final engine = JapanesePyopenjtalkEngine(
          backend: _FakeJapaneseFrontend(<JapaneseFrontendWord>[word]),
        );
        expect(
          () => engine.convert('input-is-not-echoed-in-errors'),
          throwsA(
            isA<BackendFailureException>().having(
              (error) => error.message,
              'message',
              allOf(contains('fake-pyopenjtalk'), contains('word 0')),
            ),
          ),
        );
      }
    });

    test('preserves the leading-long-vowel mora-size exception', () {
      final result = _convert(<JapaneseFrontendWord>[
        _word(surface: 'ーア', pronunciation: 'ーア', moraSize: 3),
      ]);

      expect(result.phonemes, 'ːa_-');
      final metadata = result.tokens!.single.metadata as JapaneseTokenMetadata;
      expect(metadata.moraSize, 3);
      expect(metadata.moras, <String>['ー', 'ア']);
    });
  });

  group('pronunciationToMoras', () {
    test('has the exact complete pinned mora mapping', () {
      final canonical = SplayTreeMap<String, String>()
        ..addEntries(internal.japanesePyopenjtalkMoraEntries);

      expect(canonical, hasLength(193));
      expect(
        sha256.convert(utf8.encode(jsonEncode(canonical))).toString(),
        'a4a1758acf3f7bc83f5a5c6499b83931598a82a42e4a421d797db6bf6a40aeff',
      );
    });

    test('combines small kana and retains special one-scalar moras', () {
      final moras = JapanesePyopenjtalkEngine.pronunciationToMoras('キャットンーA');

      expect(moras, <String>['キャ', 'ッ', 'ト', 'ン', 'ー']);
      expect(() => moras.add('ア'), throwsUnsupportedError);
    });

    test('uses only combinations present in the pinned inventory', () {
      expect(JapanesePyopenjtalkEngine.pronunciationToMoras('ティシェヴョ'), <String>[
        'ティ',
        'シェ',
        'ヴョ',
      ]);
      expect(
        JapanesePyopenjtalkEngine.pronunciationToMoras('ひらがなABC'),
        isEmpty,
      );
    });
  });

  group('JapanesePyopenjtalkEngine rendering', () {
    test('renders inventory specials and per-scalar pitch', () {
      final result = _convert(<JapaneseFrontendWord>[
        _word(
          surface: '特別',
          partOfSpeech: '名詞',
          pronunciation: 'キャットンー',
          moraSize: 5,
        ),
      ]);

      expect(result.phonemes, 'ᶄaʔtoɴː__-----');
      final token = result.tokens!.single;
      expect(token.text, '特別');
      expect(token.tag, '名詞');
      expect(token.phonemes, 'ᶄaʔtoɴː');
      final metadata = token.metadata as JapaneseTokenMetadata;
      expect(metadata.pronunciation, 'キャットンー');
      expect(metadata.chainFlag, isFalse);
      expect(metadata.moras, <String>['キャ', 'ッ', 'ト', 'ン', 'ー']);
      expect(metadata.accents, <int>[0, 1, 2, 2, 2]);
      expect(metadata.pitch, '__-----');
    });

    test('carries accent state across chains and resets phrase counters', () {
      final result = _convert(<JapaneseFrontendWord>[
        _word(surface: 'あ', pronunciation: 'ア', moraSize: 1),
        _word(
          surface: 'いう',
          pronunciation: 'イウ',
          moraSize: 2,
          accent: 5,
          chainFlag: true,
        ),
        _word(surface: 'えお', pronunciation: 'エオ', moraSize: 2, accent: 3),
      ]);

      expect(result.phonemes, 'aiu eo_--j_-');
      final metadata = <JapaneseTokenMetadata>[
        for (final token in result.tokens!)
          token.metadata as JapaneseTokenMetadata,
      ];
      expect(metadata.map((item) => item.chainFlag), <bool>[
        false,
        true,
        false,
      ]);
      expect(metadata[0].accents, <int>[0]);
      expect(metadata[1].accents, <int>[1, 2]);
      expect(metadata[2].accents, <int>[0, 1]);
    });

    test('chains a leading long vowel even when the backend flag is false', () {
      final result = _convert(<JapaneseFrontendWord>[
        _word(surface: 'か', pronunciation: 'カ', moraSize: 1),
        _word(surface: 'ー', pronunciation: 'ー', moraSize: 1, accent: 4),
      ]);

      expect(result.phonemes, 'kaː__-');
      final metadata = result.tokens![1].metadata as JapaneseTokenMetadata;
      expect(metadata.chainFlag, isTrue);
      expect(metadata.accents, <int>[1]);
    });

    test('does not insert a phrase-boundary space before moraic nasal', () {
      final result = _convert(<JapaneseFrontendWord>[
        _word(surface: 'か', pronunciation: 'カ', moraSize: 1),
        _word(surface: 'ん', pronunciation: 'ン', moraSize: 1),
      ]);

      expect(result.phonemes, 'kaɴ___');
      final metadata = result.tokens![1].metadata as JapaneseTokenMetadata;
      expect(metadata.chainFlag, isFalse);
    });

    test('maps punctuation, merges whitespace, and renders unknowns', () {
      final result = _convert(<JapaneseFrontendWord>[
        _word(surface: '「', partOfSpeech: '記号', pronunciation: '', moraSize: 0),
        _word(
          surface: '猫',
          partOfSpeech: '名詞',
          pronunciation: 'ネコ',
          moraSize: 2,
          accent: 1,
        ),
        _word(surface: '、', partOfSpeech: '記号', pronunciation: '', moraSize: 0),
        _word(surface: ' ', pronunciation: '', moraSize: 0),
        _word(
          surface: '未知',
          partOfSpeech: '名詞',
          pronunciation: '',
          moraSize: 0,
        ),
        _word(surface: '。', partOfSpeech: '記号', pronunciation: '', moraSize: 0),
      ]);

      expect(result.phonemes, '“neko, ❓.j^^__jjjj');
      expect(result.tokens!.map((token) => token.text), <String>[
        '“',
        '猫',
        ',',
        '未知',
        '.',
      ]);
      expect(result.tokens!.map((token) => token.whitespace), <String>[
        '',
        '',
        ' ',
        '',
        ' ',
      ]);
      expect(result.tokens![3].phonemes, isNull);
    });

    test('merges an unpronounced middle dot into preceding whitespace', () {
      final result = _convert(<JapaneseFrontendWord>[
        _word(surface: '猫', pronunciation: 'ネコ', moraSize: 2, accent: 1),
        _word(surface: '・', pronunciation: '', moraSize: 0),
        _word(surface: '犬', pronunciation: 'イヌ', moraSize: 2, accent: 1),
      ]);

      expect(result.phonemes, 'neko inu^^__j^__');
      expect(result.tokens, hasLength(2));
      expect(result.tokens!.first.whitespace, ' ');
    });

    test('uses Python whitespace semantics for frontend-only separators', () {
      final result = _convert(<JapaneseFrontendWord>[
        _word(surface: '猫', pronunciation: 'ネコ', moraSize: 2, accent: 1),
        _word(surface: '\u001c', pronunciation: '', moraSize: 0),
        _word(surface: '犬', pronunciation: 'イヌ', moraSize: 2, accent: 1),
      ]);

      expect(result.phonemes, 'neko inu^^__j^__');
      expect(result.tokens, hasLength(2));
    });

    test('counts a supplementary unknown marker as one Unicode scalar', () {
      final backend = _FakeJapaneseFrontend(<JapaneseFrontendWord>[
        _word(surface: '未知', pronunciation: '', moraSize: 0),
      ]);
      final result = JapanesePyopenjtalkEngine(
        backend: backend,
        unknownMarker: '𠀋',
      ).convert('未知');

      expect(result.phonemes, '𠀋j');
    });
  });
}

G2pResult _convert(List<JapaneseFrontendWord> words) =>
    JapanesePyopenjtalkEngine(
      backend: _FakeJapaneseFrontend(words),
    ).convert('fixture input');

JapaneseFrontendWord _word({
  required String surface,
  required String pronunciation,
  required int moraSize,
  String partOfSpeech = 'X',
  int accent = 0,
  bool chainFlag = false,
}) => JapaneseFrontendWord(
  surface: surface,
  partOfSpeech: partOfSpeech,
  pronunciation: pronunciation,
  accent: accent,
  moraSize: moraSize,
  chainFlag: chainFlag,
);

final class _FakeJapaneseFrontend implements JapaneseFrontendBackend {
  _FakeJapaneseFrontend(this.words);

  final List<JapaneseFrontendWord> words;
  final List<String> inputs = <String>[];

  @override
  final BackendInfo info = BackendInfo(
    name: 'fake-pyopenjtalk',
    version: '1.0.0',
  );

  @override
  List<JapaneseFrontendWord> analyze(String text) {
    inputs.add(text);
    return words;
  }
}

final class _ThrowingJapaneseFrontend implements JapaneseFrontendBackend {
  _ThrowingJapaneseFrontend(this.failure);

  final Exception failure;

  @override
  final BackendInfo info = BackendInfo(
    name: 'fake-pyopenjtalk',
    version: '9.9.0',
  );

  @override
  List<JapaneseFrontendWord> analyze(String text) => throw failure;
}
