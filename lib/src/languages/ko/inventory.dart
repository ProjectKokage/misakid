// Source-derived from the modern conjoining-Jamo ranges used by
// python-jamo 0.4.1 and hexgrad/misaki/misaki/g2pkc at
// fba1236595f2d2bf21d414ba6e57d25256afada3 (Misaki 0.9.4).

/// Returns the frozen modern conjoining-Jamo inventory emitted by g2pkc.
///
/// The injected Korean engine runs upstream's default `to_syl=false` mode, so
/// Hangul syllables are rendered as 19 leading consonants, 21 vowels, and 27
/// trailing consonants. Non-Hangul source text, punctuation, and whitespace
/// are passed through separately and are not part of this phoneme inventory.
Set<String> koreanPhonemeInventory() => _koreanPhonemeInventory;

final Set<String> _koreanPhonemeInventory = Set<String>.unmodifiable(<String>{
  for (var scalar = 0x1100; scalar <= 0x1112; scalar++)
    String.fromCharCode(scalar),
  for (var scalar = 0x1161; scalar <= 0x1175; scalar++)
    String.fromCharCode(scalar),
  for (var scalar = 0x11A8; scalar <= 0x11C2; scalar++)
    String.fromCharCode(scalar),
});
