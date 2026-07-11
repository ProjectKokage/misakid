// Dart adaptation of TokenContext and G2P.token_context in
// hexgrad/misaki/misaki/en.py at
// fba1236595f2d2bf21d414ba6e57d25256afada3 (Misaki 0.9.4,
// Apache-2.0).

import '../../core/token.dart';

/// Right-to-left context used by the pinned English lexicon.
final class EnglishTokenContext {
  /// Creates English token context.
  const EnglishTokenContext({this.futureVowel, this.futureTo = false});

  /// Whether the next significant phoneme is a vowel, a consonant, or unknown.
  final bool? futureVowel;

  /// Whether the token immediately to the right is the context-sensitive `to`.
  final bool futureTo;
}

/// Advances right-to-left English context using [phonemes] and [token].
EnglishTokenContext updateEnglishTokenContext(
  EnglishTokenContext context,
  String? phonemes,
  MisakiToken token,
) {
  var futureVowel = context.futureVowel;
  if (phonemes != null && phonemes.isNotEmpty) {
    for (final codePoint in phonemes.runes) {
      final character = String.fromCharCode(codePoint);
      if (_nonQuotePunctuation.contains(character)) {
        futureVowel = null;
        break;
      }
      if (_vowels.contains(character)) {
        futureVowel = true;
        break;
      }
      if (_consonants.contains(character)) {
        futureVowel = false;
        break;
      }
    }
  }

  final word = token.text;
  final futureTo =
      word == 'to' ||
      word == 'To' ||
      (word == 'TO' && (token.tag == 'TO' || token.tag == 'IN'));
  return EnglishTokenContext(futureVowel: futureVowel, futureTo: futureTo);
}

const Set<String> _vowels = <String>{
  'A',
  'I',
  'O',
  'Q',
  'W',
  'Y',
  'a',
  'i',
  'u',
  'æ',
  'ɑ',
  'ɒ',
  'ɔ',
  'ə',
  'ɛ',
  'ɜ',
  'ɪ',
  'ʊ',
  'ʌ',
  'ᵻ',
};
const Set<String> _consonants = <String>{
  'b',
  'd',
  'f',
  'h',
  'j',
  'k',
  'l',
  'm',
  'n',
  'p',
  's',
  't',
  'v',
  'w',
  'z',
  'ð',
  'ŋ',
  'ɡ',
  'ɹ',
  'ɾ',
  'ʃ',
  'ʒ',
  'ʤ',
  'ʧ',
  'θ',
};
const Set<String> _nonQuotePunctuation = <String>{
  ';',
  ':',
  ',',
  '.',
  '!',
  '?',
  '—',
  '…',
};
