// Pure-Dart adaptation of jieba 0.42.1 accurate segmentation with HMM.
//
// Upstream: https://github.com/fxsjy/jieba/tree/v0.42.1
// Copyright (c) 2013 Sun Junyi
// SPDX-License-Identifier: MIT
//
// Modifications: retain only the `lcut(cut_all=False, HMM=True)` behavior
// required by pinned Misaki's legacy Chinese frontend; require explicit,
// checksum-pinned resources; and replace Python pickle with a non-executable
// parser for the inert protocol-0 probability-map opcode subset.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:misakid/misaki_zh.dart';

import 'resource_file_loader.dart';

const _pinnedManifest = _JiebaManifest(
  dictionary: _ResourceManifest(
    sizeBytes: 5071852,
    sha256: '7197c3211ddd98962b036cdf40324d1ea2bfaa12bd028e68faa70111a88e12a8',
  ),
  probabilityStart: _ResourceManifest(
    sizeBytes: 109,
    sha256: 'dfd45976dd4f8f2bc12535a680a178bf9e75eaa38bdfdcb844469e54468d6245',
  ),
  probabilityTransition: _ResourceManifest(
    sizeBytes: 260,
    sha256: 'ea7f50162ffa01db4973c7a8120b3c0233fbc5819fc0d617513535f1f2c7fedc',
  ),
  probabilityEmission: _ResourceManifest(
    sizeBytes: 1275441,
    sha256: '1e1d1d835b0c77d234acaa6afa23a13ffce597a295be0d7a1ece6a0d440dcf08',
  ),
  dictionaryRecordCount: 349046,
  frequencyEntryCount: 498113,
  dictionaryTagEntryCount: 349045,
  totalFrequency: 60101967,
  emissionEntryCount: 35224,
);

const _pinnedPartOfSpeechManifest = _JiebaPartOfSpeechManifest(
  characterStates: _ResourceManifest(
    sizeBytes: 2113902,
    sha256: 'c0ef4bb3d698eed188225d430ac291000b30c3d6e253a538d26b7ac9687424b1',
  ),
  probabilityStart: _ResourceManifest(
    sizeBytes: 8312,
    sha256: '0fb0fbc6b1840d35a5a8499cff0ae75e06af788e348f9b4b8b9630804cd6cf09',
  ),
  probabilityTransition: _ResourceManifest(
    sizeBytes: 141551,
    sha256: '236726f5a4efc2f023652925ca1e94f1fe4bfcb9d60224e9db3de0135b21385b',
  ),
  probabilityEmission: _ResourceManifest(
    sizeBytes: 3231234,
    sha256: '449b2304b6c73034187d3c8a6f26a7a20037f4ab45659844acd0ef2114171fa8',
  ),
  characterRecordCount: 6648,
  characterStateCount: 66162,
  stateCount: 256,
  transitionEntryCount: 5218,
  emissionEntryCount: 89290,
);

const int _maximumPathUtf8Bytes = 32768;
const int _maximumDictionaryBytes = 16 * 1024 * 1024;
const int _maximumProbabilityBytes = 8 * 1024 * 1024;
const int _maximumDictionaryRecords = 1000000;
const int _maximumDictionaryLineScalars = 4096;
const int _maximumDictionaryWordScalars = 256;
const int _maximumPickleLineBytes = 256;
const int _maximumPickleStackDepth = 128;
const int _maximumPickleMemoEntries = 300000;
const int _maximumPickleMapEntries = 100000;
const int _maximumPickleTupleLength = 1024;
const double _minimumProbability = -3.14e100;

/// Maximum number of Unicode scalars accepted by one [JiebaSegmenter.segment]
/// call.
const int maximumJiebaSegmentInputScalars = 65536;

/// Checksum-pinned pure-Dart jieba 0.42.1 accurate+HMM segmenter.
///
/// This implements the `jieba.lcut(text, cut_all=False, HMM=True)` behavior
/// used by pinned Misaki's legacy Chinese frontend. Its intentionally narrow
/// [segment] contract accepts one non-empty U+4E00-U+9FFF run, which is the
/// exact value passed at that pipeline boundary.
///
/// The caller supplies the packaged jieba `dict.txt` and three finalseg
/// probability pickle files explicitly. [open] validates regular non-link
/// files, exact byte sizes, SHA-256 identities, schemas, counts, and stable
/// file snapshots. No resource is discovered, downloaded, or cached.
///
/// ```dart
/// final jieba = await JiebaSegmenter.open(
///   dictionaryPath: '/absolute/path/jieba/dict.txt',
///   probabilityStartPath: '/absolute/path/jieba/finalseg/prob_start.p',
///   probabilityTransitionPath:
///       '/absolute/path/jieba/finalseg/prob_trans.p',
///   probabilityEmissionPath: '/absolute/path/jieba/finalseg/prob_emit.p',
/// );
/// final words = jieba.segment('南京市长江大桥');
/// ```
final class JiebaSegmenter implements MisakiBackend {
  JiebaSegmenter._({
    required _JiebaDictionary dictionary,
    required _JiebaHmmModel hmm,
    required _JiebaManifest manifest,
    required _JiebaPartOfSpeechModel? partOfSpeech,
    required _JiebaPartOfSpeechManifest? partOfSpeechManifest,
  }) : _dictionary = dictionary,
       _hmm = hmm,
       _partOfSpeech = partOfSpeech,
       _logTotal = math.log(dictionary.totalFrequency),
       info = BackendInfo(
         name: 'jieba',
         version: '0.42.1',
         details: <String, String>{
           'mode': 'accurate-hmm',
           'dictionarySha256': manifest.dictionary.sha256,
           'dictionarySizeBytes': '${manifest.dictionary.sizeBytes}',
           'dictionaryRecordCount': '${manifest.dictionaryRecordCount}',
           'frequencyEntryCount': '${manifest.frequencyEntryCount}',
           'totalFrequency': '${manifest.totalFrequency}',
           'probabilityStartSha256': manifest.probabilityStart.sha256,
           'probabilityTransitionSha256': manifest.probabilityTransition.sha256,
           'probabilityEmissionSha256': manifest.probabilityEmission.sha256,
           'emissionEntryCount': '${manifest.emissionEntryCount}',
           if (partOfSpeechManifest != null) ...<String, String>{
             'partOfSpeechCharacterStatesSha256':
                 partOfSpeechManifest.characterStates.sha256,
             'partOfSpeechProbabilityStartSha256':
                 partOfSpeechManifest.probabilityStart.sha256,
             'partOfSpeechProbabilityTransitionSha256':
                 partOfSpeechManifest.probabilityTransition.sha256,
             'partOfSpeechProbabilityEmissionSha256':
                 partOfSpeechManifest.probabilityEmission.sha256,
             'partOfSpeechDictionaryTagEntryCount':
                 '${manifest.dictionaryTagEntryCount}',
             'partOfSpeechCharacterRecordCount':
                 '${partOfSpeechManifest.characterRecordCount}',
             'partOfSpeechCharacterStateCount':
                 '${partOfSpeechManifest.characterStateCount}',
             'partOfSpeechStateCount': '${partOfSpeechManifest.stateCount}',
             'partOfSpeechTransitionEntryCount':
                 '${partOfSpeechManifest.transitionEntryCount}',
             'partOfSpeechEmissionEntryCount':
                 '${partOfSpeechManifest.emissionEntryCount}',
           },
         },
       );

  final _JiebaDictionary _dictionary;
  final _JiebaHmmModel _hmm;
  final _JiebaPartOfSpeechModel? _partOfSpeech;
  final double _logTotal;

  /// Opens the exact jieba 0.42.1 resources used by the legacy Chinese mode.
  ///
  /// All paths must be absolute and identify regular non-link files. Invalid
  /// path configuration throws [InvalidConfigurationException], unavailable
  /// files throw [BackendUnavailableException], and identity or schema drift
  /// throws [MalformedDataException].
  static Future<JiebaSegmenter> open({
    required String dictionaryPath,
    required String probabilityStartPath,
    required String probabilityTransitionPath,
    required String probabilityEmissionPath,
  }) => _openJieba(
    dictionaryPath: dictionaryPath,
    probabilityStartPath: probabilityStartPath,
    probabilityTransitionPath: probabilityTransitionPath,
    probabilityEmissionPath: probabilityEmissionPath,
    manifest: _pinnedManifest,
  );

