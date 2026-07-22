// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:misakid/misaki.dart';

/// Exact dictionary distribution required by the Cutlet parity profile.
const String pinnedUnidicPyCwjDistribution = 'unidic-py';

/// Corpus variant of the exact dictionary used by the pinned fixtures.
const String pinnedUnidicPyCwjCorpus = 'cwj';

/// Release marker contained in the pinned dictionary tree.
///
/// This is descriptive metadata, not dictionary identity. The complete tree
/// hash below is the identity check.
const String pinnedUnidicPyCwjReleaseMarker = '3.1.0+2021-08-31';

/// SHA-256 of the immutable recovery archive used for the pinned tree.
const String pinnedUnidicPyCwjArchiveSha256 =
    '39ea0eae3b1f10ba8986483592cbc83bcc92f1898bb43ecbc607010f2e98cd22';

/// Exact immutable archive size.
const int pinnedUnidicPyCwjArchiveSizeBytes = 524664138;

/// Canonical SHA-256 identity of the installed 20-file tree.
const String pinnedUnidicPyCwjTreeSha256 =
    '95bd65fa96955b644c15510932ca8439f463ac8b66f57bac6dfee5e29fa03115';

/// Exact total size of the installed dictionary tree.
const int pinnedUnidicPyCwjTreeSizeBytes = 811662881;

/// Exact per-file identity of the pinned modified unidic-py CWJ tree.
const Map<String, ({int size, String sha256})>
pinnedUnidicPyCwjFileManifest = <String, ({int size, String sha256})>{
  'README': (
    size: 4490,
    sha256: '8b9c0e67caf2b1e838d63dca5a2b7ff34fa8faafe461e942ca1469f90f126e9a',
  ),
  'char.bin': (
    size: 262496,
    sha256: 'dd31396563d8924645b80fd3c9aa7b13ca089d7748f25553a1d6bc3f9b511ae8',
  ),
  'char.def': (
    size: 4292,
    sha256: '0790db12ab4f4d742b39b1737b9cce2a00c92220139a5bea9f0e8874898726e5',
  ),
  'dicrc': (
    size: 1785,
    sha256: '9b7bd3dbfdb381a078375cdcccb1e69f60256d510a5c84a3e343ae20f98dc2ce',
  ),
  'feature.def': (
    size: 8715,
    sha256: 'b50a047e6caa8a7e4158fa736728e8de46cf009bbe575b239c33312e8b30cd14',
  ),
  'left-id.def': (
    size: 1556924,
    sha256: '6e7fb23dda28ef49db733b56bc9217c39536df6ee5aa8c33d720e3d711a6baa6',
  ),
  'licenses/AUTHORS': (
    size: 22,
    sha256: 'a05bfdd3a9db36d9c64495f4a3d1824d05b95fbb4fc6dc07c660e91bc191c481',
  ),
  'licenses/BSD': (
    size: 1515,
    sha256: '770a75de30705439084f869dbcb0bc4ebcffcb7c7124c0d74f5083170318a9bb',
  ),
  'licenses/COPYING': (
    size: 210,
    sha256: 'd44b49398a72590a675e55f8f7a7dbf57bb5b71a9e20ba250f09c0cc5986bef1',
  ),
  'licenses/GPL': (
    size: 17991,
    sha256: 'a137434196f5e39d8836de895866fcfea074ad1b28243174ca1c4a585a1229b0',
  ),
  'licenses/LGPL': (
    size: 26428,
    sha256: '512d2d21b6b3384ba64781abb0208a1b87740bc31e2df48e2b206ddb7e4d5779',
  ),
  'matrix.bin': (
    size: 480905780,
    sha256: 'dd9ee6bc6bb137298cc88673e9c2143ddcf0808805c81becdd2ae5d08a869f90',
  ),
  'mecabrc': (
    size: 23,
    sha256: '8a9eb27c98dce111d8544fa8fcaaf387efc5e345efe991918363c2a5d1b7ffbc',
  ),
  'model.bin': (
    size: 83718788,
    sha256: '409efa3e3de09d8822a3443d4f97c7fda77c4f8fc991f7abc064f685e346b1c9',
  ),
  'rewrite.def': (
    size: 5076,
    sha256: '0ff0d86c7640997258ecce5468916f9eff3f2c5e5be5d43d372c0e62828deefe',
  ),
  'right-id.def': (
    size: 1767025,
    sha256: '2ec747f614eb3e8a6378f42bfbc877dfeb37fe8a331f70d9f50e0c096d4b182d',
  ),
  'sys.dic': (
    size: 243373840,
    sha256: 'f019f95838242cd614953a25201ad0b623b9c1cbca90de2507df4510db1b192c',
  ),
  'unk.def': (
    size: 1977,
    sha256: '4b40b5158f6bab29d3c0d3fd871055538241c7103406ba8e89e7d741ccf22dbc',
  ),
  'unk.dic': (
    size: 5481,
    sha256: 'a8e1067721cfd5cd7d4a17ddb53c77fb07f77fa20143b4589d7934c88f67d7e8',
  ),
  'version': (
    size: 23,
    sha256: '3240727150c25bace5f1c7e8df0208da3d01ba67121aed0ff689c0724a83d44a',
  ),
};

