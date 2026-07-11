import '../../generated/vietnamese_phonology_data.dart';

/// Returns the frozen pinned Vietnamese `vi_syms` inventory.
///
/// Entries are longest-match phonology symbols and include the upstream tone
/// digits, punctuation, and space entries. Square-bracketed unknown text and
/// arbitrary inline custom pronunciations are intentionally outside it.
///
/// ```dart
/// final phones = vietnamesePhonemeInventory();
/// print(phones.contains('ŋ͡m')); // true
/// ```
Set<String> vietnamesePhonemeInventory() => _inventory;

final Set<String> _inventory = Set<String>.unmodifiable(vietnameseSymbols);