  /// Opens every exact Jieba resource required by Chinese frontend 1.1.
  ///
  /// This retains [open]'s legacy/default segmentation behavior and adds the
  /// POS HMM used by `jieba.posseg.lcut`. All eight paths must be absolute
  /// regular non-link files and pass exact identity and schema validation.
  static Future<JiebaSegmenter> openWithPartOfSpeech({
    required String dictionaryPath,
    required String probabilityStartPath,
    required String probabilityTransitionPath,
    required String probabilityEmissionPath,
    required String partOfSpeechCharacterStatePath,
    required String partOfSpeechProbabilityStartPath,
    required String partOfSpeechProbabilityTransitionPath,
    required String partOfSpeechProbabilityEmissionPath,
  }) => _openJieba(
    dictionaryPath: dictionaryPath,
    probabilityStartPath: probabilityStartPath,
    probabilityTransitionPath: probabilityTransitionPath,
    probabilityEmissionPath: probabilityEmissionPath,
    manifest: _pinnedManifest,
    partOfSpeechPaths: _JiebaPartOfSpeechPaths(
      characterStates: partOfSpeechCharacterStatePath,
      probabilityStart: partOfSpeechProbabilityStartPath,
      probabilityTransition: partOfSpeechProbabilityTransitionPath,
      probabilityEmission: partOfSpeechProbabilityEmissionPath,
    ),
    partOfSpeechManifest: _pinnedPartOfSpeechManifest,
  );

  @override
  final BackendInfo info;

  /// Whether this instance was opened with the exact POS HMM resources.
  bool get supportsPartOfSpeech => _partOfSpeech != null;

  /// Segments one legacy-frontend Basic-CJK run in exact jieba word order.
  ///
  /// The returned immutable list contains non-empty words whose concatenation
  /// reproduces [text].
  List<String> segment(String text) {
    if (!_isValidUnicode(text)) {
      throw const InvalidConfigurationException(
        'Jieba input must contain valid Unicode scalar values.',
      );
    }
    final scalars = text.runes.toList(growable: false);
    if (scalars.isEmpty ||
        scalars.any((value) => value < 0x4E00 || value > 0x9FFF)) {
      throw const InvalidConfigurationException(
        'Jieba legacy input must be one non-empty U+4E00-U+9FFF run.',
      );
    }
    if (scalars.length > maximumJiebaSegmentInputScalars) {
      throw const InvalidConfigurationException(
        'Jieba input exceeds the 65536-scalar resource bound.',
      );
    }

    final result = <String>[];
    var blockStart = 0;
    var blockUsesDictionary = scalars.first <= 0x9FD5;
    for (var index = 1; index <= scalars.length; index++) {
      final nextUsesDictionary =
          index < scalars.length && scalars[index] <= 0x9FD5;
      if (index < scalars.length && nextUsesDictionary == blockUsesDictionary) {
        continue;
      }
      final block = scalars.sublist(blockStart, index);
      if (blockUsesDictionary) {
        result.addAll(_cutAccurateHmm(block));
      } else {
        // jieba's outer regex ends at U+9FD5. In accurate mode each scalar in
        // the unmatched remainder is yielded independently.
        result.addAll(block.map(String.fromCharCode));
      }
      blockStart = index;
      blockUsesDictionary = nextUsesDictionary;
    }
    return List<String>.unmodifiable(result);
  }

  /// Returns exact `jieba.cut_for_search(..., HMM=True)` segments.
  ///
  /// [text] follows the same one-run Basic-CJK contract as [segment]. The
  /// immutable result retains overlapping two- and three-scalar dictionary
  /// grams before each accurate-mode word, including observable duplicates.
  List<String> searchSegments(String text) {
    final result = <String>[];
    for (final word in segment(text)) {
      final scalars = word.runes.toList(growable: false);
      if (scalars.length > 2) {
        for (var index = 0; index + 1 < scalars.length; index++) {
          final gram = _stringFromRange(scalars, index, index + 2);
          if ((_dictionary.frequencies[gram] ?? 0) != 0) result.add(gram);
        }
      }
      if (scalars.length > 3) {
        for (var index = 0; index + 2 < scalars.length; index++) {
          final gram = _stringFromRange(scalars, index, index + 3);
          if ((_dictionary.frequencies[gram] ?? 0) != 0) result.add(gram);
        }
      }
      result.add(word);
    }
    return List<String>.unmodifiable(result);
  }

  /// Returns exact `jieba.posseg.lcut(..., HMM=True)` words and POS tags.
  ///
  /// Unlike [segment], this accepts the complete valid-Unicode frontend text,
  /// including whitespace, punctuation, Latin text, and supplementary-plane
  /// scalars. Calling it on an instance created by [open] throws
  /// [BackendUnavailableException]; use [openWithPartOfSpeech].
  List<ChineseSandhiWord> segmentWithPartOfSpeech(String text) {
    final partOfSpeech = _partOfSpeech;
    if (partOfSpeech == null) {
      throw const BackendUnavailableException(
        'Jieba POS segmentation requires openWithPartOfSpeech and all four POS HMM resources.',
      );
    }
    if (!_isValidUnicode(text)) {
      throw const InvalidConfigurationException(
        'Jieba POS input must contain valid Unicode scalar values.',
      );
    }
    final scalars = text.runes.toList(growable: false);
    if (scalars.length > maximumJiebaSegmentInputScalars) {
      throw const InvalidConfigurationException(
        'Jieba POS input exceeds the 65536-scalar resource bound.',
      );
    }
    if (scalars.isEmpty) return const <ChineseSandhiWord>[];

    final result = <ChineseSandhiWord>[];
    var blockStart = 0;
    var internal = _isPartOfSpeechInternal(scalars.first);
    for (var index = 1; index <= scalars.length; index++) {
      final nextInternal =
          index < scalars.length && _isPartOfSpeechInternal(scalars[index]);
      if (index < scalars.length && nextInternal == internal) continue;
      final block = scalars.sublist(blockStart, index);
      if (internal) {
        result.addAll(_cutPartOfSpeechDag(block, partOfSpeech));
      } else {
        _writePartOfSpeechExternalBlock(block, result);
      }
      blockStart = index;
      internal = nextInternal;
    }
    return List<ChineseSandhiWord>.unmodifiable(result);
  }

  List<String> _cutAccurateHmm(List<int> sentence) {
    final routeEnd = _routeEnds(sentence);
    final result = <String>[];
    final buffer = <int>[];
    var start = 0;
    while (start < sentence.length) {
      final end = routeEnd[start] + 1;
      if (end - start == 1) {
        buffer.add(sentence[start]);
      } else {
        _flushSingleRouteBuffer(buffer, result);
        result.add(_stringFromRange(sentence, start, end));
      }
      start = end;
    }
    _flushSingleRouteBuffer(buffer, result);
    return result;
  }

  List<int> _routeEnds(List<int> sentence) {
    final dag = _buildDag(sentence);
    final routeScore = List<double>.filled(sentence.length + 1, 0);
    final routeEnd = List<int>.filled(sentence.length, 0);
    routeScore[sentence.length] = 0;

    for (var start = sentence.length - 1; start >= 0; start--) {
      var bestScore = double.negativeInfinity;
      var bestEnd = -1;
      for (final end in dag[start]) {
        final word = _stringFromRange(sentence, start, end + 1);
        final frequency = _dictionary.frequencies[word] ?? 0;
        final score =
            math.log(frequency == 0 ? 1 : frequency) -
            _logTotal +
            routeScore[end + 1];
        // Python max() compares the (score, end) tuple, so a score tie selects
        // the larger end index.
        if (score > bestScore || (score == bestScore && end > bestEnd)) {
          bestScore = score;
          bestEnd = end;
        }
      }
      routeScore[start] = bestScore;
      routeEnd[start] = bestEnd;
    }
    return routeEnd;
  }

  List<List<int>> _buildDag(List<int> sentence) {
    final dag = List<List<int>>.generate(
      sentence.length,
      (_) => <int>[],
      growable: false,
    );
    for (var start = 0; start < sentence.length; start++) {
      final fragment = StringBuffer();
      for (var end = start; end < sentence.length; end++) {
        fragment.writeCharCode(sentence[end]);
        final word = fragment.toString();
        final frequency = _dictionary.frequencies[word];
        if (frequency == null) break;
        if (frequency != 0) dag[start].add(end);
      }
      if (dag[start].isEmpty) dag[start].add(start);
    }
    return dag;
  }

  void _flushSingleRouteBuffer(List<int> buffer, List<String> output) {
    if (buffer.isEmpty) return;
    if (buffer.length == 1) {
      output.add(String.fromCharCode(buffer.single));
      buffer.clear();
      return;
    }

    final word = String.fromCharCodes(buffer);
    if ((_dictionary.frequencies[word] ?? 0) == 0) {
      output.addAll(_hmm.cut(buffer));
    } else {
      output.addAll(buffer.map(String.fromCharCode));
    }
    buffer.clear();
  }

  List<ChineseSandhiWord> _cutPartOfSpeechDag(
    List<int> sentence,
    _JiebaPartOfSpeechModel partOfSpeech,
  ) {
    final routeEnd = _routeEnds(sentence);
    final result = <ChineseSandhiWord>[];
    final buffer = <int>[];
    var start = 0;
    while (start < sentence.length) {
      final end = routeEnd[start] + 1;
      if (end - start == 1) {
        buffer.add(sentence[start]);
      } else {
        _flushPartOfSpeechBuffer(buffer, result, partOfSpeech);
        final word = _stringFromRange(sentence, start, end);
        result.add(
          ChineseSandhiWord(
            word: word,
            partOfSpeech: _dictionary.tags[word] ?? 'x',
          ),
        );
      }
      start = end;
    }
    _flushPartOfSpeechBuffer(buffer, result, partOfSpeech);
    return result;
  }

