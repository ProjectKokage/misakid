import 'dart:io';

import 'package:misakid/misaki_zh.dart';
import 'package:test/test.dart';

import '../support/upstream_fixture.dart';

void main() {
  final fixtureFile = File(
    '${Directory.current.path}/test/fixtures/upstream/'
    'fba1236595f2d2bf21d414ba6e57d25256afada3/'
    'zh_legacy.jsonl',
  );
  final fixtures = readUpstreamFixtures(fixtureFile);
  final successfulFixtures = fixtures
      .where((fixture) => fixture.errorCategory == null)
      .toList(growable: false);
  final failureFixtures = fixtures
      .where((fixture) => fixture.errorCategory != null)
      .toList(growable: false);

  test('fixture declares only the exact pinned legacy Chinese mode', () {
    expect(fixtures, hasLength(24));
    expect(successfulFixtures, hasLength(22));
    expect(failureFixtures.map((fixture) => fixture.caseId), <String>[
      'cjk-upper-bound',
      'custom-unknown',
    ]);
    for (final fixture in fixtures) {
      expect(fixture.language, 'zh', reason: fixture.label);
      expect(fixture.mode, 'legacy', reason: fixture.label);
      expect(fixture.tokens, isNull, reason: fixture.label);
      expect(
        fixture.backendVersions,
        _expectedBackendVersions,
        reason: fixture.label,
      );
      expect(
        fixture.backendInput,
        isA<ChineseLegacyFixtureBackendInput>(),
        reason: fixture.label,
      );
    }
  });

  for (final fixture in successfulFixtures) {
    test(fixture.label, () {
      final backendInput =
          fixture.backendInput as ChineseLegacyFixtureBackendInput;
      final backend = _StrictLegacyFixtureBackend(backendInput);
      final engine = ChineseLegacyG2pEngine(backend: backend);

      final actual = engine.convert(fixture.input);

      expect(actual.phonemes, fixture.phonemes, reason: fixture.label);
      expect(actual.tokens, isNull, reason: fixture.label);
      expect(backend.remainingCalls, 0, reason: fixture.label);
    });
  }

  for (final fixture in failureFixtures) {
    test('${fixture.label} preserves the pinned transcription failure', () {
      final backendInput =
          fixture.backendInput as ChineseLegacyFixtureBackendInput;
      final backend = _StrictLegacyFixtureBackend(backendInput);
      final engine = ChineseLegacyG2pEngine(backend: backend);

      expect(fixture.errorCategory, 'upstreamFailure');
      expect(fixture.phonemes, isNull);
      expect(fixture.tokens, isNull);
      expect(
        () => engine.convert(fixture.input),
        throwsA(
          isA<BackendFailureException>()
              .having(
                (error) => error.message,
                'message',
                contains('invalid tone-3 Pinyin'),
              )
              .having((error) => error.cause, 'cause', isA<FormatException>()),
        ),
      );
      expect(backend.remainingCalls, 0, reason: fixture.label);
    });
  }
}

final class _StrictLegacyFixtureBackend implements ChineseLegacyBackend {
  _StrictLegacyFixtureBackend(this.input)
    : _totalCalls =
          (input.normalization == null ? 0 : 1) +
          input.runs.length +
          input.runs.fold<int>(0, (count, run) => count + run.words.length);

  final ChineseLegacyFixtureBackendInput input;
  final int _totalCalls;
  var _calls = 0;
  var _normalizationConsumed = false;
  var _runIndex = 0;
  ChineseLegacyFixtureRun? _activeRun;
  var _wordIndex = 0;

  int get remainingCalls => _totalCalls - _calls;

  @override
  final BackendInfo info = BackendInfo(
    name: 'fixture-cn2an-jieba-pypinyin',
    version: '0.5.23/0.42.1/0.53.0',
  );

  @override
  String normalizeNumbers(String text) {
    final normalization = input.normalization;
    if (normalization == null ||
        _normalizationConsumed ||
        _runIndex != 0 ||
        _activeRun != null ||
        normalization.input != text) {
      throw StateError('Normalization call differs from the capture.');
    }
    _normalizationConsumed = true;
    _calls++;
    return normalization.output;
  }

  @override
  List<String> segmentChinese(String text) {
    if ((input.normalization != null && !_normalizationConsumed) ||
        (_activeRun != null && _wordIndex != _activeRun!.words.length) ||
        _runIndex >= input.runs.length) {
      throw StateError('Segmentation call is out of captured order.');
    }
    final run = input.runs[_runIndex++];
    if (run.input != text) {
      throw StateError('Expected segmentation of `${run.input}`, got `$text`.');
    }
    _activeRun = run;
    _wordIndex = 0;
    _calls++;
    return <String>[for (final word in run.words) word.word];
  }

  @override
  List<String> tone3Pinyin(String word) {
    final run = _activeRun;
    if (run == null || _wordIndex >= run.words.length) {
      throw StateError('Unexpected Pinyin call for `$word`.');
    }
    final record = run.words[_wordIndex++];
    final pinyin = record.pinyin;
    if (record.word != word ||
        pinyin == null ||
        pinyin.input != word ||
        pinyin.stage != 'legacy-word' ||
        pinyin.style != 'tone3') {
      throw StateError('Pinyin call differs from the capture.');
    }
    _calls++;
    return List<String>.of(pinyin.output);
  }
}

const Map<String, Object?> _expectedBackendVersions = <String, Object?>{
  'addict': '2.4.0',
  'cn2an': '0.5.23',
  'jieba': '0.42.1',
  'jieba-default-dict':
      'sha256:'
      '7197c3211ddd98962b036cdf40324d1ea2bfaa12bd028e68faa70111a88e12a8',
  'ordered-set': '4.1.0',
  'proces': '0.1.7',
  'pypinyin': '0.53.0',
  'python': '3.12.11',
  'regex': '2024.11.6',
};
