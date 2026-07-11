// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0
//
// Behavior ported from curated-tokenizers 0.0.9 `_bbpe.pyx` and `merges.cc`
// as embedded by the pinned spaCy transformer environment. Its byte mapping
// and split contract originate in OpenAI GPT-2; see THIRD_PARTY_NOTICES.md.

import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:misakid/misaki.dart'
    show BackendFailureException, MalformedDataException;
import 'package:misakid_spacy_en/misakid_spacy_en.dart'
    show SpacyEnglishTokenization;

import 'regex_unicode_data.g.dart';

/// Exact byte length of the serialized byte-BPE payload in
/// `en_core_web_trf==3.8.0`.
const int spacyTransformerByteBpePayloadByteLength = 1063863;

/// Exact SHA-256 of the serialized byte-BPE payload in
/// `en_core_web_trf==3.8.0`.
const String spacyTransformerByteBpePayloadSha256 =
    '3a937453afcd04229fc5e32d7304c117781d4c48f1e7c87a603194e2077576f0';

const int _pinnedVocabularySize = 50265;
const int _pinnedMergeCount = 50000;
const int _maximumInputScalars = 1000000;
const int _maximumEncodedPieces = _maximumInputScalars * 4 + 2;
const int _maximumTableEntries = 60000;
const int _maximumPieceUtf8Bytes = 1024;

/// One ranked pair from a byte-BPE merge table.
final class SpacyTransformerByteBpeMerge {
  /// Creates a merge of [left] followed by [right].
  const SpacyTransformerByteBpeMerge(this.left, this.right);

  /// Left piece in the adjacent pair.
  final String left;

  /// Right piece in the adjacent pair.
  final String right;
}

/// Minimal tokenizer output consumed by the transformer piece encoder.
///
/// [isSpace] must carry spaCy's `Token.is_space` result. The encoder filters
/// such tokens before applying byte-BPE, matching `with_non_ws_tokens`.
final class SpacyTransformerInputToken {
  /// Creates a transformer input token.
  SpacyTransformerInputToken({
    required this.text,
    required this.whitespace,
    required this.isSpace,
  }) {
    if (text.isEmpty) {
      throw ArgumentError.value(text, 'text', 'A spaCy token cannot be empty.');
    }
    if (whitespace != '' && whitespace != ' ') {
      throw ArgumentError.value(
        whitespace,
        'whitespace',
        'spaCy token whitespace must be empty or one ASCII space.',
      );
    }
  }

  /// Exact token text.
  final String text;

  /// Exact spaCy `Token.whitespace_`, either empty or one ASCII space.
  final String whitespace;

  /// Whether spaCy classified this as a standalone whitespace token.
  final bool isSpace;
}

/// One document's byte-BPE IDs and exact token-to-piece alignment.
final class SpacyTransformerPieceSequence {
  SpacyTransformerPieceSequence._({
    required List<int> pieceIds,
    required List<int> tokenPieceLengths,
    required List<int> sourceTokenIndices,
  }) : pieceIds = List<int>.unmodifiable(pieceIds),
       tokenPieceLengths = List<int>.unmodifiable(tokenPieceLengths),
       sourceTokenIndices = List<int>.unmodifiable(sourceTokenIndices),
       raggedLengths = List<int>.unmodifiable(<int>[
         1,
         ...tokenPieceLengths,
         1,
       ]);

  /// Piece identifiers including one BOS ID and one EOS ID.
  final List<int> pieceIds;

  /// Piece count for each retained non-whitespace token.
  final List<int> tokenPieceLengths;

  /// Original input-token index for each entry in [tokenPieceLengths].
  final List<int> sourceTokenIndices;

  /// Upstream ragged lengths: BOS, every retained token, then EOS.
  final List<int> raggedLengths;
}

/// Pure-Dart implementation of the pinned GPT-2/RoBERTa byte-BPE stage.
///
/// The implementation uses the exact `regex==2024.11.6` Unicode property
/// tables committed with this package. It performs no Python, native, file,
/// model-discovery, or network operation.
final class SpacyTransformerByteBpe {
  SpacyTransformerByteBpe._(
    Map<String, int> vocabulary,
    List<SpacyTransformerByteBpeMerge> merges,
  ) : _vocabulary = Map<String, int>.unmodifiable(vocabulary),
      _mergeRanks = _buildMergeRanks(merges),
      _maximumMergedPieceSymbols = _maximumMergeResultSymbols(merges);

