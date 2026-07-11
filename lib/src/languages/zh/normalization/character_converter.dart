// Copyright (c) 2020 PaddlePaddle Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Dart adaptation of pinned misaki/zh_normalization/char_convert.py.
// Modifications: loads deterministic generated scalar strings, validates their
// lengths, and builds immutable isolate-local maps without Python globals.

import '../../../core/errors.dart';
import '../../../generated/chinese_character_map.dart';

/// Narrow boundary for the pinned traditional-to-simplified conversion stage.
///
/// The contract is synchronous and platform-neutral. The built-in
/// [PinnedChineseCharacterConverter] uses only bundled generated scalar data.
abstract interface class ChineseCharacterConverter {
  /// Converts traditional characters in [text] to their pinned simplified
  /// forms while preserving all other Unicode scalars.
  String traditionalToSimplified(String text);
}

/// Built-in pure-Dart converter generated from pinned PaddleSpeech/Misaki data.
///
/// It performs no file access, platform discovery, or runtime download.
final class PinnedChineseCharacterConverter
    implements ChineseCharacterConverter {
  /// Creates a stateless converter.
  const PinnedChineseCharacterConverter();

  @override
  String traditionalToSimplified(String text) =>
      _convert(text, _characterMaps.traditionalToSimplified);

  /// Converts simplified characters to the pinned traditional representative.
  ///
  /// As upstream, duplicate source characters use their last mapping.
  String simplifiedToTraditional(String text) =>
      _convert(text, _characterMaps.simplifiedToTraditional);
}

String _convert(String text, Map<int, int> replacements) {
  final result = StringBuffer();
  for (final scalar in text.runes) {
    result.writeCharCode(replacements[scalar] ?? scalar);
  }
  return result.toString();
}

final _CharacterMaps _characterMaps = _buildCharacterMaps();

_CharacterMaps _buildCharacterMaps() {
  final simplified = simplifiedChineseCharacters.runes.toList(growable: false);
  final traditional = traditionalChineseCharacters.runes.toList(
    growable: false,
  );
  if (simplified.length != traditional.length) {
    throw const MalformedDataException(
      'Pinned Chinese character mapping arrays have unequal lengths.',
    );
  }
  final simplifiedToTraditional = <int, int>{};
  final traditionalToSimplified = <int, int>{};
  for (var index = 0; index < simplified.length; index++) {
    simplifiedToTraditional[simplified[index]] = traditional[index];
    traditionalToSimplified[traditional[index]] = simplified[index];
  }
  return _CharacterMaps(
    simplifiedToTraditional: Map<int, int>.unmodifiable(
      simplifiedToTraditional,
    ),
    traditionalToSimplified: Map<int, int>.unmodifiable(
      traditionalToSimplified,
    ),
  );
}

final class _CharacterMaps {
  const _CharacterMaps({
    required this.simplifiedToTraditional,
    required this.traditionalToSimplified,
  });

  final Map<int, int> simplifiedToTraditional;
  final Map<int, int> traditionalToSimplified;
}
