// Dart adaptation of the frontend chunking in hexgrad/kokoro/kokoro/pipeline.py
// at dfb907a02bba8152ca444717ca5d78747ccb4bec (Kokoro 0.9.4,
// Apache-2.0).
//
// Modifications: separates English and non-English behavior into typed,
// platform-neutral APIs; consumes immutable Misaki results; and represents
// Python code points over Dart UTF-16 without replacing isolated surrogates.

import 'engine.dart';
import 'errors.dart';
import 'python312_unicode.dart';
import 'result.dart';
import 'token.dart';

const int _maximumPhonemeCodePoints = 510;
const int _nonEnglishChunkTargetCodePoints = 400;
const int _lineFeed = 0x0a;

const List<Set<String>> _englishBoundaryWaterfall = <Set<String>>[
  <String>{'!', '.', '?', '…'},
  <String>{':', ';'},
  <String>{',', '—'},
];
const Set<String> _englishBoundaryBumps = <String>{')', '”'};
const Set<int> _nonEnglishSentencePunctuation = <int>{0x21, 0x2e, 0x3f};

/// One text-and-phoneme chunk ready for Kokoro model input preparation.
///
/// This type deliberately stops before phoneme-to-vocabulary conversion,
/// voice selection, and inference. English chunks retain their exact Misaki
/// tokens; the Kokoro non-English contract does not expose tokens.
final class KokoroG2pChunk {
  KokoroG2pChunk._({
    required this.graphemes,
    required this.phonemes,
    required List<MisakiToken>? tokens,
    required this.textIndex,
  }) : tokens = tokens == null ? null : List<MisakiToken>.unmodifiable(tokens);

  /// Source text represented by this chunk.
  final String graphemes;

  /// Exact phoneme text, limited to 510 Python Unicode code points.
  final String phonemes;

  /// Exact English tokens, or `null` for the non-English Kokoro contract.
  final List<MisakiToken>? tokens;

  /// Index of the default line-feed segment, or `null` for direct token input.
  ///
  /// Empty source segments still consume an index, matching Kokoro's
  /// `enumerate(text)` result contract. Every subchunk of a segment has the
  /// same index.
  final int? textIndex;
}

/// Kokoro 0.9.4's token-aware English G2P frontend.
///
/// The injected [engine] must use an empty unknown marker, matching Kokoro's
/// `en.G2P(..., unk='')` construction. This frontend applies Kokoro's default
/// splitting on runs of line-feed characters, performs G2P once per resulting
/// segment, and then uses the 510-code-point punctuation waterfall over token
/// phonemes.
///
/// The aggregate `G2pResult.phonemes` value is not used for chunking because
/// Kokoro reconstructs phonemes from the exact token list. A `null` token
/// phoneme becomes an empty string, matching Kokoro's English pipeline.
final class KokoroEnglishG2pFrontend {
  /// Creates an English frontend backed by [engine].
  KokoroEnglishG2pFrontend({required this.engine}) {
    if (engine.unknownMarker.isNotEmpty) {
      throw InvalidConfigurationException(
        'Kokoro 0.9.4 English G2P requires an empty unknown marker; '
        'the configured engine uses `${engine.unknownMarker}`.',
      );
    }
  }

  /// Exact English G2P engine used for each default line-feed segment.
  final UnknownMarkerG2pEngine engine;

  /// Converts [text] into immutable Kokoro-compatible English chunks.
  ///
  /// This reproduces the default `split_pattern = r'\n+'` string-input path in
  /// Kokoro 0.9.4. Empty segments and chunks with empty phoneme output are
  /// omitted. The returned list is unmodifiable.
  List<KokoroG2pChunk> convert(String text) {
    final chunks = <KokoroG2pChunk>[];
    final segments = _splitDefaultSegments(text);
    for (var textIndex = 0; textIndex < segments.length; textIndex++) {
      final segment = segments[textIndex];
      if (_pythonStrip(segment).isEmpty) {
        continue;
      }
      chunks.addAll(chunkResult(engine.convert(segment), textIndex: textIndex));
    }
    return List<KokoroG2pChunk>.unmodifiable(chunks);
  }

  /// Chunks one exact English [result] without invoking an engine.
  ///
  /// This is useful when exact English G2P was performed separately. Tokens
  /// are required. The aggregate phoneme string is intentionally ignored, as
  /// it is by Kokoro's English token chunker. [textIndex] is `null` by default,
  /// matching Kokoro's direct-token path. The returned list is unmodifiable.
  static List<KokoroG2pChunk> chunkResult(G2pResult result, {int? textIndex}) {
    final sourceTokens = result.tokens;
    if (sourceTokens == null) {
      throw const BackendFailureException(
        'Kokoro English chunking requires exact token details.',
      );
    }
    final normalizedTokens = <MisakiToken>[
      for (final token in sourceTokens)
        token.phonemes == null ? _withPhonemes(token, '') : token,
    ];
    return _chunkEnglishTokens(normalizedTokens, textIndex: textIndex);
  }
}

