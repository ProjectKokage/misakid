import 'dart:convert';

import 'package:misakid/misaki_zh.dart';
import 'package:test/test.dart';

import '../support/upstream_fixture.dart';

void main() {
  test('parses and freezes synthetic legacy external-stage records', () {
    final fixture = _parse(_legacyBackendInput());
    final input = fixture.backendInput as ChineseLegacyFixtureBackendInput;

    expect(input.normalization!.input, '2只猫');
    expect(input.normalization!.output, '两只猫');
    expect(input.runs.single.input, '两只猫');
    expect(input.runs.single.words, hasLength(2));
    expect(input.runs.single.words.first.word, '两只');
    expect(input.runs.single.words.first.pinyin!.stage, 'legacy-word');
    expect(input.runs.single.words.first.pinyin!.style, 'tone3');
    expect(input.runs.single.words.first.pinyin!.output, <String>[
      'liang3',
      'zhi1',
    ]);
    expect(input.runs.clear, throwsUnsupportedError);
    expect(input.runs.single.words.clear, throwsUnsupportedError);
    expect(
      input.runs.single.words.first.pinyin!.output.clear,
      throwsUnsupportedError,
    );
  });

  test('retains null values from a partial legacy failure capture', () {
    final backendInput = _legacyBackendInput()..['normalization'] = null;
    final runs = backendInput['runs']! as List<Object?>;
    final run = runs.single as Map<String, Object?>;
    final words = run['words']! as List<Object?>;
    (words.first as Map<String, Object?>)['pinyin'] = null;

    final input =
        _parse(backendInput).backendInput as ChineseLegacyFixtureBackendInput;
    expect(input.normalization, isNull);
    expect(input.runs.single.words.first.pinyin, isNull);
  });

  test('parses and freezes synthetic frontend 1.1 external calls', () {
    final fixture = _parse(_frontendBackendInput(), mode: 'frontend-1.1');
    final input = fixture.backendInput as ChineseFrontendFixtureBackendInput;
    final call = input.frontendCalls.single;

    expect(input.normalization!.input, '不怕');
    expect(input.normalization!.output, '不怕');
    expect(call.input, '不怕');
    expect(call.segmentation.single.word, '不怕');
    expect(call.segmentation.single.pos, 'v');
    expect(call.externalCalls, hasLength(4));
    expect(call.externalCalls[0], isA<ChineseFixturePinyinCall>());
    final premerge = call.externalCalls[0] as ChineseFixturePinyinCall;
    expect(premerge.stage, 'tone-premerge');
    expect(premerge.style, 'finals-tone3');
    expect(premerge.output, <String>['u4', 'a4']);
    expect(call.externalCalls[1], isA<ChineseFixtureSearchCall>());
    expect((call.externalCalls[1] as ChineseFixtureSearchCall).output, <String>[
      '不',
      '怕',
    ]);
    expect(
      (call.externalCalls[2] as ChineseFixturePinyinCall).style,
      'initials',
    );
    expect(
      (call.externalCalls[3] as ChineseFixturePinyinCall).style,
      'finals-tone3',
    );
    expect(input.frontendCalls.clear, throwsUnsupportedError);
    expect(call.segmentation.clear, throwsUnsupportedError);
    expect(call.externalCalls.clear, throwsUnsupportedError);
  });

  test('rejects drifted Chinese serializer records', () {
    final wrongMode = _legacyBackendInput();
    (wrongMode['normalization']! as Map<String, Object?>)['mode'] = 'cn2an';

    final wrongNeutral = _legacyBackendInput();
    final wrongNeutralPinyin = _firstLegacyPinyin(wrongNeutral);
    wrongNeutralPinyin['neutralToneWithFive'] = false;

    final wrongLegacyStage = _legacyBackendInput();
    _firstLegacyPinyin(wrongLegacyStage)['stage'] = 'tone-premerge';

    final mistypedLegacyOutput = _legacyBackendInput();
    final output =
        _firstLegacyPinyin(mistypedLegacyOutput)['output']! as List<Object?>;
    output[0] = 3;

    final unknownExternal = _frontendBackendInput();
    _frontendExternalCalls(unknownExternal)[0] = <String, Object?>{
      'kind': 'unknown.external',
    };

    final wrongSearchStage = _frontendBackendInput();
    final search =
        _frontendExternalCalls(wrongSearchStage)[1] as Map<String, Object?>;
    search['stage'] = 'render';

    final extraTopLevelKey = _frontendBackendInput()..['unexpected'] = true;

    for (final backendInput in <Map<String, Object?>>[
      wrongMode,
      wrongNeutral,
      wrongLegacyStage,
      mistypedLegacyOutput,
      unknownExternal,
      wrongSearchStage,
      extraTopLevelKey,
    ]) {
      expect(
        () => _parse(backendInput),
        throwsA(isA<UpstreamFixtureFormatException>()),
      );
    }
  });
}

UpstreamFixture _parse(
  Map<String, Object?> backendInput, {
  String mode = 'legacy',
}) => UpstreamFixture.parse(
  jsonEncode(<String, Object?>{
    'backendInput': backendInput,
    'backendVersions': <String, Object?>{},
    'caseId': 'synthetic-chinese-schema',
    'input': 'synthetic-chinese-input',
    'language': 'zh',
    'mode': mode,
    'options': <String, Object?>{},
    'phonemes': 'synthetic-phoneme-output',
    'schemaVersion': 1,
    'tokens': null,
    'upstreamCommit': misakiUpstreamCommit,
    'upstreamRepository': misakiUpstreamRepository,
    'upstreamVersion': misakiUpstreamVersion,
  }),
  location: 'synthetic-chinese-record',
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
        <String, Object?>{
          'input': '不怕',
          'kind': 'jieba.cut_for_search',
          'output': <Object?>['不', '怕'],
          'stage': 'tone-sandhi',
        },
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

Map<String, Object?> _firstLegacyPinyin(Map<String, Object?> backendInput) {
  final runs = backendInput['runs']! as List<Object?>;
  final run = runs.single as Map<String, Object?>;
  final words = run['words']! as List<Object?>;
  final word = words.first as Map<String, Object?>;
  return word['pinyin']! as Map<String, Object?>;
}

List<Object?> _frontendExternalCalls(Map<String, Object?> backendInput) {
  final calls = backendInput['frontendCalls']! as List<Object?>;
  final call = calls.single as Map<String, Object?>;
  return call['externalCalls']! as List<Object?>;
}
