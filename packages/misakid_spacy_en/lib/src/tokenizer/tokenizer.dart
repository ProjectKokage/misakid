// Behavior-preserving Dart port of spaCy 3.8.4 tokenizer.pyx for the pinned
// en_core_web_sm 3.8.0 serialized rules.

import 'config.dart';
import 'python_unicode.dart';
import 'token.dart';

/// Pure-Dart tokenizer driven by an explicitly decoded spaCy resource.
final class SpacyTokenizer {
  /// Compiles [config]'s reviewed Python expressions for Dart's Unicode engine.
  factory SpacyTokenizer(SpacyTokenizerConfig config) {
    try {
      return SpacyTokenizer._(
        config: config,
        prefix: _compile(config.prefixPattern),
        suffix: _compile(config.suffixPattern),
        infix: _compile(config.infixPattern),
        tokenMatch: config.tokenMatchPattern == null
            ? null
            : _compile(config.tokenMatchPattern!),
        url: _compile(config.urlPattern, translatePythonShorthands: true),
      );
    } on FormatException {
      rethrow;
    } on ArgumentError catch (error) {
      throw FormatException('Unsupported spaCy tokenizer expression.', error);
    }
  }

  SpacyTokenizer._({
    required this.config,
    required RegExp prefix,
    required RegExp suffix,
    required RegExp infix,
    required RegExp? tokenMatch,
    required RegExp url,
  }) : _prefix = prefix,
       _suffix = suffix,
       _infix = infix,
       _tokenMatch = tokenMatch,
       _url = url {
    _phrasePatternsByFirst = _buildPhrasePatterns();
  }

  /// Immutable decoded configuration used by this tokenizer.
  final SpacyTokenizerConfig config;
  final RegExp _prefix;
  final RegExp _suffix;
  final RegExp _infix;
  final RegExp? _tokenMatch;
  final RegExp _url;
  late final Map<String, List<_PhrasePattern>> _phrasePatternsByFirst;

  /// Segments [text] with exact text, ASCII-space, norm, offset, and hash data.
  List<SpacyTokenizerToken> tokenize(String text) {
    if (text.length >= 1 << 30 && text.runes.length >= 1 << 30) {
      throw ArgumentError.value(text.length, 'text', 'spaCy input is too long');
    }
    final pieces = _tokenizeAffixes(text, withSpecialCases: true);
    _applyPhraseSpecialCases(pieces);
    final result = <SpacyTokenizerToken>[];
    var offset = 0;
    for (final piece in pieces) {
      final end = offset + piece.text.length;
      final whitespace = piece.hasTrailingSpace ? ' ' : '';
      result.add(
        SpacyTokenizerToken.create(
          text: piece.text,
          whitespace: whitespace,
          norm: piece.norm ?? config.lexemeNorm(piece.text),
          startOffsetUtf16: offset,
          endOffsetUtf16: end,
        ),
      );
      offset = end + whitespace.length;
    }
    if (offset != text.length) {
      throw StateError('spaCy tokenizer failed to preserve its input text.');
    }
    return List<SpacyTokenizerToken>.unmodifiable(result);
  }

  List<_TokenPiece> _tokenizeAffixes(
    String text, {
    required bool withSpecialCases,
  }) {
    final output = <_TokenPiece>[];
    if (text.isEmpty) {
      return output;
    }
    final scalars = text.runes.iterator;
    scalars.moveNext();
    var inWhitespace = isPython312WhitespaceScalar(scalars.current);
    var start = 0;
    var index = 0;
    do {
      final scalar = scalars.current;
      final width = scalar > 0xffff ? 2 : 1;
      final isWhitespace = isPython312WhitespaceScalar(scalar);
      if (isWhitespace != inWhitespace) {
        if (start < index) {
          _tokenizeSpan(
            output,
            text.substring(start, index),
            withSpecialCases: withSpecialCases,
          );
        }
        if (scalar == 0x20) {
          if (output.isEmpty) {
            throw StateError('spaCy ASCII-space transition lacks a token.');
          }
          output.last.hasTrailingSpace = true;
          start = index + width;
        } else {
          start = index;
        }
        inWhitespace = !inWhitespace;
      }
      index += width;
    } while (scalars.moveNext());

    if (start < index) {
      _tokenizeSpan(
        output,
        text.substring(start),
        withSpecialCases: withSpecialCases,
      );
      output.last.hasTrailingSpace =
          text.codeUnitAt(text.length - 1) == 0x20 && !inWhitespace;
    }
    return output;
  }

