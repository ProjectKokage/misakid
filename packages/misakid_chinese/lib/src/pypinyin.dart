// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0
//
// Behavior-preserving Dart adaptation of the pypinyin 0.53.0 stages used by
// hexgrad/misaki 0.9.4. The original is MIT-licensed; see
// licenses/pypinyin-LICENSE.txt. Modifications replace Python objects and
// module-global data with validated caller-provided snapshots, immutable Dart
// collections, explicit bounds, and typed package failures. The optional
// frontend-1.1 profile also adapts pypinyin-dict 0.9.0's MIT-licensed
// `large_pinyin` loader and the Apache-2.0 Misaki/PaddleSpeech overrides.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:misakid/misaki_zh.dart';

import 'resource_file_loader.dart';

const _pinnedManifest = _PypinyinManifest(
  pinyin: _ResourceManifest(
    sizeBytes: 783823,
    sha256: '19ac93a11b0cf2d1b42741c2956dcb8632944e87d2ebcd1ba7cc4d3a936b9fb5',
    recordCount: 41651,
  ),
  phrases: _ResourceManifest(
    sizeBytes: 2544982,
    sha256: 'd71fe97165dfd3eb9d8dff86ce5f62787d530b6b9f38c898779fcaf16d2522d1',
    recordCount: 47098,
  ),
);

const _largePinyinManifest = _LargePinyinManifest(
  resource: _ResourceManifest(
    sizeBytes: 9140316,
    sha256: 'f1f00a0682120f4052eb9ab03c632b040677dd9675bade5b8cb6a3bb7c0b8fd3',
    recordCount: 411959,
  ),
  phraseCount: 411957,
);

const int _maximumPathUtf8Bytes = 32768;
const int _maximumResourceBytes = 16 * 1024 * 1024;
const int _maximumRecords = 1000000;
const int _maximumPinyinValueScalars = 256;
const int _maximumPronunciationsPerScalar = 32;
const int _maximumPhraseScalars = 64;
const int _maximumSyllableScalars = 32;
const int _maximumPronunciationsPerPhraseScalar = 32;
const int _maximumLargePinyinLineBytes = 4096;

/// Maximum scalars accepted by one [PypinyinTone3Provider.tone3] call.
const int maximumPypinyinTone3InputScalars = 65536;

/// Checksum-pinned pure-Dart subset of pypinyin 0.53.0.
///
/// This provider implements exactly the behavior used by Misaki's legacy
/// Chinese path: `lazy_pinyin(text, style=Style.TONE3,
/// neutral_tone_with_five=True)`. It includes pypinyin's Han/non-Han grouping,
/// phrase maximum-forward matching, first-pronunciation fallback, tone-mark
/// conversion, and neutral-tone `5` suffix.
///
/// The caller supplies the exact pypinyin 0.53.0 JSON resources. [open]
/// validates their file kind, byte size, SHA-256, record counts, schema, and
/// stability while opening. No resource is discovered or downloaded.
final class PypinyinTone3Provider implements MisakiBackend {
  PypinyinTone3Provider._({
    required Map<int, String> singlePinyin,
    required Map<String, List<String>> phrasePinyin,
    required Set<String> phrasePrefixes,
    required _PypinyinManifest manifest,
    _LargePinyinManifest? largeManifest,
  }) : _singlePinyin = Map<int, String>.unmodifiable(singlePinyin),
       _phrasePinyin = Map<String, List<String>>.unmodifiable(phrasePinyin),
       _phrasePrefixes = Set<String>.unmodifiable(phrasePrefixes),
       info = BackendInfo(
         name: 'pypinyin',
         version: '0.53.0',
         details: <String, String>{
           'mode': largeManifest == null
               ? 'lazy-pinyin-tone3-neutral-five'
               : 'misaki-chinese-frontend-1.1',
           'pinyinDictSha256': manifest.pinyin.sha256,
           'pinyinDictSizeBytes': '${manifest.pinyin.sizeBytes}',
           'pinyinDictRecordCount': '${manifest.pinyin.recordCount}',
           'phrasesDictSha256': manifest.phrases.sha256,
           'phrasesDictSizeBytes': '${manifest.phrases.sizeBytes}',
           'phrasesDictRecordCount': '${manifest.phrases.recordCount}',
           if (largeManifest != null) ...<String, String>{
             'pypinyinDictVersion': '0.9.0',
             'largePinyinSha256': largeManifest.resource.sha256,
             'largePinyinSizeBytes': '${largeManifest.resource.sizeBytes}',
             'largePinyinRecordCount': '${largeManifest.resource.recordCount}',
             'largePinyinPhraseCount': '${largeManifest.phraseCount}',
             'customPhraseOverrideCount':
                 '${_frontend11PhraseOverrides.length}',
             'singlePronunciationOverride': '地=de,di4',
           },
         },
       );

