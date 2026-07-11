import 'dart:typed_data';

import '../message_pack.dart';
import 'hash.dart';
import 'python_unicode.dart';

/// One token in a serialized spaCy tokenizer exception.
final class SpacySpecialCaseToken {
  /// Creates a validated exception token.
  const SpacySpecialCaseToken({required this.orth, this.norm});

  /// Exact text contributed by this token.
  final String orth;

  /// Explicit `NORM` override, or `null` for the lexeme norm.
  final String? norm;
}

/// Exact tokenizer rules and lexical norm table loaded from spaCy resources.
final class SpacyTokenizerConfig {
  SpacyTokenizerConfig._({
    required this.prefixPattern,
    required this.suffixPattern,
    required this.infixPattern,
    required this.tokenMatchPattern,
    required this.urlPattern,
    required Map<String, List<SpacySpecialCaseToken>> exceptions,
    required Map<int, String> lexemeNorms,
    required this.fasterHeuristics,
  }) : exceptions = Map<String, List<SpacySpecialCaseToken>>.unmodifiable(
         exceptions,
       ),
       lexemeNorms = Map<int, String>.unmodifiable(lexemeNorms);

  /// Decodes the original `tokenizer` and optional `vocab/lookups.bin` files.
  ///
  /// Neither input may contain MessagePack extensions, binaries, executable
  /// pickles, or trailing data. [decoder] applies bounds before allocation.
  factory SpacyTokenizerConfig.decode({
    required Uint8List tokenizerBytes,
    Uint8List? vocabLookupsBytes,
    BoundedMessagePackDecoder decoder = const BoundedMessagePackDecoder(),
  }) {
    final root = _stringKeyedMap(
      decoder.decode(tokenizerBytes),
      'tokenizer root',
    );
    const expectedKeys = <String>{
      'prefix_search',
      'suffix_search',
      'infix_finditer',
      'token_match',
      'url_match',
      'exceptions',
      'faster_heuristics',
    };
    if (root.keys.toSet().difference(expectedKeys).isNotEmpty ||
        expectedKeys.difference(root.keys.toSet()).isNotEmpty) {
      throw const FormatException(
        'spaCy tokenizer root has an unexpected field set.',
      );
    }
    final exceptions = _parseExceptions(root['exceptions']);
    final fasterHeuristics = root['faster_heuristics'];
    if (fasterHeuristics is! bool) {
      throw const FormatException(
        'spaCy tokenizer faster_heuristics must be a boolean.',
      );
    }
    final norms = vocabLookupsBytes == null
        ? const <int, String>{}
        : _parseLexemeNorms(decoder.decode(vocabLookupsBytes));
    return SpacyTokenizerConfig._(
      prefixPattern: _requiredPattern(root, 'prefix_search'),
      suffixPattern: _requiredPattern(root, 'suffix_search'),
      infixPattern: _requiredPattern(root, 'infix_finditer'),
      tokenMatchPattern: _optionalPattern(root, 'token_match'),
      urlPattern: _requiredPattern(root, 'url_match'),
      exceptions: exceptions,
      lexemeNorms: norms,
      fasterHeuristics: fasterHeuristics,
    );
  }

  /// Serialized Python prefix regular expression.
  final String prefixPattern;

  /// Serialized Python suffix regular expression.
  final String suffixPattern;

  /// Serialized Python infix regular expression.
  final String infixPattern;

  /// Optional serialized Python whole-token expression.
  final String? tokenMatchPattern;

  /// Serialized Python URL expression.
  final String urlPattern;

  /// Exact tokenizer exceptions keyed by concatenated `ORTH` text.
  final Map<String, List<SpacySpecialCaseToken>> exceptions;

  /// `lexeme_norm` values keyed by signed uint64 spaCy string IDs.
  final Map<int, String> lexemeNorms;

  /// Exact serialized `faster_heuristics` setting.
  final bool fasterHeuristics;

  /// Resolves a lexeme norm through the resource table, then Unicode lowercase.
  String lexemeNorm(String text) =>
      lexemeNorms[spacyStringId(text)] ??
      _spacyBaseNorms[text] ??
      python312Lower(text);
}

