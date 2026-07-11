// Pure-Dart loader for generated English lexicons from hexgrad/misaki
// fba1236595f2d2bf21d414ba6e57d25256afada3 (Misaki 0.9.4,
// Apache-2.0).
//
// Modifications: validates JSON into a sealed typed representation and
// implements upstream's grown-dictionary aliases on lookup, avoiding a second
// in-memory copy of roughly 400,000 entries.

import 'dart:convert';

import '../../core/errors.dart';
import '../../generated/english_lexicon_json.dart';
import 'morphology.dart';

/// One value in a pinned English pronunciation lexicon.
sealed class EnglishLexiconEntry {
  const EnglishLexiconEntry();
}

/// A pronunciation that does not depend on a part-of-speech tag.
final class EnglishSimpleLexiconEntry extends EnglishLexiconEntry {
  /// Creates a simple entry.
  const EnglishSimpleLexiconEntry(this.phonemes);

  /// Exact upstream phoneme string.
  final String phonemes;
}

/// A pronunciation selected by exact or parent part-of-speech tag.
final class EnglishContextualLexiconEntry extends EnglishLexiconEntry {
  /// Creates and freezes a contextual entry.
  EnglishContextualLexiconEntry(Map<String, String?> variants)
    : variants = Map<String, String?>.unmodifiable(variants);

  /// Exact upstream variants, including the required `DEFAULT` key.
  final Map<String, String?> variants;
}

/// Lazily decoded, immutable gold and silver tables for one dialect.
final class EnglishLexiconData {
  EnglishLexiconData._({
    required this.dialect,
    required Map<String, EnglishLexiconEntry> gold,
    required Map<String, EnglishLexiconEntry> silver,
  }) : goldEntries = Map<String, EnglishLexiconEntry>.unmodifiable(gold),
       silverEntries = Map<String, EnglishLexiconEntry>.unmodifiable(silver);

  /// Dialect represented by these tables.
  final EnglishDialect dialect;

  /// Canonical upstream gold entries, before lookup-only aliases.
  final Map<String, EnglishLexiconEntry> goldEntries;

  /// Canonical upstream silver entries, before lookup-only aliases.
  final Map<String, EnglishLexiconEntry> silverEntries;

  /// Looks up [word] using upstream `grow_dictionary` behavior.
  EnglishLexiconEntry? gold(String word) => _grownLookup(goldEntries, word);

  /// Looks up [word] in silver data using upstream aliases.
  EnglishLexiconEntry? silver(String word) => _grownLookup(silverEntries, word);

  /// Whether the grown gold dictionary contains [word].
  bool containsGold(String word) => gold(word) != null;

  /// Whether the grown silver dictionary contains [word].
  bool containsSilver(String word) => silver(word) != null;
}

/// Returns the cached pinned lexicons for [dialect].
///
/// JSON is decoded only when the selected dialect is requested for the first
/// time in an isolate.
EnglishLexiconData loadEnglishLexiconData(EnglishDialect dialect) =>
    switch (dialect) {
      EnglishDialect.american => _americanData,
      EnglishDialect.british => _britishData,
    };

final EnglishLexiconData _americanData = _decodeDialect(
  dialect: EnglishDialect.american,
  goldJson: usGoldLexiconJson,
  silverJson: usSilverLexiconJson,
  expectedGoldEntries: 90201,
  expectedSilverEntries: 93361,
);

final EnglishLexiconData _britishData = _decodeDialect(
  dialect: EnglishDialect.british,
  goldJson: gbGoldLexiconJson,
  silverJson: gbSilverLexiconJson,
  expectedGoldEntries: 87352,
  expectedSilverEntries: 109766,
);

