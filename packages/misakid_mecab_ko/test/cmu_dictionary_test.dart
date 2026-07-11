import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:misakid/misaki_ko.dart';
import 'package:misakid_mecab_ko/src/cmu_dictionary.dart';
import 'package:test/test.dart';

const _pinnedPathEnvironment = 'MISAKID_MECAB_KO_CMUDICT';

void main() {
  group('CmuDictionaryPronunciationProvider', () {
    test(
      'preserves first pronunciation across both counter syntaxes',
      () async {
        final fixture = utf8.encode(
          'HELLO 1 HH AH0 L OW1\n'
          'HELLO 2 HH EH1 L OW0\n'
          'WORLD(1)  W ER1 L D\n'
          'WORLD(2)\tW ER0 L D\n'
          "AARON'S 1 EH1 R AH0 N Z\n",
        );
        final provider = await _openSynthetic(fixture, records: 5, keys: 3);

        expect(provider.lookup('hello')?.arpabet, <String>[
          'HH',
          'AH0',
          'L',
          'OW1',
        ]);
        expect(provider.lookup('world')?.arpabet, <String>[
          'W',
          'ER1',
          'L',
          'D',
        ]);
        expect(provider.lookup("aaron's")?.arpabet, <String>[
          'EH1',
          'R',
          'AH0',
          'N',
          'Z',
        ]);
        expect(provider.lookup('missing'), isNull);
        expect(provider.lookup('HELLO'), isNull);
      },
    );

    test('reports immutable identity and pronunciation values', () async {
      final fixture = utf8.encode('WORD 1 W ER1 D\n');
      final provider = await _openSynthetic(fixture, records: 1, keys: 1);
      final pronunciation = provider.lookup('word')!;

      expect(provider.info.name, 'cmudict');
      expect(provider.info.version, '0.7a');
      expect(provider.info.details, <String, String>{
        'sha256': sha256.convert(fixture).toString(),
        'sizeBytes': '${fixture.length}',
        'recordCount': '1',
        'keyCount': '1',
      });
      expect(
        () => provider.info.details['extra'] = 'mutable',
        throwsUnsupportedError,
      );
      expect(() => pronunciation.arpabet.add('Z'), throwsUnsupportedError);
    });

    test('uses file order rather than pronunciation counter order', () async {
      final fixture = utf8.encode(
        'ORDERED 9 AO1 R D ER0 D\n'
        'ORDERED 1 AO2 R D ER0 D\n',
      );
      final provider = await _openSynthetic(fixture, records: 2, keys: 1);

      expect(provider.lookup('ordered')?.arpabet, <String>[
        'AO1',
        'R',
        'D',
        'ER0',
        'D',
      ]);
    });

    test('rejects a missing path with a typed backend error', () async {
      final directory = await _temporaryDirectory();

      await expectLater(
        CmuDictionaryPronunciationProvider.open(
          '${directory.path}${Platform.pathSeparator}missing',
        ),
        throwsA(isA<BackendUnavailableException>()),
      );
    });

    test('rejects malformed paths with a typed configuration error', () async {
      for (final path in <String>[
        '  ',
        'relative-cmudict',
        _absolutePath('bad\u0000path'),
        _absolutePath(String.fromCharCode(0xD800)),
      ]) {
        await expectLater(
          CmuDictionaryPronunciationProvider.open(path),
          throwsA(isA<InvalidConfigurationException>()),
        );
      }
    });

    test('rejects directories and links instead of following them', () async {
      final directory = await _temporaryDirectory();
      await expectLater(
        openCmuDictionaryForTesting(
          directory.path,
          expectedSizeBytes: 0,
          expectedSha256: '0' * 64,
          expectedRecordCount: 1,
          expectedKeyCount: 1,
        ),
        throwsA(isA<InvalidConfigurationException>()),
      );

      if (Platform.isWindows) {
        return;
      }
      final fixture = utf8.encode('WORD 1 W ER1 D\n');
      final file = await _writeFixture(fixture, directory: directory);
      final link = Link('${directory.path}${Platform.pathSeparator}linked');
      await link.create(file.path);
      await expectLater(
        openCmuDictionaryForTesting(
          link.path,
          expectedSizeBytes: fixture.length,
          expectedSha256: sha256.convert(fixture).toString(),
          expectedRecordCount: 1,
          expectedKeyCount: 1,
        ),
        throwsA(isA<InvalidConfigurationException>()),
      );
    });

    test('rejects size and SHA-256 identity mismatches', () async {
      final fixture = utf8.encode('WORD 1 W ER1 D\n');
      final file = await _writeFixture(fixture);

      await expectLater(
        openCmuDictionaryForTesting(
          file.path,
          expectedSizeBytes: fixture.length + 1,
          expectedSha256: sha256.convert(fixture).toString(),
          expectedRecordCount: 1,
          expectedKeyCount: 1,
        ),
        throwsA(isA<MalformedDataException>()),
      );
      await expectLater(
        openCmuDictionaryForTesting(
          file.path,
          expectedSizeBytes: fixture.length,
          expectedSha256: '0' * 64,
          expectedRecordCount: 1,
          expectedKeyCount: 1,
        ),
        throwsA(isA<MalformedDataException>()),
      );
    });

    test('uses strict UTF-8 decoding', () async {
      final fixture = <int>[0x57, 0x4f, 0x52, 0x44, 0x20, 0xff, 0x0a];

      await expectLater(
        _openSynthetic(fixture, records: 1, keys: 1),
        throwsA(isA<MalformedDataException>()),
      );
    });

    for (final malformed in <String>[
      'WORD\n',
      'WORD 0 W ER1 D\n',
      'WORD(X) W ER1 D\n',
      'WORD 1\n',
      'WORD 1 W er1 D\n',
      'WORD 1 W ER3 D\n',
      'WORD 1 W\u00a0ER1 D\n',
    ]) {
      test('rejects malformed record `${malformed.trim()}`', () async {
        final fixture = utf8.encode(malformed);

        await expectLater(
          _openSynthetic(fixture, records: 1, keys: 1),
          throwsA(isA<MalformedDataException>()),
        );
      });
    }

    test('enforces exact record and unique-key counts', () async {
      final fixture = utf8.encode(
        'WORD 1 W ER1 D\n'
        'WORD 2 W AO1 R D\n',
      );

      await expectLater(
        _openSynthetic(fixture, records: 3, keys: 1),
        throwsA(isA<MalformedDataException>()),
      );
      await expectLater(
        _openSynthetic(fixture, records: 2, keys: 2),
        throwsA(isA<MalformedDataException>()),
      );
    });

    test('bounds individual input records', () async {
      final fixture = utf8.encode('${'A' * 4097} 1 AH0\n');

      await expectLater(
        _openSynthetic(fixture, records: 1, keys: 1),
        throwsA(isA<MalformedDataException>()),
      );
    });

    final pinnedPath = Platform.environment[_pinnedPathEnvironment];
    test(
      'opens the exact pinned 133,737-record dictionary when provisioned',
      () async {
        final provider = await CmuDictionaryPronunciationProvider.open(
          pinnedPath!,
        );

        expect(provider.info.details['recordCount'], '133737');
        expect(provider.info.details['keyCount'], '123455');
        expect(provider.lookup('aaronson')?.arpabet, <String>[
          'EH1',
          'R',
          'AH0',
          'N',
          'S',
          'AH0',
          'N',
        ]);
      },
      skip: pinnedPath == null
          ? 'Set $_pinnedPathEnvironment to the extracted CMUdict 0.7a file.'
          : false,
    );
  });
}

Future<CmuDictionaryPronunciationProvider> _openSynthetic(
  List<int> bytes, {
  required int records,
  required int keys,
}) async {
  final file = await _writeFixture(bytes);
  return openCmuDictionaryForTesting(
    file.path,
    expectedSizeBytes: bytes.length,
    expectedSha256: sha256.convert(bytes).toString(),
    expectedRecordCount: records,
    expectedKeyCount: keys,
  );
}

Future<Directory> _temporaryDirectory() async {
  final directory = await Directory.systemTemp.createTemp('misakid-cmudict-');
  addTearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });
  return directory;
}

Future<File> _writeFixture(List<int> bytes, {Directory? directory}) async {
  final parent = directory ?? await _temporaryDirectory();
  final file = File('${parent.path}${Platform.pathSeparator}cmudict');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

String _absolutePath(String suffix) => Platform.isWindows
    ? 'C:\\definitely-missing\\$suffix'
    : '/definitely-missing/$suffix';