const int _maximumPathUtf8Bytes = 32768;
const List<String> _requiredRuntimeFiles = <String>[
  'char.bin',
  'matrix.bin',
  'sys.dic',
  'unk.dic',
];
const List<String> _optionalRuntimeFiles = <String>['dicrc'];

final _productionManifest = _DictionaryManifest(
  files: pinnedUnidicPyCwjFileManifest,
  totalBytes: pinnedUnidicPyCwjTreeSizeBytes,
  treeSha256: pinnedUnidicPyCwjTreeSha256,
);

/// Dictionary state retained while a native MeCab context is opened.
abstract interface class UnidicDictionarySnapshot {
  /// Canonical absolute directory passed to the native MeCab frontend.
  String get resolvedPath;

  /// Detects a required-file change after validation.
  Future<void> ensureUnchanged();
}

/// Minimal filesystem validation for a caller-selected UniDic dictionary.
final class CompatibleUnidicSnapshot implements UnidicDictionarySnapshot {
  CompatibleUnidicSnapshot._({
    required this.resolvedPath,
    required Map<String, _FileSnapshot?> files,
  }) : _files = Map<String, _FileSnapshot?>.unmodifiable(files);

  @override
  final String resolvedPath;

  final Map<String, _FileSnapshot?> _files;

  /// Validates the real directory and runtime files required by MeCab.
  static Future<CompatibleUnidicSnapshot> validate(String path) async {
    _validatePath(path);
    try {
      final rootType = await FileSystemEntity.type(path, followLinks: false);
      if (rootType == FileSystemEntityType.notFound) {
        throw const BackendUnavailableException(
          'The configured UniDic directory does not exist.',
        );
      }
      if (rootType != FileSystemEntityType.directory) {
        throw const MalformedDataException(
          'The configured UniDic resource must be a real directory, not a link.',
        );
      }

      final resolvedPath = await Directory(path).resolveSymbolicLinks();
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw const MalformedDataException(
          'The configured UniDic directory changed while being resolved.',
        );
      }

      final files = <String, _FileSnapshot?>{};
      for (final name in _requiredRuntimeFiles) {
        final file = File(_joinResourcePath(resolvedPath, name));
        final type = await FileSystemEntity.type(file.path, followLinks: false);
        final stat = await file.stat();
        if (type != FileSystemEntityType.file ||
            stat.type != FileSystemEntityType.file ||
            stat.size <= 0) {
          throw MalformedDataException(
            'The configured UniDic runtime file `$name` is missing or invalid.',
          );
        }
        files[name] = _FileSnapshot.fromStat(stat);
      }
      for (final name in _optionalRuntimeFiles) {
        final file = File(_joinResourcePath(resolvedPath, name));
        final type = await FileSystemEntity.type(file.path, followLinks: false);
        if (type == FileSystemEntityType.notFound) {
          files[name] = null;
          continue;
        }
        final stat = await file.stat();
        if (type != FileSystemEntityType.file ||
            stat.type != FileSystemEntityType.file) {
          throw MalformedDataException(
            'The configured UniDic optional file `$name` must be a real file.',
          );
        }
        files[name] = _FileSnapshot.fromStat(stat);
      }

      return CompatibleUnidicSnapshot._(
        resolvedPath: resolvedPath,
        files: files,
      );
    } on MisakiException {
      rethrow;
    } on FileSystemException catch (error) {
      throw BackendUnavailableException(
        'The configured UniDic dictionary could not be read.',
        cause: error,
      );
    } on ArgumentError catch (error) {
      throw InvalidConfigurationException(
        'The configured UniDic path is invalid.',
        cause: error,
      );
    }
  }

  @override
  Future<void> ensureUnchanged() async {
    try {
      if (await FileSystemEntity.type(resolvedPath, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw const MalformedDataException(
          'The validated UniDic directory changed while opening.',
        );
      }
      for (final entry in _files.entries) {
        final path = _joinResourcePath(resolvedPath, entry.key);
        final type = await FileSystemEntity.type(path, followLinks: false);
        final snapshot = entry.value;
        if (snapshot == null) {
          if (type != FileSystemEntityType.notFound) {
            throw const MalformedDataException(
              'The UniDic runtime files changed while the backend was opening.',
            );
          }
          continue;
        }
        final stat = await File(path).stat();
        if (type != FileSystemEntityType.file || !snapshot.matches(stat)) {
          throw const MalformedDataException(
            'The UniDic runtime files changed while the backend was opening.',
          );
        }
      }
    } on MisakiException {
      rethrow;
    } on FileSystemException catch (error) {
      throw BackendUnavailableException(
        'The validated UniDic dictionary became unreadable while opening.',
        cause: error,
      );
    } on ArgumentError catch (error) {
      throw MalformedDataException(
        'The validated UniDic path became invalid.',
        cause: error,
      );
    }
  }
}

