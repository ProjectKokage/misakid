import 'dart:convert';
import 'dart:io';

import 'package:misakid/misaki.dart';
import 'package:misakid_chinese/src/jieba.dart';
import 'package:test/test.dart';

void main() {
  group('JiebaSegmenter', () {
    late Directory temporary;

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp('misakid-jieba-');
    });

    tearDown(() async {
      if (await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
    });

    test('loads inert resources and matches DAG and HMM branches', () async {
      final resources = await _writeSyntheticResources(temporary);
      final segmenter = await _openSynthetic(resources);

      expect(segmenter.info.name, 'jieba');
      expect(segmenter.info.version, '0.42.1');
      expect(segmenter.info.details, containsPair('mode', 'accurate-hmm'));
      expect(
        segmenter.info.details,
        containsPair('dictionaryRecordCount', '5'),
      );
      expect(segmenter.info.details, containsPair('frequencyEntryCount', '8'));
      expect(segmenter.info.details, containsPair('totalFrequency', '39'));
      expect(segmenter.info.details, containsPair('emissionEntryCount', '2'));

      expect(segmenter.segment('研究生命'), <String>['研究', '生命']);
      expect(segmenter.segment('甲乙'), <String>['甲乙']);
      expect(segmenter.segment('已知'), <String>['已知']);
      expect(segmenter.segment('研究鿿生命'), <String>['研究', '鿿', '生命']);
      expect(segmenter.segment('研究生命').clear, throwsUnsupportedError);
    });

    test('uses accurate DAG scoring and Python Viterbi tie-breaking', () async {
      final resources = await _writeSyntheticResources(
        temporary,
        dictionary: '甲 1 n\n甲乙 1 n\n乙 1 n\n',
        dictionaryRecordCount: 3,
        frequencyEntryCount: 3,
        totalFrequency: 3,
        start: const <String, Object>{
          'B': -100.0,
          'M': -100.0,
          'E': -100.0,
          'S': -100.0,
        },
        transitions: _zeroTransitions,
        emissions: const <String, Object>{
          'B': <String, Object>{},
          'M': <String, Object>{},
          'E': <String, Object>{},
          'S': <String, Object>{},
        },
        emissionEntryCount: 0,
      );
      final segmenter = await _openSynthetic(resources);

      // The whole word has the higher accurate-mode route probability.
      expect(segmenter.segment('甲乙'), <String>['甲乙']);

      final unknownResources = await _writeSyntheticResources(
        temporary,
        stem: 'unknown',
        start: const <String, Object>{
          'B': -100.0,
          'M': -100.0,
          'E': -100.0,
          'S': -100.0,
        },
        transitions: _zeroTransitions,
        emissions: const <String, Object>{
          'B': <String, Object>{},
          'M': <String, Object>{},
          'E': <String, Object>{},
          'S': <String, Object>{},
        },
        emissionEntryCount: 0,
      );
      final unknownSegmenter = await _openSynthetic(unknownResources);
      // With every Viterbi score tied, Python tuple comparison selects the
      // lexicographically larger predecessor and final S state.
      expect(unknownSegmenter.segment('丙丁'), <String>['丙', '丁']);
    });

    test(
      'rejects input outside the legacy CJK boundary and resource bound',
      () async {
        final segmenter = await _openSynthetic(
          await _writeSyntheticResources(temporary),
        );
        for (final input in <String>[
          '',
          '中文A',
          '𠀀',
          String.fromCharCode(0xD800),
          List<String>.filled(maximumJiebaSegmentInputScalars + 1, '中').join(),
        ]) {
          expect(
            () => segmenter.segment(input),
            throwsA(isA<InvalidConfigurationException>()),
            reason: input.length.toString(),
          );
        }
      },
    );

    test(
      'rejects relative, duplicate, missing, and wrong-identity paths',
      () async {
        await expectLater(
          JiebaSegmenter.open(
            dictionaryPath: 'relative',
            probabilityStartPath: '/start',
            probabilityTransitionPath: '/transition',
            probabilityEmissionPath: '/emission',
          ),
          throwsA(isA<InvalidConfigurationException>()),
        );
        final invalidScalar =
            '${temporary.path}/${String.fromCharCode(0xD800)}';
        await expectLater(
          JiebaSegmenter.open(
            dictionaryPath: invalidScalar,
            probabilityStartPath: '${temporary.path}/start',
            probabilityTransitionPath: '${temporary.path}/transition',
            probabilityEmissionPath: '${temporary.path}/emission',
          ),
          throwsA(isA<InvalidConfigurationException>()),
        );
        final same = '${temporary.path}/same';
        await expectLater(
          JiebaSegmenter.open(
            dictionaryPath: same,
            probabilityStartPath: same,
            probabilityTransitionPath: '${temporary.path}/transition',
            probabilityEmissionPath: '${temporary.path}/emission',
          ),
          throwsA(isA<InvalidConfigurationException>()),
        );
        await expectLater(
          JiebaSegmenter.open(
            dictionaryPath: '${temporary.path}/missing',
            probabilityStartPath: '${temporary.path}/start',
            probabilityTransitionPath: '${temporary.path}/transition',
            probabilityEmissionPath: '${temporary.path}/emission',
          ),
          throwsA(isA<BackendUnavailableException>()),
        );

        final resources = await _writeSyntheticResources(temporary);
        await expectLater(
          JiebaSegmenter.open(
            dictionaryPath: resources.dictionary.path,
            probabilityStartPath: resources.start.path,
            probabilityTransitionPath: resources.transition.path,
            probabilityEmissionPath: resources.emission.path,
          ),
          throwsA(isA<MalformedDataException>()),
        );
      },
    );

    test(
      'rejects symbolic links and malformed strict UTF-8',
      () async {
        final resources = await _writeSyntheticResources(temporary);
        final link = Link('${temporary.path}/dictionary-link');
        await link.create(resources.dictionary.path);
        final linked = (
          dictionary: File(link.path),
          start: resources.start,
          transition: resources.transition,
          emission: resources.emission,
          dictionaryRecordCount: resources.dictionaryRecordCount,
          frequencyEntryCount: resources.frequencyEntryCount,
          totalFrequency: resources.totalFrequency,
          emissionEntryCount: resources.emissionEntryCount,
        );
        await expectLater(
          _openSynthetic(linked),
          throwsA(isA<InvalidConfigurationException>()),
        );

        await resources.dictionary.writeAsBytes(<int>[0xFF, 0x0A], flush: true);
        final malformed = (
          dictionary: resources.dictionary,
          start: resources.start,
          transition: resources.transition,
          emission: resources.emission,
          dictionaryRecordCount: 1,
          frequencyEntryCount: 1,
          totalFrequency: 1,
          emissionEntryCount: resources.emissionEntryCount,
        );
        await expectLater(
          _openSynthetic(malformed),
          throwsA(isA<MalformedDataException>()),
        );
      },
      skip: Platform.isWindows ? 'Symlink privileges vary on Windows.' : false,
    );

    test('never executes or accepts executable pickle opcodes', () async {
      final resources = await _writeSyntheticResources(temporary);
      await resources.start.writeAsBytes(
        ascii.encode("cos\nsystem\n(S'echo unsafe'\ntR."),
        flush: true,
      );
      final malicious = (
        dictionary: resources.dictionary,
        start: resources.start,
        transition: resources.transition,
        emission: resources.emission,
        dictionaryRecordCount: resources.dictionaryRecordCount,
        frequencyEntryCount: resources.frequencyEntryCount,
        totalFrequency: resources.totalFrequency,
        emissionEntryCount: resources.emissionEntryCount,
      );

      await expectLater(
        _openSynthetic(malicious),
        throwsA(
          isA<MalformedDataException>().having(
            (error) => error.message,
            'bounded message',
            isNot(contains('echo unsafe')),
          ),
        ),
      );
    });

    test(
      'rejects duplicate probability keys and trailing pickle bytes',
      () async {
        final resources = await _writeSyntheticResources(temporary);
        await resources.start.writeAsBytes(
          ascii.encode("(dS'B'\nF0.0\nsS'B'\nF0.0\ns."),
          flush: true,
        );
        await expectLater(
          _openSynthetic((
            dictionary: resources.dictionary,
            start: resources.start,
            transition: resources.transition,
            emission: resources.emission,
            dictionaryRecordCount: resources.dictionaryRecordCount,
            frequencyEntryCount: resources.frequencyEntryCount,
            totalFrequency: resources.totalFrequency,
            emissionEntryCount: resources.emissionEntryCount,
          )),
          throwsA(isA<MalformedDataException>()),
        );

        await resources.start.writeAsBytes(<int>[
          ..._probabilityPickle(_defaultStart),
          0x00,
        ], flush: true);
        await expectLater(
          _openSynthetic((
            dictionary: resources.dictionary,
            start: resources.start,
            transition: resources.transition,
            emission: resources.emission,
            dictionaryRecordCount: resources.dictionaryRecordCount,
            frequencyEntryCount: resources.frequencyEntryCount,
            totalFrequency: resources.totalFrequency,
            emissionEntryCount: resources.emissionEntryCount,
          )),
          throwsA(isA<MalformedDataException>()),
        );
      },
    );
  });
}

