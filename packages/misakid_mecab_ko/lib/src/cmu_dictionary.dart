// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:misakid/misaki_ko.dart';
import 'package:misakid_adapter_support/file_system.dart';

const _pinnedManifest = _CmuDictionaryManifest(
  sizeBytes: 3820830,
  sha256: 'cad209c39eb87677d64e93d97f8eed10b7e6f9bdd42de8e7ca8efc8e17d62e8a',
  recordCount: 133737,
  keyCount: 123455,
);

const int _maximumLineLength = 4096;
const int _maximumFieldsPerRecord = 256;
const int _maximumWordLength = 1024;
const int _maximumPhoneLength = 32;

/// Checksum-pinned, pure-Dart CMUdict 0.7a pronunciation provider.
///
/// The caller supplies the exact extracted NLTK CMUdict file explicitly.
/// Opening validates that the path is a regular non-link file, streams no more
/// than the pinned byte count, verifies SHA-256, decodes strict UTF-8, and
/// validates the complete record/key counts. Nothing is discovered or
/// downloaded.
///
/// ```dart
/// final cmu = await CmuDictionaryPronunciationProvider.open(
///   '/absolute/path/cmudict/cmudict',
/// );
/// final pronunciation = cmu.lookup('school');
/// ```
final class CmuDictionaryPronunciationProvider
    implements KoreanCmuPronunciationProvider {
  CmuDictionaryPronunciationProvider._(
    Map<String, KoreanCmuPronunciation> pronunciations,
    _CmuDictionaryManifest manifest,
  ) : _pronunciations = Map<String, KoreanCmuPronunciation>.unmodifiable(
        pronunciations,
      ),
      info = BackendInfo(
        name: 'cmudict',
        version: '0.7a',
        details: <String, String>{
          'sha256': manifest.sha256,
          'sizeBytes': '${manifest.sizeBytes}',
          'recordCount': '${manifest.recordCount}',
          'keyCount': '${manifest.keyCount}',
        },
      );

  final Map<String, KoreanCmuPronunciation> _pronunciations;

  /// Opens and validates the exact pinned CMUdict resource at [path].
  ///
  /// The returned provider performs synchronous in-memory lookups. A missing
  /// or unreadable path throws [BackendUnavailableException]; an invalid path
  /// kind throws [InvalidConfigurationException]; and changed, corrupt, or
  /// incompatible data throws [MalformedDataException].
  static Future<CmuDictionaryPronunciationProvider> open(String path) =>
      _openCmuDictionary(path, _pinnedManifest);

  @override
  final BackendInfo info;

  @override
  KoreanCmuPronunciation? lookup(String word) => _pronunciations[word];
}

/// Test-only synthetic-manifest entrypoint for this unexported `src` library.
///
/// The package's public entrypoint should export only
/// [CmuDictionaryPronunciationProvider]. This function lets unit tests exercise
/// successful parsing without committing the 3.8 MB dictionary resource.
Future<CmuDictionaryPronunciationProvider> openCmuDictionaryForTesting(
  String path, {
  required int expectedSizeBytes,
  required String expectedSha256,
  required int expectedRecordCount,
  required int expectedKeyCount,
}) {
  final manifest = _CmuDictionaryManifest(
    sizeBytes: expectedSizeBytes,
    sha256: expectedSha256,
    recordCount: expectedRecordCount,
    keyCount: expectedKeyCount,
  );
  if (!manifest.isValid) {
    throw const InvalidConfigurationException(
      'The test CMUdict manifest is invalid.',
    );
  }
  return _openCmuDictionary(path, manifest);
}

