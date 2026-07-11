import 'morphology.dart';
import 'render.dart';

/// Returns the frozen built-in English phoneme inventory for one mode.
///
/// The inventory covers the pinned lexicons and deterministic eSpeak
/// postprocessor. Punctuation, whitespace, the unknown marker, and arbitrary
/// inline custom pronunciations are intentionally outside it. The American
/// version-2 inventory includes upstream data's observable `ʔ` addition even
/// though the pinned `EN_PHONES.md` count predates that data quirk.
Set<String> englishPhonemeInventory({
  required EnglishDialect dialect,
  EnglishPhonemeVersion version = EnglishPhonemeVersion.legacy,
}) => switch ((dialect, version)) {
  (EnglishDialect.american, EnglishPhonemeVersion.legacy) => _americanLegacy,
  (EnglishDialect.american, EnglishPhonemeVersion.v2) => _americanV2,
  (EnglishDialect.british, _) => _british,
};

final Set<String> _americanV2 = _frozenScalars(
  'AIOWYbdfhijklmnpstuvwzæðŋɑɔəɛɜɡɪɹɾʃʊʌʒʔʤʧˈˌθᵊᵻ',
);
final Set<String> _americanLegacy = Set<String>.unmodifiable(
  <String>{..._americanV2, 'T'}..removeAll(const <String>{'ɾ', 'ʔ'}),
);
final Set<String> _british = _frozenScalars(
  'AIQWYabdfhijklmnpstuvwzðŋɑɒɔəɛɜɡɪɹʃʊʌʒʤʧˈˌːθᵊ',
);

Set<String> _frozenScalars(String value) =>
    Set<String>.unmodifiable(value.runes.map<String>(String.fromCharCode));