typedef _SyntheticResources = ({
  File dictionary,
  File start,
  File transition,
  File emission,
  int dictionaryRecordCount,
  int frequencyEntryCount,
  int totalFrequency,
  int emissionEntryCount,
});

Future<JiebaSegmenter> _openSynthetic(_SyntheticResources resources) =>
    openJiebaForTesting(
      dictionaryPath: resources.dictionary.path,
      probabilityStartPath: resources.start.path,
      probabilityTransitionPath: resources.transition.path,
      probabilityEmissionPath: resources.emission.path,
      dictionaryRecordCount: resources.dictionaryRecordCount,
      frequencyEntryCount: resources.frequencyEntryCount,
      totalFrequency: resources.totalFrequency,
      emissionEntryCount: resources.emissionEntryCount,
    );

Future<_SyntheticResources> _writeSyntheticResources(
  Directory directory, {
  String stem = 'model',
  String dictionary = '研究 10 n\n研究生 9 n\n生命 8 n\n命 5 n\n已知 7 n\n',
  int dictionaryRecordCount = 5,
  int frequencyEntryCount = 8,
  int totalFrequency = 39,
  Map<String, Object> start = _defaultStart,
  Map<String, Object> transitions = _defaultTransitions,
  Map<String, Object> emissions = _defaultEmissions,
  int emissionEntryCount = 2,
}) async {
  final dictionaryFile = File('${directory.path}/$stem-dict.txt');
  final startFile = File('${directory.path}/$stem-start.p');
  final transitionFile = File('${directory.path}/$stem-transition.p');
  final emissionFile = File('${directory.path}/$stem-emission.p');
  await dictionaryFile.writeAsString(dictionary, flush: true);
  await startFile.writeAsBytes(_probabilityPickle(start), flush: true);
  await transitionFile.writeAsBytes(
    _probabilityPickle(transitions),
    flush: true,
  );
  await emissionFile.writeAsBytes(
    _probabilityPickle(emissions, unicodeKeys: true),
    flush: true,
  );
  return (
    dictionary: dictionaryFile,
    start: startFile,
    transition: transitionFile,
    emission: emissionFile,
    dictionaryRecordCount: dictionaryRecordCount,
    frequencyEntryCount: frequencyEntryCount,
    totalFrequency: totalFrequency,
    emissionEntryCount: emissionEntryCount,
  );
}