  final Map<int, String> _singlePinyin;
  final Map<String, List<String>> _phrasePinyin;
  final Set<String> _phrasePrefixes;

  /// Opens the exact pinned pypinyin 0.53.0 dictionaries.
  ///
  /// Both arguments must be absolute paths to regular non-link files.
  static Future<PypinyinTone3Provider> open({
    required String pinyinDictionaryPath,
    required String phrasesDictionaryPath,
  }) => _openPypinyin(
    pinyinDictionaryPath: pinyinDictionaryPath,
    phrasesDictionaryPath: phrasesDictionaryPath,
    manifest: _pinnedManifest,
  );

  /// Opens the exact pypinyin profile initialized by Misaki frontend 1.1.
  ///
  /// In addition to the two pypinyin 0.53.0 resources, the caller supplies
  /// `phrase-pinyin-data/large_pinyin.txt` from pypinyin-dict 0.9.0. Loading
  /// applies the same order as `ZHFrontend._init_pypinyin`: large phrases,
  /// Misaki's 16 phrase overrides, then the `地=de,di4` single-character
  /// ordering override.
  static Future<PypinyinTone3Provider> openFrontend11({
    required String pinyinDictionaryPath,
    required String phrasesDictionaryPath,
    required String largePinyinDictionaryPath,
  }) => _openPypinyin(
    pinyinDictionaryPath: pinyinDictionaryPath,
    phrasesDictionaryPath: phrasesDictionaryPath,
    manifest: _pinnedManifest,
    largePinyin: _LargePinyinConfiguration(
      path: largePinyinDictionaryPath,
      manifest: _largePinyinManifest,
    ),
  );

  @override
  final BackendInfo info;

  /// Returns immutable pypinyin-compatible tone-3 values synchronously.
  ///
  /// Han text produces one value per source scalar. Each contiguous non-Han
  /// run is preserved as one value, matching pypinyin's default error policy.
  List<String> tone3(String word) => _convert(word, _PypinyinStyle.tone3);

  /// Returns immutable pypinyin `Style.INITIALS` values with `strict=true`.
  List<String> initials(String word) => _convert(word, _PypinyinStyle.initials);

  /// Returns immutable pypinyin `Style.FINALS_TONE3` values.
  ///
  /// Neutral finals receive a `5`, matching
  /// `neutral_tone_with_five=true`; syllables with no valid strict final stay
  /// empty, as in pypinyin 0.53.0.
  List<String> finalsTone3(String word) =>
      _convert(word, _PypinyinStyle.finalsTone3);

  List<String> _convert(String word, _PypinyinStyle style) {
    if (!_isValidUnicode(word)) {
      throw const InvalidConfigurationException(
        'Pypinyin input must contain valid Unicode scalar values.',
      );
    }
    if (word.runes.length > maximumPypinyinTone3InputScalars) {
      throw const InvalidConfigurationException(
        'Pypinyin input exceeds the 65536-scalar resource bound.',
      );
    }
    if (word.isEmpty) return const <String>[];

    final output = <String>[];
    for (final segment in _simpleSegments(word)) {
      if (!segment.isHan) {
        output.add(segment.text);
        continue;
      }
      for (final phrase in _cutHan(segment.text)) {
        final phraseValues = _phrasePinyin[phrase];
        if (phraseValues != null) {
          for (final value in phraseValues) {
            output.add(_convertStyle(value, style));
          }
          continue;
        }
        for (final scalar in phrase.runes) {
          final value = _singlePinyin[scalar] ?? String.fromCharCode(scalar);
          output.add(_convertStyle(value, style));
        }
      }
    }
    return List<String>.unmodifiable(output);
  }

  List<_TextSegment> _simpleSegments(String text) {
    final result = <_TextSegment>[];
    final scalars = text.runes.iterator;
    if (!scalars.moveNext()) return result;

    var currentIsHan = _isPypinyinHan(scalars.current);
    var current = StringBuffer()..writeCharCode(scalars.current);
    while (scalars.moveNext()) {
      final scalar = scalars.current;
      final isHan = _isPypinyinHan(scalar);
      if (isHan == currentIsHan) {
        current.writeCharCode(scalar);
        continue;
      }
      result.add(_TextSegment(current.toString(), currentIsHan));
      current = StringBuffer()..writeCharCode(scalar);
      currentIsHan = isHan;
    }
    result.add(_TextSegment(current.toString(), currentIsHan));
    return result;
  }