  /// Decodes the exact reviewed MessagePack payload extracted from byte
  /// offset 416 of `transformer/model` in `en_core_web_trf==3.8.0`.
  ///
  /// Both the payload byte length and SHA-256 are checked before the bounded
  /// decoder examines any container or string.
  factory SpacyTransformerByteBpe.decodePinnedPayload(Uint8List payload) {
    if (payload.length != spacyTransformerByteBpePayloadByteLength) {
      throw const MalformedDataException(
        'The en_core_web_trf byte-BPE payload has the wrong byte length.',
      );
    }
    if (sha256.convert(payload).toString() !=
        spacyTransformerByteBpePayloadSha256) {
      throw const MalformedDataException(
        'The en_core_web_trf byte-BPE payload failed its identity check.',
      );
    }

    final Object? decoded;
    try {
      decoded = const _BpeMessagePackDecoder().decode(payload);
    } on FormatException catch (error) {
      throw MalformedDataException(
        'The pinned en_core_web_trf byte-BPE payload is malformed.',
        cause: error,
      );
    }
    final tables = _decodePinnedTables(decoded);
    return SpacyTransformerByteBpe._(tables.vocabulary, tables.merges);
  }

  /// Creates a processor from explicit in-memory tables.
  ///
  /// This constructor is intended for deterministic unit tests and reviewed
  /// generated assets. Unlike [decodePinnedPayload], it does not claim the
  /// tables are the pinned production vocabulary.
  factory SpacyTransformerByteBpe.fromTables({
    required Map<String, int> vocabulary,
    required List<SpacyTransformerByteBpeMerge> merges,
  }) {
    _validateTables(vocabulary, merges, requirePinnedShape: false);
    return SpacyTransformerByteBpe._(
      Map<String, int>.of(vocabulary),
      List<SpacyTransformerByteBpeMerge>.of(merges),
    );
  }

  final Map<String, int> _vocabulary;
  final Map<(String, String), int> _mergeRanks;
  final int _maximumMergedPieceSymbols;

  /// Splits [text] with the pinned regex semantics, maps its UTF-8 bytes to
  /// GPT-2 byte symbols, and applies ranked merges.
  List<String> encodeAsPieces(String text) => _encodeAsPieces(
    text,
    maximumPieces: _maximumEncodedPieces,
    configuredMaximumPieces: _maximumEncodedPieces,
  );

  List<String> _encodeAsPieces(
    String text, {
    required int maximumPieces,
    required int configuredMaximumPieces,
    _TextMetrics? knownMetrics,
  }) {
    final metrics = knownMetrics ?? _measureText(text);
    if (metrics.scalarCount > _maximumInputScalars) {
      throw const BackendFailureException(
        'Transformer byte-BPE input exceeds the pinned 1,000,000-scalar limit.',
      );
    }
    _checkPieceLowerBound(
      utf8Bytes: metrics.utf8Bytes,
      maximumPieces: maximumPieces,
      configuredMaximumPieces: configuredMaximumPieces,
    );
    final scalarText = _ScalarText.parse(text);
    final pieces = <String>[];
    var offset = 0;
    while (offset < scalarText.length) {
      final contractionLength = _contractionLength(scalarText, offset);
      if (contractionLength != 0) {
        _encodeSplitToken(
          scalarText.substring(offset, offset + contractionLength),
          pieces,
          maximumPieces: maximumPieces - pieces.length,
          configuredMaximumPieces: configuredMaximumPieces,
        );
        offset += contractionLength;
        continue;
      }

      final categoryStart =
          scalarText.scalarAt(offset) == 0x20 && offset + 1 < scalarText.length
          ? offset + 1
          : offset;
      final first = scalarText.scalarAt(categoryStart);
      final category = _splitCategory(first);
      if (category != _SplitCategory.whitespace) {
        var end = categoryStart + 1;
        while (end < scalarText.length &&
            _splitCategory(scalarText.scalarAt(end)) == category) {
          end++;
        }
        _encodeSplitToken(
          scalarText.substring(offset, end),
          pieces,
          maximumPieces: maximumPieces - pieces.length,
          configuredMaximumPieces: configuredMaximumPieces,
        );
        offset = end;
        continue;
      }

      var whitespaceEnd = offset + 1;
      while (whitespaceEnd < scalarText.length &&
          isRegex20241106WhitespaceScalar(scalarText.scalarAt(whitespaceEnd))) {
        whitespaceEnd++;
      }
      final end =
          whitespaceEnd < scalarText.length && whitespaceEnd - offset > 1
          ? whitespaceEnd - 1
          : whitespaceEnd;
      _encodeSplitToken(
        scalarText.substring(offset, end),
        pieces,
        maximumPieces: maximumPieces - pieces.length,
        configuredMaximumPieces: configuredMaximumPieces,
      );
      offset = end;
    }
    return List<String>.unmodifiable(pieces);
  }

