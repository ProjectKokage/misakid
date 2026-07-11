/// Language-specific, typed token details.
sealed class TokenMetadata {
  const TokenMetadata();
}

/// Metadata produced by the English pipeline.
final class EnglishTokenMetadata extends TokenMetadata {
  /// Creates English token metadata.
  const EnglishTokenMetadata({
    required this.isHead,
    this.alias,
    this.stress,
    this.currency,
    this.numberFlags = '',
    this.precededBySpace = false,
    this.rating,
  });

  /// Whether this token begins an upstream word group.
  final bool isHead;

  /// Optional lexical alias used for lookup.
  final String? alias;

  /// Requested stress adjustment; upstream uses integral and half-step values.
  final num? stress;

  /// Currency symbol associated with a numeric token.
  final String? currency;

  /// Ordered flags controlling upstream number pronunciation.
  final String numberFlags;

  /// Whether rendering inserts a separator before this subtoken.
  final bool precededBySpace;

  /// Upstream pronunciation quality rating when available.
  final int? rating;
}

/// Metadata produced by the pyopenjtalk-style Japanese pipeline.
final class JapaneseTokenMetadata extends TokenMetadata {
  /// Creates Japanese token metadata.
  JapaneseTokenMetadata({
    required this.pronunciation,
    required this.accent,
    required this.moraSize,
    required this.chainFlag,
    required List<String> moras,
    required List<int> accents,
    this.pitch,
  }) : moras = List<String>.unmodifiable(moras),
       accents = List<int>.unmodifiable(accents);

  /// Backend pronunciation string.
  final String pronunciation;

  /// Accent nucleus reported by the backend.
  final int accent;

  /// Backend-reported number of moras.
  final int moraSize;

  /// Whether this token continues the preceding accent phrase.
  final bool chainFlag;

  /// Parsed moras in source order.
  final List<String> moras;

  /// Upstream accent-state value for each mora.
  final List<int> accents;

  /// Per-phoneme pitch trace when the selected backend supplies one.
  final String? pitch;
}

/// Metadata produced by the Vietnamese pipeline.
final class VietnameseTokenMetadata extends TokenMetadata {
  /// Creates Vietnamese token metadata.
  const VietnameseTokenMetadata({
    this.parent,
    required this.onset,
    required this.nucleus,
    required this.coda,
    required this.tone,
  });

  /// Parent token when fallback splits a source token into substrings.
  final String? parent;

  /// Syllable onset.
  final String onset;

  /// Syllable nucleus.
  final String nucleus;

  /// Syllable coda.
  final String coda;

  /// Tone symbols.
  final String tone;
}