  Iterable<String> _cutHan(String text) sync* {
    final scalars = <String>[
      for (final scalar in text.runes) String.fromCharCode(scalar),
    ];
    var start = 0;
    while (start < scalars.length) {
      var matched = '';
      var restarted = false;
      final candidate = StringBuffer();
      for (var index = 0; start + index < scalars.length; index++) {
        candidate.write(scalars[start + index]);
        final word = candidate.toString();
        if (_phrasePrefixes.contains(word)) {
          matched = word;
          continue;
        }

        // pypinyin's strict mmseg intentionally checks only the last matched
        // prefix. If that prefix is not itself a phrase, it emits one scalar
        // even when an earlier prefix was a phrase.
        if (matched.isNotEmpty && _phrasePinyin.containsKey(matched)) {
          yield matched;
          start += index;
        } else {
          yield scalars[start];
          start++;
        }
        restarted = true;
        break;
      }
      if (restarted) continue;

      final remaining = scalars.sublist(start).join();
      if (_phrasePinyin.containsKey(remaining)) {
        yield remaining;
      } else {
        yield* scalars.sublist(start);
      }
      break;
    }
  }
}

/// Internal byte-backed constructor for exact legacy pypinyin resources.
PypinyinTone3Provider createPinnedLegacyPypinyinFromBytes({
  required Uint8List pinyinDictionaryBytes,
  required Uint8List phrasesDictionaryBytes,
}) => _createPypinyinFromBytes(
  pinyinDictionaryBytes: pinyinDictionaryBytes,
  phrasesDictionaryBytes: phrasesDictionaryBytes,
  manifest: _pinnedManifest,
);

/// Internal byte-backed constructor for exact frontend-1.1 pypinyin data.
PypinyinTone3Provider createPinnedFrontend11PypinyinFromBytes({
  required Uint8List pinyinDictionaryBytes,
  required Uint8List phrasesDictionaryBytes,
  required Uint8List largePinyinDictionaryBytes,
}) => _createPypinyinFromBytes(
  pinyinDictionaryBytes: pinyinDictionaryBytes,
  phrasesDictionaryBytes: phrasesDictionaryBytes,
  manifest: _pinnedManifest,
  largePinyinDictionaryBytes: largePinyinDictionaryBytes,
  largeManifest: _largePinyinManifest,
);

/// Test-only synthetic-manifest entrypoint for this unexported `src` library.
///
/// Production callers must use [PypinyinTone3Provider.open].
Future<PypinyinTone3Provider> openPypinyinTone3ForTesting({
  required String pinyinDictionaryPath,
  required String phrasesDictionaryPath,
  required int expectedPinyinSizeBytes,
  required String expectedPinyinSha256,
  required int expectedPinyinRecordCount,
  required int expectedPhrasesSizeBytes,
  required String expectedPhrasesSha256,
  required int expectedPhrasesRecordCount,
}) {
  final manifest = _PypinyinManifest(
    pinyin: _ResourceManifest(
      sizeBytes: expectedPinyinSizeBytes,
      sha256: expectedPinyinSha256,
      recordCount: expectedPinyinRecordCount,
    ),
    phrases: _ResourceManifest(
      sizeBytes: expectedPhrasesSizeBytes,
      sha256: expectedPhrasesSha256,
      recordCount: expectedPhrasesRecordCount,
    ),
  );
  if (!manifest.isValid) {
    throw const InvalidConfigurationException(
      'The test pypinyin resource manifest is invalid.',
    );
  }
  return _openPypinyin(
    pinyinDictionaryPath: pinyinDictionaryPath,
    phrasesDictionaryPath: phrasesDictionaryPath,
    manifest: manifest,
  );
}

/// Test-only synthetic frontend-1.1 manifest entrypoint.
Future<PypinyinTone3Provider> openPypinyinFrontend11ForTesting({
  required String pinyinDictionaryPath,
  required String phrasesDictionaryPath,
  required String largePinyinDictionaryPath,
  required int expectedPinyinSizeBytes,
  required String expectedPinyinSha256,
  required int expectedPinyinRecordCount,
  required int expectedPhrasesSizeBytes,
  required String expectedPhrasesSha256,
  required int expectedPhrasesRecordCount,
  required int expectedLargePinyinSizeBytes,
  required String expectedLargePinyinSha256,
  required int expectedLargePinyinRecordCount,
  required int expectedLargePinyinPhraseCount,
}) {
  final manifest = _PypinyinManifest(
    pinyin: _ResourceManifest(
      sizeBytes: expectedPinyinSizeBytes,
      sha256: expectedPinyinSha256,
      recordCount: expectedPinyinRecordCount,
    ),
    phrases: _ResourceManifest(
      sizeBytes: expectedPhrasesSizeBytes,
      sha256: expectedPhrasesSha256,
      recordCount: expectedPhrasesRecordCount,
    ),
  );
  final largeManifest = _LargePinyinManifest(
    resource: _ResourceManifest(
      sizeBytes: expectedLargePinyinSizeBytes,
      sha256: expectedLargePinyinSha256,
      recordCount: expectedLargePinyinRecordCount,
    ),
    phraseCount: expectedLargePinyinPhraseCount,
  );
  if (!manifest.isValid || !largeManifest.isValid) {
    throw const InvalidConfigurationException(
      'The test pypinyin frontend-1.1 resource manifest is invalid.',
    );
  }
  return _openPypinyin(
    pinyinDictionaryPath: pinyinDictionaryPath,
    phrasesDictionaryPath: phrasesDictionaryPath,
    manifest: manifest,
    largePinyin: _LargePinyinConfiguration(
      path: largePinyinDictionaryPath,
      manifest: largeManifest,
    ),
  );
}

