import 'dart:convert';
import 'dart:io';

import 'package:misakid_chinese/misakid_chinese.dart';
import 'package:test/test.dart';

void main() {
  final dictionaryPath =
      Platform.environment['MISAKID_CHINESE_JIEBA_DICTIONARY'];
  final probabilityStartPath =
      Platform.environment['MISAKID_CHINESE_JIEBA_PROB_START'];
  final probabilityTransitionPath =
      Platform.environment['MISAKID_CHINESE_JIEBA_PROB_TRANSITION'];
  final probabilityEmissionPath =
      Platform.environment['MISAKID_CHINESE_JIEBA_PROB_EMISSION'];
  final resourceSkip =
      <String?>[
        dictionaryPath,
        probabilityStartPath,
        probabilityTransitionPath,
        probabilityEmissionPath,
      ].any((path) => path == null)
      ? 'Set all four MISAKID_CHINESE_JIEBA_* resource paths.'
      : false;

  group(
    'provisioned jieba 0.42.1 resources',
    () {
      late JiebaSegmenter segmenter;
      late List<_CapturedRun> capturedRuns;

      setUpAll(() async {
        segmenter = await JiebaSegmenter.open(
          dictionaryPath: dictionaryPath!,
          probabilityStartPath: probabilityStartPath!,
          probabilityTransitionPath: probabilityTransitionPath!,
          probabilityEmissionPath: probabilityEmissionPath!,
        );
        capturedRuns = await _readCapturedRuns();
      });

      test('reports every exact immutable resource identity', () {
        expect(segmenter.info.name, 'jieba');
        expect(segmenter.info.version, '0.42.1');
        expect(segmenter.info.details, <String, String>{
          'mode': 'accurate-hmm',
          'dictionarySha256':
              '7197c3211ddd98962b036cdf40324d1ea2bfaa12bd028e68faa70111a88e12a8',
          'dictionarySizeBytes': '5071852',
          'dictionaryRecordCount': '349046',
          'frequencyEntryCount': '498113',
          'totalFrequency': '60101967',
          'probabilityStartSha256':
              'dfd45976dd4f8f2bc12535a680a178bf9e75eaa38bdfdcb844469e54468d6245',
          'probabilityTransitionSha256':
              'ea7f50162ffa01db4973c7a8120b3c0233fbc5819fc0d617513535f1f2c7fedc',
          'probabilityEmissionSha256':
              '1e1d1d835b0c77d234acaa6afa23a13ffce597a295be0d7a1ece6a0d440dcf08',
          'emissionEntryCount': '35224',
        });
      });

      test('all 41 captured legacy runs and 82 words match exactly', () {
        var wordCount = 0;
        for (final run in capturedRuns) {
          final actual = segmenter.segment(run.input);
          expect(actual, run.words, reason: run.caseId);
          expect(actual.join(), run.input, reason: run.caseId);
          wordCount += actual.length;
        }
        expect(capturedRuns, hasLength(41));
        expect(wordCount, 82);
      });
    },
    tags: 'provisioned',
    skip: resourceSkip,
  );

  final oraclePython = Platform.environment['MISAKI_ORACLE_ZH_PYTHON'];
  final oracleSkip = resourceSkip != false || oraclePython == null
      ? 'Set the four Jieba resources and MISAKI_ORACLE_ZH_PYTHON.'
      : false;
  test(
    'direct jieba 0.42.1 replay matches the pure-Dart segmenter',
    () async {
      final segmenter = await JiebaSegmenter.open(
        dictionaryPath: dictionaryPath!,
        probabilityStartPath: probabilityStartPath!,
        probabilityTransitionPath: probabilityTransitionPath!,
        probabilityEmissionPath: probabilityEmissionPath!,
      );
      final fixture = _fixtureFile();
      final result = await Process.run(
        oraclePython!,
        <String>['-c', _oracleScript, fixture.absolute.path],
        environment: <String, String>{
          ...Platform.environment,
          'PYTHONHASHSEED': '0',
        },
      );
      expect(result.exitCode, 0, reason: result.stderr as String);
      final rawRows = jsonDecode(result.stdout as String) as List<Object?>;
      final expected = <_CapturedRun>[];
      for (var index = 0; index < rawRows.length; index++) {
        final raw = rawRows[index]! as Map<String, Object?>;
        expected.add(
          _CapturedRun(
            caseId: raw['caseId']! as String,
            input: raw['input']! as String,
            words: List<String>.unmodifiable(
              (raw['words']! as List<Object?>).cast<String>(),
            ),
          ),
        );
      }
      expect(expected, hasLength(41));
      for (final run in expected) {
        expect(segmenter.segment(run.input), run.words, reason: run.caseId);
      }
    },
    tags: 'provisioned',
    skip: oracleSkip,
  );
}

