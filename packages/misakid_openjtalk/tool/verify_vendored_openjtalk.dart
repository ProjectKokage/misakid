// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const expectedVendoredOpenJtalkIdentity = VendoredOpenJtalkIdentity(
  fileCount: 139,
  totalBytes: 5382103,
  treeSha256:
      '8ce47a975dee79c078914df15c40df5906430e4a63be4fc2bc0987e7b5b2fccb',
  openJtalkCopyingSha256:
      '14f380a0db8dce139fdcfb731d21e993a31a00b68907515d1c54a5f356241343',
  mecabCopyingSha256:
      '05e94c185a3e31f0c658f7011132be952b6d1a4d588b682f92da380e0a290650',
);

/// Deterministic identity of the vendored safety-patched source tree.
final class VendoredOpenJtalkIdentity {
  const VendoredOpenJtalkIdentity({
    required this.fileCount,
    required this.totalBytes,
    required this.treeSha256,
    required this.openJtalkCopyingSha256,
    required this.mecabCopyingSha256,
  });

  final int fileCount;
  final int totalBytes;
  final String treeSha256;
  final String openJtalkCopyingSha256;
  final String mecabCopyingSha256;
}

Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    stderr.writeln('Usage: dart run tool/verify_vendored_openjtalk.dart');
    exitCode = 64;
    return;
  }
  final packageLibrary = await Isolate.resolvePackageUri(
    Uri.parse('package:misakid_openjtalk/misakid_openjtalk.dart'),
  );
  if (packageLibrary == null || packageLibrary.scheme != 'file') {
    throw StateError('Could not resolve the misakid_openjtalk package root.');
  }
  final packageRoot = File.fromUri(packageLibrary).parent.parent;
  final identity = await verifyVendoredOpenJtalkTree(
    Directory('${packageRoot.path}/native/vendor/open_jtalk'),
  );
  stdout.writeln(
    'Verified native/vendor/open_jtalk: ${identity.fileCount} files, '
    '${identity.totalBytes} bytes, SHA-256 ${identity.treeSha256}.',
  );
}

/// Verifies the exact safety-patched source distributed by this package.
Future<VendoredOpenJtalkIdentity> verifyVendoredOpenJtalkTree(
  Directory root,
) async {
  final actual = await inspectVendoredOpenJtalkTree(root);
  if (actual.openJtalkCopyingSha256 !=
          expectedVendoredOpenJtalkIdentity.openJtalkCopyingSha256 ||
      actual.mecabCopyingSha256 !=
          expectedVendoredOpenJtalkIdentity.mecabCopyingSha256) {
    throw StateError('Vendored Open JTalk license identity mismatch.');
  }
  if (actual.fileCount != expectedVendoredOpenJtalkIdentity.fileCount ||
      actual.totalBytes != expectedVendoredOpenJtalkIdentity.totalBytes ||
      actual.treeSha256 != expectedVendoredOpenJtalkIdentity.treeSha256) {
    throw StateError(
      'Vendored Open JTalk source identity mismatch: ${actual.fileCount} files, '
      '${actual.totalBytes} bytes, SHA-256 ${actual.treeSha256}.',
    );
  }
  return actual;
}

/// Computes the canonical post-patch identity without accepting it.
Future<VendoredOpenJtalkIdentity> inspectVendoredOpenJtalkTree(
  Directory root,
) async {
  final rootType = await FileSystemEntity.type(root.path, followLinks: false);
  if (rootType != FileSystemEntityType.directory) {
    throw StateError('The vendored Open JTalk root is not a real directory.');
  }

  final absoluteRoot = root.absolute.path;
  final prefix = absoluteRoot.endsWith(Platform.pathSeparator)
      ? absoluteRoot
      : '$absoluteRoot${Platform.pathSeparator}';
  final files = <String, File>{};
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    final relativePath = _relativePosixPath(entity.absolute.path, prefix);
    final type = await FileSystemEntity.type(entity.path, followLinks: false);
    if (type == FileSystemEntityType.directory) continue;
    if (type != FileSystemEntityType.file) {
      throw StateError(
        'Vendored Open JTalk contains a non-regular entry: $relativePath.',
      );
    }
    files[relativePath] = File(entity.path);
  }

  final paths = files.keys.toList(growable: false)..sort();
  var totalBytes = 0;
  var openJtalkCopyingSha256 = '';
  var mecabCopyingSha256 = '';
  final treeRecords = BytesBuilder(copy: false);
  for (final path in paths) {
    final bytes = await files[path]!.readAsBytes();
    totalBytes += bytes.length;
    final fileSha256 = sha256.convert(bytes).toString();
    treeRecords
      ..add(utf8.encode(path))
      ..addByte(0x09)
      ..add(ascii.encode(fileSha256))
      ..addByte(0x0A);
    if (path == 'COPYING') openJtalkCopyingSha256 = fileSha256;
    if (path == 'mecab/COPYING') mecabCopyingSha256 = fileSha256;
  }

  return VendoredOpenJtalkIdentity(
    fileCount: paths.length,
    totalBytes: totalBytes,
    treeSha256: sha256.convert(treeRecords.takeBytes()).toString(),
    openJtalkCopyingSha256: openJtalkCopyingSha256,
    mecabCopyingSha256: mecabCopyingSha256,
  );
}

String _relativePosixPath(String absolutePath, String rootPrefix) {
  if (!absolutePath.startsWith(rootPrefix)) {
    throw StateError('A vendored Open JTalk entry escaped its root.');
  }
  return absolutePath
      .substring(rootPrefix.length)
      .split(Platform.pathSeparator)
      .join('/');
}