/// Exact modified unidic-py CWJ identity retained across initialization.
final class PinnedUnidicPyCwjSnapshot implements UnidicDictionarySnapshot {
  PinnedUnidicPyCwjSnapshot._({
    required this.resolvedPath,
    required Map<String, _FileSnapshot> files,
    required _DictionaryManifest manifest,
  }) : _files = Map<String, _FileSnapshot>.unmodifiable(files),
       _manifest = manifest;

  @override
  final String resolvedPath;

  final Map<String, _FileSnapshot> _files;
  final _DictionaryManifest _manifest;

  /// Streams and validates every file in the pinned dictionary.
  static Future<PinnedUnidicPyCwjSnapshot> validate(String path) =>
      _validate(path, _productionManifest);

  static Future<PinnedUnidicPyCwjSnapshot> _validate(
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
        'The configured pinned unidic-py CWJ dictionary could not be read.',
        cause: error,
      );
    } on ArgumentError catch (error) {
      throw InvalidConfigurationException(
        'The configured pinned unidic-py CWJ path is invalid.',
        cause: error,
      );
    }
  }

  static Future<PinnedUnidicPyCwjSnapshot> _validateReadable(
    String path,
    _DictionaryManifest manifest,
  ) async {
    final rootType = await FileSystemEntity.type(path, followLinks: false);
    if (rootType == FileSystemEntityType.notFound) {
      throw const BackendUnavailableException(
        'The configured pinned unidic-py CWJ directory does not exist.',
      );
    }
    if (rootType != FileSystemEntityType.directory) {
      throw const MalformedDataException(
        'The configured pinned unidic-py CWJ resource must be a real directory, not a link.',
      );
    }

    final resolvedPath = await Directory(path).resolveSymbolicLinks();
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const MalformedDataException(
        'The configured pinned unidic-py CWJ directory changed while being resolved.',
      );
    }
    await _validateEntrySet(Directory(resolvedPath), manifest.files);

    final snapshots = <String, _FileSnapshot>{};
    final treeDigestSink = _DigestSink();
    final treeHasher = sha256.startChunkedConversion(treeDigestSink);
    var totalBytes = 0;
    final sortedNames = manifest.files.keys.toList(growable: false)..sort();
    for (final name in sortedNames) {
      final expected = manifest.files[name]!;
      final file = File(_joinResourcePath(resolvedPath, name));
      final typeBeforeHash = await FileSystemEntity.type(
        file.path,
        followLinks: false,
      );
      final statBeforeHash = await file.stat();
      if (typeBeforeHash != FileSystemEntityType.file ||
          statBeforeHash.type != FileSystemEntityType.file ||
          statBeforeHash.size != expected.size) {
        throw MalformedDataException(
          'Pinned unidic-py CWJ file `$name` has the wrong type or size.',
        );
      }

      final relativeBytes = utf8.encode(name);
      treeHasher
        ..add(_uint64BigEndian(relativeBytes.length))
        ..add(relativeBytes)
        ..add(_uint64BigEndian(statBeforeHash.size));
      final fileDigestSink = _DigestSink();
      final fileHasher = sha256.startChunkedConversion(fileDigestSink);
      await for (final chunk in file.openRead()) {
        fileHasher.add(chunk);
        treeHasher.add(chunk);
      }
      fileHasher.close();
      final typeAfterHash = await FileSystemEntity.type(
        file.path,
        followLinks: false,
      );
      final statAfterHash = await file.stat();
      final snapshot = _FileSnapshot.fromStat(statBeforeHash);
      if (typeAfterHash != FileSystemEntityType.file ||
          !snapshot.matches(statAfterHash)) {
        throw MalformedDataException(
          'Pinned unidic-py CWJ file `$name` changed while being validated.',
        );
      }

      final actualHash = fileDigestSink.value.toString();
      if (actualHash != expected.sha256) {
        throw MalformedDataException(
          'Pinned unidic-py CWJ file `$name` failed its SHA-256 check.',
        );
      }
      totalBytes += statBeforeHash.size;
      snapshots[name] = snapshot;
    }

    treeHasher.close();
    final treeHash = treeDigestSink.value.toString();
    if (totalBytes != manifest.totalBytes || treeHash != manifest.treeSha256) {
      throw const MalformedDataException(
        'The unidic-py CWJ tree identity does not match the pinned fixture resource.',
      );
    }
    return PinnedUnidicPyCwjSnapshot._(
      resolvedPath: resolvedPath,
      files: snapshots,
      manifest: manifest,
    );
  }

  /// Detects an entry, type, size, or timestamp change after validation.
  @override
  Future<void> ensureUnchanged() async {
    try {
      if (await FileSystemEntity.type(resolvedPath, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw const MalformedDataException(
          'The validated pinned unidic-py CWJ directory changed while opening.',
        );
      }
      await _validateEntrySet(Directory(resolvedPath), _manifest.files);
      for (final entry in _files.entries) {
        final path = _joinResourcePath(resolvedPath, entry.key);
        final type = await FileSystemEntity.type(path, followLinks: false);
        final stat = await File(path).stat();
        if (type != FileSystemEntityType.file || !entry.value.matches(stat)) {
          throw const MalformedDataException(
            'The pinned unidic-py CWJ dictionary changed while the backend was opening.',
          );
        }
      }
    } on MisakiException {
      rethrow;
    } on FileSystemException catch (error) {
      throw BackendUnavailableException(
        'The validated pinned unidic-py CWJ dictionary became unreadable while opening.',
        cause: error,
      );
    } on ArgumentError catch (error) {
      throw MalformedDataException(
        'The validated pinned unidic-py CWJ path became invalid.',
        cause: error,
      );
    }
  }
}

