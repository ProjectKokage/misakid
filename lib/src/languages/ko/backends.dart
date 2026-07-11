import '../../core/backend.dart';

/// One immutable `(surface, POS tag)` result from Korean morphology.
final class KoreanMorphologyToken {
  /// Creates a Korean morphology token.
  const KoreanMorphologyToken({required this.surface, required this.tag});

  /// Exact surface text returned by the analyzer.
  final String surface;

  /// Exact analyzer part-of-speech tag, including compound `+` tags.
  final String tag;
}

/// Explicit Korean morphology boundary matching `mecab.MeCab().pos`.
///
/// No MeCab implementation, dictionary, native discovery, or download is
/// bundled by the pure-Dart package.
abstract interface class KoreanMorphologyBackend implements MisakiBackend {
  /// Analyzes [text] into ordered surface/tag pairs.
  List<KoreanMorphologyToken> pos(String text);
}

/// One immutable first-choice CMUdict pronunciation.
final class KoreanCmuPronunciation {
  /// Creates an ARPABET pronunciation in exact phoneme order.
  KoreanCmuPronunciation(List<String> arpabet)
    : arpabet = List<String>.unmodifiable(arpabet);

  /// ARPABET symbols, including any stress digits from CMUdict.
  final List<String> arpabet;
}

/// Explicit CMUdict lookup boundary used by g2pkc English conversion.
///
/// [lookup] returns `null` for a dictionary miss. The engine spells uppercase
/// and missed ASCII words letter by letter, matching the pinned implementation.
abstract interface class KoreanCmuPronunciationProvider
    implements MisakiBackend {
  /// Returns the first pronunciation for lowercase ASCII [word], or `null`.
  KoreanCmuPronunciation? lookup(String word);
}
