// Dart adaptation of G2P.resolve_tokens in hexgrad/misaki/misaki/en.py at
// fba1236595f2d2bf21d414ba6e57d25256afada3 (Misaki 0.9.4,
// Apache-2.0).
//
// Modifications: returns frozen immutable tokens, carries quality through typed
// English metadata, and performs character classification in Unicode mode.

import '../../core/errors.dart';
import '../../core/metadata.dart';
import '../../core/token.dart';
import 'phonology.dart';
import 'python_unicode.dart';

/// Resolves punctuation, spacing, and stress across one English token group.
List<MisakiToken> resolveEnglishTokens(List<MisakiToken> input) {
  if (input.isEmpty) {
    throw const InvalidConfigurationException(
      'At least one English token is required for resolution.',
    );
  }
  final tokens = List<MisakiToken>.of(input);

  final sourceText = StringBuffer();
  for (var index = 0; index < tokens.length - 1; index++) {
    sourceText
      ..write(tokens[index].text)
      ..write(tokens[index].whitespace);
  }
  sourceText.write(tokens.last.text);
  final combinedText = sourceText.toString();

  final characterKinds = <int>{};
  for (final codePoint in combinedText.runes) {
    final character = String.fromCharCode(codePoint);
    if (_subtokenJunk.contains(character)) {
      continue;
    }
    characterKinds.add(
      isPython312AlphabeticScalar(codePoint)
          ? 0
          : (_isAsciiDigit(codePoint) ? 1 : 2),
    );
  }
  final precededBySpace =
      combinedText.contains(' ') ||
      combinedText.contains('/') ||
      characterKinds.length > 1;

  for (var index = 0; index < tokens.length; index++) {
    final token = tokens[index];
    final metadata = _metadata(token, index);
    if (token.phonemes == null) {
      if (index == tokens.length - 1 &&
          _nonQuotePunctuation.contains(token.text)) {
        tokens[index] = _copyToken(
          token,
          phonemes: token.text,
          metadata: _copyMetadata(metadata, rating: 3),
        );
      } else if (token.text.runes.every(
        (codePoint) => _subtokenJunk.contains(String.fromCharCode(codePoint)),
      )) {
        tokens[index] = _copyToken(
          token,
          phonemes: '',
          metadata: _copyMetadata(metadata, rating: 3),
        );
      }
    } else if (index > 0) {
      tokens[index] = _copyToken(
        token,
        phonemes: token.phonemes!,
        metadata: _copyMetadata(metadata, precededBySpace: precededBySpace),
      );
    }
  }

  if (precededBySpace) {
    return List<MisakiToken>.unmodifiable(tokens);
  }

  final indices = <_StressIndex>[
    for (var index = 0; index < tokens.length; index++)
      if (tokens[index].phonemes != null && tokens[index].phonemes!.isNotEmpty)
        _StressIndex(
          hasPrimary: tokens[index].phonemes!.contains(englishPrimaryStress),
          weight: englishStressWeight(tokens[index].phonemes!),
          index: index,
        ),
  ];
  if (indices.length == 2 &&
      tokens[indices.first.index].text.runes.length == 1) {
    _applyStress(tokens, indices[1].index, -0.5);
    return List<MisakiToken>.unmodifiable(tokens);
  }

  final primaryCount = indices.where((entry) => entry.hasPrimary).length;
  if (indices.length < 2 || primaryCount <= (indices.length + 1) ~/ 2) {
    return List<MisakiToken>.unmodifiable(tokens);
  }

  indices.sort((left, right) {
    final primary = (left.hasPrimary ? 1 : 0).compareTo(
      right.hasPrimary ? 1 : 0,
    );
    if (primary != 0) {
      return primary;
    }
    final weight = left.weight.compareTo(right.weight);
    return weight != 0 ? weight : left.index.compareTo(right.index);
  });
  for (final entry in indices.take(indices.length ~/ 2)) {
    _applyStress(tokens, entry.index, -0.5);
  }
  return List<MisakiToken>.unmodifiable(tokens);
}

void _applyStress(List<MisakiToken> tokens, int index, num stress) {
  final token = tokens[index];
  tokens[index] = _copyToken(
    token,
    phonemes: applyEnglishStress(token.phonemes!, stress),
    metadata: _metadata(token, index),
  );
}

EnglishTokenMetadata _metadata(MisakiToken token, int index) {
  final metadata = token.metadata;
  if (metadata is! EnglishTokenMetadata) {
    throw MalformedDataException(
      'English token $index has ${metadata.runtimeType} metadata.',
    );
  }
  return metadata;
}

MisakiToken _copyToken(
  MisakiToken token, {
  required String phonemes,
  required EnglishTokenMetadata metadata,
}) => MisakiToken(
  text: token.text,
  tag: token.tag,
  whitespace: token.whitespace,
  phonemes: phonemes,
  startTimeSeconds: token.startTimeSeconds,
  endTimeSeconds: token.endTimeSeconds,
  metadata: metadata,
);

EnglishTokenMetadata _copyMetadata(
  EnglishTokenMetadata metadata, {
  bool? precededBySpace,
  int? rating,
}) => EnglishTokenMetadata(
  isHead: metadata.isHead,
  alias: metadata.alias,
  stress: metadata.stress,
  currency: metadata.currency,
  numberFlags: metadata.numberFlags,
  precededBySpace: precededBySpace ?? metadata.precededBySpace,
  rating: rating ?? metadata.rating,
);

const Set<String> _subtokenJunk = <String>{
  "'",
  ',',
  '-',
  '.',
  '_',
  '‘',
  '’',
  '/',
};
const Set<String> _nonQuotePunctuation = <String>{
  ';',
  ':',
  ',',
  '.',
  '!',
  '?',
  '—',
  '…',
};

bool _isAsciiDigit(int codePoint) => codePoint >= 0x30 && codePoint <= 0x39;

final class _StressIndex {
  const _StressIndex({
    required this.hasPrimary,
    required this.weight,
    required this.index,
  });

  final bool hasPrimary;
  final int weight;
  final int index;
}