Future<PypinyinTone3Provider> _openPypinyin({
  required String pinyinDictionaryPath,
  required String phrasesDictionaryPath,
  required _PypinyinManifest manifest,
  _LargePinyinConfiguration? largePinyin,
}) async {
  _validatePath(pinyinDictionaryPath, 'pinyin_dict.json');
  _validatePath(phrasesDictionaryPath, 'phrases_dict.json');
  if (largePinyin != null) {
    _validatePath(largePinyin.path, 'large_pinyin.txt');
  }

  final pinyinResource = await _readResource(
    pinyinDictionaryPath,
    manifest.pinyin,
    'pinyin_dict.json',
  );
  final phrasesResource = await _readResource(
    phrasesDictionaryPath,
    manifest.phrases,
    'phrases_dict.json',
  );
  LoadedChineseResourceFile? largeResource;
  if (largePinyin != null) {
    largeResource = await _readResource(
      largePinyin.path,
      largePinyin.manifest.resource,
      'large_pinyin.txt',
    );
  }
  final provider = _createPypinyinFromBytes(
    pinyinDictionaryBytes: pinyinResource.bytes,
    phrasesDictionaryBytes: phrasesResource.bytes,
    manifest: manifest,
    largePinyinDictionaryBytes: largeResource?.bytes,
    largeManifest: largePinyin?.manifest,
  );

  await pinyinResource.ensureUnchanged();
  await phrasesResource.ensureUnchanged();
  await largeResource?.ensureUnchanged();
  return provider;
}

PypinyinTone3Provider _createPypinyinFromBytes({
  required Uint8List pinyinDictionaryBytes,
  required Uint8List phrasesDictionaryBytes,
  required _PypinyinManifest manifest,
  Uint8List? largePinyinDictionaryBytes,
  _LargePinyinManifest? largeManifest,
}) {
  if (!manifest.isValid ||
      (largePinyinDictionaryBytes == null) != (largeManifest == null) ||
      (largeManifest != null && !largeManifest.isValid)) {
    throw const InvalidConfigurationException(
      'The configured pypinyin byte resource tuple is invalid.',
    );
  }
  _validateResourceBytes(
    pinyinDictionaryBytes,
    manifest.pinyin,
    'pinyin_dict.json',
  );
  _validateResourceBytes(
    phrasesDictionaryBytes,
    manifest.phrases,
    'phrases_dict.json',
  );
  if (largeManifest != null) {
    _validateResourceBytes(
      largePinyinDictionaryBytes!,
      largeManifest.resource,
      'large_pinyin.txt',
    );
  }

  final singlePinyin = _parsePinyinDictionary(
    pinyinDictionaryBytes,
    manifest.pinyin,
  );
  final phrasePinyin = _parsePhrasesDictionary(
    phrasesDictionaryBytes,
    manifest.phrases,
  );
  if (largeManifest != null) {
    phrasePinyin.addAll(
      _parseLargePinyinDictionary(largePinyinDictionaryBytes!, largeManifest),
    );
    phrasePinyin.addAll(_frontend11PhraseOverrides);
    singlePinyin['地'.runes.single] = 'de';
  }
  return PypinyinTone3Provider._(
    singlePinyin: singlePinyin,
    phrasePinyin: phrasePinyin,
    phrasePrefixes: _buildPhrasePrefixes(phrasePinyin.keys),
    manifest: manifest,
    largeManifest: largeManifest,
  );
}

void _validateResourceBytes(
  Uint8List bytes,
  _ResourceManifest manifest,
  String label,
) {
  if (bytes.length != manifest.sizeBytes) {
    throw MalformedDataException(
      'The $label bytes must contain exactly ${manifest.sizeBytes} bytes.',
    );
  }
  if (sha256.convert(bytes).toString() != manifest.sha256) {
    throw MalformedDataException(
      'The $label bytes failed their SHA-256 identity check.',
    );
  }
}

