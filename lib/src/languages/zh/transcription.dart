// Dart adaptation of pinyin-to-IPA transcription.py at
// ef81b82bfa42601300463c50a5db063d3b47e347 (MIT).
// Copyright (c) 2024 Stefan Taubert.
// The complete MIT notice is retained in THIRD_PARTY_NOTICES.md.
//
// This file follows hexgrad/misaki/misaki/transcription.py at
// fba1236595f2d2bf21d414ba6e57d25256afada3 (Misaki 0.9.4).
// Modifications: ported to null-safe Dart, replaced pypinyin and ordered-set
// dependencies with scalar-safe local normalization and immutable ordered
// results, preserved Misaki's six initial-symbol substitutions, and exposed
// source-derived rendered scalars for the public inventory.

import 'legacy_helpers.dart';

/// One ordered IPA pronunciation variant for a Pinyin syllable.
final class PinyinIpaVariant {
  PinyinIpaVariant._(Iterable<String> phonemes)
    : phonemes = List<String>.unmodifiable(phonemes);

  /// Phonemes in exact upstream order.
  final List<String> phonemes;

  @override
  bool operator ==(Object other) =>
      other is PinyinIpaVariant && _sameStrings(phonemes, other.phonemes);

  @override
  int get hashCode => Object.hashAll(phonemes);

  @override
  String toString() => phonemes.join();
}

/// Transcribes one Pinyin syllable into ordered IPA variants.
///
/// Tone marks, trailing tone numbers, tone-number-in-vowel forms, neutral
/// tones, `v`/`ü`, zero-initial `y`/`w` spellings, contracted finals, syllabic
/// consonants, and the pinned interjections are handled like the Python
/// reference. The returned list and every variant's phoneme list are
/// unmodifiable.
///
/// Throws [FormatException] when [pinyin] has no detectable tone/final or
/// contains an unsupported syllable.
List<PinyinIpaVariant> pinyinToIpa(String pinyin) {
  final tone = _getTone(pinyin);
  final normalPinyin = _toNormal(pinyin);

  final interjection = _interjectionMappings[normalPinyin];
  if (interjection != null) {
    return _freezeOrderedVariants(_applyTone(interjection, tone));
  }

  final syllabicConsonant = _syllabicConsonantMappings[normalPinyin];
  if (syllabicConsonant != null) {
    return _freezeOrderedVariants(_applyTone(syllabicConsonant, tone));
  }

  final initial = _getInitial(normalPinyin);
  final finalName = _getFinal(normalPinyin);
  final parts = <_PhonemeVariants>[];

  if (initial != null) {
    final initialVariants = _initialMappings[initial];
    if (initialVariants == null) {
      throw FormatException(
        "Parameter 'normal_pinyin': Initial '$initial' couldn't be detected!",
      );
    }
    parts.add(initialVariants);
  }

  final _PhonemeVariants finalVariants;
  if (_retroflexInitials.contains(initial) && finalName == 'i') {
    finalVariants = _finalAfterRetroflexInitial;
  } else if (_alveolarInitials.contains(initial) && finalName == 'i') {
    finalVariants = _finalAfterAlveolarInitial;
  } else {
    finalVariants = _finalMappings[finalName]!;
  }
  parts.add(_applyTone(finalVariants, tone));

  var combinations = <List<String>>[<String>[]];
  for (final part in parts) {
    final next = <List<String>>[];
    for (final prefix in combinations) {
      for (final variant in part) {
        next.add(<String>[...prefix, ...variant]);
      }
    }
    combinations = next;
  }

  return _freezeOrderedVariants(combinations);
}

typedef _PhonemeVariants = List<List<String>>;

