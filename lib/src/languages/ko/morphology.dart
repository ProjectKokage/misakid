// Dart adaptation of annotate in hexgrad/misaki/misaki/g2pkc/utils.py at
// fba1236595f2d2bf21d414ba6e57d25256afada3.
// Copied/adapted through 5Hyeons/StyleTTS2 from Kyubyong/g2pK under
// Apache-2.0. Modifications: consumes typed injected POS results and indexes
// source text by Unicode scalar, matching Python strings rather than UTF-16.

import 'backends.dart';
import 'jamo.dart';

/// Adds the four transient g2pkc morphology markers to [input].
///
/// If analyzer surfaces do not reproduce the input after upstream's exact
/// space/newline removal, the original input is returned unchanged.
String annotateKoreanMorphology(
  String input,
  List<KoreanMorphologyToken> tokens,
) {
  final joined = tokens.map((token) => token.surface).join();
  if (input.replaceAll(_spaceOrNewline, '') != joined) {
    return input;
  }

  final source = <String>[
    for (final scalar in input.runes) String.fromCharCode(scalar),
  ];
  final blanks = <(int, String)>[
    for (var index = 0; index < source.length; index++)
      if (source[index] == ' ' || source[index] == '\n') (index, source[index]),
  ];
  final tagSequence = <String>[];
  for (final token in tokens) {
    final scalarLength = token.surface.runes.length;
    if (scalarLength == 0) {
      continue;
    }
    final finalTag = token.tag.split('+').last;
    if (finalTag.isEmpty) {
      throw StateError('Korean morphology tags must not be empty.');
    }
    final marker = finalTag == 'NNBC' || token.surface == '곳'
        ? 'B'
        : String.fromCharCode(finalTag.runes.first);
    for (var index = 1; index < scalarLength; index++) {
      tagSequence.add('_');
    }
    tagSequence.add(marker);
  }
  for (final (index, blank) in blanks) {
    if (index > tagSequence.length) {
      break;
    }
    tagSequence.insert(index, blank);
  }

  final annotated = StringBuffer();
  final length = source.length < tagSequence.length
      ? source.length
      : tagSequence.length;
  for (var index = 0; index < length; index++) {
    final character = source[index];
    final tag = tagSequence[index];
    annotated.write(character);
    if (character == '의' && tag == 'J') {
      annotated.write('/J');
    } else if (tag == 'E') {
      final decomposed = decomposeKoreanHangul(character);
      if (decomposed.isNotEmpty &&
          _rieulEnding.contains(_lastScalar(decomposed))) {
        annotated.write('/E');
      }
    } else if (tag == 'V') {
      final decomposed = decomposeKoreanHangul(character);
      if (decomposed.isNotEmpty &&
          _verbEnding.contains(_lastScalar(decomposed))) {
        annotated.write('/P');
      }
    } else if (tag == 'B') {
      annotated.write('/B');
    }
  }
  return annotated.toString();
}

String _lastScalar(String value) => String.fromCharCode(value.runes.last);

final RegExp _spaceOrNewline = RegExp(r'[ \n]');

const Set<String> _rieulEnding = <String>{'ᆯ'};
const Set<String> _verbEnding = <String>{'ᆫ', 'ᆬ', 'ᆷ', 'ᆱ', 'ᆰ', 'ᆲ', 'ᆴ'};