void _validatePath(String path, String label) {
  if (!_isAbsolutePath(path) || !_isValidPathText(path)) {
    throw InvalidConfigurationException(
      'The $label path must be absolute, valid Unicode without NUL, and no longer than 32768 UTF-8 bytes.',
    );
  }
}

Future<LoadedChineseResourceFile> _readResource(
  String path,
  _ResourceManifest manifest,
  String label,
) async {
  final resource = await loadChineseResourceFile(
    path: path,
    family: 'pypinyin',
    label: label,
    maximumBytes: _maximumResourceBytes,
    expectedBytes: manifest.sizeBytes,
  );
  if (sha256.convert(resource.bytes).toString() != manifest.sha256) {
    throw MalformedDataException(
      'The $label file failed its SHA-256 identity check.',
    );
  }
  return resource;
}

Map<int, String> _parsePinyinDictionary(
  Uint8List bytes,
  _ResourceManifest manifest,
) {
  final root = _decodeJsonObject(bytes, 'pinyin_dict.json');
  if (root.length != manifest.recordCount) {
    throw MalformedDataException(
      'pinyin_dict.json has ${root.length} records; ${manifest.recordCount} are required.',
    );
  }

  final result = <int, String>{};
  for (final entry in root.entries) {
    final scalar = _parseScalarKey(entry.key);
    final value = entry.value;
    if (scalar == null || value is! String) {
      throw const MalformedDataException(
        'pinyin_dict.json contains an invalid key or value type.',
      );
    }
    if (!_isBoundedNonEmptyUnicode(value, _maximumPinyinValueScalars)) {
      throw const MalformedDataException(
        'pinyin_dict.json contains an invalid pronunciation value.',
      );
    }
    final pronunciations = value.split(',');
    if (pronunciations.length > _maximumPronunciationsPerScalar ||
        pronunciations.any(
          (pronunciation) => !_isBoundedNonEmptyUnicode(
            pronunciation,
            _maximumSyllableScalars,
          ),
        )) {
      throw const MalformedDataException(
        'pinyin_dict.json contains malformed pronunciation alternatives.',
      );
    }
    result[scalar] = pronunciations.first;
  }
  if (result.length != manifest.recordCount) {
    throw const MalformedDataException(
      'pinyin_dict.json contains duplicate scalar identities.',
    );
  }
  return result;
}

Map<String, List<String>> _parsePhrasesDictionary(
  Uint8List bytes,
  _ResourceManifest manifest,
) {
  final root = _decodeJsonObject(bytes, 'phrases_dict.json');
  if (root.length != manifest.recordCount) {
    throw MalformedDataException(
      'phrases_dict.json has ${root.length} records; ${manifest.recordCount} are required.',
    );
  }

  final result = <String, List<String>>{};
  for (final entry in root.entries) {
    final phrase = entry.key;
    final rawScalars = entry.value;
    if (!_isBoundedNonEmptyUnicode(phrase, _maximumPhraseScalars) ||
        !_allPypinyinHan(phrase) ||
        rawScalars is! List<Object?> ||
        rawScalars.length != phrase.runes.length) {
      throw const MalformedDataException(
        'phrases_dict.json contains an invalid phrase record.',
      );
    }

    final firstPronunciations = <String>[];
    for (final rawPronunciations in rawScalars) {
      if (rawPronunciations is! List<Object?> ||
          rawPronunciations.isEmpty ||
          rawPronunciations.length > _maximumPronunciationsPerPhraseScalar) {
        throw const MalformedDataException(
          'phrases_dict.json contains an invalid pronunciation list.',
        );
      }
      String? first;
      for (final rawPronunciation in rawPronunciations) {
        if (rawPronunciation is! String ||
            !_isBoundedNonEmptyUnicode(
              rawPronunciation,
              _maximumSyllableScalars,
            )) {
          throw const MalformedDataException(
            'phrases_dict.json contains an invalid pronunciation value.',
          );
        }
        first ??= rawPronunciation;
      }
      firstPronunciations.add(first!);
    }
    result[phrase] = List<String>.unmodifiable(firstPronunciations);
  }
  return result;
}

