// Dart adaptation of G2P.fold_left and G2P.retokenize in
// hexgrad/misaki/misaki/en.py at
// fba1236595f2d2bf21d414ba6e57d25256afada3 (Misaki 0.9.4,
// Apache-2.0).
//
// Modifications: represents Python's token-or-list union with immutable sealed
// groups and rebuilds public immutable tokens instead of mutating dataclasses.

import '../../core/constants.dart';
import '../../core/errors.dart';
import '../../core/metadata.dart';
import '../../core/python312_unicode.dart';
import '../../core/token.dart';
import 'subtokenizer.dart';
import 'token_merge.dart';

/// One immutable item produced by [retokenizeEnglishTokens].
sealed class EnglishRetokenizedItem {
  const EnglishRetokenizedItem();
}

/// A token that is resolved independently.
final class EnglishRetokenizedToken extends EnglishRetokenizedItem {
  /// Creates a standalone item for [token].
  const EnglishRetokenizedToken(this.token);

  /// Token to resolve.
  final MisakiToken token;
}

/// A contiguous token group searched from right to left.
final class EnglishRetokenizedGroup extends EnglishRetokenizedItem {
  /// Creates a group and defensively freezes [tokens].
  EnglishRetokenizedGroup(List<MisakiToken> tokens)
    : tokens = List<MisakiToken>.unmodifiable(tokens) {
    if (tokens.length < 2) {
      throw const InvalidConfigurationException(
        'An English retokenized group must contain at least two tokens.',
      );
    }
  }

  /// Tokens in exact source order.
  final List<MisakiToken> tokens;
}

/// Folds tokenizer continuation heads into their preceding token.
List<MisakiToken> foldEnglishTokenHeads(
  List<MisakiToken> input, {
  String unknownMarker = defaultUnknownMarker,
}) {
  final result = <MisakiToken>[];
  for (var index = 0; index < input.length; index++) {
    final token = input[index];
    final metadata = _metadata(token, index);
    if (result.isNotEmpty && !metadata.isHead) {
      final previous = result.removeLast();
      result.add(
        mergeEnglishTokens(<MisakiToken>[
          previous,
          token,
        ], unknownMarker: unknownMarker),
      );
    } else {
      result.add(token);
    }
  }
  return List<MisakiToken>.unmodifiable(result);
}

/// Applies the pinned English subtoken, currency, punctuation, and grouping
/// rules to [input].
List<EnglishRetokenizedItem> retokenizeEnglishTokens(List<MisakiToken> input) {
  final words = <_ItemBuilder>[];
  String? currency;

  for (var tokenIndex = 0; tokenIndex < input.length; tokenIndex++) {
    final token = input[tokenIndex];
    final tokenMetadata = _metadata(token, tokenIndex);
    final subtokens = <MisakiToken>[];
    if (tokenMetadata.alias == null && token.phonemes == null) {
      final texts = subtokenizeEnglish(token.text);
      if (texts.isEmpty) {
        throw MalformedDataException(
          'English token $tokenIndex produced no subtokens.',
        );
      }
      for (final text in texts) {
        subtokens.add(
          MisakiToken(
            text: text,
            tag: token.tag,
            whitespace: '',
            startTimeSeconds: token.startTimeSeconds,
            endTimeSeconds: token.endTimeSeconds,
            metadata: EnglishTokenMetadata(
              isHead: true,
              stress: tokenMetadata.stress,
              numberFlags: tokenMetadata.numberFlags,
            ),
          ),
        );
      }
    } else {
      subtokens.add(token);
    }
    subtokens[subtokens.length - 1] = _withWhitespace(
      subtokens.last,
      token.whitespace,
    );

    for (
      var subtokenIndex = 0;
      subtokenIndex < subtokens.length;
      subtokenIndex++
    ) {
      var current = subtokens[subtokenIndex];
      var metadata = _metadata(current, subtokenIndex);
      if (metadata.alias != null || current.phonemes != null) {
        // Explicit controls are already resolved at the tokenizer boundary.
      } else if (current.tag == r'$' && _currencies.contains(current.text)) {
        currency = current.text;
        current = _withPhonemes(current, '', rating: 4);
      } else if (current.tag == ':' &&
          (current.text == '-' || current.text == '–')) {
        current = _withPhonemes(current, '—', rating: 3);
      } else if (_punctuationTags.contains(current.tag) &&
          !_allAsciiLettersAfterLowercasing(current.text, tokenIndex)) {
        final mapped = _punctuationTagPhonemes[current.tag];
        final phonemes =
            mapped ??
            String.fromCharCodes(
              current.text.runes.where(
                (codePoint) =>
                    _punctuation.contains(String.fromCharCode(codePoint)),
              ),
            );
        current = _withPhonemes(current, phonemes, rating: 4);
      } else if (currency != null) {
        if (current.tag != 'CD') {
          currency = null;
        } else if (subtokenIndex + 1 == subtokens.length &&
            (tokenIndex + 1 == input.length ||
                input[tokenIndex + 1].tag != 'CD')) {
          current = _withCurrency(current, currency);
        }
      } else if (0 < subtokenIndex &&
          subtokenIndex < subtokens.length - 1 &&
          current.text == '2' &&
          _isAlphabeticPair(
            subtokens[subtokenIndex - 1].text.runes.last,
            subtokens[subtokenIndex + 1].text.runes.first,
          )) {
        current = _withAlias(current, 'to');
      }

      metadata = _metadata(current, subtokenIndex);
      if (metadata.alias != null || current.phonemes != null) {
        words.add(_ItemBuilder(isGroup: false, tokens: <MisakiToken>[current]));
      } else if (words.isNotEmpty &&
          words.last.isGroup &&
          words.last.tokens.last.whitespace.isEmpty) {
        words.last.tokens.add(_withIsHead(current, false));
      } else {
        words.add(
          _ItemBuilder(
            isGroup: current.whitespace.isEmpty,
            tokens: <MisakiToken>[current],
          ),
        );
      }
    }
  }

  return List<EnglishRetokenizedItem>.unmodifiable(<EnglishRetokenizedItem>[
    for (final word in words)
      if (word.isGroup && word.tokens.length > 1)
        EnglishRetokenizedGroup(word.tokens)
      else
        EnglishRetokenizedToken(word.tokens.single),
  ]);
}