/// Kokoro 0.9.4's pre-G2P chunking contract for non-English languages.
///
/// Unlike [KokoroEnglishG2pFrontend], this frontend groups source sentences to
/// a target of roughly 400 Python Unicode code points *before* invoking
/// [engine].
///
/// Only ASCII `.`, `!`, and `?` end a sentence. A single sentence longer than
/// 400 code points remains intact, preserving Kokoro's observable behavior.
///
/// Each engine result is truncated to 510 Python Unicode code points and its
/// token details are discarded, matching the current Kokoro pipeline
/// contract.
final class KokoroNonEnglishG2pFrontend {
  /// Creates a non-English frontend backed by [engine].
  const KokoroNonEnglishG2pFrontend({required this.engine});

  /// G2P engine invoked once for each pre-G2P source chunk.
  final G2pEngine engine;

  /// Converts [text] into immutable Kokoro-compatible non-English chunks.
  ///
  /// This reproduces the default `split_pattern = r'\n+'` string-input path in
  /// Kokoro 0.9.4. Empty source segments and empty engine outputs are omitted.
  /// The returned list is unmodifiable.
  List<KokoroG2pChunk> convert(String text) {
    final output = <KokoroG2pChunk>[];
    final segments = _splitDefaultSegments(text);
    for (var textIndex = 0; textIndex < segments.length; textIndex++) {
      final segment = segments[textIndex];
      if (_pythonStrip(segment).isEmpty) {
        continue;
      }
      for (final chunk in _chunkNonEnglishSource(segment)) {
        if (_pythonStrip(chunk).isEmpty) {
          continue;
        }
        final result = engine.convert(chunk);
        if (result.phonemes.isEmpty) {
          continue;
        }
        output.add(
          KokoroG2pChunk._(
            graphemes: chunk,
            phonemes: _truncateCodePoints(
              result.phonemes,
              _maximumPhonemeCodePoints,
            ),
            tokens: null,
            textIndex: textIndex,
          ),
        );
      }
    }
    return List<KokoroG2pChunk>.unmodifiable(output);
  }
}

List<KokoroG2pChunk> _chunkEnglishTokens(
  List<MisakiToken> tokens, {
  required int? textIndex,
}) {
  final output = <KokoroG2pChunk>[];
  var pending = <MisakiToken>[];
  var phonemeCount = 0;

  for (final token in tokens) {
    var nextPhonemes =
        '${token.phonemes!}${token.whitespace.isEmpty ? '' : ' '}';
    final nextCount =
        phonemeCount + _codePointLength(_pythonRstrip(nextPhonemes));
    if (nextCount > _maximumPhonemeCodePoints) {
      final splitAt = _waterfallLast(pending, nextCount);
      _appendEnglishChunk(
        output,
        pending.sublist(0, splitAt),
        textIndex: textIndex,
      );
      pending = pending.sublist(splitAt);
      phonemeCount = _codePointLength(_tokensToPhonemes(pending));
      if (pending.isEmpty) {
        nextPhonemes = _pythonLstrip(nextPhonemes);
      }
    }
    pending.add(token);
    phonemeCount += _codePointLength(nextPhonemes);
  }

  if (pending.isNotEmpty) {
    _appendEnglishChunk(output, pending, textIndex: textIndex);
  }
  return List<KokoroG2pChunk>.unmodifiable(output);
}

void _appendEnglishChunk(
  List<KokoroG2pChunk> output,
  List<MisakiToken> tokens, {
  required int? textIndex,
}) {
  final phonemes = _tokensToPhonemes(tokens);
  if (phonemes.isEmpty) {
    return;
  }
  output.add(
    KokoroG2pChunk._(
      graphemes: _tokensToText(tokens),
      phonemes: _truncateCodePoints(phonemes, _maximumPhonemeCodePoints),
      tokens: tokens,
      textIndex: textIndex,
    ),
  );
}

int _waterfallLast(List<MisakiToken> tokens, int nextCount) {
  for (final boundaryGroup in _englishBoundaryWaterfall) {
    int? boundary;
    for (var index = tokens.length - 1; index >= 0; index--) {
      if (boundaryGroup.contains(tokens[index].phonemes)) {
        boundary = index;
        break;
      }
    }
    if (boundary == null) {
      continue;
    }
    var splitAt = boundary + 1;
    if (splitAt < tokens.length &&
        _englishBoundaryBumps.contains(tokens[splitAt].phonemes)) {
      splitAt++;
    }
    final prefixLength = _codePointLength(
      _tokensToPhonemes(tokens.sublist(0, splitAt)),
    );
    if (nextCount - prefixLength <= _maximumPhonemeCodePoints) {
      return splitAt;
    }
  }
  return tokens.length;
}

String _tokensToPhonemes(List<MisakiToken> tokens) {
  final output = StringBuffer();
  for (final token in tokens) {
    output.write(token.phonemes!);
    if (token.whitespace.isNotEmpty) {
      output.write(' ');
    }
  }
  return _pythonStrip(output.toString());
}

