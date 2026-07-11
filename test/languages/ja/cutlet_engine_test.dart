import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:misakid/misaki_ja.dart';
import 'package:misakid/src/languages/ja/cutlet_mapping.dart';
import 'package:test/test.dart';

void main() {
  group('JapaneseCutletEngine', () {
    test('returns null tokens and bypasses the backend for empty input', () {
      final backend = _FakeCutletBackend(
        const <JapaneseCutletMorphologyWord>[],
      );
      final result = JapaneseCutletEngine(backend: backend).convert('');

      expect(result.phonemes, '');
      expect(result.tokens, isNull);
      expect(backend.inputs, isEmpty);
    });

    test('passes exact normalized text to the backend', () {
      final backend = _FakeCutletBackend(<JapaneseCutletMorphologyWord>[
        _word('猫', 'ねこ', charType: 2, isUnknown: false),
      ]);

      final result = JapaneseCutletEngine(backend: backend).convert('猫１２匹');

      expect(backend.inputs, <String>['猫 じゅうに匹']);
      expect(result.phonemes, 'neko');
      expect(result.tokens, isNull);
    });

    test('preserves known, symbol, and silently discarded char types', () {
      final result = _convert(<JapaneseCutletMorphologyWord>[
        _word('猫', 'ねこ', charType: 3, isUnknown: false),
        _word('。', '。', charType: 3),
        _word('謎', 'なぞ', charType: 5),
      ]);

      expect(result.phonemes, 'neko.');
      expect(result.tokens, isNull);
    });

    test('uses captured grouping decisions without ja_words.txt', () {
      final grouped = _convert(<JapaneseCutletMorphologyWord>[
        _word('今', 'きょ', joinWithNext: true),
        _word('日', 'う'),
      ]);
      final separate = _convert(<JapaneseCutletMorphologyWord>[
        _word('今', 'きょ'),
        _word('日', 'う'),
      ]);

      expect(grouped.phonemes, 'kʲoɯ');
      expect(separate.phonemes, 'kʲo ɯ');
    });

    test('ports digraph, small-kana fallback, and long-vowel rules', () {
      final result = _convert(<JapaneseCutletMorphologyWord>[
        _word('きゃ', 'きゃ'),
        _word('くゃ', 'くゃ'),
        _word('こー', 'こー'),
      ]);

      expect(result.phonemes, 'kʲa kja koː');
    });

    test('ports moraic-nasal assimilation exactly', () {
      final result = _convert(<JapaneseCutletMorphologyWord>[
        _word('んま', 'んま'),
        _word('んか', 'んか'),
        _word('んに', 'んに'),
        _word('んた', 'んた'),
        _word('んあ', 'んあ'),
      ]);

      expect(result.phonemes, 'mma ŋka ɲɲi nta ɴa');
    });

    test('removes cross-word spaces around sokuon with punctuation quirks', () {
      expect(
        _convert(<JapaneseCutletMorphologyWord>[
          _word('あ', 'あ'),
          _word('っ', 'っ'),
          _word('て', 'て'),
        ]).phonemes,
        'aʔte',
      );
      expect(
        _convert(<JapaneseCutletMorphologyWord>[
          _word('あ', 'あ'),
          _word('。', '。', charType: 3),
          _word('っ', 'っ'),
          _word('て', 'て'),
        ]).phonemes,
        'a. ʔte',
      );
    });

    test('preserves punctuation spacing and parenthesis replacement', () {
      final result = _convert(<JapaneseCutletMorphologyWord>[
        _word('あ', 'あ'),
        _word('(', '('),
        _word('い', 'い'),
        _word(')', ')'),
        _word('.', '.'),
        _word('あ', 'あ'),
        _word('；', '；', charType: 3),
        _word('い', 'い'),
      ]);

      expect(result.phonemes, 'a «i». a ; i');
    });

    test('preserves Python empty-substring punctuation spacing', () {
      final result = _convert(<JapaneseCutletMorphologyWord>[
        _word('あ', 'あ'),
        _word('」', '*', charType: 3, isUnknown: false),
        _word('？', '？', charType: 3, isUnknown: false),
        _word('い', 'い'),
      ]);

      // The known closing quote romanizes to an empty string. In Python,
      // `'' in '(['` is true, so the opening-punctuation branch wins.
      expect(result.phonemes, 'a ? i');
    });

    test('preserves the rare raw-kana iteration-mark quirk', () {
      expect(
        _convert(<JapaneseCutletMorphologyWord>[
          _word('かゝ', 'かゝ'),
          _word('かゞ', 'かゞ'),
          _word('っゝ', 'っゝ'),
        ]).phonemes,
        'kaか kaɡaʔ',
      );
    });

    test('passes ASCII surfaces through exactly', () {
      expect(
        _convert(<JapaneseCutletMorphologyWord>[
          _word('ABC', 'えーびーしー'),
          _word('/', '/'),
        ]).phonemes,
        'ABC /',
      );
    });

    test('wraps backend exceptions with stable identity and cause', () {
      final cause = Exception('morphology failed');
      final backend = _FakeCutletBackend(
        const <JapaneseCutletMorphologyWord>[],
        error: cause,
      );

      expect(
        () => JapaneseCutletEngine(backend: backend).convert('猫'),
        throwsA(
          isA<BackendFailureException>()
              .having(
                (error) => error.message,
                'message',
                contains('fake-cutlet 1.0'),
              )
              .having((error) => error.cause, 'cause', same(cause)),
        ),
      );
    });

    test('preserves typed backend failures without double wrapping', () {
      const unavailable = BackendUnavailableException(
        'provision the explicit Cutlet morphology backend',
      );
      final backend = _FakeCutletBackend(
        const <JapaneseCutletMorphologyWord>[],
        error: unavailable,
      );

      expect(
        () => JapaneseCutletEngine(backend: backend).convert('猫'),
        throwsA(same(unavailable)),
      );
    });

    test('reports malformed morphology records as typed backend failures', () {
      for (final words in <List<JapaneseCutletMorphologyWord>>[
        <JapaneseCutletMorphologyWord>[_word('', '')],
        <JapaneseCutletMorphologyWord>[_word('猫', '')],
        <JapaneseCutletMorphologyWord>[_word('猫', 'ねこ', charType: -1)],
        <JapaneseCutletMorphologyWord>[_word('猫', 'ね', joinWithNext: true)],
        <JapaneseCutletMorphologyWord>[
          _word('猫', 'ね', joinWithNext: true),
          _word('。', '。', charType: 3),
        ],
        <JapaneseCutletMorphologyWord>[_word('12', '12')],
        // Ethiopic digits satisfy Python str.isdigit but not re `\d`, so
        // normalization leaves them for Cutlet's numeric-surface assertion.
        <JapaneseCutletMorphologyWord>[_word('፩', '፩')],
      ]) {
        expect(() => _convert(words), throwsA(isA<BackendFailureException>()));
      }
    });
  });

  test('Cutlet mapping has the complete pinned inventory', () {
    expect(japaneseCutletMappingCount, 189);
    expect(japaneseCutletMapping('し'), 'ɕi');
    expect(japaneseCutletMapping('ゔゅ'), 'bʲɨ');
    expect(japaneseCutletMapping('・'), ' ');
    expect(japaneseCutletMapping('っ'), isNull);
    expect(japaneseCutletMapping('ん'), isNull);
    final canonical = SplayTreeMap<String, String>()
      ..addEntries(japaneseCutletMappingEntries);
    expect(
      sha256.convert(utf8.encode(jsonEncode(canonical))).toString(),
      '13504045812cb447d4ebfe504b3629f2999d7eba6f31d8f522cdcfdc89c38f96',
    );
  });
}

G2pResult _convert(List<JapaneseCutletMorphologyWord> words) =>
    JapaneseCutletEngine(backend: _FakeCutletBackend(words)).convert('入力');

JapaneseCutletMorphologyWord _word(
  String surface,
  String hiragana, {
  int charType = 6,
  bool isUnknown = true,
  bool joinWithNext = false,
}) => JapaneseCutletMorphologyWord(
  surface: surface,
  hiragana: hiragana,
  charType: charType,
  isUnknown: isUnknown,
  joinWithNext: joinWithNext,
);

final class _FakeCutletBackend implements JapaneseCutletMorphologyBackend {
  _FakeCutletBackend(this.words, {this.error});

  final List<JapaneseCutletMorphologyWord> words;
  final Exception? error;
  final List<String> inputs = <String>[];

  @override
  BackendInfo get info => BackendInfo(name: 'fake-cutlet', version: '1.0');

  @override
  List<JapaneseCutletMorphologyWord> analyze(String normalizedText) {
    inputs.add(normalizedText);
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return words;
  }
}