Map<String, List<String>> _parseLargePinyinDictionary(
  Uint8List bytes,
  _LargePinyinManifest manifest,
) {
  final text = _decodeUtf8(bytes, 'large_pinyin.txt');
  final result = <String, List<String>>{};
  var recordCount = 0;
  var lineNumber = 0;
  for (final rawLine in const LineSplitter().convert(text)) {
    lineNumber++;
    if (utf8.encode(rawLine).length > _maximumLargePinyinLineBytes) {
      throw MalformedDataException(
        'large_pinyin.txt line $lineNumber exceeds the line-length bound.',
      );
    }
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    recordCount++;
    if (recordCount > manifest.resource.recordCount) {
      throw const MalformedDataException(
        'large_pinyin.txt contains too many pronunciation records.',
      );
    }

    final data = line.split('#').first.trim();
    final colon = data.indexOf(':');
    if (colon <= 0 || colon != data.lastIndexOf(':')) {
      throw MalformedDataException(
        'large_pinyin.txt line $lineNumber has an invalid record delimiter.',
      );
    }
    final phrase = data.substring(0, colon).trim();
    final pronunciationText = data.substring(colon + 1).trim();
    final pronunciations = pronunciationText.isEmpty
        ? const <String>[]
        : pronunciationText.split(RegExp(r'\s+'));
    if (!_isBoundedNonEmptyUnicode(phrase, _maximumPhraseScalars) ||
        !_allPypinyinHan(phrase) ||
        pronunciations.length != phrase.runes.length ||
        pronunciations.any(
          (pronunciation) => !_isBoundedNonEmptyUnicode(
            pronunciation,
            _maximumSyllableScalars,
          ),
        )) {
      throw MalformedDataException(
        'large_pinyin.txt line $lineNumber has an invalid phrase or pronunciation.',
      );
    }

    // The upstream generator merges later duplicate lines as additional
    // heteronyms. `lazy_pinyin` uses the first alternative, so retaining the
    // first record exactly preserves the selected values.
    result.putIfAbsent(phrase, () => List<String>.unmodifiable(pronunciations));
    if (result.length > manifest.phraseCount) {
      throw const MalformedDataException(
        'large_pinyin.txt contains too many unique phrases.',
      );
    }
  }
  if (recordCount != manifest.resource.recordCount) {
    throw MalformedDataException(
      'large_pinyin.txt has $recordCount records; ${manifest.resource.recordCount} are required.',
    );
  }
  if (result.length != manifest.phraseCount) {
    throw MalformedDataException(
      'large_pinyin.txt has ${result.length} unique phrases; ${manifest.phraseCount} are required.',
    );
  }
  return result;
}

Map<String, Object?> _decodeJsonObject(Uint8List bytes, String label) {
  final text = _decodeUtf8(bytes, label);

  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (error) {
    throw MalformedDataException('$label is not valid JSON.', cause: error);
  }
  if (decoded is! Map<String, Object?>) {
    throw MalformedDataException('$label must contain one JSON object.');
  }
  return decoded;
}

String _decodeUtf8(Uint8List bytes, String label) {
  try {
    return utf8.decode(bytes, allowMalformed: false);
  } on FormatException catch (error) {
    throw MalformedDataException(
      '$label is not valid strict UTF-8.',
      cause: error,
    );
  }
}

Set<String> _buildPhrasePrefixes(Iterable<String> phrases) {
  final result = <String>{};
  for (final phrase in phrases) {
    final prefix = StringBuffer();
    for (final scalar in phrase.runes) {
      prefix.writeCharCode(scalar);
      result.add(prefix.toString());
    }
  }
  return result;
}

int? _parseScalarKey(String key) {
  if (key.isEmpty || key.length > 7) return null;
  for (final codeUnit in key.codeUnits) {
    if (codeUnit < 0x30 || codeUnit > 0x39) return null;
  }
  if (key.length > 1 && key.codeUnitAt(0) == 0x30) return null;
  final scalar = int.parse(key);
  if (scalar > 0x10ffff || (scalar >= 0xd800 && scalar <= 0xdfff)) {
    return null;
  }
  return scalar;
}

bool _isBoundedNonEmptyUnicode(String value, int maximumScalars) {
  if (value.isEmpty || !_isValidUnicode(value)) return false;
  var count = 0;
  for (final _ in value.runes) {
    count++;
    if (count > maximumScalars) return false;
  }
  return true;
}

bool _allPypinyinHan(String value) => value.runes.every(_isPypinyinHan);

bool _isPypinyinHan(int scalar) =>
    scalar == 0x3007 ||
    (scalar >= 0xe815 && scalar <= 0xe864) ||
    scalar == 0xfa18 ||
    (scalar >= 0x3400 && scalar <= 0x4dbf) ||
    (scalar >= 0x4e00 && scalar <= 0x9fff) ||
    (scalar >= 0xf900 && scalar <= 0xfaff) ||
    (scalar >= 0x20000 && scalar <= 0x2a6df) ||
    (scalar >= 0x2a703 && scalar <= 0x2b73f) ||
    (scalar >= 0x2b740 && scalar <= 0x2b81d) ||
    (scalar >= 0x2b825 && scalar <= 0x2bf6e) ||
    (scalar >= 0x2c029 && scalar <= 0x2ce93) ||
    scalar == 0x2d016 ||
    (scalar >= 0x2d11b && scalar <= 0x2ebd9) ||
    (scalar >= 0x2f80a && scalar <= 0x2fa1f) ||
    (scalar >= 0x300f7 && scalar <= 0x31288) ||
    scalar == 0x30edd ||
    scalar == 0x30ede;

