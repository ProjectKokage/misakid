import 'dart:io';

import 'package:misakid/misaki_ja.dart';
import 'package:test/test.dart';

import '../support/upstream_fixture.dart';

void main() {
  final fixtureFile = File(
    '${Directory.current.path}/test/fixtures/upstream/'
    'fba1236595f2d2bf21d414ba6e57d25256afada3/'
    'ja_cutlet.jsonl',
  );
  final fixtures = readUpstreamFixtures(fixtureFile);
  final successfulFixtures = fixtures
      .where((fixture) => fixture.errorCategory == null)
      .toList(growable: false);

  test('fixture covers the pinned Cutlet mode and exact resource tuple', () {
    expect(fixtures, hasLength(27));
    expect(successfulFixtures, hasLength(26));
    final words = <CutletFixtureWord>[];
    for (final fixture in fixtures) {
      expect(fixture.language, 'ja', reason: fixture.label);
      expect(fixture.mode, 'cutlet', reason: fixture.label);
      expect(fixture.options, isEmpty, reason: fixture.label);
      expect(
        fixture.backendVersions,
        containsPair('fugashi', '1.4.0'),
        reason: fixture.label,
      );
      expect(
        fixture.backendVersions,
        containsPair('jaconv', '0.4.0'),
        reason: fixture.label,
      );
      expect(
        fixture.backendVersions,
        containsPair('unicode-data', '15.0.0'),
        reason: fixture.label,
      );
      expect(
        fixture.backendVersions,
        containsPair(
          'misaki-ja-words',
          'sha256:a93a8e8aee24db307a32becb8bf01c4c2908ecf37e6c91f7a705fafdfeba67ff'
              '+bytes:1921140+records:147571',
        ),
        reason: fixture.label,
      );
      expect(
        fixture.backendVersions,
        containsPair(
          'unidic-dictionary-tree',
          'sha256:95bd65fa96955b644c15510932ca8439f463ac8b66f57bac6dfee5e29fa03115'
              '+files:20+bytes:811662881',
        ),
        reason: fixture.label,
      );
      expect(
        fixture.backendVersions,
        containsPair(
          'fugashi-system-dictionary',
          'charset:utf8+entries:878989+binary-version:102',
        ),
        reason: fixture.label,
      );
      expect(
        fixture.backendInput,
        isA<CutletFixtureBackendInput>(),
        reason: fixture.label,
      );
      final backendInput = fixture.backendInput;
      if (backendInput is CutletFixtureBackendInput) {
        words.addAll(backendInput.words);
      }
    }
    expect(words, hasLength(126));
    expect(words.where((word) => word.joinWithNext), hasLength(12));
    expect(words.where((word) => word.isUnknown), hasLength(26));
    expect(words.where((word) => word.pronunciation == null), hasLength(26));
    expect(words.where((word) => word.pronunciation != null), hasLength(100));
    expect(words.where((word) => word.kana == null), hasLength(26));
    expect(words.where((word) => word.kana != null), hasLength(100));
  });

  for (final fixture in successfulFixtures) {
    test(fixture.label, () {
      final backendInput = fixture.backendInput;
      if (backendInput is! CutletFixtureBackendInput) {
        throw StateError('${fixture.label}: missing Cutlet backendInput');
      }
      final backend = _FixtureCutletBackend(backendInput);
      final actual = JapaneseCutletEngine(
        backend: backend,
      ).convert(fixture.input);

      expect(actual.phonemes, fixture.phonemes, reason: fixture.label);
      expect(actual.tokens, isNull, reason: fixture.label);
      if (fixture.input.isEmpty) {
        expect(backend.inputs, isEmpty, reason: fixture.label);
      } else {
        expect(backend.inputs, <String>[
          backendInput.normalizedText,
        ], reason: fixture.label);
      }
    });
  }

  test('long number preserves the pinned Cutlet assertion domain', () {
    final fixture = fixtures.singleWhere(
      (candidate) => candidate.caseId == 'long-number-diagnostic',
    );
    final backendInput = fixture.backendInput;
    if (backendInput is! CutletFixtureBackendInput) {
      throw StateError('${fixture.label}: missing Cutlet backendInput');
    }
    final backend = _FixtureCutletBackend(backendInput);

    expect(fixture.errorCategory, 'upstreamFailure');
    expect(fixture.phonemes, isNull);
    expect(fixture.tokens, isNull);
    expect(
      () => JapaneseCutletEngine(backend: backend).convert(fixture.input),
      throwsA(
        isA<BackendFailureException>()
            .having(
              (error) => error.message,
              'message',
              contains('surface `10` remained numeric'),
            )
            .having(
              (error) => error.message,
              'message',
              contains('invalid word 8'),
            ),
      ),
    );
    expect(backend.inputs, <String>[backendInput.normalizedText]);
  });
}

final class _FixtureCutletBackend implements JapaneseCutletMorphologyBackend {
  _FixtureCutletBackend(CutletFixtureBackendInput input)
    : _words = List<JapaneseCutletMorphologyWord>.unmodifiable(
        input.words.map(
          (word) => JapaneseCutletMorphologyWord(
            surface: word.surface,
            hiragana: word.hiragana,
            charType: word.charType,
            isUnknown: word.isUnknown,
            joinWithNext: word.joinWithNext,
          ),
        ),
      );

  final List<JapaneseCutletMorphologyWord> _words;
  final List<String> inputs = <String>[];

  @override
  BackendInfo get info =>
      BackendInfo(name: 'fixture-fugashi', version: '1.4.0/unidic-3.1.0');

  @override
  List<JapaneseCutletMorphologyWord> analyze(String normalizedText) {
    inputs.add(normalizedText);
    return _words;
  }
}