String _tokensToText(List<MisakiToken> tokens) {
  final output = StringBuffer();
  for (final token in tokens) {
    output
      ..write(token.text)
      ..write(token.whitespace);
  }
  return _pythonStrip(output.toString());
}

List<String> _chunkNonEnglishSource(String text) {
  final chunks = <String>[];
  var current = StringBuffer();
  var currentLength = 0;
  for (final sentence in _sentenceUnits(text)) {
    final sentenceLength = _codePointLength(sentence);
    if (currentLength + sentenceLength <= _nonEnglishChunkTargetCodePoints) {
      current.write(sentence);
      currentLength += sentenceLength;
    } else {
      final value = current.toString();
      if (value.isNotEmpty) {
        chunks.add(_pythonStrip(value));
      }
      current = StringBuffer(sentence);
      currentLength = sentenceLength;
    }
  }

  final remainder = current.toString();
  if (remainder.isNotEmpty) {
    chunks.add(_pythonStrip(remainder));
  }

  if (chunks.isEmpty) {
    final codePoints = _pythonCodePoints(text);
    for (
      var start = 0;
      start < codePoints.length;
      start += _nonEnglishChunkTargetCodePoints
    ) {
      final candidateEnd = start + _nonEnglishChunkTargetCodePoints;
      final end = candidateEnd < codePoints.length
          ? candidateEnd
          : codePoints.length;
      chunks.add(String.fromCharCodes(codePoints.sublist(start, end)));
    }
  }
  return chunks;
}

List<String> _sentenceUnits(String text) {
  final codePoints = _pythonCodePoints(text);
  final output = <String>[];
  var start = 0;
  var index = 0;
  while (index < codePoints.length) {
    if (!_nonEnglishSentencePunctuation.contains(codePoints[index])) {
      index++;
      continue;
    }
    do {
      index++;
    } while (index < codePoints.length &&
        _nonEnglishSentencePunctuation.contains(codePoints[index]));
    output.add(String.fromCharCodes(codePoints.sublist(start, index)));
    start = index;
  }
  if (start < codePoints.length || output.isEmpty) {
    output.add(String.fromCharCodes(codePoints.sublist(start)));
  }
  return output;
}

List<String> _splitDefaultSegments(String text) {
  final stripped = _pythonStrip(text);
  if (stripped.isEmpty) {
    return const <String>[];
  }
  final codePoints = _pythonCodePoints(stripped);
  final output = <String>[];
  var start = 0;
  var index = 0;
  while (index < codePoints.length) {
    if (codePoints[index] != _lineFeed) {
      index++;
      continue;
    }
    output.add(String.fromCharCodes(codePoints.sublist(start, index)));
    do {
      index++;
    } while (index < codePoints.length && codePoints[index] == _lineFeed);
    start = index;
  }
  output.add(String.fromCharCodes(codePoints.sublist(start)));
  return output;
}

MisakiToken _withPhonemes(MisakiToken token, String phonemes) => MisakiToken(
  text: token.text,
  tag: token.tag,
  whitespace: token.whitespace,
  phonemes: phonemes,
  startTimeSeconds: token.startTimeSeconds,
  endTimeSeconds: token.endTimeSeconds,
  metadata: token.metadata,
);

int _codePointLength(String value) => _pythonCodePoints(value).length;

String _truncateCodePoints(String value, int maximum) {
  final codePoints = _pythonCodePoints(value);
  if (codePoints.length <= maximum) {
    return value;
  }
  return String.fromCharCodes(codePoints.sublist(0, maximum));
}

String _pythonStrip(String value) =>
    _pythonTrim(value, trimLeft: true, trimRight: true);

String _pythonLstrip(String value) =>
    _pythonTrim(value, trimLeft: true, trimRight: false);

String _pythonRstrip(String value) =>
    _pythonTrim(value, trimLeft: false, trimRight: true);

String _pythonTrim(
  String value, {
  required bool trimLeft,
  required bool trimRight,
}) {
  final codePoints = _pythonCodePoints(value);
  var start = 0;
  var end = codePoints.length;
  if (trimLeft) {
    while (start < end && isPython312WhitespaceScalar(codePoints[start])) {
      start++;
    }
  }
  if (trimRight) {
    while (end > start && isPython312WhitespaceScalar(codePoints[end - 1])) {
      end--;
    }
  }
  if (start == 0 && end == codePoints.length) {
    return value;
  }
  return String.fromCharCodes(codePoints.sublist(start, end));
}

List<int> _pythonCodePoints(String value) {
  final codeUnits = value.codeUnits;
  final codePoints = <int>[];
  for (var index = 0; index < codeUnits.length; index++) {
    final first = codeUnits[index];
    if (first >= 0xd800 && first <= 0xdbff && index + 1 < codeUnits.length) {
      final second = codeUnits[index + 1];
      if (second >= 0xdc00 && second <= 0xdfff) {
        codePoints.add(0x10000 + ((first - 0xd800) << 10) + (second - 0xdc00));
        index++;
        continue;
      }
    }
    codePoints.add(first);
  }
  return codePoints;
}