  /// Returns vocabulary IDs for [encodeAsPieces].
  List<int> encodeAsIds(String text) => _encodeAsIds(
    text,
    maximumPieces: _maximumEncodedPieces,
    configuredMaximumPieces: _maximumEncodedPieces,
  );

  List<int> _encodeAsIds(
    String text, {
    required int maximumPieces,
    required int configuredMaximumPieces,
    _TextMetrics? knownMetrics,
  }) {
    final pieces = _encodeAsPieces(
      text,
      maximumPieces: maximumPieces,
      configuredMaximumPieces: configuredMaximumPieces,
      knownMetrics: knownMetrics,
    );
    final ids = <int>[];
    for (final piece in pieces) {
      final id = _vocabulary[piece];
      if (id == null) {
        throw BackendFailureException(
          'Byte-BPE produced a piece absent from its vocabulary '
          '(UTF-16 length ${piece.length}).',
        );
      }
      ids.add(id);
    }
    return List<int>.unmodifiable(ids);
  }

  /// Encodes spaCy tokens as one BOS/token/EOS sequence.
  ///
  /// Standalone whitespace tokens are omitted. Each retained token after the
  /// first is encoded with the previous retained token's [SpacyTransformerInputToken.whitespace]
  /// prefix, exactly as the upstream byte-BPE encoder does after
  /// `with_non_ws_tokens` filtering. [maxPieces] is the aggregate marked-piece
  /// limit, including BOS and EOS, and must be at least two.
  SpacyTransformerPieceSequence encodeTokens(
    List<SpacyTransformerInputToken> tokens, {
    int maxPieces = _maximumEncodedPieces,
  }) {
    if (maxPieces < 2 || maxPieces > _maximumEncodedPieces) {
      throw RangeError.range(maxPieces, 2, _maximumEncodedPieces, 'maxPieces');
    }
    final bosId = _requiredSpecialId('<s>', 'BOS');
    final eosId = _requiredSpecialId('</s>', 'EOS');
    _requiredSpecialId('<unk>', 'UNK');

    final ids = <int>[bosId];
    final tokenPieceLengths = <int>[];
    final sourceTokenIndices = <int>[];
    SpacyTransformerInputToken? previous;
    var scalarCount = 0;
    for (var index = 0; index < tokens.length; index++) {
      final token = tokens[index];
      if (token.isSpace) {
        continue;
      }
      final text = previous == null
          ? token.text
          : '${previous.whitespace}${token.text}';
      final metrics = _measureText(text);
      scalarCount += metrics.scalarCount;
      if (scalarCount > _maximumInputScalars) {
        throw const BackendFailureException(
          'Transformer byte-BPE input exceeds the pinned 1,000,000-scalar limit.',
        );
      }
      final tokenIds = _encodeAsIds(
        text,
        maximumPieces: maxPieces - ids.length - 1,
        configuredMaximumPieces: maxPieces,
        knownMetrics: metrics,
      );
      ids.addAll(tokenIds);
      tokenPieceLengths.add(tokenIds.length);
      sourceTokenIndices.add(index);
      previous = token;
    }
    ids.add(eosId);
    return SpacyTransformerPieceSequence._(
      pieceIds: ids,
      tokenPieceLengths: tokenPieceLengths,
      sourceTokenIndices: sourceTokenIndices,
    );
  }

