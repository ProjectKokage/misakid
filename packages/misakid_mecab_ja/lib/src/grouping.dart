// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'package:misakid/misaki_ja.dart';

import 'word_membership.dart';

/// Applies pinned Cutlet's longest membership match within each effective
/// character-type run.
///
/// This function is internal package API so the deterministic grouping stage
/// can be tested without loading native resources.
List<JapaneseCutletMorphologyWord> applyJapaneseCutletLongestGrouping(
  List<JapaneseCutletMorphologyWord> input,
  JapaneseCutletWordMembership membership,
) {
  final words = List<JapaneseCutletMorphologyWord>.of(input);
  var index = 0;
  while (index < words.length) {
    final type = _effectiveCharType(words[index]);
    var runEnd = index + 1;
    while (runEnd < words.length && _effectiveCharType(words[runEnd]) == type) {
      runEnd++;
    }

    var groupEnd = runEnd;
    var matched = false;
    while (groupEnd > index) {
      final surface = StringBuffer();
      for (var candidate = index; candidate < groupEnd; candidate++) {
        surface.write(words[candidate].surface);
      }
      if (membership.contains(surface.toString())) {
        matched = true;
        break;
      }
      groupEnd--;
    }
    if (!matched) {
      index++;
      continue;
    }
    for (var grouped = index; grouped < groupEnd - 1; grouped++) {
      final word = words[grouped];
      words[grouped] = JapaneseCutletMorphologyWord(
        surface: word.surface,
        hiragana: word.hiragana,
        charType: word.charType,
        isUnknown: word.isUnknown,
        joinWithNext: true,
      );
    }
    index = groupEnd;
  }
  return List<JapaneseCutletMorphologyWord>.unmodifiable(words);
}

int _effectiveCharType(JapaneseCutletMorphologyWord word) =>
    word.charType == 7 || !word.isUnknown ? 6 : word.charType;
