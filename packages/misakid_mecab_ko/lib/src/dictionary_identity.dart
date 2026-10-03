// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:misakid/misaki.dart';
import 'package:misakid_adapter_support/file_system.dart';

/// Package name of the exact Korean MeCab dictionary resource.
const String mecabKoDictionaryName = 'python-mecab-ko-dic';

/// Package version of the exact Korean MeCab dictionary resource.
const String mecabKoDictionaryVersion = '2.1.1.post2';

/// Canonical SHA-256 identity of the installed eleven-file dictionary tree.
const String mecabKoDictionaryTreeSha256 =
    'd851fab8708745442ac3a2d970851dbd0ef598e786a363f406847461d77a6f51';

/// Exact total byte size of the installed dictionary tree.
const int mecabKoDictionarySizeBytes = 112191702;

/// Exact per-file identity of `python-mecab-ko-dic` 2.1.1.post2.
///
/// This is internal adapter data and is not exported by the package's public
/// entrypoint. It is visible here so integrity tests can independently verify
/// the aggregate size and canonical tree digest.
const Map<String, ({int size, String sha256})>
mecabKoDictionaryFileManifest = <String, ({int size, String sha256})>{
  'char.bin': (
    size: 262560,
    sha256: '3d23b2d8f416f2c04f16cef28a1733f6634d0db004bb164d95ea88df3c6fe8db',
  ),
  'dicrc': (
    size: 1419,
    sha256: 'f8451a62428211d5af66ec59adf918ac9e4766e4f6c59da1a149c547c08f5df8',
  ),
  'feature.def': (
    size: 1042,
    sha256: '25281268cf9d722b6f901cc9e35e281a18cf01cfde0453176779ae4c4f425315',
  ),
  'left-id.def': (
    size: 76393,
    sha256: '1069548642547be316a56c8c7af641855f2611f9ee22b63ebb8bede55767f1d0',
  ),
  'matrix.bin': (
    size: 20585296,
    sha256: 'e558a8064721b4492c465f9ed55dabd5655257b63bbe68fb15bf7d054bb5a7cc',
  ),
  'model.bin': (
    size: 10583428,
    sha256: '280f55219aef084b97d0545861a92e488fff048ce81ed3be5dce9dda3198c9e9',
  ),
  'pos-id.def': (
    size: 1550,
    sha256: '650137376848e2fdafa6c73583bab85d1a90409859a56f6d89acc3caa0fe88b9',
  ),
  'rewrite.def': (
    size: 2479,
    sha256: 'b498893b6cdd7d7d3bb6f56e34efa3d848a31d384d3225c6971439a6f63b2739',
  ),
  'right-id.def': (
    size: 114511,
    sha256: '7827bb62ffb6674ccc1badde69b172b69b97533da2d813c1d357179cf3f32959',
  ),
  'sys.dic': (
    size: 80558854,
    sha256: 'e4652856d13821a391e9cde47de44532d708aa5f859ae730b5377b93d52db765',
  ),
  'unk.dic': (
    size: 4170,
    sha256: '46042dfede05bcad59e263a2039e9f2e85912adb00fc2dea040d419c691b3151',
  ),
};

final _productionManifest = _DictionaryManifest(
  files: mecabKoDictionaryFileManifest,
  totalBytes: mecabKoDictionarySizeBytes,
  treeSha256: mecabKoDictionaryTreeSha256,
);

/// Validated dictionary identity retained across native initialization.
final class MecabKoDictionarySnapshot {
  MecabKoDictionarySnapshot._({
    required this.resolvedPath,
    required Map<String, FileSnapshot> files,
    required _DictionaryManifest manifest,
  }) : _files = Map<String, FileSnapshot>.unmodifiable(files),
       _manifest = manifest;

  /// Canonical absolute path passed to the native MeCab-ko frontend.
  final String resolvedPath;

  final Map<String, FileSnapshot> _files;
  final _DictionaryManifest _manifest;

