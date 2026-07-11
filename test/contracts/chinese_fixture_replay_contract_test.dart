import 'dart:convert';

import 'package:misakid/misaki_zh.dart';
import 'package:test/test.dart';

import '../support/upstream_fixture.dart';

void main() {
  test('synthetic legacy capture drives the strict injected boundary', () {
    final fixture = _parse(_legacyBackendInput());
    final input = fixture.backendInput as ChineseLegacyFixtureBackendInput;
    final backend = _StrictLegacyReplayBackend(input);

    final result = ChineseLegacyG2pEngine(
      backend: backend,
    ).convert(fixture.input);

    expect(result.phonemes, isNotEmpty);
    expect(result.tokens, isNull);
    expect(backend.remainingCalls, 0);
  });

  test('synthetic frontend capture drives ordered POS/search/pinyin calls', () {
    final fixture = _parse(
      _frontendBackendInput(),
      mode: 'frontend-1.1',
      input: '不怕',
    );
    final input = fixture.backendInput as ChineseFrontendFixtureBackendInput;
    final backend = _StrictFrontendReplayBackend(input);

    final result = ChineseFrontend11G2pEngine(
      backend: backend,
    ).convert(fixture.input);

    expect(result.phonemes, isNotEmpty);
    expect(result.tokens, isNull);
    expect(backend.remainingCalls, 0);
  });
}

final class _StrictLegacyReplayBackend implements ChineseLegacyBackend {
  _StrictLegacyReplayBackend(this.input);

  final ChineseLegacyFixtureBackendInput input;
  var _normalizationConsumed = false;
  var _runIndex = 0;
  List<ChineseLegacyFixtureWord> _pendingWords = const [];
  var _wordIndex = 0;

  int get remainingCalls =>
      (_normalizationConsumed || input.normalization == null ? 0 : 1) +
      (input.runs.length - _runIndex) +
      (_pendingWords.length - _wordIndex);

  @override
  final BackendInfo info = BackendInfo(
    name: 'synthetic-legacy-replay',
    version: '1',
  );

  @override
  String normalizeNumbers(String text) {
    if (_normalizationConsumed) {
      throw StateError('Unexpected second normalization call.');
    }
    _normalizationConsumed = true;
    final normalization = input.normalization;
    if (normalization == null || normalization.input != text) {
      throw StateError('Normalization call differs from the capture.');
    }
    return normalization.output;
  }

  @override
  List<String> segmentChinese(String text) {
    if (_wordIndex != _pendingWords.length || _runIndex >= input.runs.length) {
      throw StateError('Segmentation call is out of captured order.');
    }
    final run = input.runs[_runIndex++];
    if (run.input != text) {
      throw StateError('Segmentation input differs from the capture.');
    }
    _pendingWords = run.words;
    _wordIndex = 0;
    return <String>[for (final word in run.words) word.word];
  }

  @override
  List<String> tone3Pinyin(String word) {
    if (_wordIndex >= _pendingWords.length) {
      throw StateError('Unexpected pinyin call.');
    }
    final record = _pendingWords[_wordIndex++];
    final pinyin = record.pinyin;
    if (record.word != word ||
        pinyin == null ||
        pinyin.input != word ||
        pinyin.stage != 'legacy-word' ||
        pinyin.style != 'tone3') {
      throw StateError('Pinyin call differs from the capture.');
    }
    return List<String>.of(pinyin.output);
  }
}

final class _StrictFrontendReplayBackend implements ChineseFrontend11Backend {
  _StrictFrontendReplayBackend(this.input);

  final ChineseFrontendFixtureBackendInput input;
  var _normalizationConsumed = false;
  var _frontendIndex = 0;
  ChineseFrontendFixtureCall? _activeCall;
  var _externalIndex = 0;

  int get remainingCalls {
    final active = _activeCall;
    return (_normalizationConsumed || input.normalization == null ? 0 : 1) +
        (input.frontendCalls.length - _frontendIndex) +
        (active == null ? 0 : active.externalCalls.length - _externalIndex);
  }

  @override
  final BackendInfo info = BackendInfo(
    name: 'synthetic-frontend-replay',
    version: '1',
  );

  @override
  String normalizeNumbers(String text) {
    if (_normalizationConsumed) {
      throw StateError('Unexpected second normalization call.');
    }
    _normalizationConsumed = true;
    final normalization = input.normalization;
    if (normalization == null || normalization.input != text) {
      throw StateError('Normalization call differs from the capture.');
    }
    return normalization.output;
  }

  @override
  List<ChineseSandhiWord> segmentWithPartOfSpeech(String text) {
    final active = _activeCall;
    if ((active != null && _externalIndex != active.externalCalls.length) ||
        _frontendIndex >= input.frontendCalls.length) {
      throw StateError('Frontend segmentation is out of captured order.');
    }
    final call = input.frontendCalls[_frontendIndex++];
    if (call.input != text) {
      throw StateError('Frontend segmentation input differs from the capture.');
    }
    _activeCall = call;
    _externalIndex = 0;
    return <ChineseSandhiWord>[
      for (final segment in call.segmentation)
        ChineseSandhiWord(word: segment.word, partOfSpeech: segment.pos),
    ];
  }

