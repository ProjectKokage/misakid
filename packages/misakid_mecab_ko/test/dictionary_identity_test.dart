import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:misakid/misaki.dart';
import 'package:misakid_mecab_ko/src/dictionary_identity.dart';
import 'package:test/test.dart';

void main() {
  test('production manifest is the exact 2.1.1.post2 dictionary', () {
    expect(mecabKoDictionaryName, 'python-mecab-ko-dic');
    expect(mecabKoDictionaryVersion, '2.1.1.post2');
    expect(mecabKoDictionaryFileManifest, hasLength(11));
    expect(mecabKoDictionaryFileManifest, const <
      String,
      ({int size, String sha256})
    >{
      'char.bin': (
        size: 262560,
        sha256:
            '3d23b2d8f416f2c04f16cef28a1733f6634d0db004bb164d95ea88df3c6fe8db',
      ),
      'dicrc': (
        size: 1419,
        sha256:
            'f8451a62428211d5af66ec59adf918ac9e4766e4f6c59da1a149c547c08f5df8',
      ),
      'feature.def': (
        size: 1042,
        sha256:
            '25281268cf9d722b6f901cc9e35e281a18cf01cfde0453176779ae4c4f425315',
      ),
      'left-id.def': (
        size: 76393,
        sha256:
            '1069548642547be316a56c8c7af641855f2611f9ee22b63ebb8bede55767f1d0',
      ),
      'matrix.bin': (
        size: 20585296,
        sha256:
            'e558a8064721b4492c465f9ed55dabd5655257b63bbe68fb15bf7d054bb5a7cc',
      ),
      'model.bin': (
        size: 10583428,
        sha256:
            '280f55219aef084b97d0545861a92e488fff048ce81ed3be5dce9dda3198c9e9',
      ),
      'pos-id.def': (
        size: 1550,
        sha256:
            '650137376848e2fdafa6c73583bab85d1a90409859a56f6d89acc3caa0fe88b9',
      ),
      'rewrite.def': (
        size: 2479,
        sha256:
            'b498893b6cdd7d7d3bb6f56e34efa3d848a31d384d3225c6971439a6f63b2739',
      ),
      'right-id.def': (
        size: 114511,
        sha256:
            '7827bb62ffb6674ccc1badde69b172b69b97533da2d813c1d357179cf3f32959',
      ),
      'sys.dic': (
        size: 80558854,
        sha256:
            'e4652856d13821a391e9cde47de44532d708aa5f859ae730b5377b93d52db765',
      ),
      'unk.dic': (
        size: 4170,
        sha256:
            '46042dfede05bcad59e263a2039e9f2e85912adb00fc2dea040d419c691b3151',
      ),
    });
    expect(
      mecabKoDictionaryFileManifest.values.fold<int>(
        0,
        (total, file) => total + file.size,
      ),
      mecabKoDictionarySizeBytes,
    );
    expect(
      _treeHash(mecabKoDictionaryFileManifest),
      mecabKoDictionaryTreeSha256,
    );
  });

  test('requires an absolute, bounded, scalar-valid path', () async {
    final invalidPaths = <String>[
      'relative-dictionary',
      _absolutePath('bad\u0000path'),
      _absolutePath('bad${String.fromCharCode(0xD800)}path'),
      _absolutePath(List<String>.filled(32769, 'a').join()),
    ];
    for (final path in invalidPaths) {
      await expectLater(
        MecabKoDictionarySnapshot.validate(path),
        throwsA(isA<InvalidConfigurationException>()),
        reason: path.length.toString(),
      );
    }
  });

  test('reports a missing absolute dictionary as unavailable', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'misakid-mecab-ko-missing-',
    );
    try {
      await expectLater(
        MecabKoDictionarySnapshot.validate(
          '${temporary.path}${Platform.pathSeparator}missing',
        ),
        throwsA(isA<BackendUnavailableException>()),
      );
    } finally {
      await temporary.delete(recursive: true);
    }
  });

  test('validates a streamed tree and snapshots every file', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'misakid-mecab-ko-valid-',
    );
    try {
      final manifest = await _writeTree(temporary, <String, List<int>>{
        'alpha.bin': <int>[0, 1, 2, 3],
        'zeta.def': utf8.encode('품사\n'),
      });
      final snapshot = await _validateSynthetic(temporary.path, manifest);

      expect(snapshot.resolvedPath, await temporary.resolveSymbolicLinks());
      await snapshot.ensureUnchanged();

      await File(
        '${temporary.path}${Platform.pathSeparator}alpha.bin',
      ).writeAsBytes(<int>[0, 1, 2, 3, 4], flush: true);
      await expectLater(
        snapshot.ensureUnchanged(),
        throwsA(isA<MalformedDataException>()),
      );
    } finally {
      await temporary.delete(recursive: true);
    }
  });

  test(
    'rejects missing, unexpected, extra, and hash-mismatched files',
    () async {
      final parent = await Directory.systemTemp.createTemp(
        'misakid-mecab-ko-invalid-',
      );
      try {
        final valid = Directory('${parent.path}${Platform.pathSeparator}valid');
        await valid.create();
        final manifest = await _writeTree(valid, <String, List<int>>{
          'alpha.bin': <int>[1, 2, 3],
          'zeta.def': <int>[4, 5, 6],
        });

        final missing = Directory(
          '${parent.path}${Platform.pathSeparator}missing',
        );
        await missing.create();
        await File(
          '${missing.path}${Platform.pathSeparator}alpha.bin',
        ).writeAsBytes(<int>[1, 2, 3]);
        await _expectMalformed(missing.path, manifest);

        final unexpected = Directory(
          '${parent.path}${Platform.pathSeparator}unexpected',
        );
        await unexpected.create();
        await File(
          '${unexpected.path}${Platform.pathSeparator}alpha.bin',
        ).writeAsBytes(<int>[1, 2, 3]);
        await File(
          '${unexpected.path}${Platform.pathSeparator}wrong.def',
        ).writeAsBytes(<int>[4, 5, 6]);
        await _expectMalformed(unexpected.path, manifest);

        final extra = Directory('${parent.path}${Platform.pathSeparator}extra');
        await extra.create();
        await _writeTree(extra, <String, List<int>>{
          'alpha.bin': <int>[1, 2, 3],
          'zeta.def': <int>[4, 5, 6],
          'extra': <int>[7],
        });
        await _expectMalformed(extra.path, manifest);

        final wrongHash = Directory(
          '${parent.path}${Platform.pathSeparator}wrong-hash',
        );
        await wrongHash.create();
        await File(
          '${wrongHash.path}${Platform.pathSeparator}alpha.bin',
        ).writeAsBytes(<int>[3, 2, 1]);
        await File(
          '${wrongHash.path}${Platform.pathSeparator}zeta.def',
        ).writeAsBytes(<int>[4, 5, 6]);
        await expectLater(
          _validateSynthetic(wrongHash.path, manifest),
          throwsA(
            isA<MalformedDataException>()
                .having(
                  (error) => error.message,
                  'message',
                  contains('alpha.bin'),
                )
                .having(
                  (error) => error.message,
                  'bounded message',
                  isNot(contains(parent.path)),
                ),
          ),
        );
      } finally {
        await parent.delete(recursive: true);
      }
    },
  );

  test('ensureUnchanged rejects a later unexpected entry', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'misakid-mecab-ko-changed-set-',
    );
    try {
      final manifest = await _writeTree(temporary, <String, List<int>>{
        'alpha.bin': <int>[1],
        'zeta.def': <int>[2],
      });
      final snapshot = await _validateSynthetic(temporary.path, manifest);
      await File(
        '${temporary.path}${Platform.pathSeparator}unexpected',
      ).writeAsBytes(<int>[3]);

      await expectLater(
        snapshot.ensureUnchanged(),
        throwsA(isA<MalformedDataException>()),
      );
    } finally {
      await temporary.delete(recursive: true);
    }
  });

  test(
    'rejects dictionary-root and dictionary-entry symbolic links',
    () async {
      final parent = await Directory.systemTemp.createTemp(
        'misakid-mecab-ko-links-',
      );
      try {
        final target = Directory(
          '${parent.path}${Platform.pathSeparator}target',
        );
        await target.create();
        final manifest = await _writeTree(target, <String, List<int>>{
          'alpha.bin': <int>[1],
          'zeta.def': <int>[2],
        });

        final rootLink = Link(
          '${parent.path}${Platform.pathSeparator}root-link',
        );
        await rootLink.create(target.path);
        await _expectMalformed(rootLink.path, manifest);

        final linkedEntry = Directory(
          '${parent.path}${Platform.pathSeparator}linked-entry',
        );
        await linkedEntry.create();
        await Link(
          '${linkedEntry.path}${Platform.pathSeparator}alpha.bin',
        ).create('${target.path}${Platform.pathSeparator}alpha.bin');
        await File(
          '${linkedEntry.path}${Platform.pathSeparator}zeta.def',
        ).writeAsBytes(<int>[2]);
        await _expectMalformed(linkedEntry.path, manifest);
      } finally {
        await parent.delete(recursive: true);
      }
    },
    skip: Platform.isWindows
        ? 'Creating symbolic links requires additional Windows privileges.'
        : false,
  );
}