/// Validates a small injected tree manifest for offline integrity tests.
Future<PinnedUnidicPyCwjSnapshot> validatePinnedUnidicPyCwjForTesting(
  String path, {
  required Map<String, ({int size, String sha256})> files,
  required int totalBytes,
  required String treeSha256,
}) => PinnedUnidicPyCwjSnapshot._validate(
  path,
  _DictionaryManifest(
    files: files,
    totalBytes: totalBytes,
    treeSha256: treeSha256,
  ),
);

Future<void> _validateEntrySet(
  Directory root,
  Map<String, ({int size, String sha256})> expectedFiles,
) async {
  final expectedDirectories = <String>{};
  for (final name in expectedFiles.keys) {
    final segments = name.split('/');
    for (var index = 1; index < segments.length; index++) {
      expectedDirectories.add(segments.take(index).join('/'));
    }
  }

  final files = <String>{};
  final directories = <String>{};
  final maximumEntries = expectedFiles.length + expectedDirectories.length;
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (files.length + directories.length >= maximumEntries) {
      throw const MalformedDataException(
        'The pinned unidic-py CWJ tree contains too many entries.',
      );
    }
    final relative = _relativeResourcePath(root.path, entity.path);
    final type = await FileSystemEntity.type(entity.path, followLinks: false);
    if (type == FileSystemEntityType.file) {
      if (!expectedFiles.containsKey(relative) || !files.add(relative)) {
        throw const MalformedDataException(
          'The unidic-py CWJ file set does not match the pinned fixture resource.',
        );
      }
    } else if (type == FileSystemEntityType.directory) {
      if (!expectedDirectories.contains(relative) ||
          !directories.add(relative)) {
        throw const MalformedDataException(
          'The unidic-py CWJ directory set does not match the pinned fixture resource.',
        );
      }
    } else {
      throw const MalformedDataException(
        'The pinned unidic-py CWJ tree contains a link or special file.',
      );
    }
  }
  if (files.length != expectedFiles.length ||
      !files.containsAll(expectedFiles.keys) ||
      directories.length != expectedDirectories.length ||
      !directories.containsAll(expectedDirectories)) {
    throw const MalformedDataException(
      'The unidic-py CWJ tree does not match the pinned fixture resource.',
    );
  }
}

