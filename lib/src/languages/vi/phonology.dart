// Dart adaptation of hexgrad/misaki/misaki/vi.py at
// fba1236595f2d2bf21d414ba6e57d25256afada3 (Misaki 0.9.4), itself a
// substantial Viphoneme adaptation. Viphoneme revision and MIT notice are in
// THIRD_PARTY_NOTICES.md. Modifications: typed scalar-safe pure functions and
// generated immutable lookup tables.

import '../../core/python311_case.dart';
import '../../generated/vietnamese_phonology_data.dart';
import 'options.dart';

/// Structured Vietnamese syllable transcription.
final class VietnameseSyllable {
  /// Creates one exact onset/nucleus/coda/tone record.
  const VietnameseSyllable({
    required this.onset,
    required this.nucleus,
    required this.coda,
    required this.tone,
  });

  /// Initial consonant or on-glide.
  final String onset;

  /// Vowel nucleus.
  final String nucleus;

  /// Final consonant or off-glide.
  final String coda;

  /// Upstream tone digits and optional closed-tone suffix.
  final String tone;

  /// Joins the four fields with [delimiter].
  String delimited(String delimiter) =>
      <String>[onset, nucleus, coda, tone].join(delimiter);

  /// Concatenates the four fields into final phonemes.
  String get phonemes => '$onset$nucleus$coda$tone';
}

/// Transcribes one lowercase NFC Vietnamese orthographic syllable.
///
/// Returns `null` when pinned Viphoneme tables cannot analyze [word].
VietnameseSyllable? transcribeVietnameseSyllable(
  String word,
  VietnameseOptions options,
) {
  final letters = <String>[
    for (final scalar in word.runes) String.fromCharCode(scalar),
  ];
  if (letters.isEmpty) {
    return null;
  }

  var onset = '';
  var nucleus = '';
  var coda = '';
  var onsetOffset = 0;
  var codaOffset = 0;
  final length = letters.length;

  for (final width in const <int>[3, 2, 1]) {
    if (length >= width) {
      final source = letters.take(width).join();
      final mapped = vietnameseOnsets[source];
      if (mapped != null) {
        onset = mapped;
        onsetOffset = width;
        break;
      }
    }
  }

  for (final width in const <int>[2, 1]) {
    if (length >= width) {
      final source = letters.skip(length - width).join();
      final mapped = vietnameseCodas[source];
      if (mapped != null) {
        coda = mapped;
        codaOffset = width;
        break;
      }
    }
  }

  final firstTwo = letters.take(2).join();
  final orthographicNucleus =
      vietnameseGi.containsKey(firstTwo) && coda.isNotEmpty && length == 3
      ? 'i'
      : letters.sublist(onsetOffset, length - codaOffset).join();
  if (vietnameseGi.containsKey(firstTwo) && coda.isNotEmpty && length == 3) {
    onset = 'z';
  }

  final simpleNucleus = vietnameseNuclei[orthographicNucleus];
  final onglide = vietnameseOnglides[orthographicNucleus];
  final onoffglide = vietnameseOnoffglides[orthographicNucleus];
  final offglide = vietnameseOffglides[orthographicNucleus];
  if (simpleNucleus != null) {
    if (onsetOffset == 0 && options.glottal && onset.isEmpty) {
      // Pinned source places the nucleus in `ons` and leaves `nuc` empty.
      onset = 'ʔ$simpleNucleus';
    } else {
      nucleus = simpleNucleus;
    }
  } else if (onglide != null && onset != 'kw') {
    nucleus = onglide;
    onset = onset.isEmpty ? 'w' : '${onset}w';
  } else if (onglide != null && onset == 'kw') {
    nucleus = onglide;
  } else if (onoffglide != null) {
    final parts = _scalars(onoffglide);
    coda = parts.removeLast();
    nucleus = parts.join();
    if (onset != 'kw') {
      onset = onset.isEmpty ? 'w' : '${onset}w';
    }
  } else if (offglide != null) {
    final parts = _scalars(offglide);
    coda = parts.removeLast();
    nucleus = parts.join();
  } else if (vietnameseGi.containsKey(word)) {
    final parts = _scalars(vietnameseGi[word]!);
    onset = parts.first;
    nucleus = parts.last;
  } else if (vietnameseQu.containsKey(word)) {
    final parts = _scalars(vietnameseQu[word]!);
    nucleus = parts.removeLast();
    final last = nucleus;
    onset = parts.join();
    nucleus = last;
  } else {
    return null;
  }

  if (options.dialect == VietnameseDialect.north) {
    if (nucleus == 'a') {
      if (coda == 'k' && codaOffset == 2) {
        nucleus = 'ɛ';
      }
      if (coda == 'ɲ' && nucleus == 'a') {
        nucleus = 'ɛ';
      }
    }
    if (options.palatals &&
        coda == 'k' &&
        const <String>{'i', 'e', 'ɛ'}.contains(nucleus)) {
      coda = 'c';
    }
  } else {
    if (const <String>{'i', 'e'}.contains(nucleus)) {
      if (coda == 'k') {
        coda = 't';
      }
      if (coda == 'ŋ') {
        coda = 'n';
      }
    } else if (const <String>{
      'iə',
      'ɯə',
      'uə',
      'u',
      'ɯ',
      'ɤ',
      'o',
      'ɔ',
      'ă',
      'ɤ̆',
    }.contains(nucleus)) {
      if (coda == 't') {
        coda = 'k';
      }
      if (coda == 'n') {
        coda = 'ŋ';
      }
    }
  }

  if (options.dialect == VietnameseDialect.south &&
      const <String>{'m', 'p'}.contains(coda)) {
    nucleus = switch (nucleus) {
      'iə' => 'i',
      'uə' => 'u',
      'ɯə' => 'ɯ',
      _ => nucleus,
    };
  }

  final tones = <int>[
    for (final character in letters) ?vietnameseToneByCharacter[character],
  ];
  var tone = tones.isNotEmpty
      ? tones.last.toString()
      : (options.effectivePham || options.effectiveCao)
      ? '1'
      : options.dialect == VietnameseDialect.central
      ? '35'
      : '33';

  if (codaOffset != 0) {
    if ((options.dialect == VietnameseDialect.north ||
            options.dialect == VietnameseDialect.south) &&
        tone == '21g' &&
        const <String>{'p', 't', 'k'}.contains(coda)) {
      tone = '21';
    }
    if (((options.dialect == VietnameseDialect.north && tone == '24') ||
            (options.dialect == VietnameseDialect.central && tone == '13')) &&
        const <String>{'p', 't', 'k'}.contains(coda)) {
      tone = '45';
    }
    if (options.effectiveCao && const <String>{'p', 't', 'k'}.contains(coda)) {
      if (tone == '5') {
        tone = '5b';
      }
      if (tone == '6') {
        tone = '6b';
      }
    }
    if (const <String>{'u', 'o', 'ɔ'}.contains(nucleus)) {
      if (coda == 'ŋ') {
        coda = 'ŋ͡m';
      }
      if (coda == 'k') {
        coda = 'k͡p';
      }
    }
  }

  return VietnameseSyllable(
    onset: onset,
    nucleus: nucleus,
    coda: coda,
    tone: tone,
  );
}