Future<_SyntheticManifest> _writeTree(
  Directory directory,
  Map<String, List<int>> files,
) async {
  final identities = <String, ({int size, String sha256})>{};
  for (final entry in files.entries) {
    final bytes = Uint8List.fromList(entry.value);
    await File(
      '${directory.path}${Platform.pathSeparator}${entry.key}',
    ).writeAsBytes(bytes, flush: true);
    identities[entry.key] = (
      size: bytes.length,
      sha256: sha256.convert(bytes).toString(),
    );
  }
  return _SyntheticManifest(
    files: identities,
    totalBytes: identities.values.fold<int>(
      0,
      (total, file) => total + file.size,
    ),
    treeSha256: _treeHash(identities),
  );
}

Future<MecabKoDictionarySnapshot> _validateSynthetic(
  String path,
  _SyntheticManifest manifest,
) => validateMecabKoDictionaryForTesting(
  path,
  files: manifest.files,
  totalBytes: manifest.totalBytes,
  treeSha256: manifest.treeSha256,
);

Future<void> _expectMalformed(String path, _SyntheticManifest manifest) =>
    expectLater(
      _validateSynthetic(path, manifest),
      throwsA(isA<MalformedDataException>()),
    );

String _treeHash(Map<String, ({int size, String sha256})> files) {
  final records = BytesBuilder(copy: false);
  final names = files.keys.toList(growable: false)..sort();
  for (final name in names) {
    records
      ..add(utf8.encode(name))
      ..addByte(0)
      ..add(ascii.encode(files[name]!.sha256))
      ..addByte(10);
  }
  return sha256.convert(records.takeBytes()).toString();
}

String _absolutePath(String suffix) => Platform.isWindows
    ? 'C:\\definitely-missing\\$suffix'
    : '/definitely-missing/$suffix';

final class _SyntheticManifest {
  const _SyntheticManifest({
    required this.files,
    required this.totalBytes,
    required this.treeSha256,
  });

  final Map<String, ({int size, String sha256})> files;
  final int totalBytes;
  final String treeSha256;
}
