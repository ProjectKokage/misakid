// Dart adaptation of merge_tokens in hexgrad/misaki/misaki/en.py at
// fba1236595f2d2bf21d414ba6e57d25256afada3 (Misaki 0.9.4,
// Apache-2.0).
//
// Modifications: consumes immutable public tokens with typed English metadata,
// validates internal invariants, and handles Unicode scalars explicitly.

import '../../core/errors.dart';
import '../../core/metadata.dart';
import '../../core/python312_unicode.dart';
import '../../core/python_whitespace.dart';
import '../../core/token.dart';

/// Merges one non-empty English token group with pinned metadata semantics.
MisakiToken mergeEnglishTokens(
  List<MisakiToken> tokens, {
  String? unknownMarker,
}) {
  if (tokens.isEmpty) {
    throw const InvalidConfigurationException(
      'At least one English token is required for merging.',
    );
  }
  final metadata = <EnglishTokenMetadata>[
    for (var index = 0; index < tokens.length; index++)
      _englishMetadata(tokens[index], index),
  ];

  final stresses = metadata.map((item) => item.stress).whereType<num>().toSet();
  final currencies = metadata
      .map((item) => item.currency)
      .whereType<String>()
      .toSet();
  final ratings = <int?>{for (final item in metadata) item.rating};

  String? phonemes;
  if (unknownMarker != null) {
    final buffer = StringBuffer();
    int? lastPhonemeScalar;
    for (var index = 0; index < tokens.length; index++) {
      final token = tokens[index];
      if (metadata[index].precededBySpace &&
          lastPhonemeScalar != null &&
          !isPythonWhitespace(lastPhonemeScalar) &&
          token.phonemes != null &&
          token.phonemes!.isNotEmpty) {
        buffer.write(' ');
        lastPhonemeScalar = 0x20;
      }
      final rendered = token.phonemes ?? unknownMarker;
      buffer.write(rendered);
      if (rendered.isNotEmpty) {
        lastPhonemeScalar = _lastScalar(rendered);
      }
    }
    phonemes = buffer.toString();
  }

  final text = StringBuffer();
  for (var index = 0; index < tokens.length - 1; index++) {
    text
      ..write(tokens[index].text)
      ..write(tokens[index].whitespace);
  }
  text.write(tokens.last.text);

  var selectedTag = tokens.first.tag;
  var selectedTagWeight = _tagWeight(tokens.first.text);
  for (var index = 1; index < tokens.length; index++) {
    final weight = _tagWeight(tokens[index].text);
    if (weight > selectedTagWeight) {
      selectedTag = tokens[index].tag;
      selectedTagWeight = weight;
    }
  }

  final flagCodePoints = <int>{
    for (final item in metadata)
      for (final codePoint in item.numberFlags.runes) codePoint,
  }.toList(growable: false)..sort();
  final sortedCurrencies = currencies.toList(growable: false)..sort();
  final nonNullRatings = ratings.whereType<int>();

  return MisakiToken(
    text: text.toString(),
    tag: selectedTag,
    whitespace: tokens.last.whitespace,
    phonemes: phonemes,
    startTimeSeconds: tokens.first.startTimeSeconds,
    endTimeSeconds: tokens.last.endTimeSeconds,
    metadata: EnglishTokenMetadata(
      isHead: metadata.first.isHead,
      stress: stresses.length == 1 ? stresses.single : null,
      currency: sortedCurrencies.isEmpty ? null : sortedCurrencies.last,
      numberFlags: String.fromCharCodes(flagCodePoints),
      precededBySpace: metadata.first.precededBySpace,
      rating: ratings.contains(null) || nonNullRatings.isEmpty
          ? null
          : nonNullRatings.reduce((left, right) => left < right ? left : right),
    ),
  );
}

EnglishTokenMetadata _englishMetadata(MisakiToken token, int index) {
  final metadata = token.metadata;
  if (metadata is! EnglishTokenMetadata) {
    throw MalformedDataException(
      'English token $index has ${metadata.runtimeType} metadata.',
    );
  }
  return metadata;
}

int _tagWeight(String text) {
  var weight = 0;
  for (final codePoint in text.runes) {
    final character = String.fromCharCode(codePoint);
    weight += character == python312Lower(character) ? 1 : 2;
  }
  return weight;
}

int _lastScalar(String value) => value.runes.last;
