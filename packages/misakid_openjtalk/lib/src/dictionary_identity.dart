// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:misakid/misaki.dart';
import 'package:misakid_adapter_support/file_system.dart';

/// Open JTalk dictionary release required by this adapter.
const String openJtalkDictionaryName = 'open_jtalk_dic_utf_8-1.11';

/// Canonical SHA-256 identity of the installed nine-file dictionary tree.
const String openJtalkDictionaryTreeSha256 =
    '8b26c37228c9e9b92333e612e1144c958f2788d219e46c8652f698a089be1ccc';

/// Exact total byte size of the installed dictionary tree.
const int openJtalkDictionarySizeBytes = 107304813;

const Map<String, ({int size, String sha256})>
_expectedFiles = <String, ({int size, String sha256})>{
  'COPYING': (
    size: 5865,
    sha256: 'f4eca42ebd930e2c6e57fca58319d989bebcd1510cb7714b149c50f5425135ea',
  ),
  'char.bin': (
    size: 262496,
    sha256: '888ee94c5a8a7a26d24ab3f1b7155441351954fd51ea06b4a2f78bd742492b2f',
  ),
  'left-id.def': (
    size: 77672,
    sha256: 'db1adac8a7f9e5854cd82ea044c85115249206c8181b9d88cf92ae2ee5e87b84',
  ),
  'matrix.bin': (
    size: 3792262,
    sha256: '62fd16b4f64c851d5dc352ef0d5740c5fc83ddc7c203b2b0b1fc5271969a14ce',
  ),
  'pos-id.def': (
    size: 1923,
    sha256: '3460aa742053085af47cdfc889a1e0e6f557e89b406e501ba81c9ccc286de0c7',
  ),
  'rewrite.def': (
    size: 7457,
    sha256: '7f7c8dfbfe24092e8a149a9b6e0a3a7f1c2cf37d6c3dc29d1cccc6c004da9c1c',
  ),
  'right-id.def': (
    size: 77672,
    sha256: 'db1adac8a7f9e5854cd82ea044c85115249206c8181b9d88cf92ae2ee5e87b84',
  ),
  'sys.dic': (
    size: 103073776,
    sha256: 'ca57d9029691a70a5dfb99afc2844180256161d7130da65b1a867510e129b9a6',
  ),
  'unk.dic': (
    size: 5690,
    sha256: 'ce97851ecda075914fa3ffe7294a1ab34ee4f6d56ba6bf9197d74143b5dffbfe',
  ),
};

/// Validated dictionary identity retained across native initialization.
final class OpenJtalkDictionarySnapshot {
  OpenJtalkDictionarySnapshot._({
    required this.resolvedPath,
    required Map<String, FileSnapshot> files,
  }) : _files = Map<String, FileSnapshot>.unmodifiable(files);

  /// Canonical path passed to the native frontend after validation.
  final String resolvedPath;
  final Map<String, FileSnapshot> _files;

  /// Streams and validates every file in the pinned dictionary.
  static Future<OpenJtalkDictionarySnapshot> validate(String path) async {
    return _open(path, verifyContents: true);
  }

  /// Opens a structurally valid dictionary previously verified by its owner.
  ///
  /// This does not authenticate file contents. It is only for app-private
  /// installs whose exact sizes and SHA-256 identities were checked in a
  /// staging directory before atomic promotion.
  static Future<OpenJtalkDictionarySnapshot> fromVerifiedInstall(
    String path,
  ) async {
    return _open(path, verifyContents: false);
  }

  static Future<OpenJtalkDictionarySnapshot> _open(
    String path, {
    required bool verifyContents,
  }) async {
    try {
      return await _validateReadable(path, verifyContents: verifyContents);
    } on MisakiException {
      rethrow;
    } on FileSystemException catch (error) {
      throw BackendUnavailableException(
        'The configured Open JTalk dictionary could not be read.',
        cause: error,
      );
    } on ArgumentError catch (error) {
      throw InvalidConfigurationException(
        'The configured Open JTalk dictionary path is invalid.',
        cause: error,
      );
    }
  }