  /// Streams and validates every file in the pinned dictionary.
  static Future<MecabKoDictionarySnapshot> validate(String path) =>
      _validate(path, _productionManifest);

  static Future<MecabKoDictionarySnapshot> _validate(
    String path,
    _DictionaryManifest manifest,
  ) async {
    _validatePath(path);
    try {
      return await _validateReadable(path, manifest);
    } on MisakiException {
      rethrow;
    } on FileSystemException catch (error) {
      throw BackendUnavailableException(
        'The configured MeCab-ko dictionary could not be read.',
        cause: error,
      );
    } on ArgumentError catch (error) {
      throw InvalidConfigurationException(
        'The configured MeCab-ko dictionary path is invalid.',
        cause: error,
      );
    }
  }

  static Future<MecabKoDictionarySnapshot> _validateReadable(
    String path,
    _DictionaryManifest manifest,
  ) async {
    final rootType = await FileSystemEntity.type(path, followLinks: false);
    if (rootType == FileSystemEntityType.notFound) {
      throw const BackendUnavailableException(
        'The configured MeCab-ko dictionary directory does not exist.',
      );
    }
    if (rootType != FileSystemEntityType.directory) {
      throw const MalformedDataException(
        'The configured MeCab-ko dictionary must be a real directory, not a link.',
      );
    }

    final resolvedPath = await Directory(path).resolveSymbolicLinks();
    final rootTypeAfterResolve = await FileSystemEntity.type(
      path,
      followLinks: false,
    );
    if (rootTypeAfterResolve != FileSystemEntityType.directory) {
      throw const MalformedDataException(
        'The configured MeCab-ko dictionary changed while it was being resolved.',
      );
    }

    await _validateEntrySet(Directory(resolvedPath), manifest.files);

    final snapshots = <String, FileSnapshot>{};
    final treeRecords = BytesBuilder(copy: false);
    var totalBytes = 0;
    final sortedNames = manifest.files.keys.toList(growable: false)..sort();
    for (final name in sortedNames) {
      final expected = manifest.files[name]!;
      final file = File('$resolvedPath${Platform.pathSeparator}$name');
      final typeBeforeHash = await FileSystemEntity.type(
        file.path,
        followLinks: false,
      );
      final statBeforeHash = await file.stat();
      if (typeBeforeHash != FileSystemEntityType.file ||
          statBeforeHash.type != FileSystemEntityType.file ||
          statBeforeHash.size != expected.size) {
        throw MalformedDataException(
          'MeCab-ko dictionary file `$name` has the wrong type or size.',
        );
      }

      final digest = await sha256.bind(file.openRead()).first;
      final typeAfterHash = await FileSystemEntity.type(
        file.path,
        followLinks: false,
      );
      final statAfterHash = await file.stat();
      final snapshot = FileSnapshot.fromStat(statBeforeHash);
      if (typeAfterHash != FileSystemEntityType.file ||
          !snapshot.matches(statAfterHash)) {
        throw MalformedDataException(
          'MeCab-ko dictionary file `$name` changed while it was being validated.',
        );
      }

      final actualHash = digest.toString();
      if (actualHash != expected.sha256) {
        throw MalformedDataException(
          'MeCab-ko dictionary file `$name` failed its SHA-256 check.',
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

    final treeHash = sha256.convert(treeRecords.takeBytes()).toString();
    if (totalBytes != manifest.totalBytes || treeHash != manifest.treeSha256) {
      throw const MalformedDataException(
        'The MeCab-ko dictionary tree identity does not match the pinned release.',
      );
    }
    return MecabKoDictionarySnapshot._(
      resolvedPath: resolvedPath,
      files: snapshots,
      manifest: manifest,
    );
  }

  /// Detects an entry, type, size, or timestamp change after validation.
  Future<void> ensureUnchanged() async {
    try {
      await _ensureReadableUnchanged();
    } on MisakiException {
      rethrow;
    } on FileSystemException catch (error) {
      throw BackendUnavailableException(
        'The validated MeCab-ko dictionary became unreadable while opening.',
        cause: error,
      );
    } on ArgumentError catch (error) {
      throw MalformedDataException(
        'The validated MeCab-ko dictionary path became invalid.',
        cause: error,
      );
    }
  }

  Future<void> _ensureReadableUnchanged() async {
    final rootType = await FileSystemEntity.type(
      resolvedPath,
      followLinks: false,
    );
    if (rootType != FileSystemEntityType.directory) {
      throw const MalformedDataException(
        'The validated MeCab-ko dictionary directory changed while opening.',
      );
    }
    await _validateEntrySet(Directory(resolvedPath), _manifest.files);
    for (final entry in _files.entries) {
      final path = '$resolvedPath${Platform.pathSeparator}${entry.key}';
      final type = await FileSystemEntity.type(path, followLinks: false);
      final stat = await File(path).stat();
      if (type != FileSystemEntityType.file || !entry.value.matches(stat)) {
        throw const MalformedDataException(
          'The MeCab-ko dictionary changed while the backend was opening.',
        );
      }
    }
  }
}

/// Validates a small injected manifest for offline integrity tests.
///
/// This function lives below `lib/src`, is never exported by the package, and
/// cannot alter the exact production manifest used by
/// [MecabKoDictionarySnapshot.validate].
Future<MecabKoDictionarySnapshot> validateMecabKoDictionaryForTesting(
  String path, {
  required Map<String, ({int size, String sha256})> files,
  required int totalBytes,
  required String treeSha256,
}) => MecabKoDictionarySnapshot._validate(
  path,
  _DictionaryManifest(
    files: files,
    totalBytes: totalBytes,
    treeSha256: treeSha256,
  ),
);

Future<void> _validateEntrySet(
  Directory directory,
  Map<String, ({int size, String sha256})> expectedFiles,
) async {
  final names = <String>{};
  await for (final entity in directory.list(followLinks: false)) {
    if (names.length >= expectedFiles.length) {
      throw const MalformedDataException(
        'The MeCab-ko dictionary contains too many entries.',
      );
    }
    final type = await FileSystemEntity.type(entity.path, followLinks: false);
    if (type != FileSystemEntityType.file) {
      throw const MalformedDataException(
        'The MeCab-ko dictionary contains a directory, link, or special file.',
      );
    }
    final name = _basename(entity.path);
    if (!expectedFiles.containsKey(name) || !names.add(name)) {
      throw const MalformedDataException(
        'The MeCab-ko dictionary file set does not match the pinned release.',
      );
    }
  }
  if (names.length != expectedFiles.length ||
      !names.containsAll(expectedFiles.keys)) {
    throw const MalformedDataException(
      'The MeCab-ko dictionary file set does not match the pinned release.',
    );
  }
}

void _validatePath(String path) {
  if (!isAbsoluteFilePath(path)) {
    throw const InvalidConfigurationException(
      'The MeCab-ko dictionary path must be a non-empty absolute path.',
    );
  }
  if (!isValidPathText(path)) {
    throw const InvalidConfigurationException(
      'The MeCab-ko dictionary path must be valid Unicode without NUL and no longer than 32768 UTF-8 bytes.',
    );
  }
}

final class _DictionaryManifest {
  _DictionaryManifest({
    required Map<String, ({int size, String sha256})> files,
    required this.totalBytes,
    required this.treeSha256,
  }) : files = Map<String, ({int size, String sha256})>.unmodifiable(files);

  final Map<String, ({int size, String sha256})> files;
  final int totalBytes;
  final String treeSha256;
}

String _basename(String path) {
  final separator = Platform.pathSeparator;
  final index = path.lastIndexOf(separator);
  return index < 0 ? path : path.substring(index + separator.length);
}
