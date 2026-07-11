// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:misakid/misaki.dart';

/// Exact model distribution accepted by this resource boundary.
const String spacyTransformerModelVersion = '3.8.0';

/// Exact `tokenizer` resource size.
const int spacyTransformerTokenizerSizeBytes = 77066;

/// Exact `tokenizer` resource SHA-256.
const String spacyTransformerTokenizerSha256 =
    'b014e8bba4958b120af2d0c1c63eabb7c00379f2bacaf10df7c5325efd2ea467';

/// Exact `vocab/lookups.bin` resource size.
const int spacyTransformerVocabLookupsSizeBytes = 70040;

/// Exact `vocab/lookups.bin` resource SHA-256.
const String spacyTransformerVocabLookupsSha256 =
    'fce9c883c56165f29573cc938c2a1c9d417ac61bd8f56b671dd5f7996de70682';

/// Exact `transformer/model` resource size.
const int spacyTransformerModelSizeBytes = 497343046;

/// Exact `transformer/model` resource SHA-256.
const String spacyTransformerModelSha256 =
    '2b7061c623f424486e5dddcff79276927127cee339cc6a9d26d87837c3e6074a';

/// Exact `tagger/model` resource size.
const int spacyTransformerTaggerModelSizeBytes = 151450;

/// Exact `tagger/model` resource SHA-256.
const String spacyTransformerTaggerModelSha256 =
    'a489a41d998a6c042eaa279b6b823cd24b40854faf602e696d280788ed62f84c';

/// Offset of the reviewed serialized Byte-BPE payload in `transformer/model`.
const int spacyTransformerByteBpeOffsetBytes = 416;

/// Length of the reviewed serialized Byte-BPE payload.
const int spacyTransformerByteBpeSizeBytes = 1063863;

/// SHA-256 of the reviewed serialized Byte-BPE payload.
const String spacyTransformerByteBpeSha256 =
    '3a937453afcd04229fc5e32d7304c117781d4c48f1e7c87a603194e2077576f0';

const int _maximumPathUtf8Bytes = 32768;
const int _readChunkBytes = 64 * 1024;

/// Immutable snapshot of the exact non-native transformer resources.
///
/// The 497 MB transformer model is streamed only for identity validation. The
/// snapshot retains its canonical path plus copies of the small tokenizer,
/// lookup, tagger-head, and reviewed Byte-BPE range only.
final class SpacyTransformerResourceSnapshot {
  SpacyTransformerResourceSnapshot._({
    required this.modelDirectoryPath,
    required this.transformerModelPath,
    required Uint8List tokenizerBytes,
    required Uint8List vocabLookupsBytes,
    required Uint8List byteBpeBytes,
    required Uint8List taggerModelBytes,
    required Map<String, _FileSnapshot> files,
  }) : _tokenizerBytes = Uint8List.fromList(tokenizerBytes),
       _vocabLookupsBytes = Uint8List.fromList(vocabLookupsBytes),
       _byteBpeBytes = Uint8List.fromList(byteBpeBytes),
       _taggerModelBytes = Uint8List.fromList(taggerModelBytes),
       _files = Map<String, _FileSnapshot>.unmodifiable(files);

  /// Canonical path to the exact extracted model root.
  final String modelDirectoryPath;

  /// Canonical path to `transformer/model`; its bytes are not retained.
  final String transformerModelPath;

  final Uint8List _tokenizerBytes;
  final Uint8List _vocabLookupsBytes;
  final Uint8List _byteBpeBytes;
  final Uint8List _taggerModelBytes;
  final Map<String, _FileSnapshot> _files;

  /// Returns a defensive copy of the exact serialized tokenizer.
  Uint8List get tokenizerBytes => Uint8List.fromList(_tokenizerBytes);

  /// Returns a defensive copy of the exact lexical lookup resource.
  Uint8List get vocabLookupsBytes => Uint8List.fromList(_vocabLookupsBytes);

  /// Returns a defensive copy of the reviewed Byte-BPE payload range.
  Uint8List get byteBpeBytes => Uint8List.fromList(_byteBpeBytes);

  /// Returns a defensive copy of the exact serialized tagger graph.
  Uint8List get taggerModelBytes => Uint8List.fromList(_taggerModelBytes);