Future<CmuDictionaryPronunciationProvider> _openCmuDictionary(
  String path,
  _CmuDictionaryManifest manifest,
) async {
  if (!isAbsoluteFilePath(path) || !isValidPathText(path)) {
    throw const InvalidConfigurationException(
      'The CMUdict file path must be absolute, valid Unicode without NUL, and no longer than 32768 UTF-8 bytes.',
    );
  }

  try {
    final configuredType = await FileSystemEntity.type(
      path,
      followLinks: false,
    );
    if (configuredType == FileSystemEntityType.notFound) {
      throw const BackendUnavailableException(
        'The configured CMUdict file does not exist.',
      );
    }
    if (configuredType != FileSystemEntityType.file) {
      throw const InvalidConfigurationException(
        'The configured CMUdict path must be a regular non-link file.',
      );
    }

    final configuredFile = File(path);
    final resolvedPath = await configuredFile.resolveSymbolicLinks();
    final file = File(resolvedPath);
    final resolvedType = await FileSystemEntity.type(
      resolvedPath,
      followLinks: false,
    );
    final statBefore = await file.stat();
    if (resolvedType != FileSystemEntityType.file ||
        statBefore.type != FileSystemEntityType.file) {
      throw const InvalidConfigurationException(
        'The configured CMUdict path must resolve to a regular file.',
      );
    }
    if (statBefore.size != manifest.sizeBytes) {
      throw MalformedDataException(
        'The CMUdict file must contain exactly ${manifest.sizeBytes} bytes.',
      );
    }

    final snapshot = _FileSnapshot.fromStat(statBefore);
    final bytes = await _readBounded(file, manifest.sizeBytes);
    final actualSha256 = sha256.convert(bytes).toString();
    if (actualSha256 != manifest.sha256) {
      throw const MalformedDataException(
        'The CMUdict file failed its SHA-256 identity check.',
      );
    }

    final pronunciations = _parseDictionary(bytes, manifest);

    final typeAfter = await FileSystemEntity.type(
      resolvedPath,
      followLinks: false,
    );
    final statAfter = await file.stat();
    if (typeAfter != FileSystemEntityType.file ||
        !snapshot.matches(statAfter)) {
      throw const MalformedDataException(
        'The CMUdict file changed while it was being opened.',
      );
    }

    return CmuDictionaryPronunciationProvider._(pronunciations, manifest);
  } on MisakiException {
    rethrow;
  } on FileSystemException catch (error) {
    throw BackendUnavailableException(
      'The configured CMUdict file could not be read.',
      cause: error,
    );
  } on ArgumentError catch (error) {
    throw InvalidConfigurationException(
      'The configured CMUdict path is invalid.',
      cause: error,
    );
  } on FormatException catch (error) {
    throw MalformedDataException(
      'The CMUdict file is not valid strict UTF-8.',
      cause: error,
    );
  }
}

Future<Uint8List> _readBounded(File file, int expectedSizeBytes) async {
  final output = BytesBuilder(copy: false);
  var byteCount = 0;
  await for (final chunk in file.openRead()) {
    byteCount += chunk.length;
    if (byteCount > expectedSizeBytes) {
      throw const MalformedDataException(
        'The CMUdict file grew beyond its expected resource bound.',
      );
    }
    output.add(chunk);
  }
  if (byteCount != expectedSizeBytes) {
    throw const MalformedDataException(
      'The CMUdict file changed size while it was being read.',
    );
  }
  return output.takeBytes();
}

Map<String, KoreanCmuPronunciation> _parseDictionary(
  Uint8List bytes,
  _CmuDictionaryManifest manifest,
) {
  final String text;
  try {
    text = utf8.decode(bytes, allowMalformed: false);
  } on FormatException catch (error) {
    throw MalformedDataException(
      'The CMUdict file is not valid strict UTF-8.',
      cause: error,
    );
  }

  final pronunciations = <String, KoreanCmuPronunciation>{};
  var recordCount = 0;
  var lineNumber = 0;
  for (final line in const LineSplitter().convert(text)) {
    lineNumber++;
    if (line.isEmpty) {
      throw MalformedDataException('CMUdict record $lineNumber is empty.');
    }
    if (line.length > _maximumLineLength) {
      throw MalformedDataException(
        'CMUdict record $lineNumber exceeds the line-length bound.',
      );
    }
    recordCount++;
    if (recordCount > manifest.recordCount) {
      throw const MalformedDataException(
        'The CMUdict file contains too many records.',
      );
    }

    final fields = _splitRecord(line, lineNumber);
    final parsed = _parseRecord(fields, lineNumber);
    pronunciations.putIfAbsent(
      parsed.word.toLowerCase(),
      () => KoreanCmuPronunciation(parsed.phones),
    );
    if (pronunciations.length > manifest.keyCount) {
      throw const MalformedDataException(
        'The CMUdict file contains too many unique keys.',
      );
    }
  }

  if (recordCount != manifest.recordCount) {
    throw MalformedDataException(
      'The CMUdict file has $recordCount records; '
      '${manifest.recordCount} are required.',
    );
  }
  if (pronunciations.length != manifest.keyCount) {
    throw MalformedDataException(
      'The CMUdict file has ${pronunciations.length} unique keys; '
      '${manifest.keyCount} are required.',
    );
  }
  return pronunciations;
}