  void _flushPartOfSpeechBuffer(
    List<int> buffer,
    List<ChineseSandhiWord> output,
    _JiebaPartOfSpeechModel partOfSpeech,
  ) {
    if (buffer.isEmpty) return;
    final captured = List<int>.of(buffer);
    buffer.clear();
    if (captured.length == 1) {
      final word = String.fromCharCode(captured.single);
      output.add(
        ChineseSandhiWord(
          word: word,
          partOfSpeech: _dictionary.tags[word] ?? 'x',
        ),
      );
      return;
    }
    final word = String.fromCharCodes(captured);
    if ((_dictionary.frequencies[word] ?? 0) == 0) {
      output.addAll(_cutPartOfSpeechDetail(captured, partOfSpeech));
      return;
    }
    for (final scalar in captured) {
      final character = String.fromCharCode(scalar);
      output.add(
        ChineseSandhiWord(
          word: character,
          partOfSpeech: _dictionary.tags[character] ?? 'x',
        ),
      );
    }
  }

  List<ChineseSandhiWord> _cutPartOfSpeechDetail(
    List<int> sentence,
    _JiebaPartOfSpeechModel partOfSpeech,
  ) {
    final result = <ChineseSandhiWord>[];
    var blockStart = 0;
    var isHan = _isPartOfSpeechHan(sentence.first);
    for (var index = 1; index <= sentence.length; index++) {
      final nextIsHan =
          index < sentence.length && _isPartOfSpeechHan(sentence[index]);
      if (index < sentence.length && nextIsHan == isHan) continue;
      final block = sentence.sublist(blockStart, index);
      if (isHan) {
        result.addAll(partOfSpeech.cut(block));
      } else {
        _writePartOfSpeechDetailNonHan(block, result);
      }
      blockStart = index;
      isHan = nextIsHan;
    }
    return result;
  }

  void _writePartOfSpeechDetailNonHan(
    List<int> block,
    List<ChineseSandhiWord> output,
  ) {
    var index = 0;
    while (index < block.length) {
      final start = index;
      final scalar = block[index];
      final String tag;
      if (_isAsciiNumberDetail(scalar)) {
        tag = 'm';
        while (index < block.length && _isAsciiNumberDetail(block[index])) {
          index++;
        }
      } else if (_isAsciiAlphaNumeric(scalar)) {
        tag = 'eng';
        while (index < block.length && _isAsciiAlphaNumeric(block[index])) {
          index++;
        }
      } else {
        tag = 'x';
        while (index < block.length &&
            !_isAsciiNumberDetail(block[index]) &&
            !_isAsciiAlphaNumeric(block[index])) {
          index++;
        }
      }
      output.add(
        ChineseSandhiWord(
          word: _stringFromRange(block, start, index),
          partOfSpeech: tag,
        ),
      );
    }
  }

  void _writePartOfSpeechExternalBlock(
    List<int> block,
    List<ChineseSandhiWord> output,
  ) {
    var index = 0;
    while (index < block.length) {
      if (block[index] == 0x0D &&
          index + 1 < block.length &&
          block[index + 1] == 0x0A) {
        output.add(const ChineseSandhiWord(word: '\r\n', partOfSpeech: 'x'));
        index += 2;
        continue;
      }
      if (_isPythonWhitespace(block[index])) {
        output.add(
          ChineseSandhiWord(
            word: String.fromCharCode(block[index]),
            partOfSpeech: 'x',
          ),
        );
        index++;
        continue;
      }

      final start = index;
      while (index < block.length &&
          !_isPythonWhitespace(block[index]) &&
          !(block[index] == 0x0D &&
              index + 1 < block.length &&
              block[index + 1] == 0x0A)) {
        index++;
      }
      final english = _isAsciiAlphaNumeric(block[start]);
      for (var scalarIndex = start; scalarIndex < index; scalarIndex++) {
        final scalar = block[scalarIndex];
        output.add(
          ChineseSandhiWord(
            word: String.fromCharCode(scalar),
            partOfSpeech: _isAsciiNumberDetail(scalar)
                ? 'm'
                : english
                ? 'eng'
                : 'x',
          ),
        );
      }
    }
  }
}

/// Test-only entrypoint for exercising parsers with small synthetic resources.
///
/// The public package entrypoint deliberately exports only [JiebaSegmenter].
Future<JiebaSegmenter> openJiebaForTesting({
  required String dictionaryPath,
  required String probabilityStartPath,
  required String probabilityTransitionPath,
  required String probabilityEmissionPath,
  required int dictionaryRecordCount,
  required int frequencyEntryCount,
  required int totalFrequency,
  required int emissionEntryCount,
}) async {
  Future<_ResourceManifest> identity(String path, String label) async {
    final resource = await loadChineseResourceFile(
      path: path,
      family: 'Jieba test',
      label: label,
      maximumBytes: _maximumDictionaryBytes,
    );
    final bytes = resource.bytes;
    return _ResourceManifest(
      sizeBytes: bytes.length,
      sha256: sha256.convert(bytes).toString(),
    );
  }

  final dictionary = await identity(dictionaryPath, 'dictionary');
  final probabilityStart = await identity(
    probabilityStartPath,
    'start-probability model',
  );
  final probabilityTransition = await identity(
    probabilityTransitionPath,
    'transition-probability model',
  );
  final probabilityEmission = await identity(
    probabilityEmissionPath,
    'emission-probability model',
  );

  return _openJieba(
    dictionaryPath: dictionaryPath,
    probabilityStartPath: probabilityStartPath,
    probabilityTransitionPath: probabilityTransitionPath,
    probabilityEmissionPath: probabilityEmissionPath,
    manifest: _JiebaManifest(
      dictionary: dictionary,
      probabilityStart: probabilityStart,
      probabilityTransition: probabilityTransition,
      probabilityEmission: probabilityEmission,
      dictionaryRecordCount: dictionaryRecordCount,
      frequencyEntryCount: frequencyEntryCount,
      dictionaryTagEntryCount: null,
      totalFrequency: totalFrequency,
      emissionEntryCount: emissionEntryCount,
    ),
  );
}

/// Internal byte-backed constructor for the exact legacy Jieba resources.
JiebaSegmenter createPinnedLegacyJiebaFromBytes({
  required Uint8List dictionaryBytes,
  required Uint8List probabilityStartBytes,
  required Uint8List probabilityTransitionBytes,
  required Uint8List probabilityEmissionBytes,
}) => _createJiebaFromBytes(
  dictionaryBytes: dictionaryBytes,
  probabilityStartBytes: probabilityStartBytes,
  probabilityTransitionBytes: probabilityTransitionBytes,
  probabilityEmissionBytes: probabilityEmissionBytes,
  manifest: _pinnedManifest,
);

/// Internal byte-backed constructor for the exact frontend-1.1 Jieba tuple.
JiebaSegmenter createPinnedFrontend11JiebaFromBytes({
  required Uint8List dictionaryBytes,
  required Uint8List probabilityStartBytes,
  required Uint8List probabilityTransitionBytes,
  required Uint8List probabilityEmissionBytes,
  required Uint8List partOfSpeechCharacterStateBytes,
  required Uint8List partOfSpeechProbabilityStartBytes,
  required Uint8List partOfSpeechProbabilityTransitionBytes,
  required Uint8List partOfSpeechProbabilityEmissionBytes,
}) => _createJiebaFromBytes(
  dictionaryBytes: dictionaryBytes,
  probabilityStartBytes: probabilityStartBytes,
  probabilityTransitionBytes: probabilityTransitionBytes,
  probabilityEmissionBytes: probabilityEmissionBytes,
  manifest: _pinnedManifest,
  partOfSpeechCharacterStateBytes: partOfSpeechCharacterStateBytes,
  partOfSpeechProbabilityStartBytes: partOfSpeechProbabilityStartBytes,
  partOfSpeechProbabilityTransitionBytes:
      partOfSpeechProbabilityTransitionBytes,
  partOfSpeechProbabilityEmissionBytes: partOfSpeechProbabilityEmissionBytes,
  partOfSpeechManifest: _pinnedPartOfSpeechManifest,
);

