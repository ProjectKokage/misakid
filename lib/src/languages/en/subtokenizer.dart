// Dart adaptation of the `subtokenize` regex in hexgrad/misaki/misaki/en.py
// at fba1236595f2d2bf21d414ba6e57d25256afada3 (Misaki 0.9.4,
// Apache-2.0).
//
// Modifications: replaces the third-party Python `regex` expression with an
// ordered Unicode-scalar scanner. Dart's native Unicode property escapes were
// exhaustively compared with regex 2024.11.6; the small pinned additions below
// bridge the Unicode-version difference.

/// Splits one English backend token using the pinned alternation semantics.
///
/// Matches are returned in left-to-right order. Scalars that match no branch
/// (notably an isolated, non-boundary apostrophe) are skipped, as with Python
/// `regex.findall`. The returned list is unmodifiable.
List<String> subtokenizeEnglish(String word) {
  final scalars = word.runes.toList(growable: false);
  final result = <String>[];
  var position = 0;
  while (position < scalars.length) {
    final end = _matchAt(scalars, position);
    if (end == null) {
      position++;
      continue;
    }
    result.add(String.fromCharCodes(scalars.sublist(position, end)));
    position = end;
  }
  return List<String>.unmodifiable(result);
}

int? _matchAt(List<int> scalars, int start) {
  // ^['‘’]+
  if (start == 0 && _isApostrophe(scalars[start])) {
    return _apostropheRunEnd(scalars, start);
  }

  // \p{Lu}(?=\p{Lu}\p{Ll})
  if (start + 2 < scalars.length &&
      _isUppercase(scalars[start]) &&
      _isUppercase(scalars[start + 1]) &&
      _isLowercase(scalars[start + 2])) {
    return start + 1;
  }

  // (?:^-)?(?:\d?[,.]?\d)+
  final numericEnd = _numericEnd(scalars, start);
  if (numericEnd != null) {
    return numericEnd;
  }

  // [-_]+
  if (_isHyphenOrUnderscore(scalars[start])) {
    var end = start + 1;
    while (end < scalars.length && _isHyphenOrUnderscore(scalars[end])) {
      end++;
    }
    return end;
  }

  // ['‘’]{2,}
  if (_isApostrophe(scalars[start])) {
    final end = _apostropheRunEnd(scalars, start);
    if (end - start >= 2) {
      return end;
    }
  }

  // \p{L}*?(?:['‘’]\p{L})*?\p{Ll}(?=\p{Lu})
  final mixedCaseEnd = _mixedCaseBoundaryEnd(scalars, start);
  if (mixedCaseEnd != null) {
    return mixedCaseEnd;
  }

  // \p{L}+(?:['‘’]\p{L})*
  final wordEnd = _letterWordEnd(scalars, start);
  if (wordEnd != null) {
    return wordEnd;
  }

  // [^-_\p{L}'‘’\d]
  final scalar = scalars[start];
  if (!_isHyphenOrUnderscore(scalar) &&
      !_isLetter(scalar) &&
      !_isApostrophe(scalar) &&
      !_isDecimalDigit(scalar)) {
    return start + 1;
  }

  // ['‘’]+$
  if (_isApostrophe(scalar)) {
    final end = _apostropheRunEnd(scalars, start);
    if (end == scalars.length) {
      return end;
    }
  }
  return null;
}

int? _numericEnd(List<int> scalars, int start) {
  var position = start;
  if (start == 0 && scalars[position] == 0x2d) {
    position++;
  }
  if (position >= scalars.length) {
    return null;
  }

  if (_isNumericSeparator(scalars[position])) {
    if (position + 1 >= scalars.length ||
        !_isDecimalDigit(scalars[position + 1])) {
      return null;
    }
    position += 2;
  } else if (_isDecimalDigit(scalars[position])) {
    position++;
  } else {
    return null;
  }

  while (position < scalars.length) {
    if (_isDecimalDigit(scalars[position])) {
      position++;
      continue;
    }
    if (_isNumericSeparator(scalars[position]) &&
        position + 1 < scalars.length &&
        _isDecimalDigit(scalars[position + 1])) {
      position += 2;
      continue;
    }
    break;
  }
  return position;
}

int? _mixedCaseBoundaryEnd(List<int> scalars, int start) {
  var letterPrefixEnd = start;
  while (true) {
    var position = letterPrefixEnd;
    while (true) {
      if (position + 1 < scalars.length &&
          _isLowercase(scalars[position]) &&
          _isUppercase(scalars[position + 1])) {
        return position + 1;
      }
      if (position + 1 < scalars.length &&
          _isApostrophe(scalars[position]) &&
          _isLetter(scalars[position + 1])) {
        position += 2;
        continue;
      }
      break;
    }
    if (letterPrefixEnd < scalars.length &&
        _isLetter(scalars[letterPrefixEnd])) {
      letterPrefixEnd++;
      continue;
    }
    return null;
  }
}