List<String> _splitRecord(String line, int lineNumber) {
  final fields = <String>[];
  var fieldStart = -1;
  for (var index = 0; index < line.length; index++) {
    final codeUnit = line.codeUnitAt(index);
    if (codeUnit == 0x20 || codeUnit == 0x09) {
      if (fieldStart >= 0) {
        fields.add(line.substring(fieldStart, index));
        fieldStart = -1;
      }
      continue;
    }
    if (codeUnit < 0x21 || codeUnit > 0x7e) {
      throw MalformedDataException(
        'CMUdict record $lineNumber contains a non-ASCII field character.',
      );
    }
    if (fieldStart < 0) {
      fieldStart = index;
    }
  }
  if (fieldStart >= 0) {
    fields.add(line.substring(fieldStart));
  }
  if (fields.length > _maximumFieldsPerRecord) {
    throw MalformedDataException(
      'CMUdict record $lineNumber contains too many fields.',
    );
  }
  return fields;
}

({String word, List<String> phones}) _parseRecord(
  List<String> fields,
  int lineNumber,
) {
  if (fields.length < 2) {
    throw MalformedDataException(
      'CMUdict record $lineNumber is missing its pronunciation.',
    );
  }

  var word = fields.first;
  var phoneStart = 1;
  final separatedCounter = fields.length >= 3
      ? _positiveCounter(fields[1])
      : null;
  if (separatedCounter != null) {
    phoneStart = 2;
  } else {
    final openingParenthesis = word.lastIndexOf('(');
    if (openingParenthesis <= 0 || !word.endsWith(')')) {
      throw MalformedDataException(
        'CMUdict record $lineNumber has an invalid pronunciation counter.',
      );
    }
    final counter = _positiveCounter(
      word.substring(openingParenthesis + 1, word.length - 1),
    );
    if (counter == null) {
      throw MalformedDataException(
        'CMUdict record $lineNumber has an invalid pronunciation counter.',
      );
    }
    word = word.substring(0, openingParenthesis);
  }

  if (word.isEmpty || word.length > _maximumWordLength) {
    throw MalformedDataException(
      'CMUdict record $lineNumber has an invalid word field.',
    );
  }
  if (phoneStart >= fields.length) {
    throw MalformedDataException(
      'CMUdict record $lineNumber is missing ARPABET phones.',
    );
  }
  final phones = fields.sublist(phoneStart);
  for (final phone in phones) {
    if (!_isArpabetPhone(phone)) {
      throw MalformedDataException(
        'CMUdict record $lineNumber has an invalid ARPABET phone.',
      );
    }
  }
  return (word: word, phones: phones);
}

int? _positiveCounter(String value) {
  if (value.isEmpty || value.length > 6) {
    return null;
  }
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x30 || codeUnit > 0x39) {
      return null;
    }
  }
  final parsed = int.parse(value);
  return parsed > 0 ? parsed : null;
}

bool _isArpabetPhone(String value) {
  if (value.isEmpty || value.length > _maximumPhoneLength) {
    return false;
  }
  for (var index = 0; index < value.length; index++) {
    final codeUnit = value.codeUnitAt(index);
    if (codeUnit >= 0x41 && codeUnit <= 0x5a) {
      continue;
    }
    final isFinalStressDigit =
        index == value.length - 1 && codeUnit >= 0x30 && codeUnit <= 0x32;
    if (!isFinalStressDigit) {
      return false;
    }
  }
  return true;
}

final class _CmuDictionaryManifest {
  const _CmuDictionaryManifest({
    required this.sizeBytes,
    required this.sha256,
    required this.recordCount,
    required this.keyCount,
  });

  final int sizeBytes;
  final String sha256;
  final int recordCount;
  final int keyCount;

  bool get isValid =>
      sizeBytes >= 0 &&
      RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256) &&
      recordCount > 0 &&
      keyCount > 0 &&
      keyCount <= recordCount;
}

final class _FileSnapshot {
  const _FileSnapshot({
    required this.type,
    required this.size,
    required this.modified,
    required this.changed,
    required this.mode,
  });

  factory _FileSnapshot.fromStat(FileStat stat) => _FileSnapshot(
    type: stat.type,
    size: stat.size,
    modified: stat.modified,
    changed: stat.changed,
    mode: stat.mode,
  );

  final FileSystemEntityType type;
  final int size;
  final DateTime modified;
  final DateTime changed;
  final int mode;

  bool matches(FileStat stat) =>
      stat.type == type &&
      stat.size == size &&
      stat.modified == modified &&
      stat.changed == changed &&
      stat.mode == mode;
}