Future<JiebaSegmenter> _openJieba({
  required String dictionaryPath,
  required String probabilityStartPath,
  required String probabilityTransitionPath,
  required String probabilityEmissionPath,
  required _JiebaManifest manifest,
  _JiebaPartOfSpeechPaths? partOfSpeechPaths,
  _JiebaPartOfSpeechManifest? partOfSpeechManifest,
}) async {
  final configuredPaths = <String>[
    dictionaryPath,
    probabilityStartPath,
    probabilityTransitionPath,
    probabilityEmissionPath,
    if (partOfSpeechPaths != null) ...<String>[
      partOfSpeechPaths.characterStates,
      partOfSpeechPaths.probabilityStart,
      partOfSpeechPaths.probabilityTransition,
      partOfSpeechPaths.probabilityEmission,
    ],
  ];
  for (final path in configuredPaths) {
    if (!_isAbsolutePath(path) || !_isValidPathText(path)) {
      throw const InvalidConfigurationException(
        'Jieba resource paths must be absolute, valid Unicode without NUL, and no longer than 32768 UTF-8 bytes.',
      );
    }
  }
  if (configuredPaths.toSet().length != configuredPaths.length) {
    throw InvalidConfigurationException(
      'Jieba requires ${configuredPaths.length} distinct configured resource paths.',
    );
  }
  if (!manifest.isValid ||
      (partOfSpeechPaths == null) != (partOfSpeechManifest == null) ||
      (partOfSpeechManifest != null && !partOfSpeechManifest.isValid)) {
    throw const InvalidConfigurationException(
      'The configured Jieba resource manifest is invalid.',
    );
  }

  final dictionaryResource = await _loadResource(
    path: dictionaryPath,
    label: 'dictionary',
    manifest: manifest.dictionary,
    maximumBytes: _maximumDictionaryBytes,
  );
  final startResource = await _loadResource(
    path: probabilityStartPath,
    label: 'start-probability model',
    manifest: manifest.probabilityStart,
    maximumBytes: _maximumProbabilityBytes,
  );
  final transitionResource = await _loadResource(
    path: probabilityTransitionPath,
    label: 'transition-probability model',
    manifest: manifest.probabilityTransition,
    maximumBytes: _maximumProbabilityBytes,
  );
  final emissionResource = await _loadResource(
    path: probabilityEmissionPath,
    label: 'emission-probability model',
    manifest: manifest.probabilityEmission,
    maximumBytes: _maximumProbabilityBytes,
  );
  final LoadedChineseResourceFile? partOfSpeechCharacterStatesResource;
  final LoadedChineseResourceFile? partOfSpeechStartResource;
  final LoadedChineseResourceFile? partOfSpeechTransitionResource;
  final LoadedChineseResourceFile? partOfSpeechEmissionResource;
  if (partOfSpeechPaths == null || partOfSpeechManifest == null) {
    partOfSpeechCharacterStatesResource = null;
    partOfSpeechStartResource = null;
    partOfSpeechTransitionResource = null;
    partOfSpeechEmissionResource = null;
  } else {
    partOfSpeechCharacterStatesResource = await _loadResource(
      path: partOfSpeechPaths.characterStates,
      label: 'POS character-state model',
      manifest: partOfSpeechManifest.characterStates,
      maximumBytes: _maximumProbabilityBytes,
    );
    partOfSpeechStartResource = await _loadResource(
      path: partOfSpeechPaths.probabilityStart,
      label: 'POS start-probability model',
      manifest: partOfSpeechManifest.probabilityStart,
      maximumBytes: _maximumProbabilityBytes,
    );
    partOfSpeechTransitionResource = await _loadResource(
      path: partOfSpeechPaths.probabilityTransition,
      label: 'POS transition-probability model',
      manifest: partOfSpeechManifest.probabilityTransition,
      maximumBytes: _maximumProbabilityBytes,
    );
    partOfSpeechEmissionResource = await _loadResource(
      path: partOfSpeechPaths.probabilityEmission,
      label: 'POS emission-probability model',
      manifest: partOfSpeechManifest.probabilityEmission,
      maximumBytes: _maximumProbabilityBytes,
    );
  }
  final resources = <LoadedChineseResourceFile>[
    dictionaryResource,
    startResource,
    transitionResource,
    emissionResource,
    ?partOfSpeechCharacterStatesResource,
    ?partOfSpeechStartResource,
    ?partOfSpeechTransitionResource,
    ?partOfSpeechEmissionResource,
  ];
  if (resources.map((resource) => resource.resolvedPath).toSet().length !=
      resources.length) {
    throw const InvalidConfigurationException(
      'Jieba resource paths must resolve to distinct files.',
    );
  }

  final segmenter = _createJiebaFromBytes(
    dictionaryBytes: dictionaryResource.bytes,
    probabilityStartBytes: startResource.bytes,
    probabilityTransitionBytes: transitionResource.bytes,
    probabilityEmissionBytes: emissionResource.bytes,
    manifest: manifest,
    partOfSpeechCharacterStateBytes: partOfSpeechCharacterStatesResource?.bytes,
    partOfSpeechProbabilityStartBytes: partOfSpeechStartResource?.bytes,
    partOfSpeechProbabilityTransitionBytes:
        partOfSpeechTransitionResource?.bytes,
    partOfSpeechProbabilityEmissionBytes: partOfSpeechEmissionResource?.bytes,
    partOfSpeechManifest: partOfSpeechManifest,
  );

  for (final resource in resources) {
    await resource.ensureUnchanged();
  }
  return segmenter;
}

JiebaSegmenter _createJiebaFromBytes({
  required Uint8List dictionaryBytes,
  required Uint8List probabilityStartBytes,
  required Uint8List probabilityTransitionBytes,
  required Uint8List probabilityEmissionBytes,
  required _JiebaManifest manifest,
  Uint8List? partOfSpeechCharacterStateBytes,
  Uint8List? partOfSpeechProbabilityStartBytes,
  Uint8List? partOfSpeechProbabilityTransitionBytes,
  Uint8List? partOfSpeechProbabilityEmissionBytes,
  _JiebaPartOfSpeechManifest? partOfSpeechManifest,
}) {
  final partOfSpeechResources = <Uint8List?>[
    partOfSpeechCharacterStateBytes,
    partOfSpeechProbabilityStartBytes,
    partOfSpeechProbabilityTransitionBytes,
    partOfSpeechProbabilityEmissionBytes,
  ];
  final hasPartOfSpeech = partOfSpeechResources.every((value) => value != null);
  if (!manifest.isValid ||
      partOfSpeechResources.any((value) => value != null) != hasPartOfSpeech ||
      (partOfSpeechManifest == null) != !hasPartOfSpeech ||
      (partOfSpeechManifest != null && !partOfSpeechManifest.isValid)) {
    throw const InvalidConfigurationException(
      'The configured Jieba byte resource tuple is invalid.',
    );
  }

  _validateResourceBytes(
    dictionaryBytes,
    label: 'dictionary',
    manifest: manifest.dictionary,
    maximumBytes: _maximumDictionaryBytes,
  );
  _validateResourceBytes(
    probabilityStartBytes,
    label: 'start-probability model',
    manifest: manifest.probabilityStart,
    maximumBytes: _maximumProbabilityBytes,
  );
  _validateResourceBytes(
    probabilityTransitionBytes,
    label: 'transition-probability model',
    manifest: manifest.probabilityTransition,
    maximumBytes: _maximumProbabilityBytes,
  );
  _validateResourceBytes(
    probabilityEmissionBytes,
    label: 'emission-probability model',
    manifest: manifest.probabilityEmission,
    maximumBytes: _maximumProbabilityBytes,
  );
  if (partOfSpeechManifest != null) {
    _validateResourceBytes(
      partOfSpeechCharacterStateBytes!,
      label: 'POS character-state model',
      manifest: partOfSpeechManifest.characterStates,
      maximumBytes: _maximumProbabilityBytes,
    );
    _validateResourceBytes(
      partOfSpeechProbabilityStartBytes!,
      label: 'POS start-probability model',
      manifest: partOfSpeechManifest.probabilityStart,
      maximumBytes: _maximumProbabilityBytes,
    );
    _validateResourceBytes(
      partOfSpeechProbabilityTransitionBytes!,
      label: 'POS transition-probability model',
      manifest: partOfSpeechManifest.probabilityTransition,
      maximumBytes: _maximumProbabilityBytes,
    );
    _validateResourceBytes(
      partOfSpeechProbabilityEmissionBytes!,
      label: 'POS emission-probability model',
      manifest: partOfSpeechManifest.probabilityEmission,
      maximumBytes: _maximumProbabilityBytes,
    );
  }

  try {
    final dictionary = _parseDictionary(dictionaryBytes, manifest);
    final hmm = _parseHmm(
      probabilityStartBytes,
      probabilityTransitionBytes,
      probabilityEmissionBytes,
      manifest,
    );
    final partOfSpeech = partOfSpeechManifest == null
        ? null
        : _parsePartOfSpeechHmm(
            partOfSpeechCharacterStateBytes!,
            partOfSpeechProbabilityStartBytes!,
            partOfSpeechProbabilityTransitionBytes!,
            partOfSpeechProbabilityEmissionBytes!,
            partOfSpeechManifest,
          );
    return JiebaSegmenter._(
      dictionary: dictionary,
      hmm: hmm,
      manifest: manifest,
      partOfSpeech: partOfSpeech,
      partOfSpeechManifest: partOfSpeechManifest,
    );
  } on MisakiException {
    rethrow;
  } on FormatException catch (error) {
    throw MalformedDataException(
      'A Jieba resource has an invalid inert data schema.',
      cause: error,
    );
  }
}