  /// Streams and validates the exact four-resource transformer profile.
  static Future<SpacyTransformerResourceSnapshot> validate(
    String modelDirectoryPath,
  ) async {
    _validateAbsolutePath(modelDirectoryPath);
    try {
      final rootType = await FileSystemEntity.type(
        modelDirectoryPath,
        followLinks: false,
      );
      if (rootType == FileSystemEntityType.notFound) {
        throw const BackendUnavailableException(
          'The configured en_core_web_trf model directory does not exist.',
        );
      }
      if (rootType != FileSystemEntityType.directory) {
        throw const InvalidConfigurationException(
          'The en_core_web_trf model root must be a real directory, not a link.',
        );
      }
      final root = await Directory(modelDirectoryPath).resolveSymbolicLinks();
      if (root != modelDirectoryPath) {
        throw const InvalidConfigurationException(
          'The en_core_web_trf model root must be an absolute canonical path.',
        );
      }

      final tokenizer = await _loadSmallResource(
        root,
        relativePath: 'tokenizer',
        expectedSize: spacyTransformerTokenizerSizeBytes,
        expectedSha256: spacyTransformerTokenizerSha256,
      );
      final lookups = await _loadSmallResource(
        root,
        relativePath: 'vocab/lookups.bin',
        expectedSize: spacyTransformerVocabLookupsSizeBytes,
        expectedSha256: spacyTransformerVocabLookupsSha256,
      );
      final tagger = await _loadSmallResource(
        root,
        relativePath: 'tagger/model',
        expectedSize: spacyTransformerTaggerModelSizeBytes,
        expectedSha256: spacyTransformerTaggerModelSha256,
      );
      final transformer = await _validateTransformerResource(root);

      return SpacyTransformerResourceSnapshot._(
        modelDirectoryPath: root,
        transformerModelPath: transformer.path,
        tokenizerBytes: tokenizer.bytes,
        vocabLookupsBytes: lookups.bytes,
        byteBpeBytes: transformer.byteBpeBytes,
        taggerModelBytes: tagger.bytes,
        files: <String, _FileSnapshot>{
          tokenizer.relativePath: tokenizer.snapshot,
          lookups.relativePath: lookups.snapshot,
          tagger.relativePath: tagger.snapshot,
          transformer.relativePath: transformer.snapshot,
        },
      );
    } on MisakiException {
      rethrow;
    } on FileSystemException catch (error) {
      throw BackendUnavailableException(
        'The configured en_core_web_trf resources could not be read.',
        cause: error,
      );
    } on ArgumentError catch (error) {
      throw InvalidConfigurationException(
        'The configured en_core_web_trf path is invalid.',
        cause: error,
      );
    }
  }

  /// Rejects a path, type, size, or timestamp change after validation.
  Future<void> ensureUnchanged() async {
    try {
      if (await FileSystemEntity.type(modelDirectoryPath, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw const MalformedDataException(
          'The validated en_core_web_trf model root changed while opening.',
        );
      }
      final resolvedRoot = await Directory(
        modelDirectoryPath,
      ).resolveSymbolicLinks();
      if (resolvedRoot != modelDirectoryPath) {
        throw const MalformedDataException(
          'The validated en_core_web_trf model root changed while opening.',
        );
      }
      for (final entry in _files.entries) {
        final path = _resourcePath(modelDirectoryPath, entry.key);
        await _requireUnchangedFile(path, entry.key, entry.value);
      }
    } on MisakiException {
      rethrow;
    } on FileSystemException catch (error) {
      throw BackendUnavailableException(
        'A validated en_core_web_trf resource became unreadable while opening.',
        cause: error,
      );
    }
  }
}

Future<_LoadedSmallResource> _loadSmallResource(
  String root, {
  required String relativePath,
  required int expectedSize,
  required String expectedSha256,
}) async {
  final path = _resourcePath(root, relativePath);
  final before = await _statCanonicalFile(
    path,
    relativePath,
    expectedSize: expectedSize,
  );
  final bytes = await _readExactRange(
    File(path),
    offset: 0,
    length: expectedSize,
    requireEndOfFile: true,
    relativePath: relativePath,
  );
  final after = await _statCanonicalFile(
    path,
    relativePath,
    expectedSize: expectedSize,
  );
  if (!before.matches(after) ||
      sha256.convert(bytes).toString() != expectedSha256) {
    throw MalformedDataException(
      'The en_core_web_trf resource `$relativePath` failed its immutable identity check.',
    );
  }
  return _LoadedSmallResource(
    relativePath: relativePath,
    bytes: bytes,
    snapshot: before,
  );
}

Future<_LoadedTransformerResource> _validateTransformerResource(
  String root,
) async {
  const relativePath = 'transformer/model';
  final path = _resourcePath(root, relativePath);
  final before = await _statCanonicalFile(
    path,
    relativePath,
    expectedSize: spacyTransformerModelSizeBytes,
  );
  final digest = await sha256
      .bind(File(path).openRead(0, spacyTransformerModelSizeBytes))
      .single;
  final afterHash = await _statCanonicalFile(
    path,
    relativePath,
    expectedSize: spacyTransformerModelSizeBytes,
  );
  if (!before.matches(afterHash) ||
      digest.toString() != spacyTransformerModelSha256) {
    throw const MalformedDataException(
      'The en_core_web_trf resource `transformer/model` failed its immutable identity check.',
    );
  }

  final byteBpeBytes = await _readExactRange(
    File(path),
    offset: spacyTransformerByteBpeOffsetBytes,
    length: spacyTransformerByteBpeSizeBytes,
    requireEndOfFile: false,
    relativePath: relativePath,
  );
  final afterRange = await _statCanonicalFile(
    path,
    relativePath,
    expectedSize: spacyTransformerModelSizeBytes,
  );
  if (!before.matches(afterRange) ||
      sha256.convert(byteBpeBytes).toString() !=
          spacyTransformerByteBpeSha256) {
    throw const MalformedDataException(
      'The reviewed Byte-BPE range changed while validating transformer/model.',
    );
  }
  return _LoadedTransformerResource(
    relativePath: relativePath,
    path: path,
    byteBpeBytes: byteBpeBytes,
    snapshot: before,
  );
}

Future<_FileSnapshot> _statCanonicalFile(
  String path,
  String relativePath, {
  required int expectedSize,
}) async {
  final type = await FileSystemEntity.type(path, followLinks: false);
  if (type == FileSystemEntityType.notFound) {
    throw BackendUnavailableException(
      'The required en_core_web_trf resource `$relativePath` does not exist.',
    );
  }
  if (type != FileSystemEntityType.file) {
    throw MalformedDataException(
      'The en_core_web_trf resource `$relativePath` must be a real file, not a link.',
    );
  }
  final resolved = await File(path).resolveSymbolicLinks();
  if (resolved != path) {
    throw MalformedDataException(
      'The en_core_web_trf resource `$relativePath` must have a canonical path without links.',
    );
  }
  final stat = await File(path).stat();
  if (stat.type != FileSystemEntityType.file || stat.size != expectedSize) {
    throw MalformedDataException(
      'The en_core_web_trf resource `$relativePath` has the wrong byte size.',
    );
  }
  return _FileSnapshot.fromStat(stat);
}

Future<void> _requireUnchangedFile(
  String path,
  String relativePath,
  _FileSnapshot snapshot,
) async {
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw MalformedDataException(
      'The validated en_core_web_trf resource `$relativePath` changed while opening.',
    );
  }
  final resolved = await File(path).resolveSymbolicLinks();
  final current = await File(path).stat();
  if (resolved != path || !snapshot.matches(_FileSnapshot.fromStat(current))) {
    throw MalformedDataException(
      'The validated en_core_web_trf resource `$relativePath` changed while opening.',
    );
  }
}