  /// Encodes output from the shared exact spaCy English tokenizer.
  SpacyTransformerPieceSequence encodeTokenization(
    SpacyEnglishTokenization tokenization, {
    int maxPieces = _maximumEncodedPieces,
  }) => encodeTokens(<SpacyTransformerInputToken>[
    for (final token in tokenization.tokens)
      SpacyTransformerInputToken(
        text: token.text,
        whitespace: token.whitespace,
        isSpace: token.isSpace,
      ),
  ], maxPieces: maxPieces);

  void _encodeSplitToken(
    String token,
    List<String> output, {
    required int maximumPieces,
    required int configuredMaximumPieces,
  }) {
    final metrics = _measureText(token);
    _checkPieceLowerBound(
      utf8Bytes: metrics.utf8Bytes,
      maximumPieces: maximumPieces,
      configuredMaximumPieces: configuredMaximumPieces,
    );
    final initialPieces = <String>[
      for (final byte in utf8.encode(token)) _byteEncoder[byte],
    ];
    output.addAll(
      _applyMerges(
        initialPieces,
        _mergeRanks,
        maximumPieces: maximumPieces,
        configuredMaximumPieces: configuredMaximumPieces,
      ),
    );
  }

  void _checkPieceLowerBound({
    required int utf8Bytes,
    required int maximumPieces,
    required int configuredMaximumPieces,
  }) {
    final minimumPieces =
        (utf8Bytes + _maximumMergedPieceSymbols - 1) ~/
        _maximumMergedPieceSymbols;
    if (minimumPieces > maximumPieces) {
      _throwPieceLimit(configuredMaximumPieces);
    }
  }

  int _requiredSpecialId(String piece, String label) {
    final id = _vocabulary[piece];
    if (id == null) {
      throw BackendFailureException(
        'Byte-BPE vocabulary does not contain the $label piece `$piece`.',
      );
    }
    return id;
  }
}

({Map<String, int> vocabulary, List<SpacyTransformerByteBpeMerge> merges})
_decodePinnedTables(Object? decoded) {
  if (decoded is! Map<Object?, Object?> ||
      decoded.length != 2 ||
      !decoded.containsKey('vocab') ||
      !decoded.containsKey('merges')) {
    throw const MalformedDataException(
      'The pinned byte-BPE payload must contain only `vocab` and `merges`.',
    );
  }
  final rawVocabulary = decoded['vocab'];
  if (rawVocabulary is! Map<Object?, Object?>) {
    throw const MalformedDataException(
      'The pinned byte-BPE vocabulary is not a map.',
    );
  }
  final vocabulary = <String, int>{};
  for (final entry in rawVocabulary.entries) {
    if (entry.key is! String || entry.value is! int) {
      throw const MalformedDataException(
        'The pinned byte-BPE vocabulary has a non-string key or non-integer ID.',
      );
    }
    vocabulary[entry.key! as String] = entry.value! as int;
  }

  final rawMerges = decoded['merges'];
  if (rawMerges is! List<Object?>) {
    throw const MalformedDataException(
      'The pinned byte-BPE merges value is not an array.',
    );
  }
  final merges = <SpacyTransformerByteBpeMerge>[];
  for (final rawMerge in rawMerges) {
    if (rawMerge is! List<Object?> ||
        rawMerge.length != 2 ||
        rawMerge[0] is! String ||
        rawMerge[1] is! String) {
      throw const MalformedDataException(
        'The pinned byte-BPE merge table contains a malformed pair.',
      );
    }
    merges.add(
      SpacyTransformerByteBpeMerge(
        rawMerge[0]! as String,
        rawMerge[1]! as String,
      ),
    );
  }
  _validateTables(vocabulary, merges, requirePinnedShape: true);
  return (vocabulary: vocabulary, merges: merges);
}