const Map<String, List<String>> _frontend11PhraseOverrides =
    <String, List<String>>{
      '开户行': <String>['ka1i', 'hu4', 'hang2'],
      '发卡行': <String>['fa4', 'ka3', 'hang2'],
      '放款行': <String>['fa4ng', 'kua3n', 'hang2'],
      '茧行': <String>['jia3n', 'hang2'],
      '行号': <String>['hang2', 'ha4o'],
      '各地': <String>['ge4', 'di4'],
      '借还款': <String>['jie4', 'hua2n', 'kua3n'],
      '时间为': <String>['shi2', 'jia1n', 'we2i'],
      '为准': <String>['we2i', 'zhu3n'],
      '色差': <String>['se4', 'cha1'],
      '嗲': <String>['dia3'],
      '呗': <String>['bei5'],
      '不': <String>['bu4'],
      '咗': <String>['zuo5'],
      '嘞': <String>['lei5'],
      '掺和': <String>['chan1', 'huo5'],
    };

String _convertStyle(String pinyin, _PypinyinStyle style) => switch (style) {
  _PypinyinStyle.tone3 => _toTone3WithNeutralFive(pinyin),
  _PypinyinStyle.initials => _initialPrefix(pinyin, strict: true),
  _PypinyinStyle.finalsTone3 => _toFinalsTone3WithNeutralFive(pinyin),
};

String _toTone3WithNeutralFive(String pinyin) {
  var value = _replacePhoneticSymbolsWithNumbers(pinyin);
  final match = _tone3Pattern.firstMatch(value);
  if (match != null) {
    value = '${match.group(1)}${match.group(3)}${match.group(2)}';
  }
  if (!_asciiToneNumber.hasMatch(value)) value = '${value}5';
  return value;
}

String _toFinalsTone3WithNeutralFive(String pinyin) {
  final withoutFive = pinyin.replaceAll('5', '');
  final numbered = _replacePhoneticSymbolsWithNumbers(withoutFive);
  final normal = numbered.replaceAll(_asciiToneNumber, '').replaceAll('v', 'ü');
  final finals = _strictFinal(normal).replaceAll('ü', 'v');
  if (finals.isEmpty) return '';
  final number = _asciiToneNumber.firstMatch(numbered)?.group(0);
  return '$finals${number ?? '5'}';
}

String _replacePhoneticSymbolsWithNumbers(String pinyin) {
  var value = pinyin;
  for (final entry in _singlePhoneticSymbols.entries) {
    value = value.replaceAll(entry.key, entry.value);
  }
  for (final entry in _multiPhoneticSymbols.entries) {
    value = value.replaceAll(entry.key, entry.value);
  }
  return value;
}

String _strictFinal(String pinyin) {
  final converted = _convertFinals(pinyin);
  var initial = _initialPrefix(converted, strict: true);
  var finals = converted.substring(initial.length);
  if (_finals.contains(finals)) return finals;

  initial = _initialPrefix(converted, strict: false);
  finals = converted.substring(initial.length);
  return _finals.contains(finals) ? finals : '';
}

String _initialPrefix(String pinyin, {required bool strict}) {
  for (final initial in _initials) {
    if (pinyin.startsWith(initial)) return initial;
  }
  if (!strict) {
    if (pinyin.startsWith('y')) return 'y';
    if (pinyin.startsWith('w')) return 'w';
  }
  return '';
}

String _convertFinals(String pinyin) {
  final raw = pinyin;
  var result = pinyin;
  if (raw.startsWith('y')) {
    final withoutY = result.substring(1);
    if (withoutY.startsWith('u')) {
      result = 'ü${result.substring(2)}';
    } else if (withoutY.startsWith('i')) {
      result = withoutY;
    } else {
      result = 'i$withoutY';
    }
  }
  if (raw.startsWith('w')) {
    final withoutW = result.substring(1);
    result = withoutW.startsWith('u') ? withoutW : 'u$withoutW';
  }
  if (!_finals.contains(result)) result = raw;

  if (result.length >= 2 &&
      (result.startsWith('j') ||
          result.startsWith('q') ||
          result.startsWith('x')) &&
      result.codeUnitAt(1) == 0x75) {
    result = '${result.substring(0, 1)}ü${result.substring(2)}';
  }
  result = _expandContractedFinal(result, 'iu', 'iou');
  result = _expandContractedFinal(result, 'ui', 'uei');
  result = _expandContractedFinal(result, 'un', 'uen');
  return result;
}