const Map<String, _PhonemeVariants> _initialMappings =
    <String, _PhonemeVariants>{
      'b': <List<String>>[
        <String>['p'],
      ],
      'c': <List<String>>[
        <String>['ʦʰ'],
      ],
      'ch': <List<String>>[
        <String>['ꭧʰ'],
      ],
      'd': <List<String>>[
        <String>['t'],
      ],
      'f': <List<String>>[
        <String>['f'],
      ],
      'g': <List<String>>[
        <String>['k'],
      ],
      'h': <List<String>>[
        <String>['x'],
        <String>['h'],
      ],
      'j': <List<String>>[
        <String>['ʨ'],
      ],
      'k': <List<String>>[
        <String>['kʰ'],
      ],
      'l': <List<String>>[
        <String>['l'],
      ],
      'm': <List<String>>[
        <String>['m'],
      ],
      'n': <List<String>>[
        <String>['n'],
      ],
      'p': <List<String>>[
        <String>['pʰ'],
      ],
      'q': <List<String>>[
        <String>['ʨʰ'],
      ],
      'r': <List<String>>[
        <String>['ɻ'],
        <String>['ʐ'],
      ],
      's': <List<String>>[
        <String>['s'],
      ],
      'sh': <List<String>>[
        <String>['ʂ'],
      ],
      't': <List<String>>[
        <String>['tʰ'],
      ],
      'x': <List<String>>[
        <String>['ɕ'],
      ],
      'z': <List<String>>[
        <String>['ʦ'],
      ],
      'zh': <List<String>>[
        <String>['ꭧ'],
      ],
    };

const Map<String, _PhonemeVariants> _syllabicConsonantMappings =
    <String, _PhonemeVariants>{
      'hm': <List<String>>[
        <String>['h', 'm0'],
      ],
      'hng': <List<String>>[
        <String>['h', 'ŋ0'],
      ],
      'm': <List<String>>[
        <String>['m0'],
      ],
      'n': <List<String>>[
        <String>['n0'],
      ],
      'ng': <List<String>>[
        <String>['ŋ0'],
      ],
    };

const Map<String, _PhonemeVariants> _interjectionMappings =
    <String, _PhonemeVariants>{
      'io': <List<String>>[
        <String>['j', 'ɔ0'],
      ],
      'ê': <List<String>>[
        <String>['ɛ0'],
      ],
      'er': <List<String>>[
        <String>['ɚ0'],
        <String>['aɚ̯0'],
      ],
      'o': <List<String>>[
        <String>['ɔ0'],
      ],
    };

const Map<String, _PhonemeVariants> _finalMappings = <String, _PhonemeVariants>{
  'a': <List<String>>[
    <String>['a0'],
  ],
  'ai': <List<String>>[
    <String>['ai̯0'],
  ],
  'an': <List<String>>[
    <String>['a0', 'n'],
  ],
  'ang': <List<String>>[
    <String>['a0', 'ŋ'],
  ],
  'ao': <List<String>>[
    <String>['au̯0'],
  ],
  'e': <List<String>>[
    <String>['ɤ0'],
  ],
  'ei': <List<String>>[
    <String>['ei̯0'],
  ],
  'en': <List<String>>[
    <String>['ə0', 'n'],
  ],
  'eng': <List<String>>[
    <String>['ə0', 'ŋ'],
  ],
  'i': <List<String>>[
    <String>['i0'],
  ],
  'ia': <List<String>>[
    <String>['j', 'a0'],
  ],
  'ian': <List<String>>[
    <String>['j', 'ɛ0', 'n'],
  ],
  'iang': <List<String>>[
    <String>['j', 'a0', 'ŋ'],
  ],
  'iao': <List<String>>[
    <String>['j', 'au̯0'],
  ],
  'ie': <List<String>>[
    <String>['j', 'e0'],
  ],
  'in': <List<String>>[
    <String>['i0', 'n'],
  ],
  'iou': <List<String>>[
    <String>['j', 'ou̯0'],
  ],
  'ing': <List<String>>[
    <String>['i0', 'ŋ'],
  ],
  'iong': <List<String>>[
    <String>['j', 'ʊ0', 'ŋ'],
  ],
  'ong': <List<String>>[
    <String>['ʊ0', 'ŋ'],
  ],
  'ou': <List<String>>[
    <String>['ou̯0'],
  ],
  'u': <List<String>>[
    <String>['u0'],
  ],
  'uei': <List<String>>[
    <String>['w', 'ei̯0'],
  ],
  'ua': <List<String>>[
    <String>['w', 'a0'],
  ],
  'uai': <List<String>>[
    <String>['w', 'ai̯0'],
  ],
  'uan': <List<String>>[
    <String>['w', 'a0', 'n'],
  ],
  'uen': <List<String>>[
    <String>['w', 'ə0', 'n'],
  ],
  'uang': <List<String>>[
    <String>['w', 'a0', 'ŋ'],
  ],
  'ueng': <List<String>>[
    <String>['w', 'ə0', 'ŋ'],
  ],
  'uo': <List<String>>[
    <String>['w', 'o0'],
  ],
  'o': <List<String>>[
    <String>['w', 'o0'],
  ],
  'ü': <List<String>>[
    <String>['y0'],
  ],
  'üe': <List<String>>[
    <String>['ɥ', 'e0'],
  ],
  'üan': <List<String>>[
    <String>['ɥ', 'ɛ0', 'n'],
  ],
  'ün': <List<String>>[
    <String>['y0', 'n'],
  ],
};