Future<Uint8List> _readExactRange(
  File file, {
  required int offset,
  required int length,
  required bool requireEndOfFile,
  required String relativePath,
}) async {
  final handle = await file.open();
  try {
    await handle.setPosition(offset);
    final builder = BytesBuilder(copy: false);
    var remaining = length;
    while (remaining > 0) {
      final chunk = await handle.read(math.min(remaining, _readChunkBytes));
      if (chunk.isEmpty) {
        throw MalformedDataException(
          'The en_core_web_trf resource `$relativePath` ended while reading a bounded range.',
        );
      }
      builder.add(chunk);
      remaining -= chunk.length;
    }
    if (requireEndOfFile && (await handle.read(1)).isNotEmpty) {
      throw MalformedDataException(
        'The en_core_web_trf resource `$relativePath` grew while reading.',
      );
    }
    return builder.takeBytes();
  } finally {
    await handle.close();
  }
}

void _validateAbsolutePath(String path) {
  if (!_isAbsolutePath(path) || !_isValidPathText(path)) {
    throw const InvalidConfigurationException(
      'The en_core_web_trf model root must be a valid canonical absolute path '
      'without NUL and no longer than 32768 UTF-8 bytes.',
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
    if (utf8Bytes > _maximumPathUtf8Bytes) return false;
  }
  return true;
}

String _resourcePath(String root, String relativePath) {
  final platformRelative = relativePath.replaceAll('/', Platform.pathSeparator);
  return '$root${Platform.pathSeparator}$platformRelative';
}

final class _LoadedSmallResource {
  const _LoadedSmallResource({
    required this.relativePath,
    required this.bytes,
    required this.snapshot,
  });

  final String relativePath;
  final Uint8List bytes;
  final _FileSnapshot snapshot;
}

final class _LoadedTransformerResource {
  const _LoadedTransformerResource({
    required this.relativePath,
    required this.path,
    required this.byteBpeBytes,
    required this.snapshot,
  });

  final String relativePath;
  final String path;
  final Uint8List byteBpeBytes;
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

  bool matches(_FileSnapshot other) =>
      size == other.size &&
      modifiedMicroseconds == other.modifiedMicroseconds &&
      changedMicroseconds == other.changedMicroseconds;
}
