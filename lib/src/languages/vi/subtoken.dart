// Dart adaptation of VIG2P.substr2ipa in pinned Misaki vi.py at
// fba1236595f2d2bf21d414ba6e57d25256afada3. Viphoneme MIT provenance is in
// THIRD_PARTY_NOTICES.md. Modifications: typed immutable parts and
// Unicode-scalar-safe suffix scans.

import '../../core/constants.dart';
import '../../core/python311_case.dart';
import '../../generated/vietnamese_cleaner_tables.dart';
import '../../generated/vietnamese_phonology_data.dart';
import 'backends.dart';
import 'options.dart';
import 'phonology.dart';

/// One token or subtoken produced by Vietnamese fallback handling.
final class VietnamesePronouncedPart {
  /// Creates one immutable part.
  const VietnamesePronouncedPart({
    required this.parent,
    required this.text,
    required this.phonemes,
  });

  /// Original unsplit token, or `null` when this is not a split.
  final String? parent;

  /// Exact part text used by the upstream token.
  final String text;

  /// Delimited Vietnamese fields, English fallback output, or brackets.
  final String phonemes;
}

/// Replays pinned acronym, English fallback, and suffix splitting behavior.
List<VietnamesePronouncedPart> splitVietnameseToken(
  String token,
  String firstAttempt,
  VietnameseOptions options, {
  VietnameseEnglishFallbackBackend? englishFallback,
}) {
  if (!firstAttempt.contains('[')) {
    return <VietnamesePronouncedPart>[
      VietnamesePronouncedPart(
        parent: null,
        text: token,
        phonemes: firstAttempt,
      ),
    ];
  }

  if (python311Upper(python311Lower(token)) == token) {
    final mapping = _containsVietnameseSpecific(token)
        ? vietnameseLetterNames
        : vietnameseEnglishLetterNames;
    return <VietnamesePronouncedPart>[
      for (final character in _scalars(python311Lower(token)))
        VietnamesePronouncedPart(
          parent: token,
          text: character,
          phonemes: convertVietnameseWord(
            mapping[character] ?? character,
            options,
          ),
        ),
    ];
  }

  final original = token;
  var remaining = python311Lower(token);
  if (!_containsVietnameseSpecific(remaining) && englishFallback != null) {
    final english = englishFallback.phonemize(remaining);
    if (english != null && !english.contains(defaultUnknownMarker)) {
      return <VietnamesePronouncedPart>[
        VietnamesePronouncedPart(
          parent: null,
          text: remaining,
          phonemes: english,
        ),
      ];
    }
  }

  if (!options.substringTokenization) {
    return <VietnamesePronouncedPart>[
      VietnamesePronouncedPart(
        parent: null,
        text: remaining,
        phonemes: firstAttempt,
      ),
    ];
  }

  final parents = <String>[];
  final parts = <String>[];
  final phonemes = <String>[];
  while (remaining.isNotEmpty) {
    final characters = _scalars(remaining);
    if (characters.length == 1) {
      final character = characters.single;
      parents.insert(0, original);
      parts.insert(0, character);
      phonemes.insert(
        0,
        convertVietnameseWord(
          vietnameseLetterNames[character] ?? character,
          options,
        ),
      );
      break;
    }

    var start = -1;
    var converted = '';
    for (var index = characters.length - 1; index >= 0; index--) {
      final suffix = characters.sublist(index).join();
      final source = suffix.runes.length > 1
          ? suffix
          : vietnameseLetterNames[suffix] ?? suffix;
      final candidate = convertVietnameseWord(source, options);
      if (!candidate.contains('[')) {
        start = index;
        converted = candidate;
      }
    }
    if (start == -1) {
      break;
    }
    parents.insert(0, original);
    parts.insert(0, characters.sublist(start).join());
    phonemes.insert(0, converted);
    remaining = characters.take(start).join();
  }

  return <VietnamesePronouncedPart>[
    for (var index = 0; index < parts.length; index++)
      VietnamesePronouncedPart(
        parent: parents[index],
        text: parts[index],
        phonemes: phonemes[index],
      ),
  ];
}

bool _containsVietnameseSpecific(String value) {
  for (final scalar in value.runes) {
    if (scalar > 0x7f &&
        vietnameseCharacterSet.contains(String.fromCharCode(scalar))) {
      return true;
    }
  }
  return false;
}

List<String> _scalars(String value) => <String>[
  for (final scalar in value.runes) String.fromCharCode(scalar),
];
