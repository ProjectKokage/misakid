// Pure-Dart loader for licensed Vietnamese cleaner mappings copied from
// hexgrad/misaki fba1236595f2d2bf21d414ba6e57d25256afada3 and derived from
// Vinorm 577c9cd9bf499e074801b703a5fd1eaad8300d43 (MIT).

import 'dart:convert';

import '../../core/errors.dart';
import '../../generated/vietnamese_cleaner_json.dart';

/// Lazily decoded immutable Vietnamese cleaner dictionaries.
final class VietnameseCleanerData {
  VietnameseCleanerData._({
    required this.acronyms,
    required this.symbols,
    required this.teencode,
  });

  /// Extended acronym expansion mapping.
  final Map<String, String> acronyms;

  /// Currency and symbol-name mapping.
  final Map<String, String> symbols;

  /// Informal teencode normalization mapping.
  final Map<String, String> teencode;
}

/// Returns cached, checksum-generated cleaner mappings.
VietnameseCleanerData loadVietnameseCleanerData() => _data;

final VietnameseCleanerData _data = VietnameseCleanerData._(
  acronyms: _decode(vietnameseAcronymsJson, 'acronyms', 3098),
  symbols: _decode(vietnameseSymbolsJson, 'symbols', 62),
  teencode: _decode(vietnameseTeencodeJson, 'teencode', 482),
);

Map<String, String> _decode(String source, String name, int expectedEntries) {
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, Object?> || decoded.length != expectedEntries) {
    throw MalformedDataException(
      'Vietnamese $name data must contain exactly $expectedEntries entries.',
    );
  }
  final result = <String, String>{};
  for (final MapEntry(key: key, value: value) in decoded.entries) {
    if (key.isEmpty || value is! String) {
      throw MalformedDataException('Vietnamese $name data is malformed.');
    }
    result[key] = value;
  }
  return Map<String, String>.unmodifiable(result);
}