  void _tokenizeSpan(
    List<_TokenPiece> output,
    String original, {
    required bool withSpecialCases,
  }) {
    if (withSpecialCases) {
      final direct = config.exceptions[original];
      if (direct != null) {
        _appendSpecial(output, direct);
        return;
      }
    }

    final prefixes = <String>[];
    final suffixes = <String>[];
    var middle = original;
    var lastSize = -1;
    while (middle.isNotEmpty && middle.length != lastSize) {
      if (_matchesFromStart(_tokenMatch, middle)) {
        break;
      }
      if (withSpecialCases && config.exceptions.containsKey(middle)) {
        break;
      }
      lastSize = middle.length;
      final prefixLength = _matchLength(_prefix.firstMatch(middle));
      final prefix = prefixLength == 0 ? '' : middle.substring(0, prefixLength);
      final withoutPrefix = middle.substring(prefixLength);
      if (withoutPrefix.isNotEmpty &&
          withSpecialCases &&
          config.exceptions.containsKey(withoutPrefix)) {
        middle = withoutPrefix;
        prefixes.add(prefix);
        break;
      }

      final suffixLength = _matchLength(_suffix.firstMatch(withoutPrefix));
      final suffix = suffixLength == 0
          ? ''
          : middle.substring(middle.length - suffixLength);
      final withoutSuffix = suffixLength == 0
          ? middle
          : middle.substring(0, middle.length - suffixLength);
      if (withoutSuffix.isNotEmpty &&
          withSpecialCases &&
          config.exceptions.containsKey(withoutSuffix)) {
        middle = withoutSuffix;
        suffixes.add(suffix);
        break;
      }

      if (prefixLength != 0 &&
          suffixLength != 0 &&
          prefixLength + suffixLength <= middle.length) {
        middle = middle.substring(prefixLength, middle.length - suffixLength);
        prefixes.add(prefix);
        suffixes.add(suffix);
      } else if (prefixLength != 0) {
        middle = withoutPrefix;
        prefixes.add(prefix);
      } else if (suffixLength != 0) {
        middle = withoutSuffix;
        suffixes.add(suffix);
      }
    }

    for (final prefix in prefixes) {
      output.add(_TokenPiece(prefix));
    }
    if (middle.isNotEmpty) {
      final special = withSpecialCases ? config.exceptions[middle] : null;
      if (special != null) {
        _appendSpecial(output, special);
      } else if (_matchesFromStart(_tokenMatch, middle) ||
          _matchesFromStart(_url, middle)) {
        output.add(_TokenPiece(middle));
      } else {
        final matches = _infix.allMatches(middle).toList(growable: false);
        if (matches.isEmpty) {
          output.add(_TokenPiece(middle));
        } else {
          var start = 0;
          const startBeforeInfixes = 0;
          for (final match in matches) {
            if (match.start == startBeforeInfixes) {
              continue;
            }
            if (match.start != start) {
              output.add(_TokenPiece(middle.substring(start, match.start)));
            }
            if (match.start != match.end) {
              output.add(_TokenPiece(middle.substring(match.start, match.end)));
            }
            start = match.end;
          }
          if (start < middle.length) {
            output.add(_TokenPiece(middle.substring(start)));
          }
        }
      }
    }
    for (final suffix in suffixes.reversed) {
      output.add(_TokenPiece(suffix));
    }
  }

  void _appendSpecial(
    List<_TokenPiece> output,
    List<SpacySpecialCaseToken> special,
  ) {
    for (final token in special) {
      output.add(_TokenPiece(token.orth, norm: token.norm));
    }
  }