/// Converts one word to a delimiter-separated four-field transcription.
///
/// Unknown input is returned in square brackets, matching pinned `convert`.
String convertVietnameseWord(
  String word,
  VietnameseOptions options, {
  String delimiter = '/',
}) =>
    transcribeVietnameseSyllable(word, options)?.delimited(delimiter) ??
    '[$word]';

/// Parses a phoneme string against the pinned longest-first symbol inventory.
String parseVietnamesePhonemes(
  String text, {
  Iterable<String>? symbols,
  String delimiter = ' ',
}) {
  final inventory = (symbols ?? vietnameseSymbols).toList()
    ..sort((left, right) => right.runes.length.compareTo(left.runes.length));
  final input = _scalars(text);
  final output = StringBuffer();
  var index = 0;
  while (index < input.length) {
    String? match;
    var matchLength = 0;
    for (final symbol in inventory) {
      final candidate = _scalars(symbol);
      if (candidate.length <= input.length - index &&
          _matchesAt(input, candidate, index)) {
        match = symbol;
        matchLength = candidate.length;
        break;
      }
    }
    if (match != null) {
      output
        ..write(delimiter)
        ..write(match);
      index += matchLength;
      continue;
    }
    if (!const <String>{'ˈ', 'ˌ', '*'}.contains(input[index])) {
      output
        ..write(delimiter)
        ..write("'");
    }
    index++;
  }
  return '${stripRightPython311Whitespace(output.toString())}$delimiter';
}

List<String> _scalars(String value) => <String>[
  for (final scalar in value.runes) String.fromCharCode(scalar),
];

bool _matchesAt(List<String> input, List<String> candidate, int start) {
  for (var index = 0; index < candidate.length; index++) {
    if (input[start + index] != candidate[index]) {
      return false;
    }
  }
  return true;
}
