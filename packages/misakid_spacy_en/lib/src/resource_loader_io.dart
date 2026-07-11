// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:misakid/misaki.dart';

import 'resource_identity.dart';

/// Loads the two tokenizer resources from an exact model directory.
Future<
  ({
    SpacyEnglishTokenizerResources resources,
    Future<void> Function() ensureUnchanged,
  })
>
loadSpacyEnglishTokenizerResources(String modelDirectoryPath) async {
  _validateModelDirectoryPath(modelDirectoryPath);
  try {
    final resolvedRoot = await _resolveModelRoot(
      modelDirectoryPath,
      missingMessage:
          'The configured pinned spaCy English model directory does not exist.',
      invalidTypeMessage:
          'The pinned spaCy English model path must be a real directory, not a link.',
    );
    final loaded = await Future.wait(<Future<_LoadedResource>>[
      _loadResource(
        resolvedRoot,
        relativePath: 'tokenizer',
        sizeBytes: spacyEnglishTokenizerSizeBytes,
        sha256Value: spacyEnglishTokenizerSha256,
        modelName: 'pinned spaCy English model',
      ),
      _loadResource(
        resolvedRoot,
        relativePath: 'vocab/lookups.bin',
        sizeBytes: spacyEnglishVocabLookupsSizeBytes,
        sha256Value: spacyEnglishVocabLookupsSha256,
        modelName: 'pinned spaCy English model',
      ),
    ]);
    final snapshots = <String, _FileSnapshot>{
      for (final resource in loaded) resource.relativePath: resource.snapshot,
    };
    return (
      resources: SpacyEnglishTokenizerResources(
        tokenizerBytes: loaded[0].bytes,
        vocabLookupsBytes: loaded[1].bytes,
      ),
      ensureUnchanged: () => _ensureFilesUnchanged(
        modelDirectoryPath: resolvedRoot,
        files: snapshots,
        modelName: 'pinned spaCy English model',
      ),
    );
  } on MisakiException {
    rethrow;
  } on FileSystemException catch (error) {
    throw BackendUnavailableException(
      'The configured pinned spaCy English tokenizer resources could not be read.',
      cause: error,
    );
  } on ArgumentError catch (error) {
    throw InvalidConfigurationException(
      'The configured pinned spaCy English model path is invalid.',
      cause: error,
    );
  }
}

/// Loads all four small-model resources from an exact model directory.
Future<
  ({
    SpacyEnglishModelResources resources,
    Future<void> Function() ensureUnchanged,
  })
>
loadSpacyEnglishModelResources(String modelDirectoryPath) async {
  _validateModelDirectoryPath(modelDirectoryPath);
  try {
    final resolvedRoot = await _resolveModelRoot(
      modelDirectoryPath,
      missingMessage:
          'The configured en_core_web_sm model directory does not exist.',
      invalidTypeMessage:
          'The en_core_web_sm model path must be a real directory, not a link.',
    );
    final loaded = await Future.wait(<Future<_LoadedResource>>[
      _loadResource(
        resolvedRoot,
        relativePath: 'tokenizer',
        sizeBytes: spacyEnglishTokenizerSizeBytes,
        sha256Value: spacyEnglishTokenizerSha256,
        modelName: 'en_core_web_sm',
      ),
      _loadResource(
        resolvedRoot,
        relativePath: 'vocab/lookups.bin',
        sizeBytes: spacyEnglishVocabLookupsSizeBytes,
        sha256Value: spacyEnglishVocabLookupsSha256,
        modelName: 'en_core_web_sm',
      ),
      _loadResource(
        resolvedRoot,
        relativePath: 'tok2vec/model',
        sizeBytes: spacyEnglishTok2vecModelSizeBytes,
        sha256Value: spacyEnglishTok2vecModelSha256,
        modelName: 'en_core_web_sm',
      ),
      _loadResource(
        resolvedRoot,
        relativePath: 'tagger/model',
        sizeBytes: spacyEnglishTaggerModelSizeBytes,
        sha256Value: spacyEnglishTaggerModelSha256,
        modelName: 'en_core_web_sm',
      ),
    ]);
    final snapshots = <String, _FileSnapshot>{
      for (final resource in loaded) resource.relativePath: resource.snapshot,
    };
    return (
      resources: SpacyEnglishModelResources(
        tokenizerBytes: loaded[0].bytes,
        vocabLookupsBytes: loaded[1].bytes,
        tok2vecModelBytes: loaded[2].bytes,
        taggerModelBytes: loaded[3].bytes,
      ),
      ensureUnchanged: () => _ensureFilesUnchanged(
        modelDirectoryPath: resolvedRoot,
        files: snapshots,
        modelName: 'en_core_web_sm',
      ),
    );
  } on MisakiException {
    rethrow;
  } on FileSystemException catch (error) {
    throw BackendUnavailableException(
      'The configured en_core_web_sm resources could not be read.',
      cause: error,
    );
  } on ArgumentError catch (error) {
    throw InvalidConfigurationException(
      'The configured en_core_web_sm path is invalid.',
      cause: error,
    );
  }
}