const _PhonemeVariants _finalAfterRetroflexInitial = <List<String>>[
  <String>['ɻ̩0'],
  <String>['ʐ̩0'],
];

const _PhonemeVariants _finalAfterAlveolarInitial = <List<String>>[
  <String>['ɹ̩0'],
  <String>['z̩0'],
];

const Set<String> _retroflexInitials = <String>{'zh', 'ch', 'sh', 'r'};
const Set<String> _alveolarInitials = <String>{'z', 'c', 's'};

const Map<int, String> _toneMappings = <int, String>{
  1: '˥',
  2: '˧˥',
  3: '˧˩˧',
  4: '˥˩',
  5: '',
};

/// Builds the phonetic-scalar inventory emitted by the legacy renderer.
///
/// This is an internal source-table bridge for `inventory.dart`. Pinned
/// `ZHG2P` selects only the first pinyin-to-IPA variant, applies its legacy
/// tone substitutions, and removes U+032F COMBINING INVERTED BREVE BELOW from
/// the final string. Deriving the set through those same observable steps
/// keeps unused alternate transcription variants out of the public inventory.
Set<String> legacyChineseRenderedPhoneticScalars() {
  final result = <String>{};
  final mappings = <_PhonemeVariants>[
    ..._initialMappings.values,
    ..._syllabicConsonantMappings.values,
    ..._interjectionMappings.values,
    ..._finalMappings.values,
    _finalAfterRetroflexInitial,
    _finalAfterAlveolarInitial,
  ];

  for (final variants in mappings) {
    final selected = variants.first;
    for (final sourcePhoneme in selected) {
      final toneValues = sourcePhoneme.contains('0')
          ? _toneMappings.values
          : const <String>[''];
      for (final tone in toneValues) {
        final rendered = retoneLegacyChinese(
          sourcePhoneme.replaceAll('0', tone),
        ).replaceAll('\u032f', '');
        result.addAll(rendered.runes.map<String>(String.fromCharCode));
      }
    }
  }

  return Set<String>.unmodifiable(result);
}

const List<String> _initials = <String>[
  'b',
  'p',
  'm',
  'f',
  'd',
  't',
  'n',
  'l',
  'g',
  'k',
  'h',
  'j',
  'q',
  'x',
  'zh',
  'ch',
  'sh',
  'r',
  'z',
  'c',
  's',
];

const Set<String> _finals = <String>{
  'i',
  'u',
  'ü',
  'a',
  'ia',
  'ua',
  'o',
  'uo',
  'e',
  'ie',
  'üe',
  'ai',
  'uai',
  'ei',
  'uei',
  'ao',
  'iao',
  'ou',
  'iou',
  'an',
  'ian',
  'uan',
  'üan',
  'en',
  'in',
  'uen',
  'ün',
  'ang',
  'iang',
  'uang',
  'eng',
  'ing',
  'ueng',
  'ong',
  'iong',
  'er',
  'ê',
};

const Map<String, String> _phoneticSymbols = <String, String>{
  'ā': 'a1',
  'á': 'a2',
  'ǎ': 'a3',
  'à': 'a4',
  'ē': 'e1',
  'é': 'e2',
  'ě': 'e3',
  'è': 'e4',
  'ō': 'o1',
  'ó': 'o2',
  'ǒ': 'o3',
  'ò': 'o4',
  'ī': 'i1',
  'í': 'i2',
  'ǐ': 'i3',
  'ì': 'i4',
  'ū': 'u1',
  'ú': 'u2',
  'ǔ': 'u3',
  'ù': 'u4',
  'ü': 'v',
  'ǖ': 'v1',
  'ǘ': 'v2',
  'ǚ': 'v3',
  'ǜ': 'v4',
  'ń': 'n2',
  'ň': 'n3',
  'ǹ': 'n4',
  'ḿ': 'm2',
  'ế': 'ê2',
  'ề': 'ê4',
};

