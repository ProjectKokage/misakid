// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:misakid/misaki.dart';
import 'package:misakid_adapter_support/file_system.dart';

import 'bounded_file_reader.dart';
import 'limits.dart';
import 'resource_identity.dart';

/// Immutable in-memory snapshot of an exactly identified external model.
final class BartResourceBundle {
  BartResourceBundle._({
    required this.configPath,
    required this.weightsPath,
    required this.configBytes,
    required this.weightsBytes,
    required FileSnapshot configSnapshot,
    required FileSnapshot weightsSnapshot,
  }) : _configSnapshot = configSnapshot,
       _weightsSnapshot = weightsSnapshot;

  final String configPath;
  final String weightsPath;
  final Uint8List configBytes;
  final Uint8List weightsBytes;
  final FileSnapshot _configSnapshot;
  final FileSnapshot _weightsSnapshot;

  static Future<BartResourceBundle> load({
    required String configPath,
    required String weightsPath,
    required BartEnglishResourceIdentity identity,
  }) async {
    _validatePaths(configPath, weightsPath);
    if (identity.configSizeBytes > maximumBartEnglishConfigBytes) {
      throw const InvalidConfigurationException(
        'The configured BART JSON identity exceeds the 1 MiB limit.',
      );
    }
    if (identity.weightsSizeBytes > maximumBartEnglishWeightsBytes) {
      throw const InvalidConfigurationException(
        'The configured BART weights identity exceeds the 16 MiB limit.',
      );
    }
    try {
      final config = await _readExactFile(
        path: configPath,
        expectedBytes: identity.configSizeBytes,
        expectedSha256: identity.configSha256,
        resourceLabel: 'configuration',
      );
      final weights = await _readExactFile(
        path: weightsPath,
        expectedBytes: identity.weightsSizeBytes,
        expectedSha256: identity.weightsSha256,
        resourceLabel: 'weights',
      );
      if (config.path == weights.path) {
        throw const InvalidConfigurationException(
          'BART configuration and weights must be separate files.',
        );
      }
      return BartResourceBundle._(
        configPath: config.path,
        weightsPath: weights.path,
        configBytes: config.bytes,
        weightsBytes: weights.bytes,
        configSnapshot: config.snapshot,
        weightsSnapshot: weights.snapshot,
      );
    } on MisakiException {
      rethrow;
    } on FileSystemException catch (error) {
      throw BackendUnavailableException(
        'The configured BART resources could not be read.',
        cause: error,
      );
    } on ArgumentError catch (error) {
      throw InvalidConfigurationException(
        'A configured BART resource path is invalid.',
        cause: error,
      );
    }
  }

  /// Rejects resources changed while their decoded model was initialized.
  Future<void> ensureUnchanged() async {
    try {
      await _ensureFileUnchanged(configPath, _configSnapshot, 'configuration');
      await _ensureFileUnchanged(weightsPath, _weightsSnapshot, 'weights');
    } on MisakiException {
      rethrow;
    } on FileSystemException catch (error) {
      throw BackendUnavailableException(
        'The validated BART resources became unreadable while opening.',
        cause: error,
      );
    }
  }
}

Future<_ReadFile> _readExactFile({
  required String path,
  required int expectedBytes,
  required String expectedSha256,
  required String resourceLabel,
}) async {
  final type = await FileSystemEntity.type(path, followLinks: false);
  if (type == FileSystemEntityType.notFound) {
    throw BackendUnavailableException(
      'The configured BART $resourceLabel file does not exist.',
    );
  }
  if (type != FileSystemEntityType.file) {
    throw MalformedDataException(
      'The configured BART $resourceLabel must be a real file, not a link or special entry.',
    );
  }
  final resolved = await File(path).resolveSymbolicLinks();
  final file = File(resolved);
  final before = await file.stat();
  if (before.type != FileSystemEntityType.file ||
      before.size != expectedBytes) {
    throw MalformedDataException(
      'The configured BART $resourceLabel has the wrong type or byte size.',
    );
  }
  final bytes = await readExactlyBoundedFile(file, expectedBytes);
  final after = await file.stat();
  final snapshot = FileSnapshot.fromStat(before);
  if (!snapshot.matches(after) ||
      bytes.length != expectedBytes ||
      sha256.convert(bytes).toString() != expectedSha256) {
    throw MalformedDataException(
      'The configured BART $resourceLabel failed its immutable identity check.',
    );
  }
  return _ReadFile(
    path: resolved,
    bytes: Uint8List.fromList(bytes),
    snapshot: snapshot,
  );
}

Future<void> _ensureFileUnchanged(
  String path,
  FileSnapshot snapshot,
  String label,
) async {
  final type = await FileSystemEntity.type(path, followLinks: false);
  if (type != FileSystemEntityType.file ||
      !snapshot.matches(await File(path).stat())) {
    throw MalformedDataException(
      'The validated BART $label changed while opening.',
    );
  }
}

void _validatePaths(String configPath, String weightsPath) {
  for (final path in <String>[configPath, weightsPath]) {
    if (!_isAbsolutePath(path)) {
      throw const InvalidConfigurationException(
        'BART resource paths must be non-empty absolute paths.',
      );
    }
    if (!_isValidPathText(path)) {
      throw const InvalidConfigurationException(
        'BART resource paths must be valid Unicode without NUL and no longer than 32768 UTF-8 bytes.',
      );
    }
  }
}

bool _isAbsolutePath(String path) {
  if (path.startsWith('/')) return true;
  if (path.startsWith(r'\\')) return true;
  return path.length >= 3 &&
      ((path.codeUnitAt(0) >= 0x41 && path.codeUnitAt(0) <= 0x5A) ||
          (path.codeUnitAt(0) >= 0x61 && path.codeUnitAt(0) <= 0x7A)) &&
      path.codeUnitAt(1) == 0x3A &&
      (path.codeUnitAt(2) == 0x2F || path.codeUnitAt(2) == 0x5C);
}

bool _isValidPathText(String path) {
  if (path.isEmpty) return false;
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
    if (utf8Bytes > maximumBartEnglishPathUtf8Bytes) return false;
  }
  return true;
}

final class _ReadFile {
  const _ReadFile({
    required this.path,
    required this.bytes,
    required this.snapshot,
  });

  final String path;
  final Uint8List bytes;
  final FileSnapshot snapshot;
}
