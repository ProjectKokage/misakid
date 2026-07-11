import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:misakid/misaki.dart';
import 'package:misakid_mecab_ja/src/dictionary_identity.dart';
import 'package:test/test.dart';

void main() {
  test('production manifest has the exact 20-file aggregate', () {
    expect(unidic310FileManifest, hasLength(20));
    expect(
      unidic310FileManifest.values.fold<int>(0, (sum, file) => sum + file.size),
      unidic310TreeSizeBytes,
    );
    expect(unidic310TreeSha256, hasLength(64));
    expect(unidic310ArchiveSha256, hasLength(64));
    expect(unidic310ArchiveSizeBytes, 524664138);
    expect(unidic310FileManifest['sys.dic']?.size, 243373840);
    expect(
      unidic310FileManifest['sys.dic']?.sha256,
      'f019f95838242cd614953a25201ad0b623b9c1cbca90de2507df4510db1b192c',
    );
  });

  test('validates nested files and detects later mutation', () async {
    final temporary = await Directory.systemTemp.createTemp('unidic-test-');
    try {
      final payloads = <String, List<int>>{
        'dicrc': utf8.encode('dictionary'),
        'licenses/BSD': utf8.encode('license'),
      };
      await _writeTree(temporary, payloads);
      final manifest = _manifest(payloads);
      final snapshot = await validateUnidic310ForTesting(
        temporary.path,
        files: manifest.files,
        totalBytes: manifest.totalBytes,
        treeSha256: manifest.treeSha256,
      );
      expect(snapshot.resolvedPath, temporary.resolveSymbolicLinksSync());
      await snapshot.ensureUnchanged();

      await File('${temporary.path}/dicrc').writeAsString('changed');
      await expectLater(
        snapshot.ensureUnchanged(),
        throwsA(isA<MalformedDataException>()),
      );
    } finally {
      await temporary.delete(recursive: true);
    }
  });

  test('rejects extra files and wrong hashes', () async {
    final temporary = await Directory.systemTemp.createTemp('unidic-test-');
    try {
      final payloads = <String, List<int>>{'dicrc': utf8.encode('dictionary')};
      await _writeTree(temporary, payloads);
      final manifest = _manifest(payloads);
      await File('${temporary.path}/extra').writeAsString('extra');
      await expectLater(
        validateUnidic310ForTesting(
          temporary.path,
          files: manifest.files,
          totalBytes: manifest.totalBytes,
          treeSha256: manifest.treeSha256,
        ),
        throwsA(isA<MalformedDataException>()),
      );
      await File('${temporary.path}/extra').delete();
      await File('${temporary.path}/dicrc').writeAsString('wrong-data');
      await expectLater(
        validateUnidic310ForTesting(
          temporary.path,
          files: manifest.files,
          totalBytes: manifest.totalBytes,
          treeSha256: manifest.treeSha256,
        ),
        throwsA(isA<MalformedDataException>()),
      );
    } finally {
      await temporary.delete(recursive: true);
    }
  });

  test(
    'rejects symbolic links anywhere in the tree',
    () async {
      final temporary = await Directory.systemTemp.createTemp('unidic-test-');
      try {
        final target = File('${temporary.path}/target')..writeAsStringSync('x');
        final link = Link('${temporary.path}/dicrc')..createSync(target.path);
        expect(link.existsSync(), isTrue);
        final bytes = target.readAsBytesSync();
        final manifest = _manifest(<String, List<int>>{'dicrc': bytes});
        await expectLater(
          validateUnidic310ForTesting(
            temporary.path,
            files: manifest.files,
            totalBytes: manifest.totalBytes,
            treeSha256: manifest.treeSha256,
          ),
          throwsA(isA<MalformedDataException>()),
        );
      } finally {
        await temporary.delete(recursive: true);
      }
    },
    skip: Platform.isWindows ? 'Creating links may require elevation.' : false,
  );

  test('rejects relative and NUL paths before filesystem access', () async {
    await expectLater(
      Unidic310Snapshot.validate('relative'),
      throwsA(isA<InvalidConfigurationException>()),
    );
    await expectLater(
      Unidic310Snapshot.validate('/tmp/bad\u0000path'),
      throwsA(isA<InvalidConfigurationException>()),
    );
  });
}

Future<void> _writeTree(Directory root, Map<String, List<int>> payloads) async {
  for (final entry in payloads.entries) {
    final path = entry.key.replaceAll('/', Platform.pathSeparator);
    final file = File('${root.path}${Platform.pathSeparator}$path');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(entry.value, flush: true);
  }
}

({
  Map<String, ({int size, String sha256})> files,
  int totalBytes,
  String treeSha256,
})
_manifest(Map<String, List<int>> payloads) {
  final names = payloads.keys.toList(growable: false)..sort();
  final tree = BytesBuilder(copy: false);
  final files = <String, ({int size, String sha256})>{};
  var total = 0;
  for (final name in names) {
    final nameBytes = utf8.encode(name);
    final bytes = payloads[name]!;
    tree
      ..add(_uint64(nameBytes.length))
      ..add(nameBytes)
      ..add(_uint64(bytes.length))
      ..add(bytes);
    files[name] = (
      size: bytes.length,
      sha256: sha256.convert(bytes).toString(),
    );
    total += bytes.length;
  }
  return (
    files: files,
    totalBytes: total,
    treeSha256: sha256.convert(tree.takeBytes()).toString(),
  );
}

Uint8List _uint64(int value) {
  final data = ByteData(8)..setUint64(0, value, Endian.big);
  return data.buffer.asUint8List();
}