int? _letterWordEnd(List<int> scalars, int start) {
  if (!_isLetter(scalars[start])) {
    return null;
  }
  var end = start + 1;
  while (end < scalars.length && _isLetter(scalars[end])) {
    end++;
  }
  while (end + 1 < scalars.length &&
      _isApostrophe(scalars[end]) &&
      _isLetter(scalars[end + 1])) {
    end += 2;
  }
  return end;
}

int _apostropheRunEnd(List<int> scalars, int start) {
  var end = start + 1;
  while (end < scalars.length && _isApostrophe(scalars[end])) {
    end++;
  }
  return end;
}

bool _isApostrophe(int scalar) =>
    scalar == 0x27 || scalar == 0x2018 || scalar == 0x2019;

bool _isHyphenOrUnderscore(int scalar) => scalar == 0x2d || scalar == 0x5f;

bool _isNumericSeparator(int scalar) => scalar == 0x2c || scalar == 0x2e;

bool _isUppercase(int scalar) =>
    _uppercasePattern.hasMatch(String.fromCharCode(scalar)) ||
    _containsRange(_uppercaseAdditions, scalar);

bool _isLowercase(int scalar) =>
    _lowercasePattern.hasMatch(String.fromCharCode(scalar)) ||
    _containsRange(_lowercaseAdditions, scalar);

bool _isLetter(int scalar) =>
    _letterPattern.hasMatch(String.fromCharCode(scalar)) ||
    _containsRange(_letterAdditions, scalar);

bool _isDecimalDigit(int scalar) =>
    _decimalDigitPattern.hasMatch(String.fromCharCode(scalar)) ||
    _containsRange(_decimalDigitAdditions, scalar);

final RegExp _uppercasePattern = RegExp(r'^\p{Lu}$', unicode: true);
final RegExp _lowercasePattern = RegExp(r'^\p{Ll}$', unicode: true);
final RegExp _letterPattern = RegExp(r'^\p{L}$', unicode: true);
final RegExp _decimalDigitPattern = RegExp(r'^\p{Nd}$', unicode: true);

bool _containsRange(List<int> ranges, int scalar) {
  for (var index = 0; index < ranges.length; index += 2) {
    if (scalar < ranges[index]) {
      return false;
    }
    if (scalar <= ranges[index + 1]) {
      return true;
    }
  }
  return false;
}

// Dart 3.11.5's native property sets are strict subsets of regex 2024.11.6.
// An exhaustive U+0000..U+10FFFF comparison found only these missing ranges.
// Pairs are inclusive and ordered; there are no native-only scalars.
// Verified counts (native/oracle): Lu 1831/1858, Ll 2233/2258,
// L 136726/141028, and Nd 680/760.
const List<int> _uppercaseAdditions = <int>[
  0x1c89,
  0x1c89,
  0xa7cb,
  0xa7cc,
  0xa7da,
  0xa7da,
  0xa7dc,
  0xa7dc,
  0x10d50,
  0x10d65,
];

const List<int> _lowercaseAdditions = <int>[
  0x1c8a,
  0x1c8a,
  0xa7cd,
  0xa7cd,
  0xa7db,
  0xa7db,
  0x10d70,
  0x10d85,
];

const List<int> _letterAdditions = <int>[
  0x1c89,
  0x1c8a,
  0xa7cb,
  0xa7cd,
  0xa7da,
  0xa7dc,
  0x105c0,
  0x105f3,
  0x10d4a,
  0x10d65,
  0x10d6f,
  0x10d85,
  0x10ec2,
  0x10ec4,
  0x11380,
  0x11389,
  0x1138b,
  0x1138b,
  0x1138e,
  0x1138e,
  0x11390,
  0x113b5,
  0x113b7,
  0x113b7,
  0x113d1,
  0x113d1,
  0x113d3,
  0x113d3,
  0x11bc0,
  0x11be0,
  0x13460,
  0x143fa,
  0x16100,
  0x1611d,
  0x16d40,
  0x16d6c,
  0x18cff,
  0x18cff,
  0x1e5d0,
  0x1e5ed,
  0x1e5f0,
  0x1e5f0,
];

const List<int> _decimalDigitAdditions = <int>[
  0x10d40,
  0x10d49,
  0x116d0,
  0x116e3,
  0x11bf0,
  0x11bf9,
  0x16130,
  0x16139,
  0x16d70,
  0x16d79,
  0x1ccf0,
  0x1ccf9,
  0x1e5f1,
  0x1e5fa,
];
