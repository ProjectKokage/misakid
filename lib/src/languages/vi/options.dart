// Dart adaptation of VIG2P configuration in hexgrad/misaki/misaki/vi.py at
// fba1236595f2d2bf21d414ba6e57d25256afada3 (Misaki 0.9.4).
// The phonemizer derives from Viphoneme under MIT; see
// THIRD_PARTY_NOTICES.md. Modifications: immutable enums/options and explicit
// backend policy.

/// Vietnamese pronunciation dialect.
enum VietnameseDialect {
  /// Northern pronunciation (`n`).
  north('n'),

  /// Central pronunciation (`c`).
  central('c'),

  /// Southern pronunciation (`s`).
  south('s');

  const VietnameseDialect(this.upstreamCode);

  /// One-letter code consumed by the pinned phonology rules.
  final String upstreamCode;
}

/// Upstream `tone_type` selection.
enum VietnameseToneType {
  /// `tone_type == 0`, which forces the Phạm digit system on.
  pham,

  /// Any nonzero `tone_type`, which forces the Cao digit system on.
  cao,
}

/// Immutable Vietnamese engine options.
final class VietnameseOptions {
  /// Creates Vietnamese options matching pinned `VIG2P` defaults, except that
  /// English fallback is supplied explicitly to the engine rather than
  /// constructed or downloaded.
  const VietnameseOptions({
    this.dialect = VietnameseDialect.north,
    this.glottal = false,
    this.pham = false,
    this.cao = false,
    this.palatals = false,
    this.substringTokenization = true,
    this.toneType = VietnameseToneType.pham,
    this.cleanAbbreviations = true,
    this.cleanAcronyms = true,
  });

  /// Dialect-specific coda and vowel behavior.
  final VietnameseDialect dialect;

  /// Whether vowel-initial syllables receive upstream's glottal behavior.
  final bool glottal;

  /// Explicit upstream `pham` flag, before `toneType` forces its mode.
  final bool pham;

  /// Explicit upstream `cao` flag, before `toneType` forces its mode.
  final bool cao;

  /// Whether northern front-vowel velar codas become palatal.
  final bool palatals;

  /// Whether unrecognized tokens are split into pronounceable substrings.
  final bool substringTokenization;

  /// Tone digit mode.
  final VietnameseToneType toneType;

  /// Whether the cleaner expands abbreviation/teencode mappings.
  final bool cleanAbbreviations;

  /// Whether the cleaner expands acronym mappings.
  final bool cleanAcronyms;

  /// Effective Phạm flag after pinned constructor forcing.
  bool get effectivePham => pham || toneType == VietnameseToneType.pham;

  /// Effective Cao flag after pinned constructor forcing.
  bool get effectiveCao => cao || toneType == VietnameseToneType.cao;
}