void _validateResourceBytes(
  Uint8List bytes, {
  required String label,
  required _ResourceManifest manifest,
  required int maximumBytes,
}) {
  if (manifest.sizeBytes > maximumBytes || bytes.length != manifest.sizeBytes) {
    throw MalformedDataException(
      'The Jieba $label bytes have an unexpected byte size.',
    );
  }
  if (sha256.convert(bytes).toString() != manifest.sha256) {
    throw MalformedDataException(
      'The Jieba $label bytes failed their SHA-256 identity check.',
    );
  }
}

Future<LoadedChineseResourceFile> _loadResource({
  required String path,
  required String label,
  required _ResourceManifest manifest,
  required int maximumBytes,
}) async {
  final loaded = await loadChineseResourceFile(
    path: path,
    family: 'Jieba',
    label: label,
    maximumBytes: maximumBytes,
    expectedBytes: manifest.sizeBytes,
  );
  if (sha256.convert(loaded.bytes).toString() != manifest.sha256) {
    throw MalformedDataException(
      'The Jieba $label file failed its SHA-256 identity check.',
    );
  }
  return loaded;
}

_JiebaDictionary _parseDictionary(Uint8List bytes, _JiebaManifest manifest) {
  final String source;
  try {
    source = utf8.decode(bytes, allowMalformed: false);
  } on FormatException catch (error) {
    throw MalformedDataException(
      'The Jieba dictionary is not valid strict UTF-8.',
      cause: error,
    );
  }
  if (source.isEmpty || !source.endsWith('\n') || source.contains('\r')) {
    throw const MalformedDataException(
      'The Jieba dictionary must be non-empty LF-terminated text.',
    );
  }

  final frequencies = <String, int>{};
  final tags = <String, String>{};
  var recordCount = 0;
  var totalFrequency = 0;
  for (final rawLine in source.substring(0, source.length - 1).split('\n')) {
    recordCount++;
    if (recordCount > _maximumDictionaryRecords) {
      throw const MalformedDataException(
        'The Jieba dictionary exceeds the record-count bound.',
      );
    }
    final line = rawLine.trim();
    if (line.isEmpty || line.runes.length > _maximumDictionaryLineScalars) {
      throw MalformedDataException(
        'Jieba dictionary record $recordCount is empty or too long.',
      );
    }
    final fields = line.split(' ');
    if (fields.length != 3 ||
        fields[0].isEmpty ||
        fields[1].isEmpty ||
        !_partOfSpeechTagPattern.hasMatch(fields[2])) {
      throw MalformedDataException(
        'Jieba dictionary record $recordCount has invalid fields.',
      );
    }
    final word = fields[0];
    final frequencyText = fields[1];
    final tag = fields[2];
    final frequency = int.tryParse(frequencyText);
    if (frequency == null || frequency <= 0) {
      throw MalformedDataException(
        'Jieba dictionary record $recordCount has an invalid frequency.',
      );
    }
    final wordScalars = word.runes.toList(growable: false);
    if (wordScalars.isEmpty ||
        wordScalars.length > _maximumDictionaryWordScalars) {
      throw MalformedDataException(
        'Jieba dictionary record $recordCount has an invalid word.',
      );
    }

    frequencies[word] = frequency;
    tags[word] = tag;
    totalFrequency += frequency;
    final prefix = StringBuffer();
    for (final scalar in wordScalars) {
      prefix.writeCharCode(scalar);
      frequencies.putIfAbsent(prefix.toString(), () => 0);
    }
  }

  if (recordCount != manifest.dictionaryRecordCount ||
      frequencies.length != manifest.frequencyEntryCount ||
      (manifest.dictionaryTagEntryCount != null &&
          tags.length != manifest.dictionaryTagEntryCount) ||
      totalFrequency != manifest.totalFrequency) {
    throw const MalformedDataException(
      'The Jieba dictionary record, prefix, or total-frequency identity differs from the pin.',
    );
  }
  return _JiebaDictionary(
    Map<String, int>.unmodifiable(frequencies),
    Map<String, String>.unmodifiable(tags),
    totalFrequency,
  );
}

_JiebaHmmModel _parseHmm(
  Uint8List startBytes,
  Uint8List transitionBytes,
  Uint8List emissionBytes,
  _JiebaManifest manifest,
) {
  final startRoot = _Protocol0ProbabilityParser(startBytes).parse();
  final transitionRoot = _Protocol0ProbabilityParser(transitionBytes).parse();
  final emissionRoot = _Protocol0ProbabilityParser(emissionBytes).parse();

  final startMap = _probabilityMap(startRoot, 'start probabilities');
  _expectExactKeys(startMap, _states, 'start probabilities');
  final starts = List<double>.generate(
    _states.length,
    (index) => _probability(startMap[_states[index]], 'start probability'),
    growable: false,
  );

  final transitionMap = _map(transitionRoot, 'transition probabilities');
  _expectExactKeys(transitionMap, _states, 'transition probabilities');
  final transitions = List<List<double>>.generate(
    _states.length,
    (_) => List<double>.filled(_states.length, _minimumProbability),
    growable: false,
  );
  for (var previous = 0; previous < _states.length; previous++) {
    final state = _states[previous];
    final values = _probabilityMap(
      transitionMap[state],
      'transition probabilities for $state',
    );
    final expectedNext = _expectedNextStates[state]!;
    _expectExactKeys(
      values,
      expectedNext,
      'transition probabilities for $state',
    );
    for (final entry in values.entries) {
      transitions[previous][_stateIndex[entry.key]!] = _probability(
        entry.value,
        'transition probability',
      );
    }
  }

  final emissionMap = _map(emissionRoot, 'emission probabilities');
  _expectExactKeys(emissionMap, _states, 'emission probabilities');
  var emissionEntryCount = 0;
  final emissions = <Map<int, double>>[];
  for (final state in _states) {
    final rawValues = _probabilityMap(
      emissionMap[state],
      'emission probabilities for $state',
    );
    final values = <int, double>{};
    for (final entry in rawValues.entries) {
      final scalars = entry.key.runes.toList(growable: false);
      if (scalars.length != 1) {
        throw FormatException(
          'Emission key for state $state must be one Unicode scalar.',
        );
      }
      values[scalars.single] = _probability(
        entry.value,
        'emission probability',
      );
    }
    emissionEntryCount += values.length;
    emissions.add(Map<int, double>.unmodifiable(values));
  }
  if (emissionEntryCount != manifest.emissionEntryCount) {
    throw const MalformedDataException(
      'The Jieba HMM emission-entry count differs from the pin.',
    );
  }
  return _JiebaHmmModel(
    List<double>.unmodifiable(starts),
    List<List<double>>.unmodifiable(transitions.map(List<double>.unmodifiable)),
    List<Map<int, double>>.unmodifiable(emissions),
  );
}

