// Dart adaptation of hexgrad/misaki/misaki/g2pkc/english.py and the English
// helpers in utils.py at fba1236595f2d2bf21d414ba6e57d25256afada3.
// Copied/adapted through 5Hyeons/StyleTTS2 from Kyubyong/g2pK under
// Apache-2.0. Modifications: CMUdict is an explicit typed lookup callback;
// there is no resource loading, download, or global dictionary.

import 'backends.dart';
import 'jamo.dart';

/// Converts embedded ASCII English words to Hangul for the g2pkc pipeline.
String convertKoreanEnglish(
  String input,
  KoreanCmuPronunciation? Function(String word) lookup,
) {
  var output = input;
  final words = <String>{
    for (final match in _englishWords.allMatches(input)) match.group(0)!,
  }.toList()..sort((left, right) => right.length.compareTo(left.length));
  for (final word in words) {
    final isUppercase = word == word.toUpperCase();
    final pronunciation = isUppercase ? null : lookup(word.toLowerCase());
    final hangul = pronunciation == null
        ? _spellAsciiWord(word.toUpperCase())
        : _arpabetToHangul(pronunciation.arpabet);
    output = output.replaceAll(word, hangul);
  }
  return output;
}

String _spellAsciiWord(String word) {
  final output = StringBuffer();
  for (final codeUnit in word.codeUnits) {
    final letter = String.fromCharCode(codeUnit);
    final hangul = _englishLetterNames[letter];
    if (hangul == null) {
      throw StateError('Unsupported ASCII English letter: $letter');
    }
    output.write(hangul);
  }
  return output.toString();
}

String _arpabetToHangul(List<String> arpabet) {
  final phonemes = _adjustArpabet(arpabet);
  final result = StringBuffer();
  for (var index = 0; index < phonemes.length; index++) {
    final phoneme = phonemes[index];
    final previous = index > 0 ? phonemes[index - 1] : '^';
    final next = index < phonemes.length - 1 ? phonemes[index + 1] : r'$';
    // This intentionally repeats index + 1, preserving the pinned p_next2
    // quirk rather than silently correcting it to index + 2.
    final next2 = index < phonemes.length - 2 ? phonemes[index + 1] : r'$';

    if ('PTK'.contains(phoneme)) {
      if (_shortVowels.contains(_takeTwo(previous)) && next == r'$') {
        result.write(_toTail(phoneme));
      } else if (_shortVowels.contains(_takeTwo(previous)) &&
          !_vowelsAndLiquids.contains(next[0])) {
        result.write(_toTail(phoneme));
      } else if (_finalOrConsonants.contains(next[0])) {
        result
          ..write(_toLead(phoneme))
          ..write('ᅳ');
      } else {
        result.write(_toLead(phoneme));
      }
    } else if ('BDG'.contains(phoneme)) {
      result.write(_toLead(phoneme));
      if (_syllableFinalOrConsonants.contains(next[0])) {
        result.write('ᅳ');
      }
    } else if (_fricatives.contains(phoneme)) {
      result.write(_toLead(phoneme));
      if (_simpleFricatives.contains(phoneme)) {
        if (_syllableFinalOrConsonants.contains(next[0])) {
          result.write('ᅳ');
        }
      } else if (phoneme == 'SH') {
        if (next[0] == r'$') {
          result.write('ᅵ');
        } else if (_consonants.contains(next[0])) {
          result.write('ᅲ');
        } else {
          result.write('Y');
        }
      } else if (phoneme == 'ZH' &&
          _syllableFinalOrConsonants.contains(next[0])) {
        result.write('ᅵ');
      }
    } else if (_affricates.contains(phoneme)) {
      result.write(_toLead(phoneme));
      if (_syllableFinalOrConsonants.contains(next[0])) {
        result.write(_dentalAffricates.contains(phoneme) ? 'ᅳ' : 'ᅵ');
      }
    } else if (_nasals.contains(phoneme)) {
      if ('MN'.contains(phoneme) && _vowels.contains(next[0])) {
        result.write(_toLead(phoneme));
      } else {
        result.write(_toTail(phoneme));
      }
    } else if (phoneme == 'L') {
      if (previous == '^') {
        result.write(_toLead(phoneme));
      } else if (_lFinalOrConsonants.contains(next[0])) {
        result.write(_toTail(phoneme));
      } else if ('MN'.contains(previous)) {
        result.write(_toLead(phoneme));
      } else if (_vowels.contains(next[0])) {
        result.write('ᆯᄅ');
      } else if ('MN'.contains(next) && !_vowels.contains(next2[0])) {
        result.write('ᆯ르');
      }
    } else if (phoneme == 'ER') {
      if (_vowels.contains(previous[0])) {
        result.write('ᄋ');
      }
      result.write(_toVowel(phoneme));
      if (_vowels.contains(next[0])) {
        result.write('ᄅ');
      }
    } else if (phoneme == 'R') {
      if (_vowels.contains(next[0])) {
        result.write(_toLead(phoneme));
      }
    } else if (_vowels.contains(phoneme[0])) {
      result.write(_toVowel(phoneme));
    } else {
      result.write(_toLead(phoneme));
    }
  }

  var reconstructed = result.toString();
  for (final (source, replacement) in _reconstructionPairs) {
    reconstructed = reconstructed.replaceAll(source, replacement);
  }
  final composed = composeKoreanJamo(reconstructed);
  return String.fromCharCodes(
    composed.runes.where((scalar) => scalar < 0x1100 || scalar > 0x11FF),
  );
}