  @override
  List<String> tone3Finals(String word) =>
      _consumePinyin(word, expectedStyle: 'finals-tone3');

  @override
  List<String> initials(String word) =>
      _consumePinyin(word, expectedStyle: 'initials');

  @override
  List<String> searchSegments(String word) {
    final call = _nextExternalCall();
    if (call is! ChineseFixtureSearchCall || call.input != word) {
      throw StateError('Search-segmentation call differs from the capture.');
    }
    return List<String>.of(call.output);
  }

  List<String> _consumePinyin(String word, {required String expectedStyle}) {
    final call = _nextExternalCall();
    if (call is! ChineseFixturePinyinCall ||
        call.input != word ||
        call.style != expectedStyle) {
      throw StateError('Pinyin call differs from the capture.');
    }
    return List<String>.of(call.output);
  }

  ChineseFixtureExternalCall _nextExternalCall() {
    final active = _activeCall;
    if (active == null || _externalIndex >= active.externalCalls.length) {
      throw StateError('Unexpected external frontend call.');
    }
    return active.externalCalls[_externalIndex++];
  }
}

UpstreamFixture _parse(
  Map<String, Object?> backendInput, {
  String mode = 'legacy',
  String input = '2只猫',
}) => UpstreamFixture.parse(
  jsonEncode(<String, Object?>{
    'backendInput': backendInput,
    'backendVersions': <String, Object?>{},
    'caseId': 'synthetic-chinese-replay',
    'input': input,
    'language': 'zh',
    'mode': mode,
    'options': <String, Object?>{},
    'phonemes': 'not-an-authoritative-expected-output',
    'schemaVersion': 1,
    'tokens': null,
    'upstreamCommit': misakiUpstreamCommit,
    'upstreamRepository': misakiUpstreamRepository,
    'upstreamVersion': misakiUpstreamVersion,
  }),
  location: 'synthetic-chinese-replay-record',
);

Map<String, Object?> _legacyBackendInput() => <String, Object?>{
  'kind': ChineseLegacyFixtureBackendInput.kind,
  'normalization': <String, Object?>{
    'input': '2只猫',
    'mode': 'an2cn',
    'output': '两只猫',
  },
  'runs': <Object?>[
    <String, Object?>{
      'input': '两只猫',
      'words': <Object?>[
        <String, Object?>{
          'pinyin': _pinyinCall(
            input: '两只',
            output: <Object?>['liang3', 'zhi1'],
            stage: 'legacy-word',
            style: 'tone3',
          ),
          'word': '两只',
        },
        <String, Object?>{
          'pinyin': _pinyinCall(
            input: '猫',
            output: <Object?>['mao1'],
            stage: 'legacy-word',
            style: 'tone3',
          ),
          'word': '猫',
        },
      ],
    },
  ],
  'schemaVersion': ChineseLegacyFixtureBackendInput.schemaVersion,
};

Map<String, Object?> _frontendBackendInput() => <String, Object?>{
  'frontendCalls': <Object?>[
    <String, Object?>{
      'externalCalls': <Object?>[
        _pinyinCall(
          input: '不怕',
          output: <Object?>['u4', 'a4'],
          stage: 'tone-premerge',
          style: 'finals-tone3',
        ),
        _pinyinCall(
          input: '不怕',
          output: <Object?>['u4', 'a4'],
          stage: 'tone-premerge',
          style: 'finals-tone3',
        ),
        _pinyinCall(
          input: '不怕',
          output: <Object?>['b', 'p'],
          stage: 'frontend-render',
          style: 'initials',
        ),
        _pinyinCall(
          input: '不怕',
          output: <Object?>['u4', 'a4'],
          stage: 'frontend-render',
          style: 'finals-tone3',
        ),
        <String, Object?>{
          'input': '不怕',
          'kind': 'jieba.cut_for_search',
          'output': <Object?>['不', '怕'],
          'stage': 'tone-sandhi',
        },
      ],
      'input': '不怕',
      'segmentation': <Object?>[
        <String, Object?>{'pos': 'v', 'word': '不怕'},
      ],
    },
  ],
  'kind': ChineseFrontendFixtureBackendInput.kind,
  'normalization': <String, Object?>{
    'input': '不怕',
    'mode': 'an2cn',
    'output': '不怕',
  },
  'schemaVersion': ChineseFrontendFixtureBackendInput.schemaVersion,
};

Map<String, Object?> _pinyinCall({
  required String input,
  required List<Object?> output,
  required String stage,
  required String style,
}) => <String, Object?>{
  'input': input,
  'kind': 'pypinyin.lazy_pinyin',
  'neutralToneWithFive': true,
  'output': output,
  'stage': stage,
  'style': style,
};