  Map<String, List<_PhrasePattern>> _buildPhrasePatterns() {
    final patterns = <String, List<_PhrasePattern>>{};
    for (final entry in config.exceptions.entries) {
      final qualifies =
          !config.fasterHeuristics ||
          _matchLength(_prefix.firstMatch(entry.key)) != 0 ||
          _infix.firstMatch(entry.key) != null ||
          _matchLength(_suffix.firstMatch(entry.key)) != 0 ||
          entry.key.contains(' ');
      if (!qualifies) {
        continue;
      }
      final pieces = _tokenizeAffixes(entry.key, withSpecialCases: false);
      if (pieces.isEmpty) {
        continue;
      }
      final pattern = _PhrasePattern(
        key: entry.key,
        texts: List<String>.unmodifiable(pieces.map((piece) => piece.text)),
      );
      patterns
          .putIfAbsent(pattern.texts.first, () => <_PhrasePattern>[])
          .add(pattern);
    }
    return Map<String, List<_PhrasePattern>>.unmodifiable(
      <String, List<_PhrasePattern>>{
        for (final entry in patterns.entries)
          entry.key: List<_PhrasePattern>.unmodifiable(entry.value),
      },
    );
  }

  void _applyPhraseSpecialCases(List<_TokenPiece> pieces) {
    if (pieces.isEmpty || _phrasePatternsByFirst.isEmpty) {
      return;
    }
    final matches = <_PhraseMatch>[];
    for (var start = 0; start < pieces.length; start++) {
      final candidates = _phrasePatternsByFirst[pieces[start].text];
      if (candidates == null) {
        continue;
      }
      for (final pattern in candidates) {
        final end = start + pattern.texts.length;
        if (end > pieces.length || pattern.texts.isEmpty) {
          continue;
        }
        var equal = true;
        final spanText = StringBuffer();
        for (var index = start; index < end; index++) {
          final relative = index - start;
          if (pieces[index].text != pattern.texts[relative]) {
            equal = false;
            break;
          }
          spanText.write(pieces[index].text);
          if (index + 1 < end && pieces[index].hasTrailingSpace) {
            spanText.write(' ');
          }
        }
        if (equal && spanText.toString() == pattern.key) {
          matches.add(_PhraseMatch(start: start, end: end, key: pattern.key));
        }
      }
    }
    matches.sort((left, right) {
      final length = (right.end - right.start).compareTo(left.end - left.start);
      return length != 0 ? length : left.start.compareTo(right.start);
    });
    final occupied = <int>{};
    final selected = <_PhraseMatch>[];
    for (final match in matches) {
      // tokenizer.pyx's `_filter_special_spans` records every examined span,
      // including a rejected overlap, before it considers the next span.
      if (occupied.contains(match.start) || occupied.contains(match.end - 1)) {
        for (var index = match.start; index < match.end; index++) {
          occupied.add(index);
        }
        continue;
      }
      selected.add(match);
      for (var index = match.start; index < match.end; index++) {
        occupied.add(index);
      }
    }
    selected.sort((left, right) => right.start.compareTo(left.start));
    for (final match in selected) {
      final finalSpace = pieces[match.end - 1].hasTrailingSpace;
      final replacement = <_TokenPiece>[];
      _appendSpecial(replacement, config.exceptions[match.key]!);
      replacement.last.hasTrailingSpace = finalSpace;
      pieces.replaceRange(match.start, match.end, replacement);
    }
  }
}