List<String> _adjustArpabet(List<String> arpabet) {
  var joined = ' ${arpabet.join(' ')} ${r'$'}';
  joined = joined.replaceAll(RegExp('[0-9]'), '');
  joined = joined
      .replaceAll(' T S ', ' TS ')
      .replaceAll(' D Z ', ' DZ ')
      .replaceAll(' AW ER ', ' AWER ')
      .replaceAll(' IH R ${r'$'}', ' IH ER ')
      .replaceAll(' EH R ${r'$'}', ' EH ER ')
      .replaceAll(' ${r'$'}', '');
  final adjusted = joined.trim().split(RegExp(r'\s+'));
  return adjusted.length == 1 && adjusted.single.isEmpty
      ? const <String>[]
      : adjusted;
}

String _takeTwo(String value) =>
    value.length < 2 ? value : value.substring(0, 2);

String _toLead(String phoneme) => _leadByArpabet[phoneme] ?? phoneme;
String _toVowel(String phoneme) => _vowelByArpabet[phoneme] ?? phoneme;
String _toTail(String phoneme) => _tailByArpabet[phoneme] ?? phoneme;

final RegExp _englishWords = RegExp(r'[A-Za-z]+');

const String _vowels = 'AEIOUY';
const String _consonants = 'BCDFGHJKLMNPQRSTVWXZ';
const String _vowelsAndLiquids = 'AEIOULRMN';
const String _finalOrConsonants = r'$BCDFGHJKLMNPQRSTVWXYZ';
const String _syllableFinalOrConsonants = r'$BCDFGHJKLMNPQRSTVWXZ';
const String _lFinalOrConsonants = r'$BCDFGHJKLPQRSTVWXZ';
const Set<String> _shortVowels = <String>{
  'AE',
  'AH',
  'AX',
  'EH',
  'IH',
  'IX',
  'UH',
};
const Set<String> _fricatives = <String>{
  'S',
  'Z',
  'F',
  'V',
  'TH',
  'DH',
  'SH',
  'ZH',
};
const Set<String> _simpleFricatives = <String>{'S', 'Z', 'F', 'V', 'TH', 'DH'};
const Set<String> _affricates = <String>{'TS', 'DZ', 'CH', 'JH'};
const Set<String> _dentalAffricates = <String>{'TS', 'DZ'};
const Set<String> _nasals = <String>{'M', 'N', 'NG'};

