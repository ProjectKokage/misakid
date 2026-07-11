import '../../core/backend.dart';
import '../../core/metadata.dart';
import '../../core/token.dart';
import 'context.dart';
import 'preprocess.dart';

/// Immutable pronunciation returned by an injected English provider.
final class EnglishPronunciation {
  /// Creates a pronunciation with optional upstream-compatible [rating].
  const EnglishPronunciation({required this.phonemes, this.rating});

  /// Exact phoneme string. An empty string is a successful empty result.
  final String phonemes;

  /// Optional pronunciation quality rating.
  final int? rating;
}

/// Explicit tokenizer and part-of-speech tagger boundary for English.
///
/// Implementations must align [EnglishPreprocessResult.controls] to their
/// backend tokens and return tokens with [EnglishTokenMetadata] already
/// populated. Concatenating every token's text and whitespace must reproduce
/// [EnglishPreprocessResult.text] exactly. In particular, multi-token slash
/// controls set `isHead` on the first token and provide empty phonemes for
/// continuation tokens.
///
/// No spaCy tokenizer or tagger adapter is bundled by the pure-Dart package.
abstract interface class EnglishTokenizerBackend implements MisakiBackend {
  /// Tokenizes and tags [input], applying its inline controls.
  List<MisakiToken> tokenize(EnglishPreprocessResult input);
}

/// Context-aware English lexicon or pronunciation-rule boundary.
///
/// Returning `null` represents a lookup miss. `PinnedEnglishLexicon` is the
/// package's offline implementation; callers may inject another provider.
abstract interface class EnglishPronunciationBackend implements MisakiBackend {
  /// Looks up [token] using right-to-left [context].
  EnglishPronunciation? lookup(MisakiToken token, EnglishTokenContext context);
}

/// Optional context-free fallback pronunciation boundary.
///
/// Returning `null` leaves the token unresolved. Model-backed implementations
/// belong in an explicitly configured adapter, not in the pure core.
abstract interface class EnglishFallbackBackend implements MisakiBackend {
  /// Attempts a fallback pronunciation for [token].
  EnglishPronunciation? pronounce(MisakiToken token);
}