_JiebaPartOfSpeechModel _parsePartOfSpeechHmm(
  Uint8List characterStateBytes,
  Uint8List startBytes,
  Uint8List transitionBytes,
  Uint8List emissionBytes,
  _JiebaPartOfSpeechManifest manifest,
) {
  final canonicalStates = <_JiebaPartOfSpeechState, _JiebaPartOfSpeechState>{};
  _JiebaPartOfSpeechState state(Object value, String location) {
    if (value is! _PickleTuple || value.values.length != 2) {
      throw FormatException('$location must be a two-string state tuple.');
    }
    final boundary = value.values[0];
    final tag = value.values[1];
    if (boundary is! String ||
        tag is! String ||
        !_stateIndex.containsKey(boundary) ||
        !_partOfSpeechTagPattern.hasMatch(tag)) {
      throw FormatException('$location has an invalid boundary or POS tag.');
    }
    final parsed = _JiebaPartOfSpeechState(boundary, tag);
    return canonicalStates.putIfAbsent(parsed, () => parsed);
  }

  final rawStart = _objectMap(
    _Protocol0ProbabilityParser(startBytes).parse(),
    'POS start probabilities',
  );
  final start = <_JiebaPartOfSpeechState, double>{};
  for (final entry in rawStart.entries) {
    final key = state(entry.key, 'POS start key');
    if (start.containsKey(key)) {
      throw const FormatException('Duplicate normalized POS start state.');
    }
    start[key] = _probability(entry.value, 'POS start probability');
  }

  final rawTransition = _objectMap(
    _Protocol0ProbabilityParser(transitionBytes).parse(),
    'POS transition probabilities',
  );
  final transition =
      <_JiebaPartOfSpeechState, Map<_JiebaPartOfSpeechState, double>>{};
  var transitionEntryCount = 0;
  for (final outer in rawTransition.entries) {
    final previous = state(outer.key, 'POS transition source');
    final rawValues = _objectMap(outer.value, 'POS transition values');
    final values = <_JiebaPartOfSpeechState, double>{};
    for (final entry in rawValues.entries) {
      final next = state(entry.key, 'POS transition target');
      if (values.containsKey(next)) {
        throw const FormatException(
          'Duplicate normalized POS transition target.',
        );
      }
      values[next] = _probability(entry.value, 'POS transition probability');
    }
    if (transition.containsKey(previous)) {
      throw const FormatException('Duplicate normalized POS transition state.');
    }
    transition[previous] = Map<_JiebaPartOfSpeechState, double>.unmodifiable(
      values,
    );
    transitionEntryCount += values.length;
  }

  final rawEmission = _objectMap(
    _Protocol0ProbabilityParser(emissionBytes).parse(),
    'POS emission probabilities',
  );
  final emission = <_JiebaPartOfSpeechState, Map<int, double>>{};
  var emissionEntryCount = 0;
  for (final outer in rawEmission.entries) {
    final current = state(outer.key, 'POS emission state');
    final rawValues = _objectMap(outer.value, 'POS emission values');
    final values = <int, double>{};
    for (final entry in rawValues.entries) {
      final character = entry.key;
      if (character is! String || character.runes.length != 1) {
        throw const FormatException(
          'POS emission key must be one Unicode scalar.',
        );
      }
      final scalar = character.runes.single;
      if (values.containsKey(scalar)) {
        throw const FormatException('Duplicate normalized POS emission key.');
      }
      values[scalar] = _probability(entry.value, 'POS emission probability');
    }
    if (emission.containsKey(current)) {
      throw const FormatException('Duplicate normalized POS emission state.');
    }
    emission[current] = Map<int, double>.unmodifiable(values);
    emissionEntryCount += values.length;
  }

  final rawCharacterStates = _objectMap(
    _Protocol0ProbabilityParser(characterStateBytes).parse(),
    'POS character states',
  );
  final characterStates = <int, List<_JiebaPartOfSpeechState>>{};
  var characterStateCount = 0;
  for (final entry in rawCharacterStates.entries) {
    final character = entry.key;
    final rawStates = entry.value;
    if (character is! String ||
        character.runes.length != 1 ||
        rawStates is! _PickleTuple ||
        rawStates.values.isEmpty) {
      throw const FormatException('Invalid POS character-state record.');
    }
    final values = <_JiebaPartOfSpeechState>[];
    final seen = <_JiebaPartOfSpeechState>{};
    for (final rawState in rawStates.values) {
      final parsed = state(rawState, 'POS character state');
      if (!seen.add(parsed)) {
        throw const FormatException('Duplicate POS character state.');
      }
      values.add(parsed);
    }
    final scalar = character.runes.single;
    if (characterStates.containsKey(scalar)) {
      throw const FormatException('Duplicate normalized POS character key.');
    }
    characterStates[scalar] = List<_JiebaPartOfSpeechState>.unmodifiable(
      values,
    );
    characterStateCount += values.length;
  }

  final stateSet = start.keys.toSet();
  bool sameStates(Iterable<_JiebaPartOfSpeechState> values) {
    final candidate = values.toSet();
    return candidate.length == stateSet.length &&
        candidate.containsAll(stateSet);
  }

  if (start.length != manifest.stateCount ||
      !sameStates(transition.keys) ||
      !sameStates(emission.keys) ||
      characterStates.length != manifest.characterRecordCount ||
      characterStateCount != manifest.characterStateCount ||
      transitionEntryCount != manifest.transitionEntryCount ||
      emissionEntryCount != manifest.emissionEntryCount ||
      characterStates.values
          .expand((values) => values)
          .any((value) => !stateSet.contains(value)) ||
      transition.values
          .expand((values) => values.keys)
          .any((value) => !stateSet.contains(value))) {
    throw const MalformedDataException(
      'The Jieba POS HMM state or entry-count identity differs from the pin.',
    );
  }

  return _JiebaPartOfSpeechModel(
    Map<int, List<_JiebaPartOfSpeechState>>.unmodifiable(characterStates),
    Map<_JiebaPartOfSpeechState, double>.unmodifiable(start),
    Map<
      _JiebaPartOfSpeechState,
      Map<_JiebaPartOfSpeechState, double>
    >.unmodifiable(transition),
    Map<_JiebaPartOfSpeechState, Map<int, double>>.unmodifiable(emission),
  );
}

Map<String, Object> _map(Object value, String location) {
  final raw = _objectMap(value, location);
  final result = <String, Object>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    if (key is! String) {
      throw FormatException('$location must contain only string keys.');
    }
    result[key] = entry.value;
  }
  return result;
}

Map<Object, Object> _objectMap(Object value, String location) {
  if (value is! Map<Object, Object>) {
    throw FormatException('$location must be a dictionary.');
  }
  return value;
}

Map<String, Object> _probabilityMap(Object? value, String location) {
  if (value == null) {
    throw FormatException('$location must be a probability dictionary.');
  }
  return _map(value, location);
}

double _probability(Object? value, String location) {
  if (value is! double || !value.isFinite || value > 0) {
    throw FormatException('$location must be a finite non-positive float.');
  }
  return value;
}

void _expectExactKeys(
  Map<String, Object> values,
  Iterable<String> expected,
  String location,
) {
  final expectedSet = expected.toSet();
  if (values.keys.toSet().difference(expectedSet).isNotEmpty ||
      expectedSet.difference(values.keys.toSet()).isNotEmpty) {
    throw FormatException('$location has missing or unexpected states.');
  }
}

final class _Protocol0ProbabilityParser {
  _Protocol0ProbabilityParser(this.bytes);

  final Uint8List bytes;
  final List<Object> _stack = <Object>[];
  final Map<int, Object> _memo = <int, Object>{};
  var _offset = 0;
  var _mapEntryCount = 0;

  Object parse() {
    while (_offset < bytes.length) {
      final opcode = bytes[_offset++];
      switch (opcode) {
        case 0x28: // MARK
          _push(_pickleMark);
        case 0x64: // DICT
          if (_stack.isEmpty || !identical(_stack.last, _pickleMark)) {
            throw const FormatException(
              'Only empty protocol-0 dictionary construction is allowed.',
            );
          }
          _stack.removeLast();
          _push(<Object, Object>{});
        case 0x70: // PUT
          final index = _memoIndex(_readAsciiLine());
          if (_stack.isEmpty ||
              _memo.containsKey(index) ||
              _memo.length >= _maximumPickleMemoEntries) {
            throw const FormatException('Invalid protocol-0 memo PUT.');
          }
          _memo[index] = _stack.last;
        case 0x67: // GET
          final index = _memoIndex(_readAsciiLine());
          final value = _memo[index];
          if (value == null) {
            throw const FormatException('Invalid protocol-0 memo GET.');
          }
          _push(value);
        case 0x53: // STRING
          _push(_parseAsciiString(_readAsciiLine()));
        case 0x56: // UNICODE
          _push(_parseRawUnicode(_readAsciiLine()));
        case 0x46: // FLOAT
          final source = _readAsciiLine();
          if (!_floatPattern.hasMatch(source)) {
            throw const FormatException('Invalid protocol-0 float literal.');
          }
          final value = double.parse(source);
          if (!value.isFinite) {
            throw const FormatException('Non-finite pickle float rejected.');
          }
          _push(value);
        case 0x74: // TUPLE
          final markIndex = _stack.lastIndexWhere(
            (value) => identical(value, _pickleMark),
          );
          if (markIndex < 0 ||
              markIndex + 1 == _stack.length ||
              _stack.length - markIndex - 1 > _maximumPickleTupleLength) {
            throw const FormatException('Invalid protocol-0 TUPLE stack.');
          }
          final values = _stack.sublist(markIndex + 1);
          _stack.removeRange(markIndex, _stack.length);
          _push(_PickleTuple(List<Object>.unmodifiable(values)));
        case 0x73: // SETITEM
          if (_stack.length < 3) {
            throw const FormatException('Invalid protocol-0 SETITEM stack.');
          }
          final value = _stack.removeLast();
          final key = _stack.removeLast();
          final target = _stack.last;
          if ((key is! String && key is! _PickleTuple) ||
              target is! Map<Object, Object>) {
            throw const FormatException(
              'Probability pickle dictionaries require inert scalar or tuple keys.',
            );
          }
          if (target.containsKey(key) ||
              ++_mapEntryCount > _maximumPickleMapEntries) {
            throw const FormatException(
              'Duplicate or excessive probability-map entry.',
            );
          }
          target[key] = value;
        case 0x2E: // STOP
          if (_offset != bytes.length ||
              _stack.length != 1 ||
              _stack.single is! Map<Object, Object>) {
            throw const FormatException(
              'Protocol-0 probability pickle has trailing or stacked data.',
            );
          }
          return _stack.single;
        default:
          throw FormatException(
            'Unsupported protocol-0 probability opcode 0x${opcode.toRadixString(16)}.',
          );
      }
    }
    throw const FormatException('Protocol-0 probability pickle has no STOP.');
  }

  void _push(Object value) {
    if (_stack.length >= _maximumPickleStackDepth) {
      throw const FormatException('Protocol-0 pickle stack is too deep.');
    }
    _stack.add(value);
  }