const Map<String, String> _multiscalarPhoneticSymbols = <String, String>{
  'm̄': 'm1',
  'm̀': 'm4',
  'ê̄': 'ê1',
  'ê̌': 'ê3',
};

const Map<String, String> _uToneMappings = <String, String>{
  'u': 'ü',
  'ū': 'ǖ',
  'ú': 'ǘ',
  'ǔ': 'ǚ',
  'ù': 'ǜ',
};

const Set<String> _iTones = <String>{'i', 'ī', 'í', 'ǐ', 'ì'};

final RegExp _tonePositionPattern = RegExp(
  r'^([a-zêü]+)([1-5])([a-zêü]*)$',
  unicode: true,
);
final RegExp _iouPattern = RegExp(r'^([a-z]+)iu$');
final RegExp _ueiPattern = RegExp(r'([a-z]+)ui$');
final RegExp _uenPattern = RegExp(r'([a-z]+)un$');

// Unicode 14 decimal-zero code points, matching the pinned Python 3.11
// oracle's scalar-based `\d` and `int` behavior.
const List<int> _decimalZeroCodePoints = <int>[
  0x0030,
  0x0660,
  0x06f0,
  0x07c0,
  0x0966,
  0x09e6,
  0x0a66,
  0x0ae6,
  0x0b66,
  0x0be6,
  0x0c66,
  0x0ce6,
  0x0d66,
  0x0de6,
  0x0e50,
  0x0ed0,
  0x0f20,
  0x1040,
  0x1090,
  0x17e0,
  0x1810,
  0x1946,
  0x19d0,
  0x1a80,
  0x1a90,
  0x1b50,
  0x1bb0,
  0x1c40,
  0x1c50,
  0xa620,
  0xa8d0,
  0xa900,
  0xa9d0,
  0xa9f0,
  0xaa50,
  0xabf0,
  0xff10,
  0x104a0,
  0x10d30,
  0x11066,
  0x110f0,
  0x11136,
  0x111d0,
  0x112f0,
  0x11450,
  0x114d0,
  0x11650,
  0x116c0,
  0x11730,
  0x118e0,
  0x11950,
  0x11c50,
  0x11d50,
  0x11da0,
  0x16a60,
  0x16ac0,
  0x16b50,
  0x1d7ce,
  0x1d7d8,
  0x1d7e2,
  0x1d7ec,
  0x1d7f6,
  0x1e140,
  0x1e2f0,
  0x1e950,
  0x1fbf0,
];

int _getTone(String pinyin) {
  final tone3 = _toTone3(pinyin);
  final scalars = _scalarCharacters(tone3);
  if (scalars.isEmpty) {
    throw const FormatException(
      "Parameter 'pinyin': Tone couldn't be detected!",
    );
  }

  final toneCharacter = scalars.last;
  final tone = _decimalDigitValue(toneCharacter.runes.single);
  if (tone == null || !_toneMappings.containsKey(tone)) {
    throw FormatException(
      "Parameter 'pinyin': Tone '$toneCharacter' couldn't be detected!",
    );
  }
  return tone;
}

String? _getInitial(String normalPinyin) {
  if (_syllabicConsonantMappings.containsKey(normalPinyin) ||
      _interjectionMappings.containsKey(normalPinyin)) {
    return null;
  }

  final initial = _initialPrefix(normalPinyin, strict: true);
  if (initial.isEmpty) {
    return null;
  }
  if (!_initialMappings.containsKey(initial)) {
    throw FormatException(
      "Parameter 'normal_pinyin': Initial '$initial' couldn't be detected!",
    );
  }
  return initial;
}

String _getFinal(String normalPinyin) {
  final finalName = _toFinal(normalPinyin);
  if (finalName.isEmpty) {
    throw const FormatException(
      "Parameter 'normal_pinyin': Final couldn't be detected!",
    );
  }
  if (!_finalMappings.containsKey(finalName)) {
    throw FormatException(
      "Parameter 'normal_pinyin': Final '$finalName' couldn't be detected!",
    );
  }
  return finalName;
}

_PhonemeVariants _applyTone(_PhonemeVariants variants, int tone) {
  final toneIpa = _toneMappings[tone]!;
  return <List<String>>[
    for (final variant in variants)
      <String>[for (final phoneme in variant) phoneme.replaceAll('0', toneIpa)],
  ];
}

