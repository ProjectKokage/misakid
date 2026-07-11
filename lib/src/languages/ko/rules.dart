// Dart adaptation of hexgrad/misaki/misaki/g2pkc/{special,regular,g2pk}.py
// and table.csv at fba1236595f2d2bf21d414ba6e57d25256afada3.
// Copied/adapted through 5Hyeons/StyleTTS2 from Kyubyong/g2pK under
// Apache-2.0. Modifications: generated table data, Unicode-scalar boundary
// handling, and explicit deterministic stage functions.

import '../../generated/korean_g2pkc_data.dart';

/// Applies the pinned ordered Hangul special, table, link, and postprocessing
/// rules to decomposed and morphology-annotated [input].
String applyKoreanG2pkcRules(
  String input, {
  bool descriptive = false,
  bool groupVowels = false,
}) {
  var output = input;
  output = _jyeo(output);
  output = descriptive ? _ye(output) : output;
  output = _consonantUi(output);
  output = descriptive
      ? _descriptiveJosaUi(output)
      : output.replaceAll('/J', '');
  output = descriptive ? _descriptiveVowelUi(output) : output;
  output = _jamoNames(output);
  output = _rieulGiyeok(output);
  output = _rieulBieub(output);
  output = _verbNieun(output);
  output = _balb(output);
  output = _palatalize(output);
  output = _modifyingRieul(output);
  output = output.replaceAll(RegExp(r'/[PJEB]'), '');

  for (final (coda, onset, replacement) in koreanG2pkcTableRules) {
    if (onset == r'(\W|$)') {
      output = _replaceFinalCoda(output, coda, replacement);
    } else {
      output = output.replaceAll('$coda$onset', replacement);
    }
  }
  output = _replacePairs(output, _link1);
  output = _replacePairs(output, _link2);
  output = _replacePairs(output, _link4);
  if (groupVowels) {
    output = output
        .replaceAll('ᅢ', 'ᅦ')
        .replaceAll('ᅤ', 'ᅨ')
        .replaceAll('ᅫ', 'ᅬ')
        .replaceAll('ᅰ', 'ᅬ');
  }
  return output.replaceAll('^', '');
}

String _jyeo(String input) =>
    input.replaceAllMapped(RegExp('([ᄌᄍᄎ])ᅧ'), (match) => '${match.group(1)}ᅥ');

String _ye(String input) => input.replaceAllMapped(
  RegExp('([ᄀᄁᄃᄄㄹᄆᄇᄈᄌᄍᄎᄏᄐᄑᄒ])ᅨ'),
  (match) => '${match.group(1)}ᅦ',
);

String _consonantUi(String input) => input.replaceAllMapped(
  RegExp('([ᄀᄁᄂᄃᄄᄅᄆᄇᄈᄉᄊᄌᄍᄎᄏᄐᄑᄒ])ᅴ'),
  (match) => '${match.group(1)}ᅵ',
);

String _descriptiveJosaUi(String input) => input.replaceAllMapped(
  RegExp(r'([^^])의/J'),
  (match) => '${match.group(1)}에',
);

String _descriptiveVowelUi(String input) => input.replaceAllMapped(
  RegExp(r'([^^\s]ᄋ)ᅴ'),
  (match) => '${match.group(1)}ᅵ',
);

String _jamoNames(String input) {
  var output = input;
  output = output.replaceAllMapped(
    RegExp('(디그)ᆮᄋ'),
    (match) => '${match.group(1)}ᄉ',
  );
  output = output.replaceAllMapped(
    RegExp('([ᄌᄎᄐᄒ]ᅵ으)[ᆽᆾᇀᇂ]ᄋ'),
    (match) => '${match.group(1)}ᄉ',
  );
  output = output.replaceAllMapped(
    RegExp('(키으)ᆿᄋ'),
    (match) => '${match.group(1)}ᄀ',
  );
  return output.replaceAllMapped(
    RegExp('(피으)ᇁᄋ'),
    (match) => '${match.group(1)}ᄇ',
  );
}

String _rieulGiyeok(String input) =>
    input.replaceAllMapped(RegExp('ᆰ/P([ᄀᄁ])'), (match) => 'ᆯᄁ');

String _rieulBieub(String input) => input.replaceAllMapped(
  RegExp(r'([ᆲᆴ])/P([ᄀᄃᄉᄌ])'),
  (match) => '${match.group(1)}${_tenseOnset[match.group(2)]}',
);

String _verbNieun(String input) {
  var output = input.replaceAllMapped(
    RegExp(r'([ᆫᆷ])/P([ᄀᄃᄉᄌ])'),
    (match) => '${match.group(1)}${_tenseOnset[match.group(2)]}',
  );
  for (final (source, coda) in const <(String, String)>[
    ('ᆬ', 'ᆫ'),
    ('ᆱ', 'ᆷ'),
  ]) {
    output = output.replaceAllMapped(
      RegExp('$source/P([ᄀᄃᄉᄌ])'),
      (match) => '$coda${_tenseOnset[match.group(1)]}',
    );
  }
  return output;
}

