import 'dart:convert';
import 'dart:io';

import 'package:misakid/misaki.dart';
import 'package:test/test.dart';

const _kokoroCommit = 'dfb907a02bba8152ca444717ca5d78747ccb4bec';

void main() {
  final fixturePath =
      'test/fixtures/upstream/$_kokoroCommit/kokoro_frontend.jsonl';
  final provenancePath =
      'test/fixtures/upstream/$_kokoroCommit/'
      'kokoro_frontend.provenance.json';
  final fixtureFile = File(fixturePath);
  final records = fixtureFile
      .readAsLinesSync()
      .map<Map<String, Object?>>(_decodeObject)
      .toList(growable: false);

  test('pinned Kokoro frontend fixture provenance is exact', () {
    final provenance = _decodeObject(File(provenancePath).readAsStringSync());
    expect(provenance['schemaVersion'], 1);
    expect(provenance['upstreamRepository'], 'hexgrad/kokoro');
    expect(provenance['upstreamCommit'], _kokoroCommit);
    expect(provenance['upstreamVersion'], '0.9.4');
    expect(provenance['caseCount'], 11);
    expect(records.map((record) => record['caseId']).toSet(), <Object?>{
      'english-exact-510',
      'english-supplementary-511',
      'english-primary-with-bump',
      'english-secondary-boundary',
      'english-tertiary-boundary',
      'english-waterfall-fallthrough',
      'english-no-boundary',
      'english-indices-oov-and-surrogates',
      'english-surrogate-phoneme-511',
      'non-english-400-401',
      'non-english-indices-and-surrogates',
    });
  });

  for (final record in records) {
    final caseId = _string(record['caseId'], 'caseId');
    test('matches pinned Kokoro frontend: $caseId', () {
      expect(record['schemaVersion'], 1);
      expect(record['upstreamRepository'], 'hexgrad/kokoro');
      expect(record['upstreamCommit'], _kokoroCommit);
      expect(record['upstreamVersion'], '0.9.4');
      final backendInput = _object(record['backendInput'], 'backendInput');
      expect(backendInput['kind'], 'kokoro.synthetic-g2p');
      expect(backendInput['schemaVersion'], 1);
      final engine = _FixtureEngine(
        _objects(backendInput['results'], 'backendInput.results'),
      );
      final input = _string(record['input'], 'input');
      final chunks = switch (record['language']) {
        'en' => KokoroEnglishG2pFrontend(engine: engine).convert(input),
        'nonEnglish' => KokoroNonEnglishG2pFrontend(
          engine: engine,
        ).convert(input),
        final Object? language => throw FormatException(
          '$caseId has unsupported language `$language`.',
        ),
      };

      expect(engine.inputs, _strings(record['engineInputs'], 'engineInputs'));
      expect(
        chunks.map<Map<String, Object?>>(_serializeChunk).toList(),
        _objects(record['chunks'], 'chunks'),
      );
      if (record['language'] == 'en') {
        expect(backendInput['configuredUnknownMarker'], isEmpty);
      } else {
        expect(backendInput['configuredUnknownMarker'], isNull);
      }
    });
  }
}

Map<String, Object?> _decodeObject(String source) =>
    _object(jsonDecode(source), 'JSON record');

Map<String, Object?> _object(Object? value, String location) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$location must be an object.');
  }
  return value;
}

List<Map<String, Object?>> _objects(Object? value, String location) {
  if (value is! List<Object?>) {
    throw FormatException('$location must be a list.');
  }
  return <Map<String, Object?>>[
    for (var index = 0; index < value.length; index++)
      _object(value[index], '$location[$index]'),
  ];
}

String _string(Object? value, String location) {
  if (value is! String) {
    throw FormatException('$location must be a string.');
  }
  return value;
}

List<String> _strings(Object? value, String location) => <String>[
  for (final (index, item) in _values(value, location).indexed)
    _string(item, '$location[$index]'),
];

List<Object?> _values(Object? value, String location) {
  if (value is! List<Object?>) {
    throw FormatException('$location must be a list.');
  }
  return value;
}

Map<String, Object?> _serializeChunk(KokoroG2pChunk chunk) => <String, Object?>{
  'graphemes': chunk.graphemes,
  'phonemes': chunk.phonemes,
  'textIndex': chunk.textIndex,
  'tokens': chunk.tokens?.map<Map<String, Object?>>(_serializeToken).toList(),
};

Map<String, Object?> _serializeToken(MisakiToken token) => <String, Object?>{
  'endTimeSeconds': token.endTimeSeconds,
  'phonemes': token.phonemes,
  'startTimeSeconds': token.startTimeSeconds,
  'tag': token.tag,
  'text': token.text,
  'whitespace': token.whitespace,
};

final class _FixtureEngine implements UnknownMarkerG2pEngine {
  _FixtureEngine(List<Map<String, Object?>> results)
    : _results = <String, Map<String, Object?>>{
        for (final result in results)
          _string(result['input'], 'backend result input'): result,
      };

  final Map<String, Map<String, Object?>> _results;
  final List<String> inputs = <String>[];

  @override
  String get unknownMarker => '';

  @override
  G2pResult convert(String text) {
    inputs.add(text);
    final result = _results[text];
    if (result == null) {
      throw StateError(
        'Unexpected fixture engine input code units: ${text.codeUnits}',
      );
    }
    final rawTokens = result['tokens'];
    if (rawTokens == null) {
      return G2pResult(
        phonemes: _string(result['phonemes'], 'backend result phonemes'),
        tokens: null,
      );
    }
    return G2pResult(
      phonemes: 'ignored by the Kokoro English token chunker',
      tokens: <MisakiToken>[
        for (final token in _objects(rawTokens, 'backend result tokens'))
          MisakiToken(
            text: _string(token['text'], 'token.text'),
            tag: _string(token['tag'], 'token.tag'),
            whitespace: _string(token['whitespace'], 'token.whitespace'),
            phonemes: switch (token['phonemes']) {
              null => null,
              final String value => value,
              final Object? value => throw FormatException(
                'token.phonemes must be null or a string, got $value.',
              ),
            },
          ),
      ],
    );
  }
}
