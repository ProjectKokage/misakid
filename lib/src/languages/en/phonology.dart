// Dart adaptation of the pure stress helpers in hexgrad/misaki/misaki/en.py
// at fba1236595f2d2bf21d414ba6e57d25256afada3 (Misaki 0.9.4,
// Apache-2.0).
//
// Modifications: operate explicitly on Unicode scalar values and surface a
// typed malformed-data failure for the upstream dangling-stress invariant.

import '../../core/errors.dart';

/// Primary lexical stress marker used by the pinned English renderer.
const String englishPrimaryStress = 'ˈ';

/// Secondary lexical stress marker used by the pinned English renderer.
const String englishSecondaryStress = 'ˌ';

const Set<String> _diphthongs = <String>{
  'A',
  'I',
  'O',
  'Q',
  'W',
  'Y',
  'ʤ',
  'ʧ',
};

const Set<String> _vowels = <String>{
  'A',
  'I',
  'O',
  'Q',
  'W',
  'Y',
  'a',
  'i',
  'u',
  'æ',
  'ɑ',
  'ɒ',
  'ɔ',
  'ə',
  'ɛ',
  'ɜ',
  'ɪ',
  'ʊ',
  'ʌ',
  'ᵻ',
};

/// Returns the upstream stress-comparison weight for [phonemes].
int englishStressWeight(String phonemes) {
  var weight = 0;
  for (final rune in phonemes.runes) {
    weight += _diphthongs.contains(String.fromCharCode(rune)) ? 2 : 1;
  }
  return weight;
}

/// Applies pinned Misaki's numeric stress control to [phonemes].
String applyEnglishStress(String phonemes, num? stress) {
  if (stress == null) {
    return phonemes;
  }
  if (stress < -1) {
    return phonemes
        .replaceAll(englishPrimaryStress, '')
        .replaceAll(englishSecondaryStress, '');
  }
  if (stress == -1 ||
      ((stress == 0 || stress == -0.5) &&
          phonemes.contains(englishPrimaryStress))) {
    return phonemes
        .replaceAll(englishSecondaryStress, '')
        .replaceAll(englishPrimaryStress, englishSecondaryStress);
  }

  final hasStress =
      phonemes.contains(englishPrimaryStress) ||
      phonemes.contains(englishSecondaryStress);
  if ((stress == 0 || stress == 0.5 || stress == 1) && !hasStress) {
    if (!_containsVowel(phonemes)) {
      return phonemes;
    }
    return _restress('$englishSecondaryStress$phonemes');
  }
  if (stress >= 1 &&
      !phonemes.contains(englishPrimaryStress) &&
      phonemes.contains(englishSecondaryStress)) {
    return phonemes.replaceAll(englishSecondaryStress, englishPrimaryStress);
  }
  if (stress > 1 && !hasStress) {
    if (!_containsVowel(phonemes)) {
      return phonemes;
    }
    return _restress('$englishPrimaryStress$phonemes');
  }
  return phonemes;
}

bool _containsVowel(String phonemes) =>
    phonemes.runes.any((rune) => _vowels.contains(String.fromCharCode(rune)));

String _restress(String phonemes) {
  final characters = phonemes.runes
      .map<String>(String.fromCharCode)
      .toList(growable: false);
  final positioned = <_PositionedPhoneme>[
    for (var index = 0; index < characters.length; index++)
      _PositionedPhoneme(index.toDouble(), characters[index]),
  ];
  for (var index = 0; index < characters.length; index++) {
    final character = characters[index];
    if (character != englishPrimaryStress &&
        character != englishSecondaryStress) {
      continue;
    }
    int? vowelIndex;
    for (var future = index; future < characters.length; future++) {
      if (_vowels.contains(characters[future])) {
        vowelIndex = future;
        break;
      }
    }
    if (vowelIndex == null) {
      throw const MalformedDataException(
        'An English stress mark must be followed by a vowel.',
      );
    }
    positioned[index] = _PositionedPhoneme(vowelIndex - 0.5, character);
  }
  positioned.sort((left, right) {
    final position = left.position.compareTo(right.position);
    return position != 0 ? position : left.phoneme.compareTo(right.phoneme);
  });
  return positioned.map((entry) => entry.phoneme).join();
}

final class _PositionedPhoneme {
  const _PositionedPhoneme(this.position, this.phoneme);

  final double position;
  final String phoneme;
}
