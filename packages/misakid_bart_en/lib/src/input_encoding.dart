// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'package:misakid/misaki.dart';

import 'config.dart';

/// Builds Python-compatible last-duplicate-wins grapheme IDs.
Map<int, int> buildBartGraphemeMap(BartConfig config) {
  final result = <int, int>{};
  for (var index = 0; index < config.graphemeCharacters.length; index++) {
    result[config.graphemeCharacters[index]] = index;
  }
  return Map<int, int>.unmodifiable(result);
}

/// Encodes one bounded scalar string as BOS, grapheme/unknown IDs, and EOS.
List<int> encodeBartEnglishInput({
  required String text,
  required Map<int, int> graphemeToToken,
  required int maximumCodePoints,
}) {
  final result = <int>[1];
  final units = text.codeUnits;
  var scalarCount = 0;
  for (var index = 0; index < units.length; index++) {
    final unit = units[index];
    int scalar;
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (index + 1 >= units.length ||
          units[index + 1] < 0xDC00 ||
          units[index + 1] > 0xDFFF) {
        throw const BackendFailureException(
          'BART English input contains an unpaired UTF-16 surrogate.',
        );
      }
      scalar = 0x10000 + ((unit - 0xD800) << 10) + (units[index + 1] - 0xDC00);
      index++;
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      throw const BackendFailureException(
        'BART English input contains an unpaired UTF-16 surrogate.',
      );
    } else {
      scalar = unit;
    }
    if (scalarCount == maximumCodePoints) {
      throw BackendFailureException(
        'BART English input exceeds the model limit of '
        '$maximumCodePoints Unicode scalars.',
      );
    }
    result.add(graphemeToToken[scalar] ?? 3);
    scalarCount++;
  }
  result.add(2);
  return List<int>.unmodifiable(result);
}