void _validatePath(String path) {
  if (!_isAbsolutePath(path)) {
    throw const InvalidConfigurationException(
      'The UniDic path must be a non-empty absolute path.',
    );
  }
  if (!_isValidPathText(path)) {
    throw const InvalidConfigurationException(
      'The UniDic path must be valid Unicode without NUL and no longer than 32768 UTF-8 bytes.',
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
    if (unit <= 0x7F) {
      utf8Bytes++;
    } else if (unit <= 0x7FF) {
      utf8Bytes += 2;
    } else if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (index + 1 >= units.length ||
          units[index + 1] < 0xDC00 ||
          units[index + 1] > 0xDFFF) {
        return false;
      }
      utf8Bytes += 4;
      index++;
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      return false;
    } else {
      utf8Bytes += 3;
    }
    if (utf8Bytes > _maximumPathUtf8Bytes) return false;
  }
  return true;
}

String _joinResourcePath(String root, String relative) =>
    '$root${Platform.pathSeparator}'
    '${relative.replaceAll('/', Platform.pathSeparator)}';

String _relativeResourcePath(String root, String path) {
  final prefix = '$root${Platform.pathSeparator}';
  if (!path.startsWith(prefix)) {
    throw const MalformedDataException(
      'The pinned unidic-py CWJ traversal escaped its configured directory.',
    );
  }
  return path.substring(prefix.length).replaceAll(Platform.pathSeparator, '/');
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

Uint8List _uint64BigEndian(int value) {
  final data = ByteData(8)..setUint64(0, value, Endian.big);
  return data.buffer.asUint8List();
}