void _validateTables(
  Map<String, int> vocabulary,
  List<SpacyTransformerByteBpeMerge> merges, {
  required bool requirePinnedShape,
}) {
  if (vocabulary.length > _maximumTableEntries ||
      merges.length > _maximumTableEntries) {
    throw const MalformedDataException(
      'The byte-BPE tables exceed their bounded entry count.',
    );
  }
  if (requirePinnedShape &&
      (vocabulary.length != _pinnedVocabularySize ||
          merges.length != _pinnedMergeCount)) {
    throw const MalformedDataException(
      'The pinned byte-BPE tables have unexpected cardinalities.',
    );
  }
  final ids = <int>{};
  for (final entry in vocabulary.entries) {
    if (entry.key.isEmpty ||
        utf8.encode(entry.key).length > _maximumPieceUtf8Bytes ||
        entry.value < 0 ||
        !ids.add(entry.value)) {
      throw const MalformedDataException(
        'The byte-BPE vocabulary has an invalid piece, negative ID, or duplicate ID.',
      );
    }
  }
  final pairs = <(String, String)>{};
  for (final merge in merges) {
    final pair = (merge.left, merge.right);
    if (merge.left.isEmpty ||
        merge.right.isEmpty ||
        utf8.encode(merge.left).length > _maximumPieceUtf8Bytes ||
        utf8.encode(merge.right).length > _maximumPieceUtf8Bytes ||
        !pairs.add(pair)) {
      throw const MalformedDataException(
        'The byte-BPE merge table has an invalid or duplicate pair.',
      );
    }
  }
  if (requirePinnedShape) {
    if (vocabulary['<s>'] != 0 ||
        vocabulary['<pad>'] != 1 ||
        vocabulary['</s>'] != 2 ||
        vocabulary['<unk>'] != 3 ||
        ids.length != _pinnedVocabularySize ||
        !ids.contains(_pinnedVocabularySize - 1)) {
      throw const MalformedDataException(
        'The pinned byte-BPE vocabulary IDs or special pieces are malformed.',
      );
    }
    for (var id = 0; id < _pinnedVocabularySize; id++) {
      if (!ids.contains(id)) {
        throw const MalformedDataException(
          'The pinned byte-BPE vocabulary IDs are not contiguous.',
        );
      }
    }
  }
}

Map<(String, String), int> _buildMergeRanks(
  List<SpacyTransformerByteBpeMerge> merges,
) => Map<(String, String), int>.unmodifiable(<(String, String), int>{
  for (var rank = 0; rank < merges.length; rank++)
    (merges[rank].left, merges[rank].right): rank,
});

int _maximumMergeResultSymbols(List<SpacyTransformerByteBpeMerge> merges) {
  var maximum = 1;
  for (final merge in merges) {
    final symbols = merge.left.runes.length + merge.right.runes.length;
    if (symbols > maximum) {
      maximum = symbols;
    }
  }
  return maximum;
}

List<String> _applyMerges(
  List<String> initialPieces,
  Map<(String, String), int> mergeRanks, {
  required int maximumPieces,
  required int configuredMaximumPieces,
}) {
  if (initialPieces.length <= 1) {
    if (initialPieces.length > maximumPieces) {
      _throwPieceLimit(configuredMaximumPieces);
    }
    return initialPieces;
  }

  final pieces = initialPieces;
  final previous = Int32List(pieces.length);
  final next = Int32List(pieces.length);
  final queuedRank = Int32List(pieces.length);
  final alive = Uint8List(pieces.length);
  final occurrences = SplayTreeMap<int, SplayTreeSet<int>>();

  for (var index = 0; index < pieces.length; index++) {
    previous[index] = index - 1;
    next[index] = index + 1 < pieces.length ? index + 1 : -1;
    queuedRank[index] = -1;
    alive[index] = 1;
  }

  void removeQueuedOccurrence(int left) {
    final rank = queuedRank[left];
    if (rank < 0) {
      return;
    }
    final bucket = occurrences[rank];
    bucket?.remove(left);
    if (bucket != null && bucket.isEmpty) {
      occurrences.remove(rank);
    }
    queuedRank[left] = -1;
  }

  void refresh(int left) {
    if (left < 0) {
      return;
    }
    removeQueuedOccurrence(left);
    if (alive[left] == 0) {
      return;
    }
    final right = next[left];
    if (right < 0) {
      return;
    }
    final rank = mergeRanks[(pieces[left], pieces[right])];
    if (rank == null) {
      return;
    }
    occurrences.putIfAbsent(rank, SplayTreeSet<int>.new).add(left);
    queuedRank[left] = rank;
  }

  for (var index = 0; index + 1 < pieces.length; index++) {
    refresh(index);
  }

  var activeCount = pieces.length;
  final affected = <int>[];
  final isAffected = Uint8List(pieces.length);

  void markAffected(int index) {
    if (index >= 0 && isAffected[index] == 0) {
      isAffected[index] = 1;
      affected.add(index);
    }
  }

  while (occurrences.isNotEmpty) {
    final selectedRank = occurrences.firstKey()!;
    final selectedStarts = occurrences
        .remove(selectedRank)!
        .toList(growable: false);
    for (final left in selectedStarts) {
      queuedRank[left] = -1;
    }

    final mergedLefts = <int>[];
    for (final left in selectedStarts) {
      if (alive[left] == 0) {
        continue;
      }
      final right = next[left];
      if (right < 0 ||
          alive[right] == 0 ||
          mergeRanks[(pieces[left], pieces[right])] != selectedRank) {
        continue;
      }

      final after = next[right];
      pieces[left] = '${pieces[left]}${pieces[right]}';
      pieces[right] = '';
      alive[right] = 0;
      next[left] = after;
      if (after >= 0) {
        previous[after] = left;
      }
      previous[right] = -1;
      next[right] = -1;
      activeCount--;
      mergedLefts.add(left);
      markAffected(right);
    }

    // Refresh only after the whole selected-pair snapshot has merged. This is
    // what preserves curated-tokenizers' simultaneous batch behavior when a
    // merge exposes a newly lower-ranked pair. Use post-batch predecessors so
    // adjacent disjoint merges expose the boundary between their results.
    for (final left in mergedLefts) {
      markAffected(left);
      markAffected(previous[left]);
    }
    for (final index in affected) {
      refresh(index);
      isAffected[index] = 0;
    }
    affected.clear();
  }

  if (activeCount > maximumPieces) {
    _throwPieceLimit(configuredMaximumPieces);
  }
  final result = <String>[];
  var index = 0;
  while (index >= 0) {
    result.add(pieces[index]);
    index = next[index];
  }
  return result;
}

