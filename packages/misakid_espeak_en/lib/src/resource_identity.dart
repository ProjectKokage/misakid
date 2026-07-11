// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:misakid/misaki.dart';

/// Exact SHA-256 of the provisioned eSpeak NG 1.52.0 macOS-arm64 library.
const String pinnedEspeakNgLibrarySha256 =
    'bb635eee1ee9c456f4a5cf06fb6cb352ecdd4d61e1951743b423ef22bb57f470';

/// Exact byte size of the provisioned eSpeak NG library.
const int pinnedEspeakNgLibrarySizeBytes = 504168;

/// Canonical relative-path/size/content digest of the eSpeak NG data tree.
const String pinnedEspeakNgDataTreeSha256 =
    '730e20a0d06976b23b8344bac21dab6e1da447d0e16906bab6a0b54db89dd6e2';

/// Exact number of files in the provisioned eSpeak NG data tree.
const int pinnedEspeakNgDataFileCount = 364;

/// Exact number of directories, including the provisioned data-tree root.
const int pinnedEspeakNgDataDirectoryCount = 37;

/// Exact aggregate byte size of the provisioned eSpeak NG data tree.
const int pinnedEspeakNgDataSizeBytes = 18373365;

/// Validated immutable snapshot of the caller-supplied eSpeak resources.
final class EspeakResourceSnapshot {
  EspeakResourceSnapshot._({
    required this.libraryPath,
    required this.dataPath,
    required _FileSnapshot library,
    required Map<String, _FileSnapshot> dataFiles,
    required Map<String, _FileSnapshot> dataDirectories,
  }) : _library = library,
       _dataFiles = Map<String, _FileSnapshot>.unmodifiable(dataFiles),
       _dataDirectories = Map<String, _FileSnapshot>.unmodifiable(
         dataDirectories,
       );

  /// Canonical native library path passed to the owned-result shim.
  final String libraryPath;

  /// Canonical data-root path passed to `espeak_Initialize`.
  final String dataPath;

  final _FileSnapshot _library;
  final Map<String, _FileSnapshot> _dataFiles;
  final Map<String, _FileSnapshot> _dataDirectories;

  /// Streams and validates the exact library and complete data-tree identity.
  static Future<EspeakResourceSnapshot> validate({
    required String libraryPath,
    required String dataPath,
  }) async {
    try {
      return await _validateReadable(
        libraryPath: libraryPath,
        dataPath: dataPath,
      );
    } on MisakiException {
      rethrow;
    } on FileSystemException catch (error) {
      throw BackendUnavailableException(
        'The configured eSpeak NG resources could not be read.',
        cause: error,
      );
    } on ArgumentError catch (error) {
      throw InvalidConfigurationException(
        'An eSpeak NG resource path is invalid.',
        cause: error,
      );
    }
  }

  static Future<EspeakResourceSnapshot> _validateReadable({
    required String libraryPath,
    required String dataPath,
  }) async {
    final libraryType = await FileSystemEntity.type(
      libraryPath,
      followLinks: false,
    );
    if (libraryType == FileSystemEntityType.notFound) {
      throw const BackendUnavailableException(
        'The configured eSpeak NG library does not exist.',
      );
    }
    if (libraryType != FileSystemEntityType.file) {
      throw const MalformedDataException(
        'The configured eSpeak NG library must be a real file, not a link.',
      );
    }
    final libraryFile = File(libraryPath);
    final resolvedLibrary = await libraryFile.resolveSymbolicLinks();
    final libraryBefore = await File(resolvedLibrary).stat();
    if (libraryBefore.type != FileSystemEntityType.file ||
        libraryBefore.size != pinnedEspeakNgLibrarySizeBytes) {
      throw const MalformedDataException(
        'The configured eSpeak NG library has the wrong type or byte size.',
      );
    }
    final libraryDigest = await sha256
        .bind(File(resolvedLibrary).openRead())
        .first;
    final libraryAfter = await File(resolvedLibrary).stat();
    final librarySnapshot = _FileSnapshot.fromStat(libraryBefore);
    if (!librarySnapshot.matches(libraryAfter) ||
        libraryDigest.toString() != pinnedEspeakNgLibrarySha256) {
      throw const MalformedDataException(
        'The configured eSpeak NG library failed its immutable identity check.',
      );
    }

    final rootType = await FileSystemEntity.type(dataPath, followLinks: false);
    if (rootType == FileSystemEntityType.notFound) {
      throw const BackendUnavailableException(
        'The configured eSpeak NG data directory does not exist.',
      );
    }
    if (rootType != FileSystemEntityType.directory) {
      throw const MalformedDataException(
        'The configured eSpeak NG data root must be a real directory, not a link.',
      );
    }
    final directory = Directory(dataPath);
    final resolvedData = await directory.resolveSymbolicLinks();
    final rootSnapshot = _FileSnapshot.fromStat(await directory.stat());
    final files = <String, File>{};
    final directories = <String, _FileSnapshot>{'': rootSnapshot};
    await for (final entity in Directory(
      resolvedData,
    ).list(recursive: true, followLinks: false)) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      final relative = _relativePath(resolvedData, entity.path);
      switch (type) {
        case FileSystemEntityType.file:
          if (files.length >= pinnedEspeakNgDataFileCount ||
              files.containsKey(relative)) {
            throw const MalformedDataException(
              'The eSpeak NG data tree contains too many or duplicate files.',
            );
          }
          files[relative] = File(entity.path);
        case FileSystemEntityType.directory:
          if (directories.containsKey(relative)) {
            throw const MalformedDataException(
              'The eSpeak NG data tree contains a duplicate directory.',
            );
          }
          directories[relative] = _FileSnapshot.fromStat(
            await Directory(entity.path).stat(),
          );
        case FileSystemEntityType.link:
        case FileSystemEntityType.pipe:
        case FileSystemEntityType.unixDomainSock:
        case FileSystemEntityType.notFound:
          throw const MalformedDataException(
            'The eSpeak NG data tree contains a link or special entry.',
          );
      }
    }
    if (files.length != pinnedEspeakNgDataFileCount) {
      throw const MalformedDataException(
        'The eSpeak NG data tree has the wrong file count.',
      );
    }
    if (directories.length != pinnedEspeakNgDataDirectoryCount) {
      throw const MalformedDataException(
        'The eSpeak NG data tree has the wrong directory count.',
      );
    }
    for (final relativeDirectory in directories.keys) {
      final prefix = relativeDirectory.isEmpty ? '' : '$relativeDirectory/';
      if (!files.keys.any((path) => path.startsWith(prefix))) {
        throw const MalformedDataException(
          'The eSpeak NG data tree contains an unexpected empty directory.',
        );
      }
    }

