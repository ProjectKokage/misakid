import 'dart:io';

import 'package:misakid/misaki_ja.dart';
import 'package:test/test.dart';

import '../support/upstream_fixture.dart';

void main() {
  final fixtureFile = File(
    '${Directory.current.path}/test/fixtures/upstream/'
    'fba1236595f2d2bf21d414ba6e57d25256afada3/'
    'ja_pyopenjtalk.jsonl',
  );
  final fixtures = readUpstreamFixtures(fixtureFile);
  final successfulFixtures = fixtures
      .where((fixture) => fixture.errorCategory == null)
      .toList(growable: false);

  test('fixture covers the pinned pyopenjtalk mode and backend', () {
    expect(fixtures, hasLength(24));
    expect(successfulFixtures, hasLength(23));
    for (final fixture in fixtures) {
      expect(fixture.language, 'ja', reason: fixture.label);
      expect(fixture.mode, 'pyopenjtalk', reason: fixture.label);
      expect(fixture.options, isEmpty, reason: fixture.label);
      expect(fixture.backendVersions, <String, Object?>{
        'pyopenjtalk': '0.4.1',
      }, reason: fixture.label);
      expect(fixture.backendInput, isNotNull, reason: fixture.label);
    }
  });

  for (final fixture in successfulFixtures) {
    test(fixture.label, () {
      final backendInput = fixture.backendInput;
      if (backendInput is! PyopenjtalkFixtureBackendInput) {
        throw StateError('${fixture.label}: missing pyopenjtalk backendInput');
      }
      final backend = _FixtureJapaneseFrontend(backendInput);
      final engine = JapanesePyopenjtalkEngine(backend: backend);

      final actual = engine.convert(fixture.input);

      expect(backend.info.name, 'pyopenjtalk');
      expect(backend.info.version, '0.4.1');
      expect(backend.analyzeCalls, 1, reason: fixture.label);
      expect(backend.inputs, <String>[fixture.input], reason: fixture.label);
      expect(actual.phonemes, fixture.phonemes, reason: fixture.label);
      _expectTokens(actual.tokens, fixture.tokens, fixture.label);
    });
  }

  test('whitespace-only captures the pinned typed backend failure', () {
    final fixture = fixtures.singleWhere(
      (candidate) => candidate.caseId == 'whitespace-only',
    );
    final backendInput = fixture.backendInput;
    if (backendInput is! PyopenjtalkFixtureBackendInput) {
      throw StateError('${fixture.label}: missing pyopenjtalk backendInput');
    }
    final backend = _FixtureJapaneseFrontend(backendInput);
    final engine = JapanesePyopenjtalkEngine(backend: backend);

    expect(fixture.errorCategory, 'upstreamFailure');
    expect(fixture.phonemes, isNull);
    expect(fixture.tokens, isNull);
    expect(
      () => engine.convert(fixture.input),
      throwsA(
        isA<BackendFailureException>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('pyopenjtalk 0.4.1'),
            contains('invalid word 0'),
            contains('leading whitespace'),
          ),
        ),
      ),
    );
    expect(backend.analyzeCalls, 1);
    expect(backend.inputs, <String>[fixture.input]);
  });
}

void _expectTokens(
  List<MisakiToken>? actual,
  List<Object?>? rawExpected,
  String fixtureLabel,
) {
  if (actual == null || rawExpected == null) {
    fail('$fixtureLabel: successful pyopenjtalk fixtures require token lists');
  }
  expect(actual, hasLength(rawExpected.length), reason: fixtureLabel);
  for (var index = 0; index < rawExpected.length; index++) {
    final expected = _object(rawExpected[index], '$fixtureLabel token $index');
    _expectExactKeys(expected, _tokenKeys, '$fixtureLabel token $index');
    final token = actual[index];
    final reason = '$fixtureLabel token $index';
    expect(token.text, _string(expected, 'text', reason), reason: reason);
    expect(token.tag, _string(expected, 'tag', reason), reason: reason);
    expect(
      token.whitespace,
      _string(expected, 'whitespace', reason),
      reason: reason,
    );
    expect(
      token.phonemes,
      _nullableString(expected, 'phonemes', reason),
      reason: reason,
    );
    expect(
      token.startTimeSeconds,
      _nullableNumber(expected, 'start_ts', reason),
      reason: reason,
    );
    expect(
      token.endTimeSeconds,
      _nullableNumber(expected, 'end_ts', reason),
      reason: reason,
    );

    final metadata = token.metadata;
    if (metadata is! JapaneseTokenMetadata) {
      fail('$reason: expected JapaneseTokenMetadata, got $metadata');
    }
    final rawMetadata = _object(expected['_'], '$reason metadata');
    _expectExactKeys(rawMetadata, _metadataKeys, '$reason metadata');
    expect(
      metadata.pronunciation,
      _string(rawMetadata, 'pron', reason),
      reason: reason,
    );
    expect(
      metadata.accent,
      _integer(rawMetadata, 'acc', reason),
      reason: reason,
    );
    expect(
      metadata.moraSize,
      _integer(rawMetadata, 'mora_size', reason),
      reason: reason,
    );
    expect(
      metadata.chainFlag,
      _chainFlag(rawMetadata['chain_flag'], reason),
      reason: reason,
    );
    expect(
      metadata.moras,
      _stringList(rawMetadata, 'moras', reason),
      reason: reason,
    );
    expect(
      metadata.accents,
      _intList(rawMetadata, 'accents', reason),
      reason: reason,
    );
    expect(
      metadata.pitch,
      _nullableString(rawMetadata, 'pitch', reason),
      reason: reason,
    );
  }
}

