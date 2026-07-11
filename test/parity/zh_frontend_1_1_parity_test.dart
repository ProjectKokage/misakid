import 'dart:io';

import 'package:misakid/misaki_zh.dart';
import 'package:test/test.dart';

import '../support/upstream_fixture.dart';

void main() {
  final fixtureFile = File(
    '${Directory.current.path}/test/fixtures/upstream/'
    'fba1236595f2d2bf21d414ba6e57d25256afada3/'
    'zh_frontend_1_1.jsonl',
  );
  final fixtures = readUpstreamFixtures(fixtureFile);

  test('fixture declares only the exact pinned frontend-1.1 mode', () {
    expect(fixtures, hasLength(26));
    expect(fixtures.where((fixture) => fixture.errorCategory != null), isEmpty);
    for (final fixture in fixtures) {
      expect(fixture.language, 'zh', reason: fixture.label);
      expect(fixture.mode, 'frontend-1.1', reason: fixture.label);
      expect(fixture.tokens, isNull, reason: fixture.label);
      expect(fixture.phonemes, isNotNull, reason: fixture.label);
      expect(
        fixture.backendVersions,
        _expectedBackendVersions,
        reason: fixture.label,
      );
      expect(
        fixture.backendInput,
        isA<ChineseFrontendFixtureBackendInput>(),
        reason: fixture.label,
      );
    }
    expect(
      fixtures
          .where((fixture) => fixture.options.isNotEmpty)
          .map(
            (fixture) => <String, Object?>{
              'caseId': fixture.caseId,
              'options': fixture.options,
            },
          ),
      <Object?>[
        <String, Object?>{
          'caseId': 'custom-unknown-mixed',
          'options': <String, Object?>{'unk': '<?>'},
        },
      ],
    );
  });

  test('fixture captures every external stage at the reviewed totals', () {
    var normalizations = 0;
    var frontendCalls = 0;
    var posSegments = 0;
    var pinyinCalls = 0;
    var pinyinSyllables = 0;
    var searchCalls = 0;
    var searchSegments = 0;
    final stages = <String, int>{};

    for (final fixture in fixtures) {
      final input = fixture.backendInput as ChineseFrontendFixtureBackendInput;
      if (input.normalization != null) normalizations++;
      frontendCalls += input.frontendCalls.length;
      for (final call in input.frontendCalls) {
        posSegments += call.segmentation.length;
        for (final external in call.externalCalls) {
          switch (external) {
            case ChineseFixturePinyinCall():
              pinyinCalls++;
              pinyinSyllables += external.output.length;
              final key = '${external.stage}/${external.style}';
              stages[key] = (stages[key] ?? 0) + 1;
            case ChineseFixtureSearchCall():
              searchCalls++;
              searchSegments += external.output.length;
              const key = 'tone-sandhi/jieba-search';
              stages[key] = (stages[key] ?? 0) + 1;
          }
        }
      }
    }

    expect(normalizations, 24);
    expect(frontendCalls, 25);
    expect(posSegments, 131);
    expect(pinyinCalls, 365);
    expect(pinyinSyllables, 746);
    expect(searchCalls, 107);
    expect(searchSegments, 164);
    expect(stages, <String, int>{
      'frontend-render/finals-tone3': 91,
      'frontend-render/initials': 91,
      'tone-premerge/finals-tone3': 183,
      'tone-sandhi/jieba-search': 107,
    });
  });

  for (final fixture in fixtures) {
    test(fixture.label, () {
      final backendInput =
          fixture.backendInput as ChineseFrontendFixtureBackendInput;
      final backend = _StrictFrontendFixtureBackend(backendInput);
      final rawUnknownMarker = fixture.options['unk'];
      final engine = ChineseFrontend11G2pEngine(
        backend: backend,
        unknownMarker: rawUnknownMarker == null
            ? defaultUnknownMarker
            : rawUnknownMarker as String,
      );

      final actual = engine.convert(fixture.input);

      expect(actual.phonemes, fixture.phonemes, reason: fixture.label);
      expect(actual.tokens, isNull, reason: fixture.label);
      expect(backend.remainingCalls, 0, reason: fixture.label);
    });
  }
}

