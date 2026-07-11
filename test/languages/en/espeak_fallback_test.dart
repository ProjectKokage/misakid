import 'package:misakid/misaki_en.dart';
import 'package:test/test.dart';

void main() {
  group('EnglishEspeakFallback', () {
    test('preserves null versus available-empty backend results', () {
      final missing = _FakeEspeakBackend(null);
      expect(
        EnglishEspeakFallback(backend: missing).pronounce(_token('unknown')),
        isNull,
      );

      final empty = _FakeEspeakBackend('');
      final result = EnglishEspeakFallback(
        backend: empty,
      ).pronounce(_token('silent'));
      expect(result?.phonemes, '');
      expect(result?.rating, 2);
    });

    test('ports common tied-phone mappings in pinned order', () {
      final backend = _FakeEspeakBackend(
        ' a^ɪ a^ʊ d^ʒ e^ɪ t^ʃ ɔ^ɪ ə^l ʲo ʲə ɚ r x ç ɐ ɬ\u0303 ',
      );
      final result = EnglishEspeakFallback(
        backend: backend,
      ).pronounce(_token('word'));

      expect(result?.phonemes, 'I W ʤ A ʧ Y ᵊl jɔ jə əɹ ɹ k k ə l');
      expect(result?.rating, 2);
    });

    test('handles syllabic marks and their glottal special cases', () {
      final backend = _FakeEspeakBackend(
        'ʔˌn\u0329 ʔn\u0329 m\u0329 n\u0329 \u0329 \u0329\u0329',
      );
      final result = EnglishEspeakFallback(
        backend: backend,
      ).pronounce(_token('button'));

      expect(result?.phonemes, 'tn tn ᵊm ᵊn  ᵊ');
    });

    test('applies American and legacy replacements exactly', () {
      final backend = _FakeEspeakBackend('o^ʊ ɜːɹ ɜː ɪə aː ɾ ʔ');
      final result = EnglishEspeakFallback(
        backend: backend,
      ).pronounce(_token('water'));

      expect(result?.phonemes, 'O ɜɹ ɜɹ iə a T t');
      expect(backend.dialects, <EnglishDialect>[EnglishDialect.american]);
    });

    test('applies British replacements without legacy conversion in 2.0', () {
      final backend = _FakeEspeakBackend('e^ə iə ə^ʊ o ɾ ʔ');
      final fallback = EnglishEspeakFallback(
        backend: backend,
        dialect: EnglishDialect.british,
        phonemeVersion: EnglishPhonemeVersion.v2,
      );

      expect(fallback.pronounce(_token('route'))?.phonemes, 'ɛː ɪə Q ɔ ɾ ʔ');
      expect(backend.dialects, <EnglishDialect>[EnglishDialect.british]);
    });

    test('uses Python whitespace stripping semantics', () {
      final backend = _FakeEspeakBackend('\u001c\u3000a^ɪ\u0085\u001f');
      final result = EnglishEspeakFallback(
        backend: backend,
      ).pronounce(_token('eye'));

      expect(result?.phonemes, 'I');
    });

    test('reports stable wrapper and raw backend identity', () {
      final fallback = EnglishEspeakFallback(
        backend: _FakeEspeakBackend('test'),
        dialect: EnglishDialect.british,
        phonemeVersion: EnglishPhonemeVersion.v2,
      );

      expect(fallback.info.name, 'misaki-espeak-fallback');
      expect(fallback.info.version, '0.9.4');
      expect(fallback.info.details, <String, String>{
        'backend': 'fake-espeak-ng',
        'backendVersion': '1.52.0',
        'dialect': 'british',
        'phonemeVersion': 'v2',
      });
    });

    test('wraps raw adapter failures with identity and cause', () {
      const error = FormatException('bad raw output');
      final fallback = EnglishEspeakFallback(
        backend: _FakeEspeakBackend(null, error: error),
      );

      expect(
        () => fallback.pronounce(_token('word')),
        throwsA(
          isA<BackendFailureException>()
              .having(
                (exception) => exception.message,
                'message',
                contains('fake-espeak-ng 1.52.0'),
              )
              .having((exception) => exception.cause, 'cause', same(error)),
        ),
      );
    });
  });
}

MisakiToken _token(String text) => MisakiToken(
  text: text,
  tag: 'NN',
  whitespace: '',
  metadata: const EnglishTokenMetadata(isHead: true),
);

final class _FakeEspeakBackend implements EnglishEspeakBackend {
  _FakeEspeakBackend(this.output, {this.error});

  final String? output;
  final Exception? error;
  final List<EnglishDialect> dialects = <EnglishDialect>[];

  @override
  BackendInfo get info =>
      BackendInfo(name: 'fake-espeak-ng', version: '1.52.0');

  @override
  String? phonemize(String text, {required EnglishDialect dialect}) {
    dialects.add(dialect);
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return output;
  }
}
