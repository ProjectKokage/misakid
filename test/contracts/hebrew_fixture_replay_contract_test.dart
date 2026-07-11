import 'dart:convert';

import 'package:misakid/misaki_he.dart';
import 'package:test/test.dart';

import '../support/upstream_fixture.dart';

void main() {
  test('synthetic fixture records replay exact text and option calls', () {
    final fixtures = <UpstreamFixture>[
      _fixture(const <String, Object?>{}),
      _fixture(const <String, Object?>{'preserve_punctuation': false}),
      _fixture(const <String, Object?>{'preserve_stress': false}),
      _fixture(const <String, Object?>{
        'preserve_punctuation': false,
        'preserve_stress': false,
      }),
    ];

    for (final fixture in fixtures) {
      expect(fixture.language, 'he');
      expect(fixture.mode, 'default');
      expect(fixture.backendInput, isNull);
      expect(fixture.tokens, isNull);
      expect(fixture.errorCategory, isNull);

      final preservePunctuation = _boolOption(
        fixture,
        'preserve_punctuation',
        defaultValue: true,
      );
      final preserveStress = _boolOption(
        fixture,
        'preserve_stress',
        defaultValue: true,
      );
      final backend = _StrictFixtureHebrewBackend(
        fixture: fixture,
        preservePunctuation: preservePunctuation,
        preserveStress: preserveStress,
      );
      final result = HebrewG2pEngine(
        backend: backend,
        options: HebrewOptions(
          preservePunctuation: preservePunctuation,
          preserveStress: preserveStress,
        ),
      ).convert(fixture.input);

      expect(result.phonemes, fixture.phonemes);
      expect(result.tokens, isNull);
      expect(backend.calls, 1);
    }
  });

  test('synthetic replay rejects non-boolean fixture options', () {
    final fixture = _fixture(const <String, Object?>{
      'preserve_stress': 'false',
    });

    expect(
      () => _boolOption(fixture, 'preserve_stress', defaultValue: true),
      throwsStateError,
    );
  });
}

UpstreamFixture _fixture(Map<String, Object?> options) {
  final suffix = options.entries
      .map((entry) => '${entry.key}=${entry.value}')
      .join(',');
  return UpstreamFixture.parse(
    jsonEncode(<String, Object?>{
      'backendVersions': <String, Object?>{
        'colorlog': '6.9.0',
        'docopt': '0.6.2',
        'mishkal-hebrew': '0.3.2',
        'num2words': '0.5.14',
        'python': '3.12.11',
      },
      'caseId': 'synthetic-$suffix',
      'input': 'synthetic-hebrew-input',
      'language': 'he',
      'mode': 'default',
      'options': options,
      'phonemes': 'synthetic-phoneme-output',
      'schemaVersion': 1,
      'tokens': null,
      'upstreamCommit': misakiUpstreamCommit,
      'upstreamRepository': misakiUpstreamRepository,
      'upstreamVersion': misakiUpstreamVersion,
    }),
    location: 'synthetic-hebrew-record',
  );
}

bool _boolOption(
  UpstreamFixture fixture,
  String key, {
  required bool defaultValue,
}) {
  final value = fixture.options[key];
  if (value == null) {
    return defaultValue;
  }
  if (value is! bool) {
    throw StateError('${fixture.label}: $key must be a boolean');
  }
  return value;
}

final class _StrictFixtureHebrewBackend implements HebrewPhonemizerBackend {
  _StrictFixtureHebrewBackend({
    required this.fixture,
    required this.preservePunctuation,
    required this.preserveStress,
  });

  final UpstreamFixture fixture;
  final bool preservePunctuation;
  final bool preserveStress;
  int calls = 0;

  @override
  final BackendInfo info = BackendInfo(
    name: 'synthetic-fixture-mishkal',
    version: '0.3.2',
  );

  @override
  Set<String> phonemeInventory() => const <String>{'synthetic'};

  @override
  String phonemize(
    String text, {
    required bool preservePunctuation,
    required bool preserveStress,
  }) {
    calls++;
    if (calls != 1) {
      throw StateError('Synthetic fixture backend was called more than once.');
    }
    if (text != fixture.input ||
        preservePunctuation != this.preservePunctuation ||
        preserveStress != this.preserveStress) {
      throw StateError('Synthetic fixture call does not match its record.');
    }
    return fixture.phonemes!;
  }
}
