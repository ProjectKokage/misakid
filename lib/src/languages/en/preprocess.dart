// Dart adaptation of G2P.preprocess in hexgrad/misaki/misaki/en.py at
// fba1236595f2d2bf21d414ba6e57d25256afada3 (Misaki 0.9.4,
// Apache-2.0).
//
// Modifications: replaces Python's mixed feature dictionary with sealed typed
// controls, freezes all returned collections, and implements Python 3.12
// whitespace behavior explicitly over Unicode scalar values.

/// Base type for an inline English pronunciation or normalization control.
sealed class EnglishInlineControl {
  const EnglishInlineControl();
}

/// A signed integral or half-step stress control.
final class EnglishStressControl extends EnglishInlineControl {
  /// Creates a stress control with [stress].
  const EnglishStressControl(this.stress);

  /// Upstream stress value.
  ///
  /// Parsed controls are integers or one of `-0.5` and `0.5`.
  final num stress;
}

/// A slash-delimited custom pronunciation control.
final class EnglishPronunciationControl extends EnglishInlineControl {
  const EnglishPronunciationControl._(this.encoded);

  /// Exact normalized upstream feature, including its leading slash.
  ///
  /// All trailing slashes are removed except for the single discriminator.
  final String encoded;

  /// Pronunciation assigned by the downstream tokenizer.
  ///
  /// Upstream removes every leading slash when applying the feature.
  String get phonemes => _stripLeadingScalar(encoded, 0x2f);
}

/// A hash-delimited number-normalization flag control.
final class EnglishNumberFlagsControl extends EnglishInlineControl {
  const EnglishNumberFlagsControl._(this.encoded);

  /// Exact normalized upstream feature, including its leading hash.
  ///
  /// All trailing hashes are removed except for the single discriminator.
  final String encoded;

  /// Flags assigned by the downstream tokenizer.
  ///
  /// Upstream removes every leading hash when applying the feature.
  String get flags => _stripLeadingScalar(encoded, 0x23);
}

/// Immutable output of [EnglishInlinePreprocessor.preprocess].
final class EnglishPreprocessResult {
  /// Creates a result and defensively freezes its collections.
  EnglishPreprocessResult({
    required this.text,
    required List<String> sourceWords,
    required Map<int, EnglishInlineControl> controls,
  }) : sourceWords = List<String>.unmodifiable(sourceWords),
       controls = Map<int, EnglishInlineControl>.unmodifiable(controls);

  /// Input with leading Python whitespace removed and valid link syntax
  /// replaced by each link's visible source text.
  final String text;

  /// Source strings used later to align controls with backend tokens.
  ///
  /// Text outside controls is split using Python's whitespace rules. A link's
  /// visible source is retained as one entry even when it contains whitespace.
  final List<String> sourceWords;

  /// Inline controls keyed by index in [sourceWords].
  final Map<int, EnglishInlineControl> controls;
}

/// Pure parser for Misaki's English inline controls.
final class EnglishInlinePreprocessor {
  /// Creates a stateless English inline preprocessor.
  const EnglishInlinePreprocessor();

  /// Removes inline syntax from [input] and records each valid control.
  EnglishPreprocessResult preprocess(String input) {
    final text = _pythonLstrip(input);
    final result = StringBuffer();
    final sourceWords = <String>[];
    final controls = <int, EnglishInlineControl>{};
    var lastEnd = 0;

    for (final match in _linkPattern.allMatches(text)) {
      final preceding = text.substring(lastEnd, match.start);
      result.write(preceding);
      sourceWords.addAll(_pythonWhitespaceSplit(preceding));

      final source = match.group(1)!;
      final destination = match.group(2)!;
      final control = _parseControl(destination);
      if (control != null) {
        controls[sourceWords.length] = control;
      }
      result.write(source);
      sourceWords.add(source);
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      final trailing = text.substring(lastEnd);
      result.write(trailing);
      sourceWords.addAll(_pythonWhitespaceSplit(trailing));
    }

    return EnglishPreprocessResult(
      text: result.toString(),
      sourceWords: sourceWords,
      controls: controls,
    );
  }
}

final RegExp _linkPattern = RegExp(r'\[([^\]]+)\]\(([^\)]*)\)', unicode: true);

EnglishInlineControl? _parseControl(String value) {
  final signed = value.startsWith('-') || value.startsWith('+');
  final digits = value.substring(signed ? 1 : 0);
  if (_isAsciiDigits(digits)) {
    return EnglishStressControl(int.parse(value));
  }
  if (value == '0.5' || value == '+0.5') {
    return const EnglishStressControl(0.5);
  }
  if (value == '-0.5') {
    return const EnglishStressControl(-0.5);
  }
  if (_scalarLength(value) > 1 &&
      value.startsWith('/') &&
      value.endsWith('/')) {
    final body = _stripTrailingScalar(value.substring(1), 0x2f);
    return EnglishPronunciationControl._('/$body');
  }
  if (_scalarLength(value) > 1 &&
      value.startsWith('#') &&
      value.endsWith('#')) {
    final body = _stripTrailingScalar(value.substring(1), 0x23);
    return EnglishNumberFlagsControl._('#$body');
  }
  return null;
}

bool _isAsciiDigits(String value) {
  if (value.isEmpty) {
    return false;
  }
  return value.runes.every(
    (codePoint) => codePoint >= 0x30 && codePoint <= 0x39,
  );
}

String _pythonLstrip(String value) {
  final codePoints = value.runes.toList(growable: false);
  var first = 0;
  while (first < codePoints.length && _isPythonWhitespace(codePoints[first])) {
    first++;
  }
  return String.fromCharCodes(codePoints.skip(first));
}

List<String> _pythonWhitespaceSplit(String value) {
  final words = <String>[];
  final current = <int>[];
  for (final codePoint in value.runes) {
    if (_isPythonWhitespace(codePoint)) {
      if (current.isNotEmpty) {
        words.add(String.fromCharCodes(current));
        current.clear();
      }
    } else {
      current.add(codePoint);
    }
  }
  if (current.isNotEmpty) {
    words.add(String.fromCharCodes(current));
  }
  return words;
}

// CPython 3.12 str.isspace/lstrip/split uses bidirectional WS/B/S characters,
// Unicode Zs, and the historic ASCII information separators U+001C..U+001F.
bool _isPythonWhitespace(int codePoint) =>
    (codePoint >= 0x09 && codePoint <= 0x0d) ||
    (codePoint >= 0x1c && codePoint <= 0x20) ||
    codePoint == 0x85 ||
    codePoint == 0xa0 ||
    codePoint == 0x1680 ||
    (codePoint >= 0x2000 && codePoint <= 0x200a) ||
    codePoint == 0x2028 ||
    codePoint == 0x2029 ||
    codePoint == 0x202f ||
    codePoint == 0x205f ||
    codePoint == 0x3000;

int _scalarLength(String value) => value.runes.length;

String _stripTrailingScalar(String value, int scalar) {
  final codePoints = value.runes.toList(growable: false);
  var end = codePoints.length;
  while (end > 0 && codePoints[end - 1] == scalar) {
    end--;
  }
  return String.fromCharCodes(codePoints.take(end));
}

String _stripLeadingScalar(String value, int scalar) {
  final codePoints = value.runes.toList(growable: false);
  var start = 0;
  while (start < codePoints.length && codePoints[start] == scalar) {
    start++;
  }
  return String.fromCharCodes(codePoints.skip(start));
}
