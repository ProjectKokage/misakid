import 'dart:convert';

import 'package:misakid/misaki_vi.dart';
import 'package:test/test.dart';

import '../support/upstream_fixture.dart';
import '../support/vietnamese_fixture_replay.dart';

void main() {
  test('synthetic schema record replays the public Vietnamese engine', () {
    final fixture = UpstreamFixture.parse(
      jsonEncode(_record),
      location: 'memory:1',
    );
    final replay = VietnameseFixtureTokenizerReplay(
      fixture.backendInput! as VietnameseFixtureBackendInput,
    );

    final actual = VietnameseG2pEngine(
      tokenizer: replay,
    ).convert(fixture.input);

    expect(actual.phonemes, fixture.phonemes);
    expectVietnameseFixtureTokens(actual.tokens, fixture.tokens, fixture.label);
    replay.expectComplete(fixture.label);
  });
}

final Map<String, Object?> _record = <String, Object?>{
  'backendInput': <String, Object?>{
    'input': 'xin chào',
    'kind': VietnameseFixtureBackendInput.kind,
    'schemaVersion': VietnameseFixtureBackendInput.schemaVersion,
    'tokens': <Object?>['xin', 'chào'],
  },
  'backendVersions': <String, Object?>{
    'python': '3.11.13',
    'underthesea': '6.8.4',
    'unicode-data': '14.0.0',
  },
  'caseId': 'synthetic-greeting',
  'input': 'Xin chào',
  'language': 'vi',
  'mode': 'north-no-english-fallback',
  'options': <String, Object?>{},
  'phonemes': 'sin1 caw2',
  'schemaVersion': 1,
  'tokens': <Object?>[
    <String, Object?>{
      '_': <String, Object?>{
        'codas': 'n',
        'nuclei': 'i',
        'onsets': 's',
        'parent': null,
        'tone': '1',
      },
      'end_ts': null,
      'phonemes': 'sin1',
      'start_ts': null,
      'tag': '',
      'text': 'xin',
      'whitespace': ' ',
    },
    <String, Object?>{
      '_': <String, Object?>{
        'codas': 'w',
        'nuclei': 'a',
        'onsets': 'c',
        'parent': null,
        'tone': '2',
      },
      'end_ts': null,
      'phonemes': 'caw2',
      'start_ts': null,
      'tag': '',
      'text': 'chào',
      'whitespace': ' ',
    },
  ],
  'upstreamCommit': misakiUpstreamCommit,
  'upstreamRepository': misakiUpstreamRepository,
  'upstreamVersion': misakiUpstreamVersion,
};