List<PinyinIpaVariant> _freezeOrderedVariants(Iterable<List<String>> variants) {
  final result = <PinyinIpaVariant>[];
  for (final variant in variants) {
    if (result.any((existing) => _sameStrings(existing.phonemes, variant))) {
      continue;
    }
    result.add(PinyinIpaVariant._(variant));
  }
  return List<PinyinIpaVariant>.unmodifiable(result);
}

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

String _toTone3(String pinyin) {
  final withoutAsciiFive = pinyin.replaceAll('5', '');
  var result = _toneToTone2(
    withoutAsciiFive,
    vToU: true,
    neutralToneWithFive: true,
  );
  result = _tone2ToTone3(result, vToU: false);
  return _fixV(result, vToU: true);
}

String _toNormal(String pinyin) {
  var result = _toneToTone2(pinyin, vToU: true, neutralToneWithFive: false);
  result = _tone2ToNormal(result, vToU: false);
  return _fixV(result, vToU: false);
}

String _toneToTone2(
  String tone, {
  required bool vToU,
  required bool neutralToneWithFive,
}) {
  final tone3 = _toneMarkedToTone3(
    tone,
    vToU: true,
    neutralToneWithFive: neutralToneWithFive,
  );
  final result = _tone3ToTone2(tone3, vToU: false);
  return _fixV(result, vToU: vToU);
}

String _toneMarkedToTone3(
  String tone, {
  required bool vToU,
  required bool neutralToneWithFive,
}) {
  var result = _moveToneNumberToEnd(_replacePhoneticSymbols(tone));
  if (_firstDecimalDigit(result) == null &&
      neutralToneWithFive &&
      result.isNotEmpty) {
    result = '${result}5';
  }
  return _fixV(result, vToU: vToU);
}

String _tone3ToTone2(String tone3, {required bool vToU}) {
  final withoutNumber = _tone3ToNormal(tone3, vToU: false);
  final number = _firstDecimalDigit(tone3);
  if (number == null) {
    return tone3;
  }

  final markIndex = _rightToneMarkIndex(withoutNumber);
  final boundary = (markIndex ?? withoutNumber.length - 1) + 1;
  final result =
      '${withoutNumber.substring(0, boundary)}'
      '$number${withoutNumber.substring(boundary)}';
  return _fixV(result, vToU: vToU);
}

String _tone2ToTone3(String tone2, {required bool vToU}) =>
    _fixV(_moveToneNumberToEnd(tone2), vToU: vToU);

String _tone2ToNormal(String tone2, {required bool vToU}) =>
    _fixV(_removeDecimalDigits(tone2), vToU: vToU);

String _tone3ToNormal(String tone3, {required bool vToU}) =>
    _fixV(_removeDecimalDigits(tone3), vToU: vToU);

String _moveToneNumberToEnd(String value) {
  final match = _tonePositionPattern.firstMatch(value);
  if (match == null) {
    return value;
  }
  return '${match.group(1)}${match.group(3)}${match.group(2)}';
}

String _replacePhoneticSymbols(String value) {
  var result = value;
  for (final entry in _phoneticSymbols.entries) {
    result = result.replaceAll(entry.key, entry.value);
  }
  for (final entry in _multiscalarPhoneticSymbols.entries) {
    result = result.replaceAll(entry.key, entry.value);
  }
  return result;
}

String _replacePhoneticSymbolsWithoutTone(String value) =>
    _removeDecimalDigits(_replacePhoneticSymbols(value));

String _fixV(String value, {required bool vToU}) =>
    vToU ? value.replaceAll('v', 'ü') : value.replaceAll('ü', 'v');

int? _rightToneMarkIndex(String pinyin) {
  if (pinyin.contains('iou')) {
    return pinyin.indexOf('u');
  }
  if (pinyin.contains('uei')) {
    return pinyin.indexOf('i');
  }
  if (pinyin.contains('uen')) {
    return pinyin.indexOf('u');
  }
  for (final value in <String>['a', 'o', 'e']) {
    final index = pinyin.indexOf(value);
    if (index >= 0) {
      return index;
    }
  }
  for (final value in <String>['iu', 'ui']) {
    final index = pinyin.indexOf(value);
    if (index >= 0) {
      return index + 1;
    }
  }
  for (final value in <String>['i', 'u', 'v', 'ü', 'n', 'm', 'ê']) {
    final index = pinyin.indexOf(value);
    if (index >= 0) {
      return index;
    }
  }
  return null;
}

