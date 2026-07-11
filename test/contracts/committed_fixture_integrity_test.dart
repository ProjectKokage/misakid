import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../support/upstream_fixture.dart';

void main() {
  final directory = Directory(
    '${Directory.current.path}/test/fixtures/upstream/'
    'fba1236595f2d2bf21d414ba6e57d25256afada3',
  );

  test('all committed JSONL fixtures satisfy the pinned schema', () {
    final files =
        directory
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.jsonl'))
            .toList(growable: false)
          ..sort((left, right) => left.path.compareTo(right.path));

    expect(
      files.map((file) => file.uri.pathSegments.last),
      containsAll(<String>[
        'en_american_espeak_fallback.jsonl',
        'en_american_no_fallback.jsonl',
        'en_american_no_fallback_adversarial.jsonl',
        'en_american_trf_espeak_fallback.jsonl',
        'en_american_trf_no_fallback.jsonl',
        'en_british_espeak_fallback.jsonl',
        'en_british_no_fallback.jsonl',
        'en_british_no_fallback_adversarial.jsonl',
        'en_british_trf_espeak_fallback.jsonl',
        'en_british_trf_no_fallback.jsonl',
        'ja_num2kana.jsonl',
        'ja_pyopenjtalk.jsonl',
        'ko_g2pkc_default.jsonl',
        'zh_frontend_1_1_en_small_no_fallback.jsonl',
        'zh_legacy.jsonl',
      ]),
    );

    final caseIds = <String>{};
    final expectedFailures = <String>[];
    for (final file in files) {
      for (final fixture in readUpstreamFixtures(file)) {
        if (fixture.errorCategory != null) {
          expectedFailures.add(
            '${fixture.language}/${fixture.caseId}:${fixture.errorCategory}',
          );
        }
        final caseId = fixture.caseId;
        expect(caseId, isNotNull, reason: file.path);
        final englishModel = fixture.language == 'en'
            ? fixture.options['trf'] == true
                  ? 'trf'
                  : 'small'
            : '';
        expect(
          caseIds.add(
            '${fixture.language}/${fixture.mode}/$englishModel/$caseId',
          ),
          isTrue,
          reason: 'duplicate case id in ${file.path}',
        );
      }
    }
    expect(expectedFailures, <String>[
      'ja/long-number-diagnostic:upstreamFailure',
      'ja/whitespace-only:upstreamFailure',
      'ko/numeral-place-limit:upstreamFailure',
      'zh/cjk-upper-bound:upstreamFailure',
      'zh/custom-unknown:upstreamFailure',
    ]);
  });

  test('aggregate verifier manifest covers every committed fixture', () {
    final manifest =
        jsonDecode(
              File(
                '${Directory.current.path}/tool/reference/'
                'accepted_fixtures.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    expect(manifest.keys.toSet(), <String>{
      'fixtures',
      'schemaVersion',
      'upstreamCommit',
    });
    expect(manifest['schemaVersion'], 1);
    expect(
      manifest['upstreamCommit'],
      'fba1236595f2d2bf21d414ba6e57d25256afada3',
    );
    final entries = manifest['fixtures']! as List<Object?>;
    final expectedPaths = <String>{};
    var caseCount = 0;
    for (final rawEntry in entries) {
      final entry = rawEntry! as Map<String, Object?>;
      expect(entry.keys.toSet(), <String>{
        'caseCount',
        'expected',
        'input',
        'language',
        'pythonKey',
      });
      final expected = File(entry['expected']! as String);
      final input = File(entry['input']! as String);
      final declaredCount = entry['caseCount']! as int;
      expect(expected.existsSync(), isTrue, reason: expected.path);
      expect(input.existsSync(), isTrue, reason: input.path);
      expect(
        expected.readAsLinesSync().where((line) => line.isNotEmpty),
        hasLength(declaredCount),
        reason: expected.path,
      );
      expect(expectedPaths.add(expected.absolute.path), isTrue);
      caseCount += declaredCount;
    }
    expect(caseCount, 431);
    expect(
      expectedPaths,
      directory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.jsonl'))
          .map((file) => file.absolute.path)
          .toSet(),
    );
  });

  test('English fixtures record the exact provisioned backend versions', () {
    for (final entry in <String, int>{
      'en_american_no_fallback.jsonl': 32,
      'en_british_no_fallback.jsonl': 32,
      'en_american_no_fallback_adversarial.jsonl': 21,
      'en_british_no_fallback_adversarial.jsonl': 21,
    }.entries) {
      final name = entry.key;
      final fixtures = readUpstreamFixtures(File('${directory.path}/$name'));

      expect(fixtures, hasLength(entry.value), reason: name);
      for (final fixture in fixtures) {
        expect(fixture.backendVersions, <String, Object?>{
          'en-core-web-sm': '3.8.0',
          'num2words': '0.5.14',
          'spacy': '3.8.4',
        }, reason: fixture.label);
      }
    }
  });

  test('English adversarial controls capture every number-flag branch', () {
    for (final name in <String>[
      'en_american_no_fallback_adversarial.jsonl',
      'en_british_no_fallback_adversarial.jsonl',
    ]) {
      final record = File('${directory.path}/$name')
          .readAsLinesSync()
          .map((line) => jsonDecode(line) as Map<String, Object?>)
          .singleWhere((record) => record['caseId'] == 'adv-number-flags');
      final backendInput = record['backendInput']! as Map<String, Object?>;
      final preprocess = backendInput['preprocess']! as Map<String, Object?>;
      final features = preprocess['features']! as List<Object?>;
      final rawTokens = backendInput['tokens']! as List<Object?>;

      expect(
        features
            .map((raw) => (raw! as Map<String, Object?>)['sourceWordIndex'])
            .toList(growable: false),
        <int>[0, 1, 2, 3, 4],
        reason: name,
      );
      expect(
        features
            .map((raw) => (raw! as Map<String, Object?>)['value'])
            .toList(growable: false),
        <String>['#a', '#&', '#n', '#o', '#an'],
        reason: name,
      );
      expect(
        rawTokens
            .map(
              (raw) =>
                  ((raw! as Map<String, Object?>)['_']!
                      as Map<String, Object?>)['num_flags'],
            )
            .toList(growable: false),
        <String>['a', '&', 'n', 'o', 'an'],
        reason: name,
      );
    }
  });

  test('English eSpeak fixtures pin raw backend calls and resources', () {
    const backendVersions = <String, Object?>{
      'en-core-web-sm': '3.8.0',
      'espeakng-data':
          'sha256:730e20a0d06976b23b8344bac21dab6e1da447d0e16906bab6a0b54db89dd6e2+files:364+bytes:18373365',
      'espeakng-library':
          'sha256:bb635eee1ee9c456f4a5cf06fb6cb352ecdd4d61e1951743b423ef22bb57f470+bytes:504168',
      'espeakng-loader': '0.2.4',
      'joblib': '1.4.2',
      'num2words': '0.5.14',
      'phonemizer-fork': '3.3.2',
      'python': '3.12.11',
      'spacy': '3.8.4',
    };
    for (final stem in <String>[
      'en_american_espeak_fallback',
      'en_british_espeak_fallback',
    ]) {
      final fixtureFile = File('${directory.path}/$stem.jsonl');
      final fixtures = readUpstreamFixtures(fixtureFile);
      expect(fixtures, hasLength(20), reason: stem);
      for (final fixture in fixtures) {
        expect(fixture.backendVersions, backendVersions, reason: fixture.label);
      }
      final inputs = fixtures
          .map((fixture) => fixture.backendInput! as EnglishFixtureBackendInput)
          .toList(growable: false);
      expect(
        inputs.fold<int>(0, (total, input) => total + input.tokens.length),
        43,
        reason: stem,
      );
      expect(
        inputs.fold<int>(
          0,
          (total, input) => total + input.espeakCalls!.length,
        ),
        29,
        reason: stem,
      );

      final provenance =
          jsonDecode(
                File(
                  '${directory.path}/$stem.provenance.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      final captured = provenance['backendInput']! as Map<String, Object?>;
      expect(
        sha256.convert(fixtureFile.readAsBytesSync()).toString(),
        provenance['fixtureSha256'],
        reason: stem,
      );
      expect(provenance, containsPair('caseCount', 20), reason: stem);
      expect(captured, containsPair('schemaVersion', 2), reason: stem);
      expect(captured, containsPair('rawTokenCount', 43), reason: stem);
      expect(captured, containsPair('espeakCallCount', 29), reason: stem);
    }
  });

  test('English transformer eSpeak fixtures pin model, fallback, and lock', () {
    const backendVersions = <String, Object?>{
      'en-core-web-trf': '3.8.0',
      'espeakng-data':
          'sha256:730e20a0d06976b23b8344bac21dab6e1da447d0e16906bab6a0b54db89dd6e2+files:364+bytes:18373365',
      'espeakng-library':
          'sha256:bb635eee1ee9c456f4a5cf06fb6cb352ecdd4d61e1951743b423ef22bb57f470+bytes:504168',
      'espeakng-loader': '0.2.4',
      'joblib': '1.4.2',
      'num2words': '0.5.14',
      'phonemizer-fork': '3.3.2',
      'python': '3.12.11',
      'spacy': '3.8.4',
    };
    const identities = <String, ({String corpusSha256, String fixtureSha256})>{
      'en_american_trf_espeak_fallback': (
        corpusSha256:
            '9b85a80e6eff9787e5cfbb301b800e1c81f965bed83255443b8569a283738339',
        fixtureSha256:
            'b9e6c575c229a860ec1ad058a3e19d13c8c37b87e1da160e056f2ed40919c8bc',
      ),
      'en_british_trf_espeak_fallback': (
        corpusSha256:
            'a1eb07bd3cbfbb39a61ecc6140dfd2c48ad85436a16f02f9d6c32c38a011efc7',
        fixtureSha256:
            'ffd7728b6f2c144997d938a95ef51ecabbc979baffc92e5c2b736336c1aaaeba',
      ),
    };
    final dependencyLock = File(
      '${Directory.current.path}/tool/reference/'
      'requirements-en-trf-espeak-py312.txt',
    );
    const dependencyLockSha256 =
        'a6b1d7ab358f2627aa40d5cda684bc0da42bb3dbabd6072288d5e458a1ff0542';
    expect(
      sha256.convert(dependencyLock.readAsBytesSync()).toString(),
      dependencyLockSha256,
    );
    expect(
      dependencyLock
          .readAsLinesSync()
          .where((line) => line.startsWith('joblib=='))
          .toList(growable: false),
      <String>['joblib==1.4.2'],
    );

    for (final entry in identities.entries) {
      final stem = entry.key;
      final fixture = File('${directory.path}/$stem.jsonl');
      final corpus = File(
        '${Directory.current.path}/tool/reference/cases/$stem.jsonl',
      );
      final fixtures = readUpstreamFixtures(fixture);
      expect(fixtures, hasLength(20), reason: stem);
      expect(
        fixtures.map((item) => item.caseId).toSet(),
        hasLength(20),
        reason: stem,
      );
      expect(
        fixtures.every((item) => item.options['trf'] == true),
        isTrue,
        reason: stem,
      );
      for (final item in fixtures) {
        expect(item.backendVersions, backendVersions, reason: item.label);
      }
      final backendInputs = fixtures
          .map((item) => item.backendInput! as EnglishFixtureBackendInput)
          .toList(growable: false);
      expect(
        backendInputs.fold<int>(
          0,
          (total, input) => total + input.tokens.length,
        ),
        43,
        reason: stem,
      );
      expect(
        backendInputs.fold<int>(
          0,
          (total, input) => total + input.espeakCalls!.length,
        ),
        25,
        reason: stem,
      );
      expect(
        sha256.convert(corpus.readAsBytesSync()).toString(),
        entry.value.corpusSha256,
        reason: stem,
      );
      expect(
        sha256.convert(fixture.readAsBytesSync()).toString(),
        entry.value.fixtureSha256,
        reason: stem,
      );

      final provenance =
          jsonDecode(
                File(
                  '${directory.path}/$stem.provenance.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      final captured = provenance['backendInput']! as Map<String, Object?>;
      final model = provenance['model']! as Map<String, Object?>;
      expect(provenance['backendVersions'], backendVersions, reason: stem);
      expect(provenance, containsPair('caseCount', 20), reason: stem);
      expect(
        provenance,
        containsPair('caseCorpusSha256', entry.value.corpusSha256),
        reason: stem,
      );
      expect(
        provenance,
        containsPair('fixtureSha256', entry.value.fixtureSha256),
        reason: stem,
      );
      expect(
        provenance,
        containsPair(
          'dependencyLock',
          'tool/reference/requirements-en-trf-espeak-py312.txt',
        ),
        reason: stem,
      );
      expect(
        provenance,
        containsPair('dependencyLockSha256', dependencyLockSha256),
        reason: stem,
      );
      expect(captured, containsPair('schemaVersion', 2), reason: stem);
      expect(captured, containsPair('rawTokenCount', 43), reason: stem);
      expect(captured, containsPair('espeakCallCount', 25), reason: stem);
      expect(model, containsPair('sizeBytes', 457421864), reason: stem);
      expect(
        model,
        containsPair(
          'sha256',
          '272a31e9d8530d1e075351d30a462d7e80e31da23574f1b274e200f3fff35bf5',
        ),
        reason: stem,
      );
      expect(
        model,
        containsPair(
          'inventorySha256',
          '4e3cae8256e9e701739cdbd720ffe5f3047202e4a0ebace4bc469a33b1ae7eba',
        ),
        reason: stem,
      );
    }
  });

  test('British case corpus changes only the requested mode', () {
    List<Map<String, Object?>> records(String name) =>
        File('${Directory.current.path}/tool/reference/cases/$name')
            .readAsLinesSync()
            .map((line) => jsonDecode(line) as Map<String, Object?>)
            .toList(growable: false);

    for (final suffix in <String>['', '_adversarial']) {
      final american = records('en_american_no_fallback$suffix.jsonl');
      final british = records('en_british_no_fallback$suffix.jsonl');
      final expectedCount = suffix.isEmpty ? 32 : 21;
      expect(american, hasLength(expectedCount));
      expect(british, hasLength(expectedCount));
      for (var index = 0; index < american.length; index++) {
        final us = Map<String, Object?>.of(american[index]);
        final gb = Map<String, Object?>.of(british[index]);
        expect(us.remove('mode'), 'american-no-fallback');
        expect(gb.remove('mode'), 'british-no-fallback');
        expect(gb, us, reason: '$suffix case record ${index + 1}');
      }
    }
  });

  test('British fixture reuses the exact raw token stream', () {
    List<Map<String, Object?>> records(String name) =>
        File('${directory.path}/$name')
            .readAsLinesSync()
            .map((line) => jsonDecode(line) as Map<String, Object?>)
            .toList(growable: false);

    for (final suffix in <String>['', '_adversarial']) {
      final american = records('en_american_no_fallback$suffix.jsonl');
      final british = records('en_british_no_fallback$suffix.jsonl');
      final expectedCount = suffix.isEmpty ? 32 : 21;
      expect(american, hasLength(expectedCount));
      expect(british, hasLength(expectedCount));
      for (var index = 0; index < american.length; index++) {
        final us = american[index];
        final gb = british[index];
        expect(us['mode'], 'american-no-fallback');
        expect(gb['mode'], 'british-no-fallback');
        for (final key in <String>[
          'backendInput',
          'backendVersions',
          'caseId',
          'input',
          'options',
          'schemaVersion',
          'upstreamCommit',
          'upstreamRepository',
          'upstreamVersion',
        ]) {
          expect(gb[key], us[key], reason: '${gb['caseId']} field $key');
        }
      }
    }
  });

  test('English provenance pins both accepted fixture byte streams', () {
    for (final entry in <String, int>{
      'en_american_no_fallback': 154,
      'en_british_no_fallback': 154,
      'en_american_no_fallback_adversarial': 175,
      'en_british_no_fallback_adversarial': 175,
    }.entries) {
      final stem = entry.key;
      final fixture = File('${directory.path}/$stem.jsonl');
      final provenance =
          jsonDecode(
                File(
                  '${directory.path}/$stem.provenance.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      final backendInput = provenance['backendInput']! as Map<String, Object?>;

      expect(
        sha256.convert(fixture.readAsBytesSync()).toString(),
        provenance['fixtureSha256'],
        reason: stem,
      );
      expect(
        provenance,
        containsPair('caseCount', stem.endsWith('_adversarial') ? 21 : 32),
        reason: stem,
      );
      expect(backendInput, containsPair('schemaVersion', 1), reason: stem);
      expect(
        backendInput,
        containsPair('rawTokenCount', entry.value),
        reason: stem,
      );
      expect(
        sha256
            .convert(
              File(
                '${Directory.current.path}/tool/reference/cases/$stem.jsonl',
              ).readAsBytesSync(),
            )
            .toString(),
        provenance['caseCorpusSha256'],
        reason: stem,
      );
    }
  });

  test('English transformer fixtures pin exact model and token streams', () {
    const backendVersions = <String, Object?>{
      'en-core-web-trf': '3.8.0',
      'num2words': '0.5.14',
      'spacy': '3.8.4',
    };
    final fixtureRecords = <List<Map<String, Object?>>>[];
    for (final stem in <String>[
      'en_american_trf_no_fallback',
      'en_british_trf_no_fallback',
    ]) {
      final fixture = File('${directory.path}/$stem.jsonl');
      final fixtures = readUpstreamFixtures(fixture);
      expect(fixtures, hasLength(38), reason: stem);
      expect(
        fixtures.fold<int>(
          0,
          (total, item) =>
              total +
              (item.backendInput! as EnglishFixtureBackendInput).tokens.length,
        ),
        1096,
        reason: stem,
      );
      for (final item in fixtures) {
        expect(item.backendVersions, backendVersions, reason: item.label);
        expect(item.options['trf'], isTrue, reason: item.label);
      }

      final provenance =
          jsonDecode(
                File(
                  '${directory.path}/$stem.provenance.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      final model = provenance['model']! as Map<String, Object?>;
      expect(
        sha256.convert(fixture.readAsBytesSync()).toString(),
        provenance['fixtureSha256'],
        reason: stem,
      );
      expect(provenance, containsPair('caseCount', 38), reason: stem);
      expect(model, containsPair('sizeBytes', 457421864), reason: stem);
      expect(
        model,
        containsPair(
          'sha256',
          '272a31e9d8530d1e075351d30a462d7e80e31da23574f1b274e200f3fff35bf5',
        ),
        reason: stem,
      );
      expect(
        sha256
            .convert(
              File(
                '${Directory.current.path}/'
                '${model['inventory']! as String}',
              ).readAsBytesSync(),
            )
            .toString(),
        model['inventorySha256'],
        reason: stem,
      );
      fixtureRecords.add(
        fixture
            .readAsLinesSync()
            .map((line) => jsonDecode(line) as Map<String, Object?>)
            .toList(growable: false),
      );
    }

    for (var index = 0; index < fixtureRecords.first.length; index++) {
      expect(
        fixtureRecords.last[index]['backendInput'],
        fixtureRecords.first[index]['backendInput'],
        reason: 'transformer record ${index + 1}',
      );
    }
  });

  test('Korean fixture records exact morphology and CMUdict resources', () {
    final fixtures = readUpstreamFixtures(
      File('${directory.path}/ko_g2pkc_default.jsonl'),
    );

    expect(fixtures, hasLength(34));
    for (final fixture in fixtures) {
      expect(fixture.backendVersions, <String, Object?>{
        'jamo': '0.4.1',
        'nltk': '3.9.1',
        'nltk-cmudict':
            '0.7a+sha256:'
            'd07cca47fd72ad32ea9d8ad1219f85301eeaf4568f8b6b73747506a71fb5afd6',
        'python-mecab-ko': '1.3.7',
        'python-mecab-ko-dic': '2.1.1.post2',
      });
      expect(fixture.backendInput, isA<KoreanFixtureBackendInput>());
      expect(fixture.tokens, isNull);
    }
    expect(
      <String, List<String>>{
        for (final fixture in fixtures)
          if ((fixture.backendInput as KoreanFixtureBackendInput)
              .cmuLookups
              .isNotEmpty)
            fixture.caseId!: <String>[
              for (final lookup
                  in (fixture.backendInput as KoreanFixtureBackendInput)
                      .cmuLookups)
                '${lookup.key}:${lookup.arpabet?.join(' ') ?? '<miss>'}',
            ],
      },
      <String, List<String>>{
        'english-cmudict': <String>[
          'school:S K UW1 L',
          'game:G EY1 M',
          'file:F AY1 L',
          'old:OW1 L D',
        ],
        'mixed-english': <String>['game:G EY1 M', 'file:F AY1 L'],
        'english-acronyms': <String>['file:F AY1 L'],
        'english-unknown': <String>['qzxxw:<miss>'],
        'english-arpabet-branches': <String>[
          'yellowstone:Y EH1 L OW0 S T OW2 N',
          'underworld:AH1 N D ER0 W ER2 L D',
          'visionary:V IH1 ZH AH0 N EH2 R IY0',
          'judgment:JH AH1 JH M AH0 N T',
          'nothing:N AH1 TH IH0 NG',
          'church:CH ER1 CH',
          'power:P AW1 ER0',
          'bags:B AE1 G Z',
        ],
        'english-overlap-case': <String>[
          'friendship:F R EH1 N D SH IH0 P',
          'scatter:S K AE1 T ER0',
          'game:G EY1 M',
          'game:G EY1 M',
          'cat:K AE1 T',
        ],
        'english-adjacent-vowels': <String>[
          'abbreviate:AH0 B R IY1 V IY0 EY2 T',
          'abiola:AA2 B IY0 OW1 L AH0',
        ],
      },
    );
  });

  test('Korean provenance pins the accepted fixture bytes and schema', () {
    final fixture = File('${directory.path}/ko_g2pkc_default.jsonl');
    final provenance =
        jsonDecode(
              File(
                '${directory.path}/ko_g2pkc_default.provenance.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final backendInput = provenance['backendInput']! as Map<String, Object?>;

    expect(
      sha256.convert(fixture.readAsBytesSync()).toString(),
      provenance['fixtureSha256'],
    );
    expect(
      sha256
          .convert(
            File(
              '${Directory.current.path}/tool/reference/cases/'
              'ko_g2pkc_default.jsonl',
            ).readAsBytesSync(),
          )
          .toString(),
      provenance['caseCorpusSha256'],
    );
    expect(provenance, containsPair('caseCount', 34));
    expect(provenance, containsPair('successCount', 33));
    expect(provenance['expectedFailures'], <Object?>[
      <String, Object?>{
        'caseId': 'numeral-place-limit',
        'category': 'upstreamFailure',
        'cause':
            'Pinned process_num leaves name unbound for a nonzero digit at '
            'position 16',
      },
    ]);
    expect(backendInput, containsPair('schemaVersion', 2));
    expect(backendInput, containsPair('rawAnalyzerTokenCount', 293));
    expect(backendInput, containsPair('cmuLookupCount', 23));
    expect(backendInput, containsPair('cmuMissCount', 1));
    expect(provenance['numeralDifferential'], <String, Object?>{
      'caseCount': 4096,
      'mismatchCount': 0,
      'pythonHashSeed': '0',
      'pythonVersion': '3.12.11',
      'coverage': <Object?>[
        'overlapping bare numerals and repeated prefixes',
        'comma-grouped and Unicode decimal numerals',
        'spaced, unspaced, repeated, and overlapping bound nouns',
      ],
    });
  });

  test('Chinese legacy fixture pins exact external stages and resources', () {
    final fixture = File('${directory.path}/zh_legacy.jsonl');
    final fixtures = readUpstreamFixtures(fixture);
    final expectedVersions = <String, Object?>{
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

    expect(fixtures, hasLength(24));
    expect(
      fixtures.where((fixture) => fixture.errorCategory == null),
      hasLength(22),
    );
    for (final fixture in fixtures) {
      expect(fixture.language, 'zh', reason: fixture.label);
      expect(fixture.mode, 'legacy', reason: fixture.label);
      expect(fixture.backendVersions, expectedVersions, reason: fixture.label);
      expect(
        fixture.backendInput,
        isA<ChineseLegacyFixtureBackendInput>(),
        reason: fixture.label,
      );
      expect(fixture.tokens, isNull, reason: fixture.label);
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
          'caseId': 'custom-unknown',
          'options': <String, Object?>{'unk': '<?>'},
        },
      ],
    );

    final provenance =
        jsonDecode(
              File(
                '${directory.path}/zh_legacy.provenance.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final backendInput = provenance['backendInput']! as Map<String, Object?>;
    final resources = provenance['resources']! as List<Object?>;
    expect(
      sha256.convert(fixture.readAsBytesSync()).toString(),
      provenance['fixtureSha256'],
    );
    expect(
      sha256
          .convert(
            File(
              '${Directory.current.path}/tool/reference/cases/'
              'zh_legacy.jsonl',
            ).readAsBytesSync(),
          )
          .toString(),
      provenance['caseCorpusSha256'],
    );
    expect(provenance, containsPair('caseCount', 24));
    expect(provenance, containsPair('successCount', 22));
    expect(provenance['backendVersions'], expectedVersions);
    expect(backendInput, <String, Object?>{
      'kind': ChineseLegacyFixtureBackendInput.kind,
      'normalizationCallCount': 22,
      'pinyinCallCount': 82,
      'pinyinSyllableCount': 152,
      'rawSegmentedWordCount': 82,
      'runCount': 41,
      'schemaVersion': ChineseLegacyFixtureBackendInput.schemaVersion,
    });
    expect(resources, <Object?>[
      <String, Object?>{
        'distribution': 'jieba 0.42.1',
        'distributionLicense': 'MIT',
        'name': 'jieba default dict.txt',
        'sha256':
            '7197c3211ddd98962b036cdf40324d1ea2bfaa12bd028e68faa70111a88e12a8',
        'sizeBytes': 5071852,
      },
    ]);
    expect(provenance['expectedFailures'], <Object?>[
      <String, Object?>{
        'caseId': 'cjk-upper-bound',
        'category': 'upstreamFailure',
        'cause':
            'Pinned transcription rejects pypinyin fallback syllable `鿿5`: '
            "ValueError: Parameter 'normal_pinyin': Final couldn't be "
            'detected!',
      },
      <String, Object?>{
        'caseId': 'custom-unknown',
        'category': 'upstreamFailure',
        'cause':
            'Pinned transcription rejects pypinyin fallback syllable `鿿5`: '
            "ValueError: Parameter 'normal_pinyin': Final couldn't be "
            'detected!',
      },
    ]);
  });

  test('Chinese English callback fixture pins its combined oracle', () {
    final fixture = File(
      '${directory.path}/zh_frontend_1_1_en_small_no_fallback.jsonl',
    );
    final fixtures = readUpstreamFixtures(fixture);
    const expectedVersions = <String, Object?>{
      'addict': '2.4.0',
      'cn2an': '0.5.23',
      'en-core-web-sm': '3.8.0',
      'jieba': '0.42.1',
      'jieba-default-dict':
          'sha256:'
          '7197c3211ddd98962b036cdf40324d1ea2bfaa12bd028e68faa70111a88e12a8',
      'num2words': '0.5.14',
      'ordered-set': '4.1.0',
      'proces': '0.1.7',
      'pypinyin': '0.53.0',
      'pypinyin-dict': '0.9.0',
      'python': '3.12.11',
      'regex': '2024.11.6',
      'spacy': '3.8.4',
    };

    expect(fixtures, hasLength(14));
    var callbackCalls = 0;
    var rawTokens = 0;
    var finalTokens = 0;
    for (final fixture in fixtures) {
      expect(fixture.language, 'zh', reason: fixture.label);
      expect(
        fixture.mode,
        'frontend-1.1-en-small-no-fallback',
        reason: fixture.label,
      );
      expect(fixture.backendVersions, expectedVersions, reason: fixture.label);
      expect(fixture.tokens, isNull, reason: fixture.label);
      final backendInput =
          fixture.backendInput! as ChineseFrontendEnglishFixtureBackendInput;
      callbackCalls += backendInput.english.calls.length;
      for (final call in backendInput.english.calls) {
        rawTokens += call.backendInput.tokens.length;
        finalTokens += call.tokens.length;
      }
    }
    expect(callbackCalls, 14);
    expect(rawTokens, 40);
    expect(finalTokens, 33);

    final provenance =
        jsonDecode(
              File(
                '${directory.path}/'
                'zh_frontend_1_1_en_small_no_fallback.provenance.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final backendInput = provenance['backendInput']! as Map<String, Object?>;
    final locks = provenance['dependencyLocks']! as List<Object?>;
    final resources = provenance['resources']! as List<Object?>;
    expect(
      sha256.convert(fixture.readAsBytesSync()).toString(),
      provenance['fixtureSha256'],
    );
    expect(
      sha256
          .convert(
            File(
              '${Directory.current.path}/tool/reference/cases/'
              'zh_frontend_1_1_en_small_no_fallback.jsonl',
            ).readAsBytesSync(),
          )
          .toString(),
      provenance['caseCorpusSha256'],
    );
    expect(provenance, containsPair('caseCount', 14));
    expect(provenance, containsPair('successCount', 14));
    expect(provenance['expectedFailures'], isEmpty);
    expect(provenance['backendVersions'], expectedVersions);
    expect(backendInput, <String, Object?>{
      'callbackCallCount': 14,
      'finalEnglishTokenCount': 33,
      'kind': ChineseFrontendEnglishFixtureBackendInput.kind,
      'rawEnglishTokenCount': 40,
      'schemaVersion': ChineseFrontendEnglishFixtureBackendInput.schemaVersion,
    });
    for (final rawLock in locks) {
      final lock = rawLock! as Map<String, Object?>;
      expect(
        sha256
            .convert(File(lock['path']! as String).readAsBytesSync())
            .toString(),
        lock['sha256'],
        reason: lock['path']! as String,
      );
    }
    expect(locks, hasLength(3));
    expect(
      <String, String>{
        for (final rawResource in resources)
          (rawResource! as Map<String, Object?>)['name']! as String:
              (rawResource as Map<String, Object?>)['sha256']! as String,
      },
      const <String, String>{
        'jieba/dict.txt':
            '7197c3211ddd98962b036cdf40324d1ea2bfaa12bd028e68faa70111a88e12a8',
        'jieba/finalseg/prob_start.p':
            'dfd45976dd4f8f2bc12535a680a178bf9e75eaa38bdfdcb844469e54468d6245',
        'jieba/finalseg/prob_trans.p':
            'ea7f50162ffa01db4973c7a8120b3c0233fbc5819fc0d617513535f1f2c7fedc',
        'jieba/finalseg/prob_emit.p':
            '1e1d1d835b0c77d234acaa6afa23a13ffce597a295be0d7a1ece6a0d440dcf08',
        'jieba/posseg/char_state_tab.p':
            'c0ef4bb3d698eed188225d430ac291000b30c3d6e253a538d26b7ac9687424b1',
        'jieba/posseg/prob_start.p':
            '0fb0fbc6b1840d35a5a8499cff0ae75e06af788e348f9b4b8b9630804cd6cf09',
        'jieba/posseg/prob_trans.p':
            '236726f5a4efc2f023652925ca1e94f1fe4bfcb9d60224e9db3de0135b21385b',
        'jieba/posseg/prob_emit.p':
            '449b2304b6c73034187d3c8a6f26a7a20037f4ab45659844acd0ef2114171fa8',
        'pypinyin/pinyin_dict.json':
            '19ac93a11b0cf2d1b42741c2956dcb8632944e87d2ebcd1ba7cc4d3a936b9fb5',
        'pypinyin/phrases_dict.json':
            'd71fe97165dfd3eb9d8dff86ce5f62787d530b6b9f38c898779fcaf16d2522d1',
        'phrase-pinyin-data/large_pinyin.txt':
            'f1f00a0682120f4052eb9ab03c632b040677dd9675bade5b8cb6a3bb7c0b8fd3',
        'en_core_web_sm/tokenizer':
            'b014e8bba4958b120af2d0c1c63eabb7c00379f2bacaf10df7c5325efd2ea467',
        'en_core_web_sm/vocab/lookups.bin':
            'fce9c883c56165f29573cc938c2a1c9d417ac61bd8f56b671dd5f7996de70682',
        'en_core_web_sm/tok2vec/model':
            'e84fc06eb319c94d28e460fc334e292120b01f18baa5dc8b50c977459820a090',
        'en_core_web_sm/tagger/model':
            '1ec3d93f38cebe172f2b5c89d84be72856ce42c8f1a64f1699f1d98a771f36b7',
      },
    );
    final exporter = provenance['exporter']! as Map<String, Object?>;
    expect(
      sha256
          .convert(File(exporter['path']! as String).readAsBytesSync())
          .toString(),
      exporter['sha256'],
    );
    final provisioning =
        provenance['oracleProvisioning']! as Map<String, Object?>;
    final recordCopy = provisioning['recordCopy']! as Map<String, Object?>;
    expect(
      sha256
          .convert(File(recordCopy['tool']! as String).readAsBytesSync())
          .toString(),
      recordCopy['toolSha256'],
    );
    expect(
      (provenance['modelWheel']! as Map<String, Object?>)['sha256'],
      '1932429db727d4bff3deed6b34cfc05df17794f4a52eeb26cf8928f7c1a0fb85',
    );
    expect(
      (provenance['oracleVerification']! as Map<String, Object?>),
      containsPair('mismatchCount', 0),
    );
  });
}