enum _SplitCategory { letter, number, other, whitespace }

_SplitCategory _splitCategory(int scalar) {
  if (isRegex20241106LetterScalar(scalar)) {
    return _SplitCategory.letter;
  }
  if (isRegex20241106NumberScalar(scalar)) {
    return _SplitCategory.number;
  }
  if (isRegex20241106WhitespaceScalar(scalar)) {
    return _SplitCategory.whitespace;
  }
  return _SplitCategory.other;
}

const List<List<int>> _contractionSuffixes = <List<int>>[
  <int>[0x73],
  <int>[0x74],
  <int>[0x72, 0x65],
  <int>[0x76, 0x65],
  <int>[0x6D],
  <int>[0x6C, 0x6C],
  <int>[0x64],
];

int _contractionLength(_ScalarText text, int offset) {
  if (text.scalarAt(offset) != 0x27) {
    return 0;
  }
  for (final suffix in _contractionSuffixes) {
    if (offset + suffix.length >= text.length) {
      continue;
    }
    var matches = true;
    for (var index = 0; index < suffix.length; index++) {
      if (text.scalarAt(offset + index + 1) != suffix[index]) {
        matches = false;
        break;
      }
    }
    if (matches) {
      return suffix.length + 1;
    }
  }
  return 0;
}

final List<String> _byteEncoder = _buildByteEncoder();

List<String> _buildByteEncoder() {
  final mapped = List<String>.filled(256, '');
  final direct = List<bool>.filled(256, false);
  for (var byte = 0x21; byte <= 0x7E; byte++) {
    direct[byte] = true;
  }
  for (var byte = 0xA1; byte <= 0xAC; byte++) {
    direct[byte] = true;
  }
  for (var byte = 0xAE; byte <= 0xFF; byte++) {
    direct[byte] = true;
  }
  for (var byte = 0; byte < 256; byte++) {
    if (direct[byte]) {
      mapped[byte] = String.fromCharCode(byte);
    }
  }
  var nextScalar = 0x100;
  for (var byte = 0; byte < 256; byte++) {
    if (!direct[byte]) {
      mapped[byte] = String.fromCharCode(nextScalar++);
    }
  }
  return List<String>.unmodifiable(mapped);
}

final class _ScalarText {
  _ScalarText._(this.source, this.scalars, this.utf16Offsets);