RegExp _compile(
  String pythonPattern, {
  bool translatePythonShorthands = false,
}) {
  var dartPattern = pythonPattern;
  if (dartPattern.startsWith('(?u)')) {
    dartPattern = dartPattern.substring(4);
  }
  dartPattern = dartPattern.replaceAllMapped(RegExp(r'\\U([0-9A-Fa-f]{8})'), (
    match,
  ) {
    final scalar = int.parse(match.group(1)!, radix: 16);
    if (scalar > 0x10ffff) {
      throw const FormatException('Python regex has an invalid scalar.');
    }
    return '\\u{${scalar.toRadixString(16)}}';
  });
  // Python permits identity escapes for ASCII punctuation. ECMAScript Unicode
  // mode rejects the two such escapes present in the pinned spaCy patterns.
  dartPattern = dartPattern.replaceAll(r'\!', '!').replaceAll(r"\'", "'");
  if (translatePythonShorthands) {
    // The pinned URL pattern has its sole `\w` inside this scheme class.
    dartPattern = dartPattern.replaceAll(
      r'[\w\+\-\.]',
      '[$python312WordRegExpClassContents\\+\\-\\.]',
    );
    dartPattern = dartPattern
        .replaceAll(r'\d', _pythonDecimalPattern)
        .replaceAll(r'\S', _pythonNonWhitespacePattern);
    if (dartPattern.contains(r'\w') ||
        dartPattern.contains(r'\d') ||
        dartPattern.contains(r'\S')) {
      throw const FormatException(
        'Untranslated Python Unicode shorthand in spaCy URL regex.',
      );
    }
  }
  return RegExp(dartPattern, unicode: true);
}

bool _matchesFromStart(RegExp? expression, String text) {
  if (expression == null) {
    return false;
  }
  final match = expression.firstMatch(text);
  return match != null && match.start == 0;
}

int _matchLength(RegExpMatch? match) =>
    match == null ? 0 : match.end - match.start;

final class _TokenPiece {
  _TokenPiece(this.text, {this.norm});

  final String text;
  final String? norm;
  var hasTrailingSpace = false;
}

final class _PhrasePattern {
  const _PhrasePattern({required this.key, required this.texts});

  final String key;
  final List<String> texts;
}

final class _PhraseMatch {
  const _PhraseMatch({
    required this.start,
    required this.end,
    required this.key,
  });

  final int start;
  final int end;
  final String key;
}

const String _pythonDecimalPattern =
    r'[\u0030-\u0039\u0660-\u0669\u06f0-\u06f9\u07c0-\u07c9\u0966-\u096f\u09e6-\u09ef\u0a66-\u0a6f\u0ae6-\u0aef\u0b66-\u0b6f\u0be6-\u0bef\u0c66-\u0c6f\u0ce6-\u0cef\u0d66-\u0d6f\u0de6-\u0def\u0e50-\u0e59\u0ed0-\u0ed9\u0f20-\u0f29\u1040-\u1049\u1090-\u1099\u17e0-\u17e9\u1810-\u1819\u1946-\u194f\u19d0-\u19d9\u1a80-\u1a89\u1a90-\u1a99\u1b50-\u1b59\u1bb0-\u1bb9\u1c40-\u1c49\u1c50-\u1c59\ua620-\ua629\ua8d0-\ua8d9\ua900-\ua909\ua9d0-\ua9d9\ua9f0-\ua9f9\uaa50-\uaa59\uabf0-\uabf9\uff10-\uff19\u{104a0}-\u{104a9}\u{10d30}-\u{10d39}\u{11066}-\u{1106f}\u{110f0}-\u{110f9}\u{11136}-\u{1113f}\u{111d0}-\u{111d9}\u{112f0}-\u{112f9}\u{11450}-\u{11459}\u{114d0}-\u{114d9}\u{11650}-\u{11659}\u{116c0}-\u{116c9}\u{11730}-\u{11739}\u{118e0}-\u{118e9}\u{11950}-\u{11959}\u{11c50}-\u{11c59}\u{11d50}-\u{11d59}\u{11da0}-\u{11da9}\u{11f50}-\u{11f59}\u{16a60}-\u{16a69}\u{16ac0}-\u{16ac9}\u{16b50}-\u{16b59}\u{1d7ce}-\u{1d7d7}\u{1d7d8}-\u{1d7e1}\u{1d7e2}-\u{1d7eb}\u{1d7ec}-\u{1d7f5}\u{1d7f6}-\u{1d7ff}\u{1e140}-\u{1e149}\u{1e2f0}-\u{1e2f9}\u{1e4f0}-\u{1e4f9}\u{1e950}-\u{1e959}\u{1fbf0}-\u{1fbf9}]';

const String _pythonNonWhitespacePattern =
    r'[^\u0009-\u000d\u001c-\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]';