Future<List<_CapturedRun>> _readCapturedRuns() async {
  final rows = <_CapturedRun>[];
  var lineNumber = 0;
  await for (final line
      in _fixtureFile()
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    lineNumber++;
    final fixture = jsonDecode(line) as Map<String, Object?>;
    final backendInput = fixture['backendInput']! as Map<String, Object?>;
    final rawRuns = backendInput['runs']! as List<Object?>;
    for (var runIndex = 0; runIndex < rawRuns.length; runIndex++) {
      final run = rawRuns[runIndex]! as Map<String, Object?>;
      final words = <String>[];
      for (final rawWord in run['words']! as List<Object?>) {
        words.add((rawWord! as Map<String, Object?>)['word']! as String);
      }
      rows.add(
        _CapturedRun(
          caseId: '${fixture['caseId']} run $runIndex',
          input: run['input']! as String,
          words: List<String>.unmodifiable(words),
        ),
      );
    }
  }
  if (lineNumber != 24) {
    throw StateError('Expected 24 Chinese legacy fixture records.');
  }
  return List<_CapturedRun>.unmodifiable(rows);
}

File _fixtureFile() => File(
  '../../test/fixtures/upstream/'
  'fba1236595f2d2bf21d414ba6e57d25256afada3/'
  'zh_legacy.jsonl',
);

final class _CapturedRun {
  const _CapturedRun({
    required this.caseId,
    required this.input,
    required this.words,
  });

  final String caseId;
  final String input;
  final List<String> words;
}

const String _oracleScript = r'''
import hashlib
import json
import pathlib
import sys

import jieba

if jieba.__version__ != '0.42.1':
    raise SystemExit('unexpected jieba version')
root = pathlib.Path(jieba.__file__).resolve().parent
resources = {
    root / 'dict.txt': '7197c3211ddd98962b036cdf40324d1ea2bfaa12bd028e68faa70111a88e12a8',
    root / 'finalseg' / 'prob_start.p': 'dfd45976dd4f8f2bc12535a680a178bf9e75eaa38bdfdcb844469e54468d6245',
    root / 'finalseg' / 'prob_trans.p': 'ea7f50162ffa01db4973c7a8120b3c0233fbc5819fc0d617513535f1f2c7fedc',
    root / 'finalseg' / 'prob_emit.p': '1e1d1d835b0c77d234acaa6afa23a13ffce597a295be0d7a1ece6a0d440dcf08',
}
for path, expected in resources.items():
    if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        raise SystemExit('unexpected jieba resource')

rows = []
with open(sys.argv[1], encoding='utf-8') as source:
    for line in source:
        fixture = json.loads(line)
        for index, run in enumerate(fixture['backendInput']['runs']):
            rows.append({
                'caseId': '{} run {}'.format(fixture['caseId'], index),
                'input': run['input'],
                'words': jieba.lcut(run['input'], cut_all=False, HMM=True),
            })
print(json.dumps(rows, ensure_ascii=False, separators=(',', ':')))
''';
