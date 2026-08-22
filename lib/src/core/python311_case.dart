// Exact CPython 3.11.15 / Unicode 14 text behavior captured as a candidate
// for the pinned 3.11.13 Vietnamese oracle.
//
// This is host-independent and preserves isolated UTF-16 surrogates. The
// tables and Final_Sigma properties capture the accepted CPython behavior.

import '../generated/python311_case_data.dart';

/// Lowercases [text] exactly like CPython 3.11.15's default `str.lower()`.
String python311Lower(String text) =>
    _mapCase(text, python311LowercaseMappings, lowercase: true);

/// Uppercases [text] exactly like CPython 3.11.15's default `str.upper()`.
String python311Upper(String text) =>
    _mapCase(text, python311UppercaseMappings, lowercase: false);

/// Whether [scalar] has Unicode 14's `Cased` property.
bool isPython311CasedScalar(int scalar) =>
    _containsRange(python311CasedRanges, scalar);

/// Whether [scalar] has Unicode 14's `Case_Ignorable` property.
bool isPython311CaseIgnorableScalar(int scalar) =>
    _containsRange(python311CaseIgnorableRanges, scalar);

/// Whether [scalar] satisfies CPython 3.11.15 `str.isspace()`.
bool isPython311WhitespaceScalar(int scalar) =>
    _containsRange(python311WhitespaceRanges, scalar);

/// Strips the exact CPython 3.11.15 whitespace set from both ends.
String stripPython311Whitespace(String text) {
  final codePoints = _codePointsPreservingSurrogates(text);
  var start = 0;
  while (start < codePoints.length &&
      isPython311WhitespaceScalar(codePoints[start])) {
    start++;
  }
  var end = codePoints.length;
  while (end > start && isPython311WhitespaceScalar(codePoints[end - 1])) {
    end--;
  }
  return start == 0 && end == codePoints.length
      ? text
      : String.fromCharCodes(codePoints.getRange(start, end));
}

/// Strips the exact CPython 3.11.15 whitespace set from the right edge.
String stripRightPython311Whitespace(String text) {
  final codePoints = _codePointsPreservingSurrogates(text);
  var end = codePoints.length;
  while (end > 0 && isPython311WhitespaceScalar(codePoints[end - 1])) {
    end--;
  }
  return end == codePoints.length
      ? text
      : String.fromCharCodes(codePoints.getRange(0, end));
}

String _mapCase(
  String text,
  Map<int, String> mappings, {
  required bool lowercase,
}) {
  if (text.isEmpty) {
    return text;
  }
  final source = _codePointsPreservingSurrogates(text);
  final output = StringBuffer();
  var changed = false;
  for (var index = 0; index < source.length; index++) {
    final codePoint = source[index];
    if (lowercase && codePoint == 0x03a3 && _isFinalSigma(source, index)) {
      output.writeCharCode(0x03c2);
      changed = true;
      continue;
    }
    final mapped = mappings[codePoint];
    if (mapped == null) {
      output.writeCharCode(codePoint);
    } else {
      output.write(mapped);
      changed = true;
    }
  }
  return changed ? output.toString() : text;
}

bool _isFinalSigma(List<int> source, int sigmaIndex) {
  var before = sigmaIndex - 1;
  while (before >= 0 && isPython311CaseIgnorableScalar(source[before])) {
    before--;
  }
  if (before < 0 || !isPython311CasedScalar(source[before])) {
    return false;
  }

  var after = sigmaIndex + 1;
  while (after < source.length &&
      isPython311CaseIgnorableScalar(source[after])) {
    after++;
  }
  return after == source.length || !isPython311CasedScalar(source[after]);
}

bool _containsRange(List<int> ranges, int scalar) {
  var low = 0;
  var high = ranges.length ~/ 2 - 1;
  while (low <= high) {
    final middle = (low + high) >> 1;
    final start = ranges[middle * 2];
    final end = ranges[middle * 2 + 1];
    if (scalar < start) {
      high = middle - 1;
    } else if (scalar > end) {
      low = middle + 1;
    } else {
      return true;
    }
  }
  return false;
}

List<int> _codePointsPreservingSurrogates(String text) {
  final result = <int>[];
  final codeUnits = text.codeUnits;
  for (var index = 0; index < codeUnits.length; index++) {
    final first = codeUnits[index];
    if (first >= 0xd800 && first <= 0xdbff && index + 1 < codeUnits.length) {
      final second = codeUnits[index + 1];
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