final class _StrictFrontendFixtureBackend implements ChineseFrontend11Backend {
  _StrictFrontendFixtureBackend(this.input)
    : _totalCalls =
          (input.normalization == null ? 0 : 1) +
          input.frontendCalls.length +
          input.frontendCalls.fold<int>(
            0,
            (count, call) => count + call.externalCalls.length,
          );

  final ChineseFrontendFixtureBackendInput input;
  final int _totalCalls;
  var _calls = 0;
  var _normalizationConsumed = false;
  var _frontendIndex = 0;
  ChineseFrontendFixtureCall? _activeCall;
  var _externalIndex = 0;
  var _renderStarted = false;

  int get remainingCalls => _totalCalls - _calls;

  @override
  final BackendInfo info = BackendInfo(
    name: 'fixture-cn2an-jieba-pos-pypinyin-dict',
    version: '0.5.23/0.42.1/0.53.0/0.9.0',
  );

  @override
  String normalizeNumbers(String text) {
    final normalization = input.normalization;
    if (normalization == null ||
        _normalizationConsumed ||
        _frontendIndex != 0 ||
        _activeCall != null ||
        normalization.input != text) {
      throw StateError('Normalization call differs from the capture.');
    }
    _normalizationConsumed = true;
    _calls++;
    return normalization.output;
  }

  @override
  List<ChineseSandhiWord> segmentWithPartOfSpeech(String text) {
    final active = _activeCall;
    if ((input.normalization != null && !_normalizationConsumed) ||
        (active != null && _externalIndex != active.externalCalls.length) ||
        _frontendIndex >= input.frontendCalls.length) {
      throw StateError('Frontend segmentation call is out of captured order.');
    }
    final call = input.frontendCalls[_frontendIndex++];
    if (call.input != text) {
      throw StateError(
        'Expected frontend segmentation of `${call.input}`, got `$text`.',
      );
    }
    _activeCall = call;
    _externalIndex = 0;
    _renderStarted = false;
    _calls++;
    return <ChineseSandhiWord>[
      for (final segment in call.segmentation)
        ChineseSandhiWord(word: segment.word, partOfSpeech: segment.pos),
    ];
  }

  @override
  List<String> initials(String word) {
    _renderStarted = true;
    return _consumePinyin(
      word,
      expectedStage: 'frontend-render',
      expectedStyle: 'initials',
    );
  }

  @override
  List<String> tone3Finals(String word) => _consumePinyin(
    word,
    expectedStage: _renderStarted ? 'frontend-render' : 'tone-premerge',
    expectedStyle: 'finals-tone3',
  );

  @override
  List<String> searchSegments(String word) {
    if (!_renderStarted) {
      throw StateError('Search segmentation occurred before frontend render.');
    }
    final external = _nextExternalCall();
    if (external is! ChineseFixtureSearchCall || external.input != word) {
      throw StateError('Search-segmentation call differs from the capture.');
    }
    return List<String>.of(external.output);
  }

  List<String> _consumePinyin(
    String word, {
    required String expectedStage,
    required String expectedStyle,
  }) {
    final external = _nextExternalCall();
    if (external is! ChineseFixturePinyinCall ||
        external.input != word ||
        external.stage != expectedStage ||
        external.style != expectedStyle) {
      throw StateError(
        'Pinyin call differs from the captured $expectedStage/'
        '$expectedStyle call.',
      );
    }
    return List<String>.of(external.output);
  }

  ChineseFixtureExternalCall _nextExternalCall() {
    final active = _activeCall;
    if (active == null || _externalIndex >= active.externalCalls.length) {
      throw StateError('Unexpected external frontend call.');
    }
    _calls++;
    return active.externalCalls[_externalIndex++];
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
  'pypinyin-dict': '0.9.0',
  'python': '3.12.11',
  'regex': '2024.11.6',
};