  static Future<OpenJtalkDictionarySnapshot> _validateReadable(
    String path, {
    required bool verifyContents,
  }) async {
    final rootType = await FileSystemEntity.type(path, followLinks: false);
    if (rootType == FileSystemEntityType.notFound) {
      throw const BackendUnavailableException(
        'The configured Open JTalk dictionary directory does not exist.',
      );
    }
    if (rootType != FileSystemEntityType.directory) {
      throw const MalformedDataException(
        'The configured Open JTalk dictionary must be a real directory, not a link.',
      );
    }

    final directory = Directory(path);
    final resolvedPath = await directory.resolveSymbolicLinks();
    final names = <String>{};
    await for (final entity in directory.list(followLinks: false)) {
      if (names.length >= _expectedFiles.length) {
        throw const MalformedDataException(
          'The Open JTalk 1.11 dictionary contains too many entries.',
        );
      }
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type != FileSystemEntityType.file) {
        throw const MalformedDataException(
          'The Open JTalk dictionary contains a directory, link, or special file.',
        );
      }
      final name = _basename(entity.path);
      if (!_expectedFiles.containsKey(name) || !names.add(name)) {
        throw const MalformedDataException(
          'The Open JTalk 1.11 dictionary file set does not match the pinned release.',
        );
      }
    }
    if (names.length != _expectedFiles.length ||
        !names.containsAll(_expectedFiles.keys)) {
      throw const MalformedDataException(
        'The Open JTalk 1.11 dictionary file set does not match the pinned release.',
      );
    }

    final snapshots = <String, FileSnapshot>{};
    final treeRecords = BytesBuilder(copy: false);
    var totalBytes = 0;
    final sortedNames = _expectedFiles.keys.toList(growable: false)..sort();
    for (final name in sortedNames) {
      final expected = _expectedFiles[name]!;
      final file = File('$resolvedPath/$name');
      final type = await FileSystemEntity.type(file.path, followLinks: false);
      final statBeforeHash = await file.stat();
      if (type != FileSystemEntityType.file ||
          statBeforeHash.type != FileSystemEntityType.file ||
          statBeforeHash.size != expected.size) {
        throw MalformedDataException(
          'Open JTalk dictionary file `$name` has the wrong type or size.',
        );
      }
      final snapshot = FileSnapshot.fromStat(statBeforeHash);
      if (!verifyContents) {
        snapshots[name] = snapshot;
        continue;
      }
      final digest = await sha256.bind(file.openRead()).first;
      final typeAfterHash = await FileSystemEntity.type(
        file.path,
        followLinks: false,
      );
      final statAfterHash = await file.stat();
      if (typeAfterHash != FileSystemEntityType.file ||
          !snapshot.matches(statAfterHash)) {
        throw MalformedDataException(
          'Open JTalk dictionary file `$name` changed while it was being validated.',
        );
      }
      final actualHash = digest.toString();
      if (actualHash != expected.sha256) {
        throw MalformedDataException(
          'Open JTalk dictionary file `$name` failed its SHA-256 check.',
        );
      }
      totalBytes += statBeforeHash.size;
      treeRecords
        ..add(utf8.encode(name))
        ..addByte(0)
        ..add(ascii.encode(actualHash))
        ..addByte(10);
      snapshots[name] = snapshot;
    }
    if (verifyContents) {
      final treeHash = sha256.convert(treeRecords.takeBytes()).toString();
      if (totalBytes != openJtalkDictionarySizeBytes ||
          treeHash != openJtalkDictionaryTreeSha256) {
        throw const MalformedDataException(
          'The Open JTalk dictionary tree identity does not match the pinned release.',
        );
      }
    }
    return OpenJtalkDictionarySnapshot._(
      resolvedPath: resolvedPath,
      files: snapshots,
    );
  }

  /// Detects a size or timestamp change between validation and native open.
  Future<void> ensureUnchanged() async {
    try {
      await _ensureReadableUnchanged();
    } on MisakiException {
      rethrow;
    } on FileSystemException catch (error) {
      throw BackendUnavailableException(
        'The validated Open JTalk dictionary became unreadable while opening.',
        cause: error,
      );
    }
  }

  Future<void> _ensureReadableUnchanged() async {
    for (final entry in _files.entries) {
      final path = '$resolvedPath/${entry.key}';
      final type = await FileSystemEntity.type(path, followLinks: false);
      final stat = await File(path).stat();
      if (type != FileSystemEntityType.file || !entry.value.matches(stat)) {
        throw const MalformedDataException(
          'The Open JTalk dictionary changed while the backend was opening.',
        );
      }
    }
  }
}

String _basename(String path) {
  final separator = Platform.pathSeparator;
  final index = path.lastIndexOf(separator);
  return index < 0 ? path : path.substring(index + separator.length);
}
