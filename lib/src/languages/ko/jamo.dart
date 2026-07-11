// Dart adaptation of python-jamo 0.4.1 h2j/j2h behavior and the compose helper
// copied through hexgrad/misaki/misaki/g2pkc/utils.py at
// fba1236595f2d2bf21d414ba6e57d25256afada3 (Misaki 0.9.4).
//
// Both source chains are Apache-2.0. Modifications: operates on Unicode
// scalars in pure Dart and deterministically scans modern composition groups.

/// Decomposes modern precomposed Hangul syllables into conjoining Jamo.
///
/// Non-Hangul scalars, including compatibility Jamo, are preserved exactly.
String decomposeKoreanHangul(String input) {
  final output = StringBuffer();
  for (final scalar in input.runes) {
    if (scalar < _hangulBase || scalar > _hangulEnd) {
      output.writeCharCode(scalar);
      continue;
    }
    final offset = scalar - _hangulBase;
    final tail = offset % _tailCount;
    final vowel = (offset ~/ _tailCount) % _vowelCount;
    final lead = offset ~/ (_vowelCount * _tailCount);
    output
      ..writeCharCode(_leadBase + lead)
      ..writeCharCode(_vowelBase + vowel);
    if (tail != 0) {
      output.writeCharCode(_tailBase + tail);
    }
  }
  return output.toString();
}

/// Composes modern conjoining Jamo using the pinned g2pkc helper semantics.
///
/// A standalone modern vowel first receives the silent onset `ᄋ`, matching
/// upstream's non-overlapping regular-expression substitution. Consecutive
/// standalone vowels therefore receive an onset only at alternating
/// positions. Compatibility and archaic Jamo are otherwise preserved.
String composeKoreanJamo(String input) {
  final source = input.runes.toList(growable: false);
  final expanded = <int>[];
  var sourceIndex = 0;
  while (sourceIndex < source.length) {
    final scalar = source[sourceIndex];
    if (sourceIndex == 0 && _isModernVowel(scalar)) {
      expanded
        ..add(_silentLead)
        ..add(scalar);
      sourceIndex++;
      continue;
    }
    if (!_isModernLead(scalar) &&
        sourceIndex + 1 < source.length &&
        _isModernVowel(source[sourceIndex + 1])) {
      expanded
        ..add(scalar)
        ..add(_silentLead)
        ..add(source[sourceIndex + 1]);
      sourceIndex += 2;
      continue;
    }
    expanded.add(scalar);
    sourceIndex++;
  }

  final output = StringBuffer();
  var index = 0;
  while (index < expanded.length) {
    final lead = expanded[index];
    if (_isModernLead(lead) &&
        index + 1 < expanded.length &&
        _isModernVowel(expanded[index + 1])) {
      final vowel = expanded[index + 1];
      var tail = 0;
      var consumed = 2;
      if (index + 2 < expanded.length && _isModernTail(expanded[index + 2])) {
        tail = expanded[index + 2] - _tailBase;
        consumed = 3;
      }
      final syllable =
          _hangulBase +
          (lead - _leadBase) * _vowelCount * _tailCount +
          (vowel - _vowelBase) * _tailCount +
          tail;
      output.writeCharCode(syllable);
      index += consumed;
      continue;
    }
    output.writeCharCode(lead);
    index++;
  }
  return output.toString();
}

bool _isModernLead(int scalar) =>
    scalar >= _leadBase && scalar < _leadBase + _leadCount;

bool _isModernVowel(int scalar) =>
    scalar >= _vowelBase && scalar < _vowelBase + _vowelCount;

bool _isModernTail(int scalar) =>
    scalar > _tailBase && scalar < _tailBase + _tailCount;

const int _hangulBase = 0xAC00;
const int _hangulEnd = 0xD7A3;
const int _leadBase = 0x1100;
const int _vowelBase = 0x1161;
const int _tailBase = 0x11A7;
const int _silentLead = 0x110B;
const int _leadCount = 19;
const int _vowelCount = 21;
const int _tailCount = 28;
