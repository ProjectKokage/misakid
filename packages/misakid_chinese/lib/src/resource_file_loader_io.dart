// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'dart:typed_data';

import 'package:misakid/misaki.dart';

import 'resource_file.dart';

/// Reads one regular non-link file with bounded immutable-snapshot checks.
Future<LoadedChineseResourceFile> loadChineseResourceFile({
  required String path,
  required String family,
  required String label,
  required int maximumBytes,
  int? expectedBytes,
}) async {
  try {
    final configuredType = await FileSystemEntity.type(
      path,
      followLinks: false,
    );
    if (configuredType == FileSystemEntityType.notFound) {
      throw BackendUnavailableException(
        'The configured $family $label file does not exist.',
      );
    }
    if (configuredType != FileSystemEntityType.file) {
      throw InvalidConfigurationException(
        'The configured $family $label path must be a regular non-link file.',
      );
    }

    final resolvedPath = await File(path).resolveSymbolicLinks();
    final file = File(resolvedPath);
    final resolvedType = await FileSystemEntity.type(
      resolvedPath,
      followLinks: false,
    );
    final before = await file.stat();
    if (resolvedType != FileSystemEntityType.file ||
        before.type != FileSystemEntityType.file) {
      throw InvalidConfigurationException(
        'The configured $family $label path must resolve to a regular file.',
      );
    }
    if (before.size <= 0 ||
        before.size > maximumBytes ||
        (expectedBytes != null && before.size != expectedBytes)) {
      throw MalformedDataException(
        'The $family $label file has an unexpected byte size.',
      );
    }

    final snapshot = _FileSnapshot.fromStat(before);
    final bytes = await _readBounded(file, before.size, family, label);

    Future<void> ensureUnchanged() async {
      try {
        final type = await FileSystemEntity.type(
          resolvedPath,
          followLinks: false,
        );
        final current = await file.stat();
        if (type != FileSystemEntityType.file || !snapshot.matches(current)) {
          throw MalformedDataException(
            'The $family $label file changed while it was being opened.',
          );
        }
      } on MisakiException {
        rethrow;
      } on FileSystemException catch (error) {
        throw BackendUnavailableException(
          'The configured $family $label file could not be revalidated.',
          cause: error,
        );
      }
    }

    await ensureUnchanged();
    return LoadedChineseResourceFile(
      resolvedPath: resolvedPath,
      bytes: bytes,
      ensureUnchanged: ensureUnchanged,
    );
  } on MisakiException {
    rethrow;
  } on FileSystemException catch (error) {
    throw BackendUnavailableException(
      'The configured $family $label file could not be read.',
      cause: error,
    );
  } on ArgumentError catch (error) {
    throw InvalidConfigurationException(
      'The configured $family $label path is invalid.',
      cause: error,
    );
  }
}

Future<Uint8List> _readBounded(
  File file,
  int expectedBytes,
  String family,
  String label,
) async {
  final output = BytesBuilder(copy: false);
  var byteCount = 0;
  await for (final chunk in file.openRead()) {
    byteCount += chunk.length;
    if (byteCount > expectedBytes) {
      throw MalformedDataException(
        'The $family $label file grew beyond its expected resource bound.',
      );
    }
    output.add(chunk);
  }
  if (byteCount != expectedBytes) {
    throw MalformedDataException(
      'The $family $label file changed size while it was being read.',
    );
  }
  return output.takeBytes();
}

final class _FileSnapshot {
  const _FileSnapshot({
    required this.size,
    required this.modified,
    required this.changed,
    required this.mode,
  });

  factory _FileSnapshot.fromStat(FileStat stat) => _FileSnapshot(
    size: stat.size,
    modified: stat.modified,
    changed: stat.changed,
    mode: stat.mode,
  );

  final int size;
  final DateTime modified;
  final DateTime changed;
  final int mode;

  bool matches(FileStat stat) =>
      stat.type == FileSystemEntityType.file &&
      stat.size == size &&
      stat.modified == modified &&
      stat.changed == changed &&
      stat.mode == mode;
}