String _balb(String input) {
  var output = input.replaceAllMapped(
    RegExp(r'(바)ᆲ($|[^ᄋᄒ])'),
    (match) => '${match.group(1)}ᆸ${match.group(2)}',
  );
  output = output.replaceAllMapped(
    RegExp(r'(너)ᆲ([ᄌᄍ]ᅮ|[ᄃᄄ]ᅮ)'),
    (match) => '${match.group(1)}ᆸ${match.group(2)}',
  );
  return output;
}

String _palatalize(String input) {
  var output = input.replaceAllMapped(
    RegExp('ᆮᄋ([ᅵᅧ])'),
    (match) => 'ᄌ${match.group(1)}',
  );
  output = output.replaceAllMapped(
    RegExp('ᇀᄋ([ᅵᅧ])'),
    (match) => 'ᄎ${match.group(1)}',
  );
  output = output.replaceAllMapped(
    RegExp('ᆴᄋ([ᅵᅧ])'),
    (match) => 'ᆯᄎ${match.group(1)}',
  );
  return output.replaceAllMapped(RegExp('ᆮ히'), (_) => '치');
}

String _modifyingRieul(String input) =>
    _replacePairs(input, const <(String, String)>[
      ('ᆯ걸', 'ᆯ껄'),
      ('ᆯ밖에', 'ᆯ빠께'),
      ('ᆯ세라', 'ᆯ쎄라'),
      ('ᆯ수록', 'ᆯ쑤록'),
      ('ᆯ지라도', 'ᆯ찌라도'),
      ('ᆯ지언정', 'ᆯ찌언정'),
      ('ᆯ진대', 'ᆯ찐대'),
    ]);

String _replaceFinalCoda(String input, String coda, String replacement) {
  final characters = <String>[
    for (final scalar in input.runes) String.fromCharCode(scalar),
  ];
  final output = StringBuffer();
  for (var index = 0; index < characters.length; index++) {
    final character = characters[index];
    if (character == coda &&
        (index + 1 == characters.length ||
            !_isPythonWordScalar(characters[index + 1].runes.single))) {
      output.write(replacement.replaceAll(r'\1', ''));
    } else {
      output.write(character);
    }
  }
  return output.toString();
}

bool _isPythonWordScalar(int scalar) {
  // Python's Unicode `\w` is `str.isalnum()` plus underscore. Dart's `\w`
  // is ASCII-only, so use Unicode general categories explicitly.
  return _pythonWordScalar.hasMatch(String.fromCharCode(scalar));
}

final RegExp _pythonWordScalar = RegExp(r'^[_\p{L}\p{N}]$', unicode: true);

String _replacePairs(String input, List<(String, String)> pairs) {
  var output = input;
  for (final (source, replacement) in pairs) {
    output = output.replaceAll(source, replacement);
  }
  return output;
}

const Map<String, String> _tenseOnset = <String, String>{
  'ᄀ': 'ᄁ',
  'ᄃ': 'ᄄ',
  'ᄉ': 'ᄊ',
  'ᄌ': 'ᄍ',
};

const List<(String, String)> _link1 = <(String, String)>[
  ('ᆨᄋ', 'ᄀ'),
  ('ᆩᄋ', 'ᄁ'),
  ('ᆫᄋ', 'ᄂ'),
  ('ᆮᄋ', 'ᄃ'),
  ('ᆯᄋ', 'ᄅ'),
  ('ᆷᄋ', 'ᄆ'),
  ('ᆸᄋ', 'ᄇ'),
  ('ᆺᄋ', 'ᄉ'),
  ('ᆻᄋ', 'ᄊ'),
  ('ᆽᄋ', 'ᄌ'),
  ('ᆾᄋ', 'ᄎ'),
  ('ᆿᄋ', 'ᄏ'),
  ('ᇀᄋ', 'ᄐ'),
  ('ᇁᄋ', 'ᄑ'),
];

const List<(String, String)> _link2 = <(String, String)>[
  ('ᆪᄋ', 'ᆨᄊ'),
  ('ᆬᄋ', 'ᆫᄌ'),
  ('ᆰᄋ', 'ᆯᄀ'),
  ('ᆱᄋ', 'ᆯᄆ'),
  ('ᆲᄋ', 'ᆯᄇ'),
  ('ᆳᄋ', 'ᆯᄊ'),
  ('ᆴᄋ', 'ᆯᄐ'),
  ('ᆵᄋ', 'ᆯᄑ'),
  ('ᆹᄋ', 'ᆸᄊ'),
];

const List<(String, String)> _link4 = <(String, String)>[
  ('ᇂᄋ', 'ᄋ'),
  ('ᆭᄋ', 'ᄂ'),
  ('ᆶᄋ', 'ᄅ'),
];
