// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0
//
// Behavior-preserving Dart transcription of spaCy 3.8.4
// `training/align.pyx:get_alignments`, restricted to the y-to-x flattened
// array observed by pinned Misaki's inline-control loop.

import 'tokenizer/python_unicode.dart';

/// Returns spaCy's flattened backend-token-to-source-token alignment data.
List<int> flattenedSpacyY2xAlignment(
  List<String> sourceTokens,
  List<String> backendTokens,
) {
  final charToSource = _characterToToken(sourceTokens);
  final charToBackend = _characterToToken(backendTokens);
  final sourceText = _pythonCodePoints(python312Lower(sourceTokens.join()));
  final backendText = _pythonCodePoints(python312Lower(backendTokens.join()));
  if (!_equalWithoutPythonWhitespace(sourceText, backendText) ||
      sourceText.length != charToSource.length ||
      backendText.length != charToBackend.length) {
    throw const FormatException(
      'spaCy alignment requires text that differs only in whitespace and case.',
    );
  }

  var sourceCharacter = 0;
  var backendCharacter = 0;
  var previousBackendToken = -1;
  final backendToSource = <Set<int>>[];
  while (sourceCharacter < sourceText.length &&
      backendCharacter < backendText.length) {
    final sourceToken = charToSource[sourceCharacter];
    final backendToken = charToBackend[backendCharacter];
    if (previousBackendToken != backendToken) {
      backendToSource.add(<int>{});
    }
    final sourceAtTokenStart =
        sourceCharacter == 0 || charToSource[sourceCharacter - 1] < sourceToken;
    final backendAtTokenStart =
        backendCharacter == 0 ||
        charToBackend[backendCharacter - 1] < backendToken;
    if (sourceTokens[sourceToken] == backendTokens[backendToken] &&
        sourceAtTokenStart &&
        backendAtTokenStart) {
      backendToSource.last.add(sourceToken);
      sourceCharacter += _pythonCodePoints(sourceTokens[sourceToken]).length;
      backendCharacter += _pythonCodePoints(backendTokens[backendToken]).length;
    } else if (sourceText[sourceCharacter] == backendText[backendCharacter]) {
      backendToSource.last.add(sourceToken);
      sourceCharacter++;
      backendCharacter++;
    } else if (isPython312WhitespaceScalar(sourceText[sourceCharacter])) {
      sourceCharacter++;
    } else if (isPython312WhitespaceScalar(backendText[backendCharacter])) {
      backendCharacter++;
    } else {
      throw const FormatException(
        'spaCy alignment requires text that differs only in whitespace and case.',
      );
    }
    previousBackendToken = backendToken;
  }

  final trailingBackendTokens = <int>{
    for (var index = backendCharacter; index < charToBackend.length; index++)
      charToBackend[index],
  };
  for (var index = 0; index < trailingBackendTokens.length; index++) {
    backendToSource.add(<int>{});
  }

  return List<int>.unmodifiable(<int>[
    for (final sourceIndices in backendToSource)
      ...sourceIndices.toList(growable: false)..sort(),
  ]);
}

List<int> _characterToToken(List<String> tokens) {
  final result = <int>[];
  for (var tokenIndex = 0; tokenIndex < tokens.length; tokenIndex++) {
    final length = _pythonCodePoints(python312Lower(tokens[tokenIndex])).length;
    for (var index = 0; index < length; index++) {
      result.add(tokenIndex);
    }
  }
  return result;
}

bool _equalWithoutPythonWhitespace(List<int> left, List<int> right) {
  final leftVisible = left
      .where((scalar) => !isPython312WhitespaceScalar(scalar))
      .toList(growable: false);
  final rightVisible = right
      .where((scalar) => !isPython312WhitespaceScalar(scalar))
      .toList(growable: false);
  if (leftVisible.length != rightVisible.length) {
    return false;
  }
  for (var index = 0; index < leftVisible.length; index++) {
    if (leftVisible[index] != rightVisible[index]) {
      return false;
    }
  }
  return true;
}

List<int> _pythonCodePoints(String text) {
  final result = <int>[];
  final units = text.codeUnits;
  for (var index = 0; index < units.length; index++) {
    final first = units[index];
    if (first >= 0xd800 && first <= 0xdbff && index + 1 < units.length) {
      final second = units[index + 1];
      if (second >= 0xdc00 && second <= 0xdfff) {
        result.add(0x10000 + ((first - 0xd800) << 10) + (second - 0xdc00));
        index++;
        continue;
      }
    }
    result.add(first);
  }
  return result;
}
