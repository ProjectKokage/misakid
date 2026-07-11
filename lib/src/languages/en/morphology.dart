// Dart adaptation of the pure suffix rules in hexgrad/misaki/misaki/en.py at
// fba1236595f2d2bf21d414ba6e57d25256afada3 (Misaki 0.9.4,
// Apache-2.0).
//
// Modifications: extracted the phoneme-only rules from the Python lexicon into
// an immutable, typed stage that does not load dictionaries or NLP backends.

/// English pronunciation dialect selected for dialect-sensitive suffixes.
enum EnglishDialect {
  /// American English.
  american,

  /// British English.
  british,
}

/// Pure phoneme transformations for English inflectional suffixes.
final class EnglishInflectionRules {
  /// Creates suffix rules for [dialect].
  const EnglishInflectionRules(this.dialect);

  /// Selected English dialect.
  final EnglishDialect dialect;

  bool get _isBritish => dialect == EnglishDialect.british;

  /// Appends the pronunciation of plural or possessive `s`.
  String? appendS(String? stem) {
    if (stem == null || stem.isEmpty) {
      return null;
    }
    final last = _lastScalar(stem);
    if (_voicelessPluralEnds.contains(last)) {
      return '${stem}s';
    }
    if (_sibilantEnds.contains(last)) {
      return '$stem${_isBritish ? 'ɪ' : 'ᵻ'}z';
    }
    return '${stem}z';
  }

  /// Appends the pronunciation of past-tense `ed`.
  String? appendEd(String? stem) {
    if (stem == null || stem.isEmpty) {
      return null;
    }
    final characters = _scalars(stem);
    final last = characters.last;
    if (_voicelessPastEnds.contains(last)) {
      return '${stem}t';
    }
    if (last == 'd') {
      return '$stem${_isBritish ? 'ɪ' : 'ᵻ'}d';
    }
    if (last != 't') {
      return '${stem}d';
    }
    if (_isBritish || characters.length < 2) {
      return '$stemɪd';
    }
    if (_americanFlapPredecessors.contains(characters[characters.length - 2])) {
      return '${characters.take(characters.length - 1).join()}ɾᵻd';
    }
    return '$stemᵻd';
  }

  /// Appends the pronunciation of present-participle `ing`.
  String? appendIng(String? stem) {
    if (stem == null || stem.isEmpty) {
      return null;
    }
    final characters = _scalars(stem);
    final last = characters.last;
    if (_isBritish && (last == 'ə' || last == 'ː')) {
      return null;
    }
    if (!_isBritish &&
        characters.length > 1 &&
        last == 't' &&
        _americanFlapPredecessors.contains(characters[characters.length - 2])) {
      return '${characters.take(characters.length - 1).join()}ɾɪŋ';
    }
    return '$stemɪŋ';
  }
}

const Set<String> _voicelessPluralEnds = <String>{'p', 't', 'k', 'f', 'θ'};
const Set<String> _sibilantEnds = <String>{'s', 'z', 'ʃ', 'ʒ', 'ʧ', 'ʤ'};
const Set<String> _voicelessPastEnds = <String>{
  'p',
  'k',
  'f',
  'θ',
  'ʃ',
  's',
  'ʧ',
};
const Set<String> _americanFlapPredecessors = <String>{
  'A',
  'I',
  'O',
  'W',
  'Y',
  'i',
  'u',
  'æ',
  'ɑ',
  'ə',
  'ɛ',
  'ɪ',
  'ɹ',
  'ʊ',
  'ʌ',
};

String _lastScalar(String value) => String.fromCharCode(value.runes.last);

List<String> _scalars(String value) =>
    value.runes.map<String>(String.fromCharCode).toList(growable: false);