String _expandContractedFinal(String pinyin, String suffix, String expanded) {
  if (!pinyin.endsWith(suffix) || pinyin.length == suffix.length) return pinyin;
  final prefix = pinyin.substring(0, pinyin.length - suffix.length);
  if (!prefix.codeUnits.every((unit) => unit >= 0x61 && unit <= 0x7a)) {
    return pinyin;
  }
  return '$prefix$expanded';
}

final RegExp _tone3Pattern = RegExp(r'^([a-zêü]+)([1-5])([a-zêü]*)$');
final RegExp _asciiToneNumber = RegExp(r'[0-9]');

const List<String> _initials = <String>[
  'b',
  'p',
  'm',
  'f',
  'd',
  't',
  'n',
  'l',
  'g',
  'k',
  'h',
  'j',
  'q',
  'x',
  'zh',
  'ch',
  'sh',
  'r',
  'z',
  'c',
  's',
];

const Set<String> _finals = <String>{
  'i',
  'u',
  'ü',
  'a',
  'ia',
  'ua',
  'o',
  'uo',
  'e',
  'ie',
  'üe',
  'ai',
  'uai',
  'ei',
  'uei',
  'ao',
  'iao',
  'ou',
  'iou',
  'an',
  'ian',
  'uan',
  'üan',
  'en',
  'in',
  'uen',
  'ün',
  'ang',
  'iang',
  'uang',
  'eng',
  'ing',
  'ueng',
  'ong',
  'iong',
  'er',
  'ê',
};

const Map<String, String> _singlePhoneticSymbols = <String, String>{
  'ā': 'a1',
  'á': 'a2',
  'ǎ': 'a3',
  'à': 'a4',
  'ē': 'e1',
  'é': 'e2',
  'ě': 'e3',
  'è': 'e4',
  'ō': 'o1',
  'ó': 'o2',
  'ǒ': 'o3',
  'ò': 'o4',
  'ī': 'i1',
  'í': 'i2',
  'ǐ': 'i3',
  'ì': 'i4',
  'ū': 'u1',
  'ú': 'u2',
  'ǔ': 'u3',
  'ù': 'u4',
  'ü': 'v',
  'ǖ': 'v1',
  'ǘ': 'v2',
  'ǚ': 'v3',
  'ǜ': 'v4',
  'ń': 'n2',
  'ň': 'n3',
  'ǹ': 'n4',
  'ḿ': 'm2',
  'ế': 'ê2',
  'ề': 'ê4',
};

const Map<String, String> _multiPhoneticSymbols = <String, String>{
  'm̄': 'm1',
  'm̀': 'm4',
  'ê̄': 'ê1',
  'ê̌': 'ê3',
};

bool _isAbsolutePath(String path) {
  if (path.isEmpty) return false;
  return path.startsWith('/') ||
      RegExp(r'^(?:[A-Za-z]:[\\/]|\\\\)').hasMatch(path);
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

bool _isValidUnicode(String value) {
  final units = value.codeUnits;
  for (var index = 0; index < units.length; index++) {
    final unit = units[index];
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (index + 1 >= units.length ||
          units[index + 1] < 0xdc00 ||
          units[index + 1] > 0xdfff) {
        return false;
      }
      index++;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return false;
    }
  }
  return true;
}

final class _ResourceManifest {
  const _ResourceManifest({
    required this.sizeBytes,
    required this.sha256,
    required this.recordCount,
  });

  final int sizeBytes;
  final String sha256;
  final int recordCount;

  bool get isValid =>
      sizeBytes > 0 &&
      sizeBytes <= _maximumResourceBytes &&
      RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256) &&
      recordCount > 0 &&
      recordCount <= _maximumRecords;
}

final class _PypinyinManifest {
  const _PypinyinManifest({required this.pinyin, required this.phrases});

  final _ResourceManifest pinyin;
  final _ResourceManifest phrases;

  bool get isValid => pinyin.isValid && phrases.isValid;
}

final class _LargePinyinManifest {
  const _LargePinyinManifest({
    required this.resource,
    required this.phraseCount,
  });

  final _ResourceManifest resource;
  final int phraseCount;

  bool get isValid =>
      resource.isValid &&
      phraseCount > 0 &&
      phraseCount <= resource.recordCount;
}

final class _LargePinyinConfiguration {
  const _LargePinyinConfiguration({required this.path, required this.manifest});

  final String path;
  final _LargePinyinManifest manifest;
}

enum _PypinyinStyle { tone3, initials, finalsTone3 }

final class _TextSegment {
  const _TextSegment(this.text, this.isHan);

  final String text;
  final bool isHan;
}
