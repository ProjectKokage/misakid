import 'package:misakid/misaki_ko.dart';
import 'package:test/test.dart';

void main() {
  test('injects CMUdict before morphology and preserves null tokens', () {
    final morphology = _FakeMorphology((text) {
      expect(text, '게임');
      return const <KoreanMorphologyToken>[
        KoreanMorphologyToken(surface: '게임', tag: 'NNG'),
      ];
    });
    final cmu = _FakeCmu((word) {
      expect(word, 'game');
      return KoreanCmuPronunciation(<String>['G', 'EY1', 'M']);
    });

    final result = KoreanG2pkcEngine(
      morphology: morphology,
      cmuPronunciations: cmu,
    ).convert('game');

    expect(result.phonemes, '게임');
    expect(result.tokens, isNull);
    expect(cmu.lookups, <String>['game']);
    expect(morphology.inputs, <String>['게임']);
  });

  test('wraps CMUdict exceptions with backend identity and cause', () {
    const failure = FormatException('broken dictionary');
    final engine = KoreanG2pkcEngine(
      morphology: _FakeMorphology((_) => const <KoreanMorphologyToken>[]),
      cmuPronunciations: _FakeCmu((_) => throw failure),
    );

    expect(
      () => engine.convert('game'),
      throwsA(
        isA<BackendFailureException>()
            .having(
              (error) => error.message,
              'message',
              allOf(contains('fake-cmudict 0.7a'), contains('game')),
            )
            .having((error) => error.cause, 'cause', same(failure)),
      ),
    );
  });

  test('wraps morphology exceptions and rejects malformed records', () {
    const failure = FormatException('broken analyzer');
    final throwing = KoreanG2pkcEngine(
      morphology: _FakeMorphology((_) => throw failure),
      cmuPronunciations: _FakeCmu((_) => null),
    );
    expect(
      () => throwing.convert('한국어'),
      throwsA(
        isA<BackendFailureException>()
            .having(
              (error) => error.message,
              'message',
              contains('fake-mecab 1.3.7'),
            )
            .having((error) => error.cause, 'cause', same(failure)),
      ),
    );

    final malformed = KoreanG2pkcEngine(
      morphology: _FakeMorphology(
        (_) => const <KoreanMorphologyToken>[
          KoreanMorphologyToken(surface: '', tag: 'NNG'),
        ],
      ),
      cmuPronunciations: _FakeCmu((_) => null),
    );
    expect(
      () => malformed.convert('한국어'),
      throwsA(
        isA<BackendFailureException>().having(
          (error) => error.message,
          'message',
          contains('invalid token 0'),
        ),
      ),
    );
  });

  test('preserves typed provider exceptions without wrapping', () {
    const unavailable = BackendUnavailableException('resource unavailable');
    final morphologyFailure = KoreanG2pkcEngine(
      morphology: _FakeMorphology((_) => throw unavailable),
      cmuPronunciations: _FakeCmu((_) => null),
    );
    expect(() => morphologyFailure.convert('한국어'), throwsA(same(unavailable)));

    final cmuFailure = KoreanG2pkcEngine(
      morphology: _FakeMorphology((_) => const <KoreanMorphologyToken>[]),
      cmuPronunciations: _FakeCmu((_) => throw unavailable),
    );
    expect(() => cmuFailure.convert('game'), throwsA(same(unavailable)));
  });

  test('rejects an empty CMUdict pronunciation as a typed failure', () {
    final engine = KoreanG2pkcEngine(
      morphology: _FakeMorphology((_) => const <KoreanMorphologyToken>[]),
      cmuPronunciations: _FakeCmu(
        (_) => KoreanCmuPronunciation(const <String>[]),
      ),
    );

    expect(
      () => engine.convert('game'),
      throwsA(
        isA<BackendFailureException>().having(
          (error) => error.message,
          'message',
          contains('invalid empty pronunciation'),
        ),
      ),
    );
  });
}

final class _FakeMorphology implements KoreanMorphologyBackend {
  _FakeMorphology(this.callback);

  final List<KoreanMorphologyToken> Function(String text) callback;
  final List<String> inputs = <String>[];

  @override
  final BackendInfo info = BackendInfo(name: 'fake-mecab', version: '1.3.7');

  @override
  List<KoreanMorphologyToken> pos(String text) {
    inputs.add(text);
    return callback(text);
  }
}

final class _FakeCmu implements KoreanCmuPronunciationProvider {
  _FakeCmu(this.callback);

  final KoreanCmuPronunciation? Function(String word) callback;
  final List<String> lookups = <String>[];

  @override
  final BackendInfo info = BackendInfo(name: 'fake-cmudict', version: '0.7a');

  @override
  KoreanCmuPronunciation? lookup(String word) {
    lookups.add(word);
    return callback(word);
  }
}