  String _readAsciiLine() {
    final start = _offset;
    while (_offset < bytes.length && bytes[_offset] != 0x0A) {
      final value = bytes[_offset++];
      if (value < 0x20 || value > 0x7E) {
        throw const FormatException(
          'Protocol-0 argument must be printable ASCII.',
        );
      }
      if (_offset - start > _maximumPickleLineBytes) {
        throw const FormatException('Protocol-0 argument line is too long.');
      }
    }
    if (_offset >= bytes.length) {
      throw const FormatException('Unterminated protocol-0 argument line.');
    }
    final result = ascii.decode(bytes.sublist(start, _offset));
    _offset++;
    return result;
  }
}

int _memoIndex(String source) {
  if (!_memoPattern.hasMatch(source)) {
    throw const FormatException('Invalid protocol-0 memo index.');
  }
  final value = int.parse(source);
  if (value >= _maximumPickleMemoEntries) {
    throw const FormatException('Protocol-0 memo index exceeds the bound.');
  }
  return value;
}

String _parseAsciiString(String source) {
  if (source.length < 3 ||
      source.codeUnitAt(0) != 0x27 ||
      source.codeUnitAt(source.length - 1) != 0x27) {
    throw const FormatException(
      'Protocol-0 STRING must be one quoted inert ASCII atom.',
    );
  }
  final value = source.substring(1, source.length - 1);
  if (!_pickleAsciiAtomPattern.hasMatch(value)) {
    throw const FormatException(
      'Protocol-0 STRING contains unsupported or excessive data.',
    );
  }
  return value;
}

String _parseRawUnicode(String source) {
  if (source.isEmpty) {
    throw const FormatException('Protocol-0 UNICODE must not be empty.');
  }
  final output = StringBuffer();
  for (var index = 0; index < source.length;) {
    final unit = source.codeUnitAt(index++);
    if (unit != 0x5C) {
      output.writeCharCode(unit);
      continue;
    }
    if (index >= source.length) {
      throw const FormatException('Incomplete raw-Unicode escape.');
    }
    final kind = source.codeUnitAt(index++);
    final width = switch (kind) {
      0x75 => 4, // u
      0x55 => 8, // U
      _ => throw const FormatException('Unsupported raw-Unicode escape.'),
    };
    if (index + width > source.length) {
      throw const FormatException('Incomplete raw-Unicode scalar escape.');
    }
    final digits = source.substring(index, index + width);
    if (!RegExp('^[0-9A-Fa-f]{$width}\$').hasMatch(digits)) {
      throw const FormatException('Invalid raw-Unicode scalar escape.');
    }
    final scalar = int.parse(digits, radix: 16);
    if (scalar > 0x10FFFF || (scalar >= 0xD800 && scalar <= 0xDFFF)) {
      throw const FormatException('Invalid raw-Unicode scalar value.');
    }
    output.writeCharCode(scalar);
    index += width;
  }
  return output.toString();
}

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

bool _isValidUnicode(String value) {
  final units = value.codeUnits;
  for (var index = 0; index < units.length; index++) {
    final unit = units[index];
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (index + 1 >= units.length ||
          units[index + 1] < 0xDC00 ||
          units[index + 1] > 0xDFFF) {
        return false;
      }
      index++;
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      return false;
    }
  }
  return true;
}

String _stringFromRange(List<int> scalars, int start, int end) =>
    String.fromCharCodes(scalars.getRange(start, end));

bool _isPartOfSpeechInternal(int scalar) =>
    _isPartOfSpeechHan(scalar) ||
    _isAsciiAlphaNumeric(scalar) ||
    scalar == 0x2B ||
    scalar == 0x23 ||
    scalar == 0x26 ||
    scalar == 0x2E ||
    scalar == 0x5F;

bool _isPartOfSpeechHan(int scalar) => scalar >= 0x4E00 && scalar <= 0x9FD5;

bool _isAsciiAlphaNumeric(int scalar) =>
    (scalar >= 0x30 && scalar <= 0x39) ||
    (scalar >= 0x41 && scalar <= 0x5A) ||
    (scalar >= 0x61 && scalar <= 0x7A);

bool _isAsciiNumberDetail(int scalar) =>
    scalar == 0x2E || (scalar >= 0x30 && scalar <= 0x39);

bool _isPythonWhitespace(int scalar) =>
    (scalar >= 0x09 && scalar <= 0x0D) ||
    (scalar >= 0x1C && scalar <= 0x20) ||
    scalar == 0x85 ||
    scalar == 0xA0 ||
    scalar == 0x1680 ||
    (scalar >= 0x2000 && scalar <= 0x200A) ||
    scalar == 0x2028 ||
    scalar == 0x2029 ||
    scalar == 0x202F ||
    scalar == 0x205F ||
    scalar == 0x3000;

final class _JiebaDictionary {
  const _JiebaDictionary(this.frequencies, this.tags, this.totalFrequency);

  final Map<String, int> frequencies;
  final Map<String, String> tags;
  final int totalFrequency;
}

final class _JiebaHmmModel {
  const _JiebaHmmModel(this.start, this.transition, this.emission);

  final List<double> start;
  final List<List<double>> transition;
  final List<Map<int, double>> emission;

  List<String> cut(List<int> sentence) {
    if (sentence.isEmpty) return const <String>[];

    var scores = List<double>.generate(
      _states.length,
      (state) =>
          start[state] +
          (emission[state][sentence.first] ?? _minimumProbability),
      growable: false,
    );
    final backPointers = List<List<int>>.generate(
      sentence.length,
      (_) => List<int>.filled(_states.length, -1),
      growable: false,
    );

    for (var index = 1; index < sentence.length; index++) {
      final next = List<double>.filled(_states.length, double.negativeInfinity);
      for (var state = 0; state < _states.length; state++) {
        final emissionProbability =
            emission[state][sentence[index]] ?? _minimumProbability;
        var bestPrevious = -1;
        var bestScore = double.negativeInfinity;
        for (final previous in _previousStates[state]) {
          final score =
              scores[previous] +
              transition[previous][state] +
              emissionProbability;
          if (score > bestScore ||
              (score == bestScore &&
                  _stateCodeUnits[previous] >
                      (bestPrevious < 0
                          ? -1
                          : _stateCodeUnits[bestPrevious]))) {
            bestScore = score;
            bestPrevious = previous;
          }
        }
        next[state] = bestScore;
        backPointers[index][state] = bestPrevious;
      }
      scores = next;
    }

    var finalState = _stateE;
    if (scores[_stateS] > scores[_stateE] ||
        scores[_stateS] == scores[_stateE]) {
      // Python max((probability, state) for state in 'ES') selects S on a
      // probability tie because tuple comparison then compares the state.
      finalState = _stateS;
    }
    final states = List<int>.filled(sentence.length, finalState);
    for (var index = sentence.length - 1; index > 0; index--) {
      states[index - 1] = backPointers[index][states[index]];
    }

    final result = <String>[];
    var begin = 0;
    var nextIndex = 0;
    for (var index = 0; index < sentence.length; index++) {
      switch (states[index]) {
        case _stateB:
          begin = index;
        case _stateE:
          result.add(_stringFromRange(sentence, begin, index + 1));
          nextIndex = index + 1;
        case _stateS:
          result.add(String.fromCharCode(sentence[index]));
          nextIndex = index + 1;
      }
    }
    if (nextIndex < sentence.length) {
      result.add(_stringFromRange(sentence, nextIndex, sentence.length));
    }
    return result;
  }
}

final class _JiebaPartOfSpeechState
    implements Comparable<_JiebaPartOfSpeechState> {
  const _JiebaPartOfSpeechState(this.boundary, this.tag);

  final String boundary;
  final String tag;

  @override
  int compareTo(_JiebaPartOfSpeechState other) {
    final boundaryOrder = boundary.compareTo(other.boundary);
    return boundaryOrder == 0 ? tag.compareTo(other.tag) : boundaryOrder;
  }

  @override
  bool operator ==(Object other) =>
      other is _JiebaPartOfSpeechState &&
      boundary == other.boundary &&
      tag == other.tag;

  @override
  int get hashCode => Object.hash(boundary, tag);
}

final class _JiebaPartOfSpeechModel {
  _JiebaPartOfSpeechModel(
    this.characterStates,
    this.start,
    this.transition,
    this.emission,
  ) : allStates = List<_JiebaPartOfSpeechState>.unmodifiable(transition.keys);

  final Map<int, List<_JiebaPartOfSpeechState>> characterStates;
  final Map<_JiebaPartOfSpeechState, double> start;
  final Map<_JiebaPartOfSpeechState, Map<_JiebaPartOfSpeechState, double>>
  transition;
  final Map<_JiebaPartOfSpeechState, Map<int, double>> emission;
  final List<_JiebaPartOfSpeechState> allStates;

