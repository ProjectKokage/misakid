import 'package:misakid/misaki_vi.dart';
import 'package:test/test.dart';

void main() {
  group('VietnameseG2pEngine', () {
    test('cleans before tokenization and returns exact typed syllables', () {
      final tokenizer = _FakeTokenizer((input) {
        expect(input, 'xin chào');
        return const <String>['xin', 'chào'];
      });

      final result = VietnameseG2pEngine(
        tokenizer: tokenizer,
      ).convert('  XIN\tCHÀO  ');

      expect(result.phonemes, 'sin1 caw2');
      expect(result.tokens, hasLength(2));
      expect(result.tokens![0].text, 'xin');
      expect(result.tokens![0].phonemes, 'sin1');
      expect(result.tokens![0].whitespace, ' ');
      expect(
        _metadata(result.tokens![0]),
        isA<VietnameseTokenMetadata>()
            .having((metadata) => metadata.parent, 'parent', isNull)
            .having((metadata) => metadata.onset, 'onset', 's')
            .having((metadata) => metadata.nucleus, 'nucleus', 'i')
            .having((metadata) => metadata.coda, 'coda', 'n')
            .having((metadata) => metadata.tone, 'tone', '1'),
      );
      expect(
        _metadata(result.tokens![1]),
        isA<VietnameseTokenMetadata>()
            .having((metadata) => metadata.onset, 'onset', 'c')
            .having((metadata) => metadata.nucleus, 'nucleus', 'a')
            .having((metadata) => metadata.coda, 'coda', 'w')
            .having((metadata) => metadata.tone, 'tone', '2'),
      );
    });

    test('keeps an available empty tokenization distinct from null', () {
      final result = VietnameseG2pEngine(
        tokenizer: _FakeTokenizer((input) {
          expect(input, '');
          return const <String>[];
        }),
      ).convert(' \t\n ');

      expect(result.phonemes, '');
      expect(result.tokens, isNotNull);
      expect(result.tokens, isEmpty);
    });

    test('preprocesses substring separators before cleaning', () {
      final enabled = VietnameseG2pEngine(
        tokenizer: _FakeTokenizer((input) {
          expect(input, 'xin chào blôk êban');
          return const <String>[];
        }),
      ).convert('XIN_CHÀO Blôk-Êban');
      final disabled = VietnameseG2pEngine(
        tokenizer: _FakeTokenizer((input) {
          expect(input, 'xin_chào blôk êban');
          return const <String>[];
        }),
        options: const VietnameseOptions(substringTokenization: false),
      ).convert('XIN_CHÀO Blôk-Êban');

      expect(enabled.phonemes, '');
      expect(disabled.phonemes, '');
    });

    test('replays analyzer punctuation splitting and normalization', () {
      final result = VietnameseG2pEngine(
        tokenizer: _FakeTokenizer(
          (_) => const <String>['xin,chào.', '{', '“', '😀'],
        ),
      ).convert('ignored');

      expect(result.phonemes, 'sin1 , caw2 . ( " [😀]');
      expect(result.tokens!.map((token) => token.text), <String>[
        'xin',
        ',',
        'chào',
        '.',
        '(',
        '"',
        '😀',
      ]);
      expect(result.tokens!.last.metadata, isNull);
      expect(result.tokens!.last.phonemes, '[😀]');
    });

    test('normalizes the complete pinned punctuation map', () {
      final result = VietnameseG2pEngine(
        tokenizer: _FakeTokenizer(
          (_) => const <String>[
            '.',
            ',',
            ';',
            ':',
            '!',
            '?',
            ')',
            '}',
            ']',
            '(',
            '{',
            '[',
            '"',
            "'",
            '–',
            '“',
            '”',
          ],
        ),
      ).convert('ignored');

      expect(result.phonemes, '. , ; : ! ? ) ) ) ( ( ( " \' – " "');
      expect(result.tokens!.map((token) => token.text), <String>[
        '.',
        ',',
        ';',
        ':',
        '!',
        '?',
        ')',
        ')',
        ')',
        '(',
        '(',
        '(',
        '"',
        "'",
        '–',
        '"',
        '"',
      ]);
      expect(result.tokens!.every((token) => token.metadata == null), isTrue);
    });

    test('applies inline controls after tokenizer case folding', () {
      final result = VietnameseG2pEngine(
        tokenizer: _FakeTokenizer((input) {
          expect(input, 'xin chào');
          return const <String>['xin', 'chào'];
        }),
      ).convert('[XIN](/CUSTOM/) chào');

      expect(result.phonemes, 'CUSTOM caw2');
      expect(result.tokens!.first.text, 'xin');
      expect(result.tokens!.first.metadata, isNull);
    });

    test(
      'splits foreign-looking Vietnamese substrings with parent metadata',
      () {
        final result = VietnameseG2pEngine(
          tokenizer: _FakeTokenizer((_) => const <String>['blôk', 'êban']),
        ).convert('ignored');

        expect(result.phonemes, 'be1 lok͡p1 e1 ban1');
        expect(result.tokens!.map((token) => token.text), <String>[
          'b',
          'lôk',
          'ê',
          'ban',
        ]);
        expect(
          result.tokens!.map((token) => _metadata(token).parent),
          <String?>['blôk', 'blôk', 'êban', 'êban'],
        );
      },
    );

    test('uses English fallback only for non-Vietnamese unresolved words', () {
      final fallback = _FakeEnglishFallback((token) {
        expect(token, 'hello');
        return 'həlˈoʊ';
      });
      final result = VietnameseG2pEngine(
        tokenizer: _FakeTokenizer((_) => const <String>['hello']),
        englishFallback: fallback,
      ).convert('ignored');

      expect(result.phonemes, 'həlˈoʊ');
      expect(fallback.calls, <String>['hello']);
      expect(
        _metadata(result.tokens!.single),
        isA<VietnameseTokenMetadata>()
            .having((metadata) => metadata.parent, 'parent', isNull)
            .having((metadata) => metadata.onset, 'onset', '')
            .having((metadata) => metadata.nucleus, 'nucleus', '')
            .having((metadata) => metadata.coda, 'coda', '')
            .having((metadata) => metadata.tone, 'tone', ''),
      );
    });

    test('rejects fallback output containing the unknown marker', () {
      final fallback = _FakeEnglishFallback((_) => 'h❓');
      final result = VietnameseG2pEngine(
        tokenizer: _FakeTokenizer((_) => const <String>['hello', 'blôk']),
        englishFallback: fallback,
      ).convert('ignored');

      expect(result.phonemes, 'hɛ1 lɤ2 lɔ1 be1 lok͡p1');
      expect(fallback.calls, <String>['hello']);
      expect(result.tokens!.map((token) => _metadata(token).parent), <String?>[
        'hello',
        'hello',
        'hello',
        'blôk',
        'blôk',
      ]);
    });

    test('wraps tokenizer and English provider failures with identity', () {
      final tokenizerError = Exception('tokenizer exploded');
      expect(
        () => VietnameseG2pEngine(
          tokenizer: _FakeTokenizer((_) => throw tokenizerError),
        ).convert('xin'),
        throwsA(
          isA<BackendFailureException>()
              .having(
                (error) => error.message,
                'message',
                contains('fake-underthesea 6.8.4'),
              )
              .having((error) => error.cause, 'cause', same(tokenizerError)),
        ),
      );

      final fallbackError = Exception('fallback exploded');
      expect(
        () => VietnameseG2pEngine(
          tokenizer: _FakeTokenizer((_) => const <String>['hello']),
          englishFallback: _FakeEnglishFallback((_) => throw fallbackError),
        ).convert('hello'),
        throwsA(
          isA<BackendFailureException>()
              .having(
                (error) => error.message,
                'message',
                contains('fake-english 0.9.4'),
              )
              .having((error) => error.cause, 'cause', same(fallbackError)),
        ),
      );
    });

    test('preserves typed provider failures without double wrapping', () {
      const unavailable = BackendUnavailableException(
        'provision the explicit Vietnamese backend',
      );
      expect(
        () => VietnameseG2pEngine(
          tokenizer: _FakeTokenizer((_) => throw unavailable),
        ).convert('xin'),
        throwsA(same(unavailable)),
      );
      expect(
        () => VietnameseG2pEngine(
          tokenizer: _FakeTokenizer((_) => const <String>['hello']),
          englishFallback: _FakeEnglishFallback((_) => throw unavailable),
        ).convert('hello'),
        throwsA(same(unavailable)),
      );
    });

    test('rejects empty analyzer tokens with an actionable failure', () {
      expect(
        () => VietnameseG2pEngine(
          tokenizer: _FakeTokenizer((_) => const <String>['xin', '']),
        ).convert('xin'),
        throwsA(
          isA<BackendFailureException>().having(
            (error) => error.message,
            'message',
            contains('empty token at index 1'),
          ),
        ),
      );
    });
  });
}

VietnameseTokenMetadata _metadata(MisakiToken token) =>
    token.metadata! as VietnameseTokenMetadata;

final class _FakeTokenizer implements VietnameseTokenizerBackend {
  _FakeTokenizer(this.callback);

  final List<String> Function(String input) callback;

  @override
  final BackendInfo info = BackendInfo(
    name: 'fake-underthesea',
    version: '6.8.4',
  );

  @override
  List<String> tokenize(String text) => callback(text);
}

final class _FakeEnglishFallback implements VietnameseEnglishFallbackBackend {
  _FakeEnglishFallback(this.callback);

  final String? Function(String token) callback;
  final List<String> calls = <String>[];

  @override
  final BackendInfo info = BackendInfo(name: 'fake-english', version: '0.9.4');

  @override
  String? phonemize(String token) {
    calls.add(token);
    return callback(token);
  }
}