Future<String> _resolveModelRoot(
  String modelDirectoryPath, {
  required String missingMessage,
  required String invalidTypeMessage,
}) async {
  final rootType = await FileSystemEntity.type(
    modelDirectoryPath,
    followLinks: false,
  );
  if (rootType == FileSystemEntityType.notFound) {
    throw BackendUnavailableException(missingMessage);
  }
  if (rootType != FileSystemEntityType.directory) {
    throw InvalidConfigurationException(invalidTypeMessage);
  }
  return Directory(modelDirectoryPath).resolveSymbolicLinks();
}

Future<void> _ensureFilesUnchanged({
  required String modelDirectoryPath,
  required Map<String, _FileSnapshot> files,
  required String modelName,
}) async {
  try {
    for (final entry in files.entries) {
      final path = '$modelDirectoryPath/${entry.key}';
      if (await FileSystemEntity.type(path, followLinks: false) !=
              FileSystemEntityType.file ||
          !entry.value.matches(await File(path).stat())) {
        throw MalformedDataException(
          'The validated $modelName resource `${entry.key}` changed while opening.',
        );
      }
    }
  } on MisakiException {
    rethrow;
  } on FileSystemException catch (error) {
    throw BackendUnavailableException(
      'A validated $modelName resource became unreadable while opening.',
      cause: error,
    );
  }
}

Future<_LoadedResource> _loadResource(
  String root, {
  required String relativePath,
  required int sizeBytes,
  required String sha256Value,
  required String modelName,
}) async {
  final path = '$root/$relativePath';
  final typeBefore = await FileSystemEntity.type(path, followLinks: false);
  if (typeBefore == FileSystemEntityType.notFound) {
    throw BackendUnavailableException(
      'The required $modelName resource `$relativePath` does not exist.',
    );
  }
  if (typeBefore != FileSystemEntityType.file) {
    throw MalformedDataException(
      'The $modelName resource `$relativePath` must be a real file, not a link.',
    );
  }
  final file = File(path);
  final before = await file.stat();
  if (before.type != FileSystemEntityType.file || before.size != sizeBytes) {
    throw MalformedDataException(
      'The $modelName resource `$relativePath` has the wrong byte size.',
    );
  }
  final bytes = await file.readAsBytes();
  final after = await file.stat();
  final snapshot = _FileSnapshot.fromStat(before);
  if (!snapshot.matches(after) ||
      sha256.convert(bytes).toString() != sha256Value) {
    throw MalformedDataException(
      'The $modelName resource `$relativePath` failed its immutable identity check.',
    );
  }
  return _LoadedResource(
    relativePath: relativePath,
    bytes: bytes,
    snapshot: snapshot,
  );
}

void _validateModelDirectoryPath(String path) {
  if (!_isAbsolutePath(path) || !_isValidPathText(path)) {
    throw const InvalidConfigurationException(
      'The pinned spaCy English model directory must be a valid non-empty absolute '
      'path without NUL and no longer than 32768 UTF-8 bytes.',
    );
  }
}

bool _isAbsolutePath(String path) {
  if (path.isEmpty) return false;
  if (!Platform.isWindows) return path.startsWith('/');
  return RegExp(r'^(?:[A-Za-z]:[\\/]|\\\\)').hasMatch(path);
}

bool _isValidPathText(String path) {
  var utf8Bytes = 0;
  final units = path.codeUnits;
  for (var index = 0; index < units.length; index++) {
    final unit = units[index];
    if (unit == 0) return false;
    if (unit <= 0x7f) {
      utf8Bytes++;
    } else if (unit <= 0x7ff) {
      utf8Bytes += 2;
    } else if (unit >= 0xd800 && unit <= 0xdbff) {
      if (index + 1 >= units.length ||
          units[index + 1] < 0xdc00 ||
          units[index + 1] > 0xdfff) {
        return false;
      }
      utf8Bytes += 4;
      index++;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return false;
    } else {
      utf8Bytes += 3;
    }
    if (utf8Bytes > 32768) return false;
  }
  return true;
}

final class _LoadedResource {
  const _LoadedResource({
    required this.relativePath,
    required this.bytes,
    required this.snapshot,
  });

  final String relativePath;
  final Uint8List bytes;
  final _FileSnapshot snapshot;
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
      stat.type == FileSystemEntityType.file &&
      stat.size == size &&
      stat.modified.microsecondsSinceEpoch == modifiedMicroseconds &&
      stat.changed.microsecondsSinceEpoch == changedMicroseconds;
}