  List<ChineseSandhiWord> cut(List<int> sentence) {
    if (sentence.isEmpty) return const <ChineseSandhiWord>[];

    var scores = <_JiebaPartOfSpeechState, double>{};
    final backPointers =
        <Map<_JiebaPartOfSpeechState, _JiebaPartOfSpeechState?>>[];
    final firstPointers = <_JiebaPartOfSpeechState, _JiebaPartOfSpeechState?>{};
    for (final state in characterStates[sentence.first] ?? allStates) {
      scores[state] =
          start[state]! +
          (emission[state]![sentence.first] ?? _minimumProbability);
      firstPointers[state] = null;
    }
    backPointers.add(firstPointers);

    for (var index = 1; index < sentence.length; index++) {
      final previousStates = <_JiebaPartOfSpeechState>[
        for (final state in backPointers[index - 1].keys)
          if (transition[state]!.isNotEmpty) state,
      ];
      final expectedNext = <_JiebaPartOfSpeechState>{};
      for (final state in previousStates) {
        expectedNext.addAll(transition[state]!.keys);
      }
      var candidates = <_JiebaPartOfSpeechState>[
        for (final state in characterStates[sentence[index]] ?? allStates)
          if (expectedNext.contains(state)) state,
      ];
      if (candidates.isEmpty) {
        candidates = expectedNext.isEmpty
            ? List<_JiebaPartOfSpeechState>.of(allStates)
            : List<_JiebaPartOfSpeechState>.of(expectedNext);
      }

      final nextScores = <_JiebaPartOfSpeechState, double>{};
      final nextPointers =
          <_JiebaPartOfSpeechState, _JiebaPartOfSpeechState?>{};
      for (final current in candidates) {
        final emit = emission[current]![sentence[index]] ?? _minimumProbability;
        _JiebaPartOfSpeechState? bestPrevious;
        var bestScore = double.negativeInfinity;
        for (final previous in previousStates) {
          final transitionProbability =
              transition[previous]![current] ?? double.negativeInfinity;
          final score = scores[previous]! + transitionProbability + emit;
          if (score > bestScore ||
              (score == bestScore &&
                  (bestPrevious == null ||
                      previous.compareTo(bestPrevious) > 0))) {
            bestScore = score;
            bestPrevious = previous;
          }
        }
        if (bestPrevious == null) {
          throw const MalformedDataException(
            'The Jieba POS HMM has no previous state for an observation.',
          );
        }
        nextScores[current] = bestScore;
        nextPointers[current] = bestPrevious;
      }
      scores = nextScores;
      backPointers.add(nextPointers);
    }

    _JiebaPartOfSpeechState? finalState;
    var finalScore = double.negativeInfinity;
    for (final entry in scores.entries) {
      if (entry.value > finalScore ||
          (entry.value == finalScore &&
              (finalState == null || entry.key.compareTo(finalState) > 0))) {
        finalScore = entry.value;
        finalState = entry.key;
      }
    }
    if (finalState == null) {
      throw const MalformedDataException(
        'The Jieba POS HMM produced no final state.',
      );
    }

    final route = List<_JiebaPartOfSpeechState>.filled(
      sentence.length,
      finalState,
    );
    for (var index = sentence.length - 1; index > 0; index--) {
      route[index - 1] = backPointers[index][route[index]]!;
    }

    final result = <ChineseSandhiWord>[];
    var begin = 0;
    var nextIndex = 0;
    for (var index = 0; index < sentence.length; index++) {
      final state = route[index];
      switch (state.boundary) {
        case 'B':
          begin = index;
        case 'E':
          result.add(
            ChineseSandhiWord(
              word: _stringFromRange(sentence, begin, index + 1),
              partOfSpeech: state.tag,
            ),
          );
          nextIndex = index + 1;
        case 'S':
          result.add(
            ChineseSandhiWord(
              word: String.fromCharCode(sentence[index]),
              partOfSpeech: state.tag,
            ),
          );
          nextIndex = index + 1;
      }
    }
    if (nextIndex < sentence.length) {
      result.add(
        ChineseSandhiWord(
          word: _stringFromRange(sentence, nextIndex, sentence.length),
          partOfSpeech: route[nextIndex].tag,
        ),
      );
    }
    return result;
  }
}

final class _PickleTuple {
  const _PickleTuple(this.values);

  final List<Object> values;

  @override
  bool operator ==(Object other) {
    if (other is! _PickleTuple || other.values.length != values.length) {
      return false;
    }
    for (var index = 0; index < values.length; index++) {
      if (values[index] != other.values[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(values);
}

final class _ResourceManifest {
  const _ResourceManifest({required this.sizeBytes, required this.sha256});

  final int sizeBytes;
  final String sha256;

  bool get isValid =>
      sizeBytes > 0 && RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256);
}

final class _JiebaManifest {
  const _JiebaManifest({
    required this.dictionary,
    required this.probabilityStart,
    required this.probabilityTransition,
    required this.probabilityEmission,
    required this.dictionaryRecordCount,
    required this.frequencyEntryCount,
    required this.dictionaryTagEntryCount,
    required this.totalFrequency,
    required this.emissionEntryCount,
  });

  final _ResourceManifest dictionary;
  final _ResourceManifest probabilityStart;
  final _ResourceManifest probabilityTransition;
  final _ResourceManifest probabilityEmission;
  final int dictionaryRecordCount;
  final int frequencyEntryCount;
  final int? dictionaryTagEntryCount;
  final int totalFrequency;
  final int emissionEntryCount;

  bool get isValid =>
      dictionary.isValid &&
      probabilityStart.isValid &&
      probabilityTransition.isValid &&
      probabilityEmission.isValid &&
      dictionaryRecordCount > 0 &&
      dictionaryRecordCount <= _maximumDictionaryRecords &&
      frequencyEntryCount >= dictionaryRecordCount &&
      (dictionaryTagEntryCount == null ||
          (dictionaryTagEntryCount! > 0 &&
              dictionaryTagEntryCount! <= dictionaryRecordCount)) &&
      totalFrequency > 0 &&
      emissionEntryCount >= 0 &&
      emissionEntryCount <= _maximumPickleMapEntries;
}

final class _JiebaPartOfSpeechManifest {
  const _JiebaPartOfSpeechManifest({
    required this.characterStates,
    required this.probabilityStart,
    required this.probabilityTransition,
    required this.probabilityEmission,
    required this.characterRecordCount,
    required this.characterStateCount,
    required this.stateCount,
    required this.transitionEntryCount,
    required this.emissionEntryCount,
  });

  final _ResourceManifest characterStates;
  final _ResourceManifest probabilityStart;
  final _ResourceManifest probabilityTransition;
  final _ResourceManifest probabilityEmission;
  final int characterRecordCount;
  final int characterStateCount;
  final int stateCount;
  final int transitionEntryCount;
  final int emissionEntryCount;

  bool get isValid =>
      characterStates.isValid &&
      probabilityStart.isValid &&
      probabilityTransition.isValid &&
      probabilityEmission.isValid &&
      characterRecordCount > 0 &&
      characterRecordCount <= _maximumPickleMapEntries &&
      characterStateCount >= characterRecordCount &&
      characterStateCount <= _maximumPickleMemoEntries &&
      stateCount > 0 &&
      stateCount <= _maximumPickleMapEntries &&
      transitionEntryCount >= 0 &&
      transitionEntryCount <= _maximumPickleMapEntries &&
      emissionEntryCount >= 0 &&
      emissionEntryCount <= _maximumPickleMapEntries;
}

final class _JiebaPartOfSpeechPaths {
  const _JiebaPartOfSpeechPaths({
    required this.characterStates,
    required this.probabilityStart,
    required this.probabilityTransition,
    required this.probabilityEmission,
  });

  final String characterStates;
  final String probabilityStart;
  final String probabilityTransition;
  final String probabilityEmission;
}

const Object _pickleMark = Object();
const List<String> _states = <String>['B', 'M', 'E', 'S'];
const Map<String, int> _stateIndex = <String, int>{
  'B': 0,
  'M': 1,
  'E': 2,
  'S': 3,
};
const Map<String, List<String>> _expectedNextStates = <String, List<String>>{
  'B': <String>['E', 'M'],
  'E': <String>['B', 'S'],
  'M': <String>['E', 'M'],
  'S': <String>['B', 'S'],
};
const int _stateB = 0;
const int _stateM = 1;
const int _stateE = 2;
const int _stateS = 3;
const List<int> _stateCodeUnits = <int>[0x42, 0x4D, 0x45, 0x53];
const List<List<int>> _previousStates = <List<int>>[
  <int>[_stateE, _stateS], // B <- E,S
  <int>[_stateM, _stateB], // M <- M,B
  <int>[_stateB, _stateM], // E <- B,M
  <int>[_stateS, _stateE], // S <- S,E
];
final RegExp _memoPattern = RegExp(r'^(?:0|[1-9][0-9]*)$');
final RegExp _pickleAsciiAtomPattern = RegExp(r'^[A-Za-z0-9_.+-]{1,32}$');
final RegExp _partOfSpeechTagPattern = RegExp(r'^[a-z]{1,16}$');
final RegExp _floatPattern = RegExp(
  r'^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:e[+-]?[0-9]+)?$',
);