const Map<String, String> _englishLetterNames = <String, String>{
  'A': '에이',
  'B': '비',
  'C': '씨',
  'D': '디',
  'E': '이',
  'F': '에프',
  'G': '지',
  'H': '에이치',
  'I': '아이',
  'J': '제이',
  'K': '케이',
  'L': '엘',
  'M': '엠',
  'N': '엔',
  'O': '오',
  'P': '피',
  'Q': '큐',
  'R': '알',
  'S': '에스',
  'T': '티',
  'U': '유',
  'V': '브이',
  'W': '더블유',
  'X': '엑스',
  'Y': '와이',
  'Z': '지',
};

const Map<String, String> _leadByArpabet = <String, String>{
  'B': 'ᄇ',
  'CH': 'ᄎ',
  'D': 'ᄃ',
  'DH': 'ᄃ',
  'DZ': 'ᄌ',
  'F': 'ᄑ',
  'G': 'ᄀ',
  'HH': 'ᄒ',
  'JH': 'ᄌ',
  'K': 'ᄏ',
  'L': 'ᄅ',
  'M': 'ᄆ',
  'N': 'ᄂ',
  'NG': 'ᄋ',
  'P': 'ᄑ',
  'R': 'ᄅ',
  'S': 'ᄉ',
  'SH': 'ᄉ',
  'T': 'ᄐ',
  'TH': 'ᄉ',
  'TS': 'ᄎ',
  'V': 'ᄇ',
  'W': 'W',
  'Y': 'Y',
  'Z': 'ᄌ',
  'ZH': 'ᄌ',
};

const Map<String, String> _vowelByArpabet = <String, String>{
  'AA': 'ᅡ',
  'AE': 'ᅢ',
  'AH': 'ᅥ',
  'AO': 'ᅩ',
  'AW': 'ᅡ우',
  'AWER': 'ᅡ워',
  'AY': 'ᅡ이',
  'EH': 'ᅦ',
  'ER': 'ᅥ',
  'EY': 'ᅦ이',
  'IH': 'ᅵ',
  'IY': 'ᅵ',
  'OW': 'ᅩ',
  'OY': 'ᅩ이',
  'UH': 'ᅮ',
  'UW': 'ᅮ',
};

const Map<String, String> _tailByArpabet = <String, String>{
  'B': 'ᆸ',
  'CH': 'ᆾ',
  'D': 'ᆮ',
  'DH': 'ᆮ',
  'F': 'ᇁ',
  'G': 'ᆨ',
  'HH': 'ᇂ',
  'JH': 'ᆽ',
  'K': 'ᆨ',
  'L': 'ᆯ',
  'M': 'ᆷ',
  'N': 'ᆫ',
  'NG': 'ᆼ',
  'P': 'ᆸ',
  'R': 'ᆯ',
  'S': 'ᆺ',
  'SH': 'ᆺ',
  'T': 'ᆺ',
  'TH': 'ᆺ',
  'V': 'ᆸ',
  'W': 'ᆼ',
  'Y': 'ᆼ',
  'Z': 'ᆽ',
  'ZH': 'ᆽ',
};

const List<(String, String)> _reconstructionPairs = <(String, String)>[
  ('그W', 'ᄀW'),
  ('흐W', 'ᄒW'),
  ('크W', 'ᄏW'),
  ('ᄂYᅥ', '니어'),
  ('ᄃYᅥ', '디어'),
  ('ᄅYᅥ', '리어'),
  ('Yᅵ', 'ᅵ'),
  ('Yᅡ', 'ᅣ'),
  ('Yᅢ', 'ᅤ'),
  ('Yᅥ', 'ᅧ'),
  ('Yᅦ', 'ᅨ'),
  ('Yᅩ', 'ᅭ'),
  ('Yᅮ', 'ᅲ'),
  ('Wᅡ', 'ᅪ'),
  ('Wᅢ', 'ᅫ'),
  ('Wᅥ', 'ᅯ'),
  ('Wᅩ', 'ᅯ'),
  ('Wᅮ', 'ᅮ'),
  ('Wᅦ', 'ᅰ'),
  ('Wᅵ', 'ᅱ'),
  ('ᅳᅵ', 'ᅴ'),
  ('Y', 'ᅵ'),
  ('W', 'ᅮ'),
];
