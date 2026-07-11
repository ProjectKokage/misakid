import 'cutlet_mapping.dart';
import 'pyopenjtalk_engine.dart';

/// Selects one of pinned Misaki's distinct Japanese phoneme contracts.
enum JapanesePhonemeMode {
  /// IPA-oriented Cutlet rendering.
  cutlet,

  /// Mora rendering from the pyopenjtalk-style frontend.
  pyopenjtalk,
}

/// Returns the frozen built-in phonetic-scalar inventory for [mode].
///
/// The Cutlet inventory includes its 164 phonetic mapping entries plus the
/// algorithmic sokuon, moraic-nasal, and long-vowel symbols. Punctuation and
/// arbitrary ASCII or unknown-symbol pass-through are intentionally excluded.
///
/// The pyopenjtalk inventory comes from all 193 mora mappings. Punctuation,
/// whitespace, the configurable unknown marker, and the appended pitch-trace
/// markers `_`, `-`, and `^` are outside it. The scalar `j` remains because it
/// is also a phoneme in the pinned mora table.
///
/// ```dart
/// final phones = japanesePhonemeInventory(JapanesePhonemeMode.cutlet);
/// print(phones.contains('ʔ')); // true
/// ```
Set<String> japanesePhonemeInventory(JapanesePhonemeMode mode) =>
    switch (mode) {
      JapanesePhonemeMode.cutlet => _cutletInventory,
      JapanesePhonemeMode.pyopenjtalk => _pyopenjtalkInventory,
    };

final Set<String> _cutletInventory = _frozenScalars(
  japaneseCutletPhoneticMappingValues,
  additional: 'ʔŋɴː',
);

final Set<String> _pyopenjtalkInventory = _frozenScalars(
  japanesePyopenjtalkMoraEntries.map((entry) => entry.value),
);

Set<String> _frozenScalars(Iterable<String> values, {String additional = ''}) {
  final result = <String>{};
  for (final value in values) {
    result.addAll(value.runes.map<String>(String.fromCharCode));
  }
  result.addAll(additional.runes.map<String>(String.fromCharCode));
  return Set<String>.unmodifiable(result);
}