  factory _ScalarText.parse(String source) {
    final scalars = <int>[];
    final offsets = <int>[];
    var offset = 0;
    while (offset < source.length) {
      if (scalars.length >= _maximumInputScalars) {
        throw const BackendFailureException(
          'Transformer byte-BPE input exceeds the pinned 1,000,000-scalar limit.',
        );
      }
      offsets.add(offset);
      final first = source.codeUnitAt(offset);
      if (first >= 0xD800 && first <= 0xDBFF) {
        if (offset + 1 >= source.length) {
          throw const BackendFailureException(
            'Transformer byte-BPE input contains an unpaired UTF-16 surrogate.',
          );
        }
        final second = source.codeUnitAt(offset + 1);
        if (second < 0xDC00 || second > 0xDFFF) {
          throw const BackendFailureException(
            'Transformer byte-BPE input contains an unpaired UTF-16 surrogate.',
          );
        }
        scalars.add(0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00));
        offset += 2;
      } else if (first >= 0xDC00 && first <= 0xDFFF) {
        throw const BackendFailureException(
          'Transformer byte-BPE input contains an unpaired UTF-16 surrogate.',
        );
      } else {
        scalars.add(first);
        offset++;
      }
    }
    offsets.add(source.length);
    return _ScalarText._(
      source,
      List<int>.unmodifiable(scalars),
      List<int>.unmodifiable(offsets),
    );
  }

  final String source;
  final List<int> scalars;
  final List<int> utf16Offsets;

  int get length => scalars.length;

  int scalarAt(int index) => scalars[index];

  String substring(int start, int end) =>
      source.substring(utf16Offsets[start], utf16Offsets[end]);
}

final class _TextMetrics {
  const _TextMetrics({required this.scalarCount, required this.utf8Bytes});

  final int scalarCount;
  final int utf8Bytes;
}

_TextMetrics _measureText(String text) {
  var scalarCount = 0;
  var utf8Bytes = 0;
  var offset = 0;
  while (offset < text.length) {
    final first = text.codeUnitAt(offset);
    if (first >= 0xD800 && first <= 0xDBFF) {
      if (offset + 1 >= text.length) {
        throw const BackendFailureException(
          'Transformer byte-BPE input contains an unpaired UTF-16 surrogate.',
        );
      }
      final second = text.codeUnitAt(offset + 1);
      if (second < 0xDC00 || second > 0xDFFF) {
        throw const BackendFailureException(
          'Transformer byte-BPE input contains an unpaired UTF-16 surrogate.',
        );
      }
      utf8Bytes += 4;
      offset += 2;
    } else if (first >= 0xDC00 && first <= 0xDFFF) {
      throw const BackendFailureException(
        'Transformer byte-BPE input contains an unpaired UTF-16 surrogate.',
      );
    } else {
      utf8Bytes += first <= 0x7F
          ? 1
          : first <= 0x7FF
          ? 2
          : 3;
      offset++;
    }
    scalarCount++;
    if (scalarCount > _maximumInputScalars) {
      throw const BackendFailureException(
        'Transformer byte-BPE input exceeds the pinned 1,000,000-scalar limit.',
      );
    }
  }
  return _TextMetrics(scalarCount: scalarCount, utf8Bytes: utf8Bytes);
}

Never _throwPieceLimit(int configuredMaximumPieces) =>
    throw BackendFailureException(
      'Transformer byte-BPE output exceeds the configured aggregate limit of '
      '$configuredMaximumPieces marked pieces.',
    );

final class _BpeMessagePackDecoder {
  const _BpeMessagePackDecoder();

  Object? decode(Uint8List bytes) {
    if (bytes.length > spacyTransformerByteBpePayloadByteLength) {
      throw const FormatException('MessagePack input exceeds its byte limit.');
    }
    final reader = _BpeMessagePackReader(bytes);
    final value = reader.read(depth: 0);
    if (!reader.isAtEnd) {
      throw FormatException(
        'Trailing bytes after MessagePack value at offset ${reader.offset}.',
      );
    }
    return value;
  }
}

final class _BpeMessagePackReader {
  _BpeMessagePackReader(this.bytes) : _data = ByteData.sublistView(bytes);

  static const int _maximumDepth = 4;
  static const int _maximumContainerLength = _maximumTableEntries;
  static const int _maximumStringBytes = _maximumPieceUtf8Bytes;
  static const int _maximumValues = 300000;

  final Uint8List bytes;
  final ByteData _data;
  var offset = 0;
  var _values = 0;

