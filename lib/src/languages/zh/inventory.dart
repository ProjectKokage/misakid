import 'frontend_1_1_engine.dart';
import 'transcription.dart';

/// Selects one of pinned Misaki's distinct Chinese rendering contracts.
enum ChinesePhonemeMode {
  /// Legacy/default IPA rendering with arrow-style tones.
  legacy,

  /// Frontend version 1.1 Bopomofo-style rendering.
  frontend11,
}

/// Returns the frozen source-derived render-scalar inventory for [mode].
///
/// The legacy inventory contains only scalars emitted by the first
/// pinyin-to-IPA variant selected by pinned `ZHG2P`, after legacy tone
/// replacement and U+032F cleanup. Punctuation, whitespace, mixed-script
/// pass-through, and backend-supplied text are excluded.
///
/// The frontend 1.1 inventory is derived from every value in its pinned phone
/// map. It therefore includes tone digits and the map's structural space,
/// slash, and punctuation entries. Configurable unknown markers and arbitrary
/// output from an injected English callback are excluded from both modes.
///
/// ```dart
/// final legacy = chinesePhonemeInventory(ChinesePhonemeMode.legacy);
/// print(legacy.contains('↗')); // true
/// ```
Set<String> chinesePhonemeInventory(ChinesePhonemeMode mode) => switch (mode) {
  ChinesePhonemeMode.legacy => _legacyInventory,
  ChinesePhonemeMode.frontend11 => _frontend11Inventory,
};

final Set<String> _legacyInventory = legacyChineseRenderedPhoneticScalars();
final Set<String> _frontend11Inventory = frontend11ChineseRenderedScalars();
