// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const expectedVendoredMecabIdentity = VendoredMecabIdentity(
  fileCount: 54,
  totalBytes: 4499769,
  treeSha256:
      '473f27f510fbcb70ab6a73c556a56cf00b0fac23091dd3656efbee05cf032258',
  copyingSha256:
      '05e94c185a3e31f0c658f7011132be952b6d1a4d588b682f92da380e0a290650',
);

/// The deterministic identity of the vendored pyopenjtalk MeCab subtree.
final class VendoredMecabIdentity {
  const VendoredMecabIdentity({
    required this.fileCount,
    required this.totalBytes,
    required this.treeSha256,
    required this.copyingSha256,
  });

  final int fileCount;
  final int totalBytes;
  final String treeSha256;
  final String copyingSha256;
}

Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    stderr.writeln('Usage: dart run tool/verify_vendored_mecab.dart');
    exitCode = 64;
    return;
  }

  final packageLibrary = await Isolate.resolvePackageUri(
    Uri.parse('package:misakid_mecab_ja/misakid_mecab_ja.dart'),
  );
  if (packageLibrary == null || packageLibrary.scheme != 'file') {
    throw StateError('Could not resolve the misakid_mecab_ja package root.');
  }
  final packageRoot = File.fromUri(packageLibrary).parent.parent;
  final identity = await verifyVendoredMecabTree(
    Directory('${packageRoot.path}/native/vendor/mecab'),
  );
  stdout.writeln(
    'Verified native/vendor/mecab: ${identity.fileCount} files, '
    '${identity.totalBytes} bytes, SHA-256 ${identity.treeSha256}.',
  );
}

/// Verifies the exact, unmodified MeCab subtree distributed by this package.
Future<VendoredMecabIdentity> verifyVendoredMecabTree(Directory root) async {
  final actual = await inspectVendoredMecabTree(root);
  if (actual.copyingSha256 != expectedVendoredMecabIdentity.copyingSha256) {
    throw StateError(
      'Vendored MeCab COPYING failed its SHA-256 check: '
      '${actual.copyingSha256}.',
    );
  }
  if (actual.fileCount != expectedVendoredMecabIdentity.fileCount ||
      actual.totalBytes != expectedVendoredMecabIdentity.totalBytes ||
      actual.treeSha256 != expectedVendoredMecabIdentity.treeSha256) {
    throw StateError(
      'Vendored MeCab source identity mismatch: ${actual.fileCount} files, '
      '${actual.totalBytes} bytes, SHA-256 ${actual.treeSha256}.',
    );
  }
  return actual;
}

/// Computes the canonical identity without accepting an unpinned tree.
Future<VendoredMecabIdentity> inspectVendoredMecabTree(Directory root) async {
  final rootType = await FileSystemEntity.type(root.path, followLinks: false);
  if (rootType != FileSystemEntityType.directory) {
    throw StateError('The vendored MeCab root is not a real directory.');
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
        'Vendored MeCab contains a non-regular entry: $relativePath.',
      );
    }
    files[relativePath] = File(entity.path);
  }

  final paths = files.keys.toList(growable: false)..sort();
  var totalBytes = 0;
  var copyingSha256 = '';
  final treeRecords = BytesBuilder(copy: false);
  for (final path in paths) {
    final bytes = await files[path]!.readAsBytes();
    totalBytes += bytes.length;
    final fileSha256 = sha256.convert(bytes).toString();
    treeRecords
      ..add(utf8.encode(path))
      ..addByte(0)
      ..add(ascii.encode(fileSha256))
      ..addByte(10);
    if (path == 'COPYING') copyingSha256 = fileSha256;
  }

  return VendoredMecabIdentity(
    fileCount: paths.length,
    totalBytes: totalBytes,
    treeSha256: sha256.convert(treeRecords.takeBytes()).toString(),
    copyingSha256: copyingSha256,
  );
}

String _relativePosixPath(String absolutePath, String rootPrefix) {
  if (!absolutePath.startsWith(rootPrefix)) {
    throw StateError('A vendored MeCab entry escaped its root.');
  }
  return absolutePath
      .substring(rootPrefix.length)
      .split(Platform.pathSeparator)
      .join('/');
}