  bool get isAtEnd => offset == bytes.length;

  Object? read({required int depth}) {
    _values++;
    if (_values > _maximumValues) {
      throw const FormatException('MessagePack value count exceeds its limit.');
    }
    final marker = _readByte();
    if (marker <= 0x7F) {
      return marker;
    }
    if (marker >= 0xE0) {
      return marker - 0x100;
    }
    if (marker >= 0xA0 && marker <= 0xBF) {
      return _readString(marker & 0x1F);
    }
    if (marker >= 0x90 && marker <= 0x9F) {
      return _readArray(marker & 0x0F, depth);
    }
    if (marker >= 0x80 && marker <= 0x8F) {
      return _readMap(marker & 0x0F, depth);
    }
    return switch (marker) {
      0xC0 => null,
      0xC2 => false,
      0xC3 => true,
      0xCC => _readUnsigned(1),
      0xCD => _readUnsigned(2),
      0xCE => _readUnsigned(4),
      0xD0 => _readSigned(1),
      0xD1 => _readSigned(2),
      0xD2 => _readSigned(4),
      0xD9 => _readString(_readUnsigned(1)),
      0xDA => _readString(_readUnsigned(2)),
      0xDB => _readString(_readUnsigned(4)),
      0xDC => _readArray(_readUnsigned(2), depth),
      0xDD => _readArray(_readUnsigned(4), depth),
      0xDE => _readMap(_readUnsigned(2), depth),
      0xDF => _readMap(_readUnsigned(4), depth),
      _ => throw FormatException(
        'Unsupported MessagePack marker 0x${marker.toRadixString(16)} '
        'at offset ${offset - 1}.',
      ),
    };
  }

  int _readByte() {
    _require(1);
    return bytes[offset++];
  }

  int _readUnsigned(int width) {
    _require(width);
    final start = offset;
    offset += width;
    return switch (width) {
      1 => _data.getUint8(start),
      2 => _data.getUint16(start, Endian.big),
      4 => _data.getUint32(start, Endian.big),
      _ => throw StateError('Unsupported unsigned width $width.'),
    };
  }

  int _readSigned(int width) {
    _require(width);
    final start = offset;
    offset += width;
    return switch (width) {
      1 => _data.getInt8(start),
      2 => _data.getInt16(start, Endian.big),
      4 => _data.getInt32(start, Endian.big),
      _ => throw StateError('Unsupported signed width $width.'),
    };
  }

  String _readString(int length) {
    if (length > _maximumStringBytes) {
      throw const FormatException('MessagePack string exceeds its byte limit.');
    }
    _require(length);
    final start = offset;
    offset += length;
    try {
      return utf8.decode(
        Uint8List.sublistView(bytes, start, start + length),
        allowMalformed: false,
      );
    } on FormatException catch (error) {
      throw FormatException(
        'Invalid UTF-8 in MessagePack string at offset $start.',
        error,
      );
    }
  }

  List<Object?> _readArray(int length, int depth) {
    _checkContainer(length, depth, 'array');
    final result = <Object?>[];
    for (var index = 0; index < length; index++) {
      result.add(read(depth: depth + 1));
    }
    return List<Object?>.unmodifiable(result);
  }

  Map<Object?, Object?> _readMap(int length, int depth) {
    _checkContainer(length, depth, 'map');
    final result = <Object?, Object?>{};
    for (var index = 0; index < length; index++) {
      final key = read(depth: depth + 1);
      if (key is List<Object?> || key is Map<Object?, Object?>) {
        throw const FormatException('MessagePack map key is not scalar.');
      }
      if (result.containsKey(key)) {
        throw FormatException('Duplicate MessagePack map key `$key`.');
      }
      result[key] = read(depth: depth + 1);
    }
    return Map<Object?, Object?>.unmodifiable(result);
  }

  void _checkContainer(int length, int depth, String kind) {
    if (depth >= _maximumDepth) {
      throw FormatException('MessagePack $kind nesting exceeds its limit.');
    }
    if (length > _maximumContainerLength) {
      throw FormatException('MessagePack $kind length exceeds its limit.');
    }
  }

  void _require(int length) {
    if (length < 0 || offset + length > bytes.length) {
      throw FormatException(
        'Truncated MessagePack value at byte offset $offset.',
      );
    }
  }
}
