import 'dart:io';

import 'package:misakid/misaki_ko.dart';
import 'package:test/test.dart';

import '../support/upstream_fixture.dart';

void main() {
  final fixtureFile = File(
    '${Directory.current.path}/test/fixtures/upstream/'
    'fba1236595f2d2bf21d414ba6e57d25256afada3/'
    'ko_g2pkc_default.jsonl',
  );
  final fixtures = readUpstreamFixtures(fixtureFile);
  final successfulFixtures = fixtures
      .where((fixture) => fixture.errorCategory == null)
      .toList(growable: false);

  test('fixture declares the exact morphology-backed Korean mode', () {
    expect(fixtures, hasLength(34));
    expect(successfulFixtures, hasLength(33));
    for (final fixture in fixtures) {
      expect(fixture.language, 'ko', reason: fixture.label);
      expect(fixture.mode, 'g2pkc-default', reason: fixture.label);
      expect(fixture.options, isEmpty, reason: fixture.label);
      expect(fixture.tokens, isNull, reason: fixture.label);
      expect(
        fixture.backendInput,
        isA<KoreanFixtureBackendInput>(),
        reason: fixture.label,
      );
    }
  });

  test('all conjoining Jamo outputs belong to the declared inventory', () {
    final inventory = koreanPhonemeInventory();
    for (final fixture in successfulFixtures) {
      for (final scalar in fixture.phonemes!.runes) {
        if (scalar >= 0x1100 && scalar <= 0x11FF) {
          expect(
            inventory,
            contains(String.fromCharCode(scalar)),
            reason:
                '${fixture.label}: U+'
                '${scalar.toRadixString(16).toUpperCase().padLeft(4, '0')}',
          );
        }
      }
    }
  });

  for (final fixture in successfulFixtures) {
    test(fixture.label, () {
      final backendInput = fixture.backendInput as KoreanFixtureBackendInput;
      final morphology = _FixtureKoreanMorphology(backendInput);
      final cmu = _FixtureCmuPronunciations(backendInput.cmuLookups);
      final engine = KoreanG2pkcEngine(
        morphology: morphology,
        cmuPronunciations: cmu,
      );

      final actual = engine.convert(fixture.input);

      expect(actual.phonemes, fixture.phonemes, reason: fixture.label);
      expect(actual.tokens, isNull, reason: fixture.label);
      expect(morphology.inputs, <String>[backendInput.input]);
      expect(morphology.calls, 1);
      expect(
        cmu.lookups,
        backendInput.cmuLookups.map((lookup) => lookup.key),
        reason: fixture.label,
      );
      expect(cmu.remaining, 0, reason: fixture.label);
    });
  }

  test('seventeenth numeral place preserves the pinned failure boundary', () {
    final fixture = fixtures.singleWhere(
      (candidate) => candidate.caseId == 'numeral-place-limit',
    );
    final backendInput = fixture.backendInput as KoreanFixtureBackendInput;
    final morphology = _FixtureKoreanMorphology(backendInput);
    final cmu = _FixtureCmuPronunciations(backendInput.cmuLookups);
    final engine = KoreanG2pkcEngine(
      morphology: morphology,
      cmuPronunciations: cmu,
    );

    expect(fixture.errorCategory, 'upstreamFailure');
    expect(fixture.phonemes, isNull);
    expect(
      () => engine.convert(fixture.input),
      throwsA(
        isA<InvalidConfigurationException>().having(
          (error) => error.message,
          'message',
          contains('positions above 15'),
        ),
      ),
    );
    expect(morphology.inputs, <String>[backendInput.input]);
    expect(morphology.calls, 1);
    expect(cmu.lookups, isEmpty);
    expect(cmu.remaining, 0);
  });
}

final class _FixtureKoreanMorphology implements KoreanMorphologyBackend {
  _FixtureKoreanMorphology(this.fixture);

  final KoreanFixtureBackendInput fixture;
  final List<String> inputs = <String>[];
  int calls = 0;

  @override
  final BackendInfo info = BackendInfo(
    name: 'python-mecab-ko',
    version: '1.3.7',
  );

  @override
  List<KoreanMorphologyToken> pos(String text) {
    calls++;
    inputs.add(text);
    if (text != fixture.input) {
      throw StateError('Expected `${fixture.input}`, got `$text`.');
    }
    return <KoreanMorphologyToken>[
      for (final token in fixture.tokens)
        KoreanMorphologyToken(surface: token.surface, tag: token.tag),
    ];
  }
}

final class _FixtureCmuPronunciations
    implements KoreanCmuPronunciationProvider {
  _FixtureCmuPronunciations(this.expected);

  final List<KoreanFixtureCmuLookup> expected;
  final List<String> lookups = <String>[];
  int _index = 0;

  int get remaining => expected.length - _index;

  @override
  final BackendInfo info = BackendInfo(
    name: 'fixture-cmudict',
    version: '0.7a',
  );

  @override
  KoreanCmuPronunciation? lookup(String word) {
    lookups.add(word);
    if (_index >= expected.length) {
      throw StateError('Unexpected CMUdict lookup `$word`.');
    }
    final lookup = expected[_index++];
    if (word != lookup.key) {
      throw StateError('Expected CMUdict lookup `${lookup.key}`, got `$word`.');
    }
    final arpabet = lookup.arpabet;
    return arpabet == null ? null : KoreanCmuPronunciation(arpabet);
  }
}
