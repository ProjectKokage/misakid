// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:misakid/misaki.dart';

/// Exact SHA-256 of pinned Misaki's `misaki/data/ja_words.txt`.
const String pinnedMisakiCutletWordsSha256 =
    'a93a8e8aee24db307a32becb8bf01c4c2908ecf37e6c91f7a705fafdfeba67ff';

/// Exact byte size of pinned Misaki's grouping resource.
const int pinnedMisakiCutletWordsSizeBytes = 1921140;

/// Exact number of unique sorted records in the grouping resource.
const int pinnedMisakiCutletWordsRecordCount = 147571;

const String _upstreamCommit = 'fba1236595f2d2bf21d414ba6e57d25256afada3';
const int _maximumPathUtf8Bytes = 32768;

/// Explicit, provenance-bearing membership boundary for Cutlet grouping.
///
/// The pinned Cutlet algorithm performs longest-match lookup against a word
/// set. Callers may inject a separately licensed implementation through this
/// interface instead of using [PinnedMisakiCutletWordMembership].
abstract interface class JapaneseCutletWordMembership implements MisakiBackend {
  /// Whether [surface] is an exact member of the configured word set.
  bool contains(String surface);
}

/// In-memory exact membership for an explicitly supplied pinned Misaki word
/// list.
///
/// The file is validated byte-for-byte and never auto-discovered or
/// downloaded. This package identifies the file's location in pinned Misaki;
/// it does not assert undocumented provenance for the list's underlying data.
final class PinnedMisakiCutletWordMembership
    implements JapaneseCutletWordMembership {
  PinnedMisakiCutletWordMembership._(Set<String> words)
    : _words = Set<String>.unmodifiable(words),
      info = BackendInfo(
        name: 'misaki-ja-words',
        version: _upstreamCommit,
        details: const <String, String>{
          'repository': 'hexgrad/misaki',
          'path': 'misaki/data/ja_words.txt',
          'sha256': pinnedMisakiCutletWordsSha256,
          'bytes': '1921140',
          'records': '147571',
          'terminalLf': 'false',
        },
      );

  final Set<String> _words;

  @override
  final BackendInfo info;

  /// Loads an owned byte copy after the same exact validation as [open].
  ///
  /// This entry point is intended for Flutter assets and other mobile resource
  /// loaders that cannot expose packaged data as a stable filesystem path.
  static PinnedMisakiCutletWordMembership fromBytes(Uint8List source) {
    final bytes = Uint8List.fromList(source);
    return _parseValidatedBytes(bytes);
  }

  /// Loads the explicitly configured regular file after exact validation.
  static Future<PinnedMisakiCutletWordMembership> open(String path) async {
    _validatePath(path);
    try {
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        throw const BackendUnavailableException(
          'The configured pinned Misaki Japanese word list does not exist.',
        );
      }
      if (type != FileSystemEntityType.file) {
        throw const MalformedDataException(
          'The pinned Misaki Japanese word list must be a real file, not a link.',
        );
      }
      final file = File(path);
      final before = await file.stat();
      if (before.type != FileSystemEntityType.file ||
          before.size != pinnedMisakiCutletWordsSizeBytes) {
        throw const MalformedDataException(
          'The pinned Misaki Japanese word list has the wrong type or size.',
        );
      }
      final bytes = await file.readAsBytes();
      final after = await file.stat();
      if (!_sameSnapshot(before, after) ||
          await FileSystemEntity.type(path, followLinks: false) !=
              FileSystemEntityType.file) {
        throw const MalformedDataException(
          'The pinned Misaki Japanese word list changed while being loaded.',
        );
      }
      return _parseValidatedBytes(bytes);
    } on MisakiException {
      rethrow;
    } on FileSystemException catch (error) {
      throw BackendUnavailableException(
        'The pinned Misaki Japanese word list could not be read.',
        cause: error,
      );
    } on ArgumentError catch (error) {
      throw InvalidConfigurationException(
        'The pinned Misaki Japanese word-list path is invalid.',
        cause: error,
      );
    }
  }

  @override
  bool contains(String surface) => _words.contains(surface);
}

PinnedMisakiCutletWordMembership _parseValidatedBytes(Uint8List bytes) {
  if (bytes.length != pinnedMisakiCutletWordsSizeBytes) {
    throw const MalformedDataException(
      'The pinned Misaki Japanese word list has the wrong size.',
    );
  }
  if (sha256.convert(bytes).toString() != pinnedMisakiCutletWordsSha256) {
    throw const MalformedDataException(
      'The pinned Misaki Japanese word list failed its SHA-256 check.',
    );
  }
  if (bytes.isEmpty || bytes.last == 0x0A) {
    throw const MalformedDataException(
      'The pinned Misaki Japanese word list must have no terminal LF.',
    );
  }

  final String text;
  try {
    text = utf8.decode(bytes, allowMalformed: false);
  } on FormatException catch (error) {
    throw MalformedDataException(
      'The pinned Misaki Japanese word list is not valid UTF-8.',
      cause: error,
    );
  }
  final records = text.split('\n');
  if (records.length != pinnedMisakiCutletWordsRecordCount) {
    throw const MalformedDataException(
      'The pinned Misaki Japanese word list has the wrong record count.',
    );
  }
  for (var index = 0; index < records.length; index++) {
    final record = records[index];
    if (record.isEmpty || record.contains('\r') || record.contains('\u0000')) {
      throw MalformedDataException(
        'The pinned Misaki Japanese word list has an invalid record at $index.',
      );
    }
    if (index > 0 && _compareUnicodeScalars(records[index - 1], record) >= 0) {
      throw MalformedDataException(
        'The pinned Misaki Japanese word list is not unique and sorted at $index.',
      );
    }
  }
  final words = records.toSet();
  if (words.length != pinnedMisakiCutletWordsRecordCount) {
    throw const MalformedDataException(
      'The pinned Misaki Japanese word list contains duplicate records.',
    );
  }
  return PinnedMisakiCutletWordMembership._(words);
}

bool _sameSnapshot(FileStat first, FileStat second) =>
    second.type == FileSystemEntityType.file &&
    first.size == second.size &&
    first.modified.microsecondsSinceEpoch ==
        second.modified.microsecondsSinceEpoch &&
    first.changed.microsecondsSinceEpoch ==
        second.changed.microsecondsSinceEpoch;

int _compareUnicodeScalars(String left, String right) {
  final leftRunes = left.runes.iterator;
  final rightRunes = right.runes.iterator;
  while (true) {
    final hasLeft = leftRunes.moveNext();
    final hasRight = rightRunes.moveNext();
    if (!hasLeft || !hasRight) {
      if (hasLeft == hasRight) return 0;
      return hasLeft ? 1 : -1;
    }
    final difference = leftRunes.current - rightRunes.current;
    if (difference != 0) return difference;
  }
}

void _validatePath(String path) {
  if (!_isAbsolutePath(path)) {
    throw const InvalidConfigurationException(
      'The pinned Misaki Japanese word-list path must be a non-empty absolute path.',
    );
  }
  if (!_isValidPathText(path)) {
    throw const InvalidConfigurationException(
      'The pinned Misaki Japanese word-list path must be valid Unicode without NUL and no longer than 32768 UTF-8 bytes.',
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