    final treeDigestSink = _DigestSink();
    final treeSink = sha256.startChunkedConversion(treeDigestSink);
    final snapshots = <String, _FileSnapshot>{};
    var totalBytes = 0;
    final paths = files.keys.toList(growable: false)..sort();
    for (final relative in paths) {
      final file = files[relative]!;
      final typeBefore = await FileSystemEntity.type(
        file.path,
        followLinks: false,
      );
      final before = await file.stat();
      if (typeBefore != FileSystemEntityType.file ||
          before.type != FileSystemEntityType.file) {
        throw MalformedDataException(
          'eSpeak NG data file `$relative` changed type during validation.',
        );
      }
      final relativeBytes = utf8.encode(relative);
      treeSink
        ..add(_uint64BigEndian(relativeBytes.length))
        ..add(relativeBytes)
        ..add(_uint64BigEndian(before.size));
      await for (final chunk in file.openRead()) {
        treeSink.add(chunk);
      }
      final typeAfter = await FileSystemEntity.type(
        file.path,
        followLinks: false,
      );
      final after = await file.stat();
      final snapshot = _FileSnapshot.fromStat(before);
      if (typeAfter != FileSystemEntityType.file || !snapshot.matches(after)) {
        throw MalformedDataException(
          'eSpeak NG data file `$relative` changed during validation.',
        );
      }
      snapshots[relative] = snapshot;
      totalBytes += before.size;
    }
    treeSink.close();
    if (totalBytes != pinnedEspeakNgDataSizeBytes ||
        treeDigestSink.value.toString() != pinnedEspeakNgDataTreeSha256) {
      throw const MalformedDataException(
        'The eSpeak NG data-tree identity does not match the pinned runtime.',
      );
    }
    return EspeakResourceSnapshot._(
      libraryPath: resolvedLibrary,
      dataPath: resolvedData,
      library: librarySnapshot,
      dataFiles: snapshots,
      dataDirectories: directories,
    );
  }

  /// Rejects a resource changed between validation and native initialization.
  Future<void> ensureUnchanged() async {
    try {
      if (!_library.matches(await File(libraryPath).stat())) {
        throw const MalformedDataException(
          'The validated eSpeak NG library changed while opening.',
        );
      }
      for (final entry in _dataFiles.entries) {
        final path = '$dataPath/${entry.key}';
        if (await FileSystemEntity.type(path, followLinks: false) !=
                FileSystemEntityType.file ||
            !entry.value.matches(await File(path).stat())) {
          throw const MalformedDataException(
            'The validated eSpeak NG data changed while opening.',
          );
        }
      }
      for (final entry in _dataDirectories.entries) {
        final path = entry.key.isEmpty ? dataPath : '$dataPath/${entry.key}';
        if (await FileSystemEntity.type(path, followLinks: false) !=
                FileSystemEntityType.directory ||
            !entry.value.matches(await Directory(path).stat())) {
          throw const MalformedDataException(
            'The validated eSpeak NG data directories changed while opening.',
          );
        }
      }
    } on MisakiException {
      rethrow;
    } on FileSystemException catch (error) {
      throw BackendUnavailableException(
        'The validated eSpeak NG resources became unreadable while opening.',
        cause: error,
      );
    }
  }
}

final class _DigestSink implements Sink<Digest> {
  Digest? _value;

  Digest get value {
    final result = _value;
    if (result == null) {
      throw StateError('SHA-256 conversion produced no digest.');
    }
    return result;
  }

  @override
  void add(Digest data) => _value = data;

  @override
  void close() {}
}

final class _FileSnapshot {
  const _FileSnapshot({
    required this.size,
    required this.modifiedMicroseconds,
    required this.changedMicroseconds,
  });

  factory _FileSnapshot.fromStat(FileStat stat) => _FileSnapshot(
    size: stat.size,
    modifiedMicroseconds: stat.modified.microsecondsSinceEpoch,
    changedMicroseconds: stat.changed.microsecondsSinceEpoch,
  );

  final int size;
  final int modifiedMicroseconds;
  final int changedMicroseconds;

  bool matches(FileStat stat) =>
      stat.size == size &&
      stat.modified.microsecondsSinceEpoch == modifiedMicroseconds &&
      stat.changed.microsecondsSinceEpoch == changedMicroseconds;
}

Uint8List _uint64BigEndian(int value) {
  final bytes = ByteData(8)..setUint64(0, value, Endian.big);
  return bytes.buffer.asUint8List();
}

String _relativePath(String root, String path) {
  final prefix = '$root${Platform.pathSeparator}';
  if (!path.startsWith(prefix)) {
    throw const MalformedDataException(
      'The eSpeak NG data traversal escaped its configured root.',
    );
  }
  return path.substring(prefix.length).split(Platform.pathSeparator).join('/');
}