List<int> _probabilityPickle(
  Map<String, Object> values, {
  bool unicodeKeys = false,
}) {
  final output = StringBuffer();
  _writePickleMap(output, values, unicodeKeys: unicodeKeys);
  output.write('.');
  return ascii.encode(output.toString());
}

void _writePickleMap(
  StringBuffer output,
  Map<String, Object> values, {
  required bool unicodeKeys,
}) {
  output.write('(d');
  for (final entry in values.entries) {
    if (unicodeKeys) {
      output
        ..write('V')
        ..write(_rawUnicode(entry.key))
        ..write('\n');
    } else {
      output
        ..write("S'")
        ..write(entry.key)
        ..write("'\n");
    }
    final value = entry.value;
    if (value is Map<String, Object>) {
      _writePickleMap(output, value, unicodeKeys: unicodeKeys);
    } else if (value is double) {
      output
        ..write('F')
        ..write(value)
        ..write('\n');
    } else {
      throw StateError('Unsupported synthetic pickle value $value.');
    }
    output.write('s');
  }
}

String _rawUnicode(String input) {
  final result = StringBuffer();
  for (final scalar in input.runes) {
    if (scalar >= 0x20 && scalar <= 0x7E && scalar != 0x5C) {
      result.writeCharCode(scalar);
    } else if (scalar <= 0xFFFF) {
      result
        ..write(r'\u')
        ..write(scalar.toRadixString(16).padLeft(4, '0'));
    } else {
      result
        ..write(r'\U')
        ..write(scalar.toRadixString(16).padLeft(8, '0'));
    }
  }
  return result.toString();
}

const Map<String, Object> _defaultStart = <String, Object>{
  'B': 0.0,
  'M': -100.0,
  'E': -100.0,
  'S': -100.0,
};

const Map<String, Object> _defaultTransitions = <String, Object>{
  'B': <String, Object>{'E': 0.0, 'M': -100.0},
  'E': <String, Object>{'B': 0.0, 'S': -100.0},
  'M': <String, Object>{'E': 0.0, 'M': -100.0},
  'S': <String, Object>{'B': 0.0, 'S': -100.0},
};

const Map<String, Object> _zeroTransitions = <String, Object>{
  'B': <String, Object>{'E': 0.0, 'M': 0.0},
  'E': <String, Object>{'B': 0.0, 'S': 0.0},
  'M': <String, Object>{'E': 0.0, 'M': 0.0},
  'S': <String, Object>{'B': 0.0, 'S': 0.0},
};

const Map<String, Object> _defaultEmissions = <String, Object>{
  'B': <String, Object>{'甲': 0.0},
  'M': <String, Object>{},
  'E': <String, Object>{'乙': 0.0},
  'S': <String, Object>{},
};
