import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../tool/verify_vendored_mecab.dart';

void main() {
  final vendoredRoot = Directory('native/vendor/mecab');

  test('vendored pyopenjtalk MeCab subtree has its exact identity', () async {
    final identity = await verifyVendoredMecabTree(vendoredRoot);

    expect(identity.fileCount, expectedVendoredMecabIdentity.fileCount);
    expect(identity.totalBytes, expectedVendoredMecabIdentity.totalBytes);
    expect(identity.treeSha256, expectedVendoredMecabIdentity.treeSha256);
  });

  test('vendored BSD notice is preserved byte for byte', () async {
    final vendoredNotice = await File(
      '${vendoredRoot.path}/COPYING',
    ).readAsBytes();
    final installedNotice = await File(
      'native/licenses/mecab-COPYING',
    ).readAsBytes();

    expect(vendoredNotice, orderedEquals(installedNotice));
    expect(
      sha256.convert(vendoredNotice).toString(),
      expectedVendoredMecabIdentity.copyingSha256,
    );
  });

  test('verification rejects a byte mutation', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'misakid-mecab-vendor-integrity-',
    );
    try {
      final copy = Directory('${temporary.path}/mecab');
      await _copyDirectory(vendoredRoot, copy);
      final target = File('${copy.path}/src/connector.cpp');
      final bytes = await target.readAsBytes();
      bytes[0] ^= 0xff;
      await target.writeAsBytes(bytes, flush: true);

      await expectLater(
        verifyVendoredMecabTree(copy),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('source identity mismatch'),
          ),
        ),
      );
    } finally {
      await temporary.delete(recursive: true);
    }
  });
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  final sourcePrefix = '${source.absolute.path}${Platform.pathSeparator}';
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    final relative = entity.absolute.path.substring(sourcePrefix.length);
    final targetPath = '${destination.path}${Platform.pathSeparator}$relative';
    if (entity is Directory) {
      await Directory(targetPath).create(recursive: true);
    } else if (entity is File) {
      await File(targetPath).parent.create(recursive: true);
      await entity.copy(targetPath);
    } else {
      throw StateError('Unexpected non-file in the pinned source tree.');
    }
  }
}
