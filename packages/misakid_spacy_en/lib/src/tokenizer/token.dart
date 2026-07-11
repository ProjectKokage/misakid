import 'hash.dart';
import 'python_unicode.dart';

/// Immutable tokenizer output and exact lexical features consumed by spaCy.
final class SpacyTokenizerToken {
  SpacyTokenizerToken._({
    required this.text,
    required this.whitespace,
    required this.norm,
    required this.startOffsetUtf16,
    required this.endOffsetUtf16,
  }) : orthId = spacyStringId(text),
       normId = spacyStringId(norm),
       prefixId = spacyStringId(_prefix(text)),
       suffixId = spacyStringId(_suffix(text)),
       shapeId = spacyStringId(_wordShape(text)),
       spacy = whitespace == ' ' ? 1 : 0,
       isSpace = _isPythonSpace(text) ? 1 : 0;

  /// Exact token text.
  final String text;

  /// spaCy's exact `Token.whitespace_`, either empty or one ASCII space.
  final String whitespace;

  /// Exact lexical or exception-provided `Token.norm_`.
  final String norm;

  /// Inclusive UTF-16 offset in the source Dart string.
  final int startOffsetUtf16;

  /// Exclusive UTF-16 offset in the source Dart string.
  final int endOffsetUtf16;

  /// spaCy `ORTH` string-store ID as signed uint64 bits.
  final int orthId;

  /// spaCy `NORM` string-store ID as signed uint64 bits.
  final int normId;

  /// spaCy `PREFIX` string-store ID as signed uint64 bits.
  final int prefixId;

  /// spaCy `SUFFIX` string-store ID as signed uint64 bits.
  final int suffixId;

  /// spaCy `SHAPE` string-store ID as signed uint64 bits.
  final int shapeId;

  /// Integer `SPACY` feature: 1 only when one ASCII space follows the token.
  final int spacy;

  /// Integer `IS_SPACE` feature using CPython 3.12 whitespace semantics.
  final int isSpace;

  /// Creates a fully derived token after segmentation has fixed its offsets.
  static SpacyTokenizerToken create({
    required String text,
    required String whitespace,
    required String norm,
    required int startOffsetUtf16,
    required int endOffsetUtf16,
  }) => SpacyTokenizerToken._(
    text: text,
    whitespace: whitespace,
    norm: norm,
    startOffsetUtf16: startOffsetUtf16,
    endOffsetUtf16: endOffsetUtf16,
  );
}

String _prefix(String text) {
  final iterator = text.runes.iterator;
  return iterator.moveNext() ? String.fromCharCode(iterator.current) : '';
}

String _suffix(String text) {
  final scalars = text.runes.toList(growable: false);
  final start = scalars.length > 3 ? scalars.length - 3 : 0;
  return String.fromCharCodes(scalars.skip(start));
}

String _wordShape(String text) {
  final scalars = text.runes.toList(growable: false);
  if (scalars.length >= 100) {
    return 'LONG';
  }
  final result = StringBuffer();
  String? last;
  var sequence = 0;
  for (final scalar in scalars) {
    final character = String.fromCharCode(scalar);
    final shape = isPython312AlphabeticScalar(scalar)
        ? (isPython312UppercaseScalar(scalar) ? 'X' : 'x')
        : isPython312DigitScalar(scalar)
        ? 'd'
        : character;
    if (shape == last) {
      sequence++;
    } else {
      sequence = 0;
      last = shape;
    }
    if (sequence < 4) {
      result.write(shape);
    }
  }
  return result.toString();
}

bool _isPythonSpace(String text) =>
    text.isNotEmpty && text.runes.every(isPython312WhitespaceScalar);
