// Exact NFC/NFKC behavior for CPython 3.12.11's Unicode 15.0.0 database, plus
// the complete ten-scalar CCC delta needed for CPython 3.11/Unicode 14 NFC.
//
// The generated tables come from the pinned executable-reference runtime.
// This implementation follows canonical decomposition, ordering, and
// composition, including algorithmic Hangul handling. It deliberately does
// not consult the host platform's Unicode version.

import '../generated/python312_nfkc_data.dart';

/// Normalizes [text] exactly like `unicodedata.normalize('NFKC', text)` in
/// CPython 3.12.11 (Unicode 15.0.0).
String normalizePython312Nfkc(String text) =>
    _normalize(text, python312NfkdDecompositions);

/// Normalizes [text] exactly like `unicodedata.normalize('NFC', text)` in
/// CPython 3.12.11 (Unicode 15.0.0).
String normalizePython312Nfc(String text) =>
    _normalize(text, python312NfdDecompositions);

/// Normalizes [text] exactly like CPython 3.11's Unicode 14.0.0 NFC.
///
/// Unicode 14 and 15 have identical canonical decompositions and composition
/// pairs. Unicode 15 assigns a nonzero combining class to ten formerly
/// unassigned scalars; treating those ten as starters is the complete NFC
/// delta. This is used by the Python-3.11-pinned Vietnamese oracle.
String normalizePython311Nfc(String text) => _normalize(
  text,
  python312NfdDecompositions,
  zeroCombiningClass: _python311UnassignedCombiningMarks,
);

String _normalize(
  String text,
  Map<int, String> decompositions, {
  Set<int> zeroCombiningClass = const <int>{},
}) {
  if (text.isEmpty) {
    return text;
  }
  final decomposed = <int>[];
  for (final codePoint in _codePointsPreservingSurrogates(text)) {
    _appendDecomposition(
      decomposed,
      codePoint,
      decompositions,
      zeroCombiningClass,
    );
  }
  return String.fromCharCodes(_compose(decomposed, zeroCombiningClass));
}

void _appendDecomposition(
  List<int> output,
  int codePoint,
  Map<int, String> decompositions,
  Set<int> zeroCombiningClass,
) {
  if (codePoint >= _hangulSBase && codePoint < _hangulSBase + _hangulSCount) {
    final syllableIndex = codePoint - _hangulSBase;
    final leading = _hangulLBase + syllableIndex ~/ _hangulNCount;
    final vowel =
        _hangulVBase + (syllableIndex % _hangulNCount) ~/ _hangulTCount;
    final trailingIndex = syllableIndex % _hangulTCount;
    _appendCanonicallyOrdered(output, leading, zeroCombiningClass);
    _appendCanonicallyOrdered(output, vowel, zeroCombiningClass);
    if (trailingIndex != 0) {
      _appendCanonicallyOrdered(
        output,
        _hangulTBase + trailingIndex,
        zeroCombiningClass,
      );
    }
    return;
  }

  final mapping = decompositions[codePoint];
  if (mapping == null) {
    _appendCanonicallyOrdered(output, codePoint, zeroCombiningClass);
    return;
  }
  for (final mappedCodePoint in mapping.runes) {
    _appendCanonicallyOrdered(output, mappedCodePoint, zeroCombiningClass);
  }
}

void _appendCanonicallyOrdered(
  List<int> output,
  int codePoint,
  Set<int> zeroCombiningClass,
) {
  final combiningClass = _combiningClass(codePoint, zeroCombiningClass);
  output.add(codePoint);
  if (combiningClass == 0) {
    return;
  }

  var index = output.length - 1;
  while (index > 0) {
    final precedingClass = _combiningClass(
      output[index - 1],
      zeroCombiningClass,
    );
    if (precedingClass == 0 || precedingClass <= combiningClass) {
      break;
    }
    output[index] = output[index - 1];
    index--;
  }
  output[index] = codePoint;
}

List<int> _compose(List<int> decomposed, Set<int> zeroCombiningClass) {
  if (decomposed.isEmpty) {
    return const <int>[];
  }

  final output = <int>[decomposed.first];
  var starterPosition = 0;
  var starter = decomposed.first;
  var lastCombiningClass = _combiningClass(
    decomposed.first,
    zeroCombiningClass,
  );

  for (var index = 1; index < decomposed.length; index++) {
    final codePoint = decomposed[index];
    final combiningClass = _combiningClass(codePoint, zeroCombiningClass);
    final composite =
        lastCombiningClass < combiningClass || lastCombiningClass == 0
        ? _composePair(starter, codePoint)
        : null;
    if (composite != null) {
      output[starterPosition] = composite;
      starter = composite;
      continue;
    }

    if (combiningClass == 0) {
      starterPosition = output.length;
      starter = codePoint;
    }
    output.add(codePoint);
    lastCombiningClass = combiningClass;
  }
  return output;
}

int? _composePair(int starter, int codePoint) {
  final leadingIndex = starter - _hangulLBase;
  if (leadingIndex >= 0 && leadingIndex < _hangulLCount) {
    final vowelIndex = codePoint - _hangulVBase;
    if (vowelIndex >= 0 && vowelIndex < _hangulVCount) {
      return _hangulSBase +
          (leadingIndex * _hangulVCount + vowelIndex) * _hangulTCount;
    }
  }

  final syllableIndex = starter - _hangulSBase;
  if (syllableIndex >= 0 &&
      syllableIndex < _hangulSCount &&
      syllableIndex % _hangulTCount == 0) {
    final trailingIndex = codePoint - _hangulTBase;
    if (trailingIndex > 0 && trailingIndex < _hangulTCount) {
      return starter + trailingIndex;
    }
  }

  return python312CanonicalCompositions[(starter << 21) | codePoint];
}

int _combiningClass(int codePoint, Set<int> zeroCombiningClass) =>
    zeroCombiningClass.contains(codePoint)
    ? 0
    : python312CanonicalCombiningClasses[codePoint] ?? 0;

const Set<int> _python311UnassignedCombiningMarks = <int>{
  0x10efd,
  0x10efe,
  0x10eff,
  0x11f41,
  0x11f42,
  0x1e08f,
  0x1e4ec,
  0x1e4ed,
  0x1e4ee,
  0x1e4ef,
};

Iterable<int> _codePointsPreservingSurrogates(String text) sync* {
  final codeUnits = text.codeUnits;
  for (var index = 0; index < codeUnits.length; index++) {
    final first = codeUnits[index];
    if (first >= 0xd800 && first <= 0xdbff && index + 1 < codeUnits.length) {
      final second = codeUnits[index + 1];
      if (second >= 0xdc00 && second <= 0xdfff) {
        yield 0x10000 + ((first - 0xd800) << 10) + (second - 0xdc00);
        index++;
        continue;
      }
    }
    yield first;
  }
}

const int _hangulSBase = 0xac00;
const int _hangulLBase = 0x1100;
const int _hangulVBase = 0x1161;
const int _hangulTBase = 0x11a7;
const int _hangulLCount = 19;
const int _hangulVCount = 21;
const int _hangulTCount = 28;
const int _hangulNCount = _hangulVCount * _hangulTCount;
const int _hangulSCount = _hangulLCount * _hangulNCount;