EnglishLexiconData _decodeDialect({
  required EnglishDialect dialect,
  required String goldJson,
  required String silverJson,
  required int expectedGoldEntries,
  required int expectedSilverEntries,
}) => EnglishLexiconData._(
  dialect: dialect,
  gold: _decodeTable(
    goldJson,
    name: '${dialect.name} gold',
    expectedEntries: expectedGoldEntries,
    contextualValuesAllowed: true,
    allowedPhonemes: dialect == EnglishDialect.british
        ? _britishVocabulary
        : _americanVocabulary,
  ),
  silver: _decodeTable(
    silverJson,
    name: '${dialect.name} silver',
    expectedEntries: expectedSilverEntries,
    contextualValuesAllowed: false,
    allowedPhonemes: dialect == EnglishDialect.british
        ? _britishVocabulary
        : _americanVocabulary,
  ),
);

Map<String, EnglishLexiconEntry> _decodeTable(
  String source, {
  required String name,
  required int expectedEntries,
  required bool contextualValuesAllowed,
  Set<int>? allowedPhonemes,
}) {
  final Object? decoded = jsonDecode(source);
  if (decoded is! Map<Object?, Object?> || decoded.length != expectedEntries) {
    throw MalformedDataException(
      '$name lexicon must contain exactly $expectedEntries entries.',
    );
  }
  final result = <String, EnglishLexiconEntry>{};
  for (final entry in decoded.entries) {
    final key = entry.key;
    if (key is! String || !_isAscii(key)) {
      throw MalformedDataException('$name lexicon has a non-ASCII key.');
    }
    final value = entry.value;
    if (value is String) {
      _validatePhonemes(name, key, value, allowedPhonemes);
      result[key] = EnglishSimpleLexiconEntry(value);
      continue;
    }
    if (!contextualValuesAllowed || value is! Map<Object?, Object?>) {
      throw MalformedDataException('$name lexicon entry $key is malformed.');
    }
    final variants = <String, String?>{};
    for (final variant in value.entries) {
      final variantKey = variant.key;
      final variantValue = variant.value;
      if (variantKey is! String ||
          (variantValue != null && variantValue is! String)) {
        throw MalformedDataException(
          '$name contextual lexicon entry $key is malformed.',
        );
      }
      variants[variantKey] = variantValue as String?;
      if (variantValue is String) {
        _validatePhonemes(name, key, variantValue, allowedPhonemes);
      }
    }
    if (!variants.containsKey('DEFAULT')) {
      throw MalformedDataException(
        '$name contextual lexicon entry $key has no DEFAULT.',
      );
    }
    result[key] = EnglishContextualLexiconEntry(variants);
  }
  return result;
}

void _validatePhonemes(
  String name,
  String key,
  String value,
  Set<int>? allowed,
) {
  if (allowed == null) {
    return;
  }
  for (final scalar in value.runes) {
    if (!allowed.contains(scalar)) {
      throw MalformedDataException(
        '$name lexicon entry $key contains an invalid phoneme scalar.',
      );
    }
  }
}

EnglishLexiconEntry? _grownLookup(
  Map<String, EnglishLexiconEntry> entries,
  String word,
) {
  final exact = entries[word];
  if (exact != null || word.runes.length < 2 || !_isAscii(word)) {
    return exact;
  }
  final lower = word.toLowerCase();
  final capitalized = _asciiCapitalize(word);
  if (word == capitalized && word != lower) {
    final source = entries[lower];
    if (source != null && lower != _asciiCapitalize(lower)) {
      return source;
    }
  } else if (word == lower) {
    final sourceKey = _asciiCapitalize(word);
    return entries[sourceKey];
  }
  return null;
}

String _asciiCapitalize(String value) {
  if (value.isEmpty) {
    return value;
  }
  return '${value[0].toUpperCase()}${value.substring(1).toLowerCase()}';
}

bool _isAscii(String value) => value.codeUnits.every((unit) => unit <= 0x7f);

final Set<int> _americanVocabulary =
    'AIOWYbdfhijklmnpstuvwzæðŋɑɔəɛɜɡɪɹɾʃʊʌʒʤʧˈˌθᵊᵻʔ'.runes.toSet();
final Set<int> _britishVocabulary =
    'AIQWYabdfhijklmnpstuvwzðŋɑɒɔəɛɜɡɪɹʃʊʌʒʤʧˈˌːθᵊ'.runes.toSet();