String _toFinal(String normalPinyin) {
  final noTone = _replacePhoneticSymbolsWithoutTone(
    normalPinyin,
  ).replaceAll('v', 'ü');
  return _strictFinal(noTone).replaceAll('v', 'ü');
}

String _strictFinal(String pinyin) {
  final converted = _convertFinals(pinyin);
  final initial = _initialPrefix(converted, strict: true);
  var finalName = converted.substring(initial.length);
  if (!_finals.contains(finalName)) {
    final looseInitial = _initialPrefix(converted, strict: false);
    finalName = converted.substring(looseInitial.length);
    return _finals.contains(finalName) ? finalName : '';
  }
  return finalName;
}

String _initialPrefix(String pinyin, {required bool strict}) {
  for (final initial in _initials) {
    if (pinyin.startsWith(initial)) {
      return initial;
    }
  }
  if (!strict) {
    if (pinyin.startsWith('y')) {
      return 'y';
    }
    if (pinyin.startsWith('w')) {
      return 'w';
    }
  }
  return '';
}

String _convertFinals(String pinyin) {
  var result = _convertZeroConsonant(pinyin);
  result = _convertUv(result);
  result = _replaceContracted(result, _iouPattern, 'iou');
  result = _replaceContracted(result, _ueiPattern, 'uei');
  result = _replaceContracted(result, _uenPattern, 'uen');
  return result;
}

String _convertZeroConsonant(String pinyin) {
  final rawPinyin = pinyin;
  var result = pinyin;
  if (rawPinyin.startsWith('y')) {
    final withoutY = result.substring(1);
    final first = _firstScalar(withoutY);
    final convertedU = first == null ? null : _uToneMappings[first];
    if (convertedU != null) {
      result = '$convertedU${_dropFirstScalar(withoutY)}';
    } else if (first != null && _iTones.contains(first)) {
      result = withoutY;
    } else {
      result = 'i$withoutY';
    }
  }

  if (rawPinyin.startsWith('w')) {
    final withoutW = result.substring(1);
    final first = _firstScalar(withoutW);
    if (first != null && _uToneMappings.containsKey(first)) {
      result = withoutW;
    } else {
      result = 'u$withoutW';
    }
  }

  return _finals.contains(result) ? result : rawPinyin;
}

String _convertUv(String pinyin) {
  if (pinyin.length < 2 ||
      !(pinyin.startsWith('j') ||
          pinyin.startsWith('q') ||
          pinyin.startsWith('x'))) {
    return pinyin;
  }
  final remainder = pinyin.substring(1);
  final first = _firstScalar(remainder);
  final converted = first == null ? null : _uToneMappings[first];
  if (converted == null) {
    return pinyin;
  }
  return '${pinyin.substring(0, 1)}$converted${_dropFirstScalar(remainder)}';
}

String _replaceContracted(String value, RegExp pattern, String expanded) {
  final match = pattern.firstMatch(value);
  if (match == null) {
    return value;
  }
  return value.replaceRange(
    match.start,
    match.end,
    '${match.group(1)}$expanded',
  );
}

String? _firstScalar(String value) {
  if (value.isEmpty) {
    return null;
  }
  return String.fromCharCode(value.runes.first);
}

String _dropFirstScalar(String value) {
  final first = _firstScalar(value);
  return first == null ? '' : value.substring(first.length);
}

List<String> _scalarCharacters(String value) =>
    value.runes.map<String>(String.fromCharCode).toList(growable: false);

String? _firstDecimalDigit(String value) {
  for (final scalar in value.runes) {
    if (_decimalDigitValue(scalar) != null) {
      return String.fromCharCode(scalar);
    }
  }
  return null;
}

String _removeDecimalDigits(String value) {
  final result = StringBuffer();
  for (final scalar in value.runes) {
    if (_decimalDigitValue(scalar) == null) {
      result.writeCharCode(scalar);
    }
  }
  return result.toString();
}

int? _decimalDigitValue(int scalar) {
  for (final zero in _decimalZeroCodePoints) {
    final value = scalar - zero;
    if (value >= 0 && value <= 9) {
      return value;
    }
  }
  return null;
}