// Exact spaCy 3.8.4 `spacy.lang.norm_exceptions.BASE_NORMS`. Model-specific
// vocab lookups above intentionally take precedence over these base values.
const Map<String, String> _spacyBaseNorms = <String, String>{
  "'s": "'s",
  "'S": "'s",
  '’s': "'s",
  '’S': "'s",
  '’': "'",
  '‘': "'",
  '´': "'",
  '`': "'",
  '”': '"',
  '“': '"',
  "''": '"',
  '``': '"',
  '´´': '"',
  '„': '"',
  '»': '"',
  '«': '"',
  '‘‘': '"',
  '’’': '"',
  '？': '?',
  '！': '!',
  '，': ',',
  '；': ';',
  '：': ':',
  '。': '.',
  '।': '.',
  '…': '...',
  '—': '-',
  '–': '-',
  '--': '-',
  '---': '-',
  '——': '-',
  '€': r'$',
  '£': r'$',
  '¥': r'$',
  '฿': r'$',
  r'US$': r'$',
  r'C$': r'$',
  r'A$': r'$',
  '₺': r'$',
  '₹': r'$',
  '৳': r'$',
  '₩': r'$',
  r'Mex$': r'$',
  '₣': r'$',
  r'E£': r'$',
};

String _requiredPattern(Map<String, Object?> map, String field) {
  final value = map[field];
  if (value is! String || value.isEmpty) {
    throw FormatException('spaCy tokenizer $field must be a non-empty string.');
  }
  return value;
}

String? _optionalPattern(Map<String, Object?> map, String field) {
  final value = map[field];
  if (value != null && value is! String) {
    throw FormatException('spaCy tokenizer $field must be null or a string.');
  }
  return value as String?;
}

Map<String, List<SpacySpecialCaseToken>> _parseExceptions(Object? value) {
  final encoded = _stringKeyedMap(value, 'tokenizer exceptions');
  final result = <String, List<SpacySpecialCaseToken>>{};
  for (final entry in encoded.entries) {
    final rawTokens = entry.value;
    if (rawTokens is! List<Object?> || rawTokens.isEmpty) {
      throw FormatException(
        'spaCy exception `${entry.key}` must contain token maps.',
      );
    }
    final tokens = <SpacySpecialCaseToken>[];
    final reconstructed = StringBuffer();
    for (var index = 0; index < rawTokens.length; index++) {
      final attributes = _objectMap(
        rawTokens[index],
        'spaCy exception `${entry.key}` token $index',
      );
      if (!attributes.containsKey(65) ||
          attributes.keys.any((key) => key != 65 && key != 67)) {
        throw FormatException(
          'spaCy exception `${entry.key}` token $index has invalid attributes.',
        );
      }
      final orth = attributes[65];
      final norm = attributes[67];
      if (orth is! String || (norm != null && norm is! String)) {
        throw FormatException(
          'spaCy exception `${entry.key}` token $index has non-string text.',
        );
      }
      tokens.add(SpacySpecialCaseToken(orth: orth, norm: norm as String?));
      reconstructed.write(orth);
    }
    if (reconstructed.toString() != entry.key) {
      throw FormatException(
        'spaCy exception `${entry.key}` ORTH values do not reconstruct it.',
      );
    }
    result[entry.key] = List<SpacySpecialCaseToken>.unmodifiable(tokens);
  }
  return result;
}

Map<int, String> _parseLexemeNorms(Object? value) {
  final root = _stringKeyedMap(value, 'vocab lookups root');
  if (root.length != 1 || !root.containsKey('lexeme_norm')) {
    throw const FormatException(
      'spaCy vocab lookups must contain only lexeme_norm.',
    );
  }
  final encoded = _objectMap(root['lexeme_norm'], 'lexeme_norm');
  final result = <int, String>{};
  for (final entry in encoded.entries) {
    if (entry.key is! int || entry.value is! String) {
      throw const FormatException(
        'spaCy lexeme_norm entries must map uint64 IDs to strings.',
      );
    }
    result[entry.key! as int] = entry.value! as String;
  }
  return result;
}

Map<String, Object?> _stringKeyedMap(Object? value, String location) {
  final raw = _objectMap(value, location);
  final result = <String, Object?>{};
  for (final entry in raw.entries) {
    if (entry.key is! String) {
      throw FormatException('$location must use string keys.');
    }
    result[entry.key! as String] = entry.value;
  }
  return result;
}

Map<Object?, Object?> _objectMap(Object? value, String location) {
  if (value is! Map<Object?, Object?>) {
    throw FormatException('$location must be a map.');
  }
  return value;
}