Map<String, Object?> _object(Object? value, String location) {
  if (value is! Map<String, Object?>) {
    throw StateError('$location must be an object');
  }
  return value;
}

String _string(Map<String, Object?> map, String key, String location) {
  final value = map[key];
  if (value is! String) {
    throw StateError('$location: $key must be a string');
  }
  return value;
}

String? _nullableString(Map<String, Object?> map, String key, String location) {
  final value = map[key];
  if (value != null && value is! String) {
    throw StateError('$location: $key must be a string or null');
  }
  return value as String?;
}

num? _nullableNumber(Map<String, Object?> map, String key, String location) {
  final value = map[key];
  if (value != null && value is! num) {
    throw StateError('$location: $key must be a number or null');
  }
  return value as num?;
}

int _integer(Map<String, Object?> map, String key, String location) {
  final value = map[key];
  if (value is! int) {
    throw StateError('$location: $key must be an integer');
  }
  return value;
}

List<String> _stringList(
  Map<String, Object?> map,
  String key,
  String location,
) {
  final value = map[key];
  if (value is! List<Object?>) {
    throw StateError('$location: $key must be an array');
  }
  final result = <String>[];
  for (final item in value) {
    if (item is! String) {
      throw StateError('$location: $key must contain only strings');
    }
    result.add(item);
  }
  return result;
}

List<int> _intList(Map<String, Object?> map, String key, String location) {
  final value = map[key];
  if (value is! List<Object?>) {
    throw StateError('$location: $key must be an array');
  }
  final result = <int>[];
  for (final item in value) {
    if (item is! int) {
      throw StateError('$location: $key must contain only integers');
    }
    result.add(item);
  }
  return result;
}

bool _chainFlag(Object? value, String location) {
  if (value is bool) {
    return value;
  }
  if (value is List<Object?> && value.isEmpty) {
    // Python's boolean `and` expression leaks `[]` for a first token. The Dart
    // API deliberately projects that falsey value onto its typed bool field.
    return false;
  }
  throw StateError('$location: chain_flag must be a bool or an empty array');
}

void _expectExactKeys(
  Map<String, Object?> map,
  Set<String> expected,
  String location,
) {
  final actual = map.keys.toSet();
  if (!actual.containsAll(expected) || !expected.containsAll(actual)) {
    fail('$location: expected keys $expected, got $actual');
  }
}

final class _FixtureJapaneseFrontend implements JapaneseFrontendBackend {
  _FixtureJapaneseFrontend(PyopenjtalkFixtureBackendInput input)
    : _words = List<JapaneseFrontendWord>.unmodifiable(
        input.words.map<JapaneseFrontendWord>(
          (word) => JapaneseFrontendWord(
            surface: word.surface,
            partOfSpeech: word.partOfSpeech,
            pronunciation: word.pronunciation,
            accent: word.accent,
            moraSize: word.moraSize,
            chainFlag: word.rawChainFlag == 1,
          ),
        ),
      );

  final List<JapaneseFrontendWord> _words;

  @override
  final BackendInfo info = BackendInfo(name: 'pyopenjtalk', version: '0.4.1');

  final List<String> inputs = <String>[];
  int analyzeCalls = 0;

  @override
  List<JapaneseFrontendWord> analyze(String text) {
    analyzeCalls++;
    inputs.add(text);
    return _words;
  }
}

const Set<String> _tokenKeys = <String>{
  '_',
  'end_ts',
  'phonemes',
  'start_ts',
  'tag',
  'text',
  'whitespace',
};

const Set<String> _metadataKeys = <String>{
  'acc',
  'accents',
  'chain_flag',
  'mora_size',
  'moras',
  'pitch',
  'pron',
};