final class _ItemBuilder {
  _ItemBuilder({required this.isGroup, required this.tokens});

  final bool isGroup;
  final List<MisakiToken> tokens;
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

MisakiToken _withWhitespace(MisakiToken token, String whitespace) =>
    MisakiToken(
      text: token.text,
      tag: token.tag,
      whitespace: whitespace,
      phonemes: token.phonemes,
      startTimeSeconds: token.startTimeSeconds,
      endTimeSeconds: token.endTimeSeconds,
      metadata: token.metadata,
    );

MisakiToken _withPhonemes(
  MisakiToken token,
  String phonemes, {
  required int rating,
}) {
  final metadata = _metadata(token, 0);
  return _copyToken(
    token,
    phonemes: phonemes,
    metadata: _copyMetadata(metadata, rating: rating),
  );
}

MisakiToken _withCurrency(MisakiToken token, String currency) {
  final metadata = _metadata(token, 0);
  return _copyToken(
    token,
    phonemes: token.phonemes,
    metadata: _copyMetadata(metadata, currency: currency),
  );
}

MisakiToken _withAlias(MisakiToken token, String alias) {
  final metadata = _metadata(token, 0);
  return _copyToken(
    token,
    phonemes: token.phonemes,
    metadata: _copyMetadata(metadata, alias: alias),
  );
}

MisakiToken _withIsHead(MisakiToken token, bool isHead) {
  final metadata = _metadata(token, 0);
  return _copyToken(
    token,
    phonemes: token.phonemes,
    metadata: _copyMetadata(metadata, isHead: isHead),
  );
}

MisakiToken _copyToken(
  MisakiToken token, {
  required String? phonemes,
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
  bool? isHead,
  String? alias,
  String? currency,
  int? rating,
}) => EnglishTokenMetadata(
  isHead: isHead ?? metadata.isHead,
  alias: alias ?? metadata.alias,
  stress: metadata.stress,
  currency: currency ?? metadata.currency,
  numberFlags: metadata.numberFlags,
  precededBySpace: metadata.precededBySpace,
  rating: rating ?? metadata.rating,
);

bool _allAsciiLettersAfterLowercasing(String text, int tokenIndex) {
  for (final codePoint in text.runes) {
    final lower = python312Lower(String.fromCharCode(codePoint));
    final lowerScalars = lower.runes.toList(growable: false);
    if (lowerScalars.length != 1) {
      throw MalformedDataException(
        'English punctuation token $tokenIndex has a multi-scalar lowercase mapping.',
      );
    }
    if (lowerScalars.single < 0x61 || lowerScalars.single > 0x7a) {
      return false;
    }
  }
  return true;
}

bool _isAlphabeticPair(int left, int right) =>
    isPython312AlphabeticScalar(left) && isPython312AlphabeticScalar(right);

const Set<String> _currencies = <String>{r'$', '£', '€'};
const Set<String> _punctuationTags = <String>{
  '.',
  ',',
  '-LRB-',
  '-RRB-',
  '``',
  '""',
  "''",
  ':',
  r'$',
  '#',
  'NFP',
};
const Map<String, String> _punctuationTagPhonemes = <String, String>{
  '-LRB-': '(',
  '-RRB-': ')',
  '``': '“',
  '""': '”',
  "''": '”',
};
const Set<String> _punctuation = <String>{
  ';',
  ':',
  ',',
  '.',
  '!',
  '?',
  '—',
  '…',
  '"',
  '“',
  '”',
};
