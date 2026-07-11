// Dart adaptation of `Lexicon` in hexgrad/misaki/misaki/en.py at
// fba1236595f2d2bf21d414ba6e57d25256afada3 (Misaki 0.9.4,
// Apache-2.0).
//
// Modifications: uses immutable typed generated lexicons, clean-room number
// spelling, typed token metadata, and a pure-Dart Unicode normalizer. It never
// loads Python, spaCy, a model, or network resources.

import '../../core/backend.dart';
import '../../core/errors.dart';
import '../../core/metadata.dart';
import '../../core/python312_nfkc.dart';
import '../../core/python312_unicode.dart';
import '../../core/token.dart';
import 'backends.dart';
import 'context.dart';
import 'lexicon_data.dart';
import 'morphology.dart';
import 'number_speller.dart';
import 'phonology.dart';
import 'python_numeric.dart';

/// Offline pronunciation provider for the pinned Misaki English lexicons.
///
/// ```dart
/// const provider = PinnedEnglishLexicon();
/// final pronunciation = provider.lookup(
///   MisakiToken(
///     text: 'hello',
///     tag: 'NN',
///     whitespace: '',
///     metadata: EnglishTokenMetadata(isHead: true),
///   ),
///   const EnglishTokenContext(),
/// );
/// ```
///
/// Loading is offline and lazy per dialect. A tokenizer/tagger remains an
/// explicit injected boundary when this provider is used with the engine.
final class PinnedEnglishLexicon implements EnglishPronunciationBackend {
  /// Creates a provider for [dialect]. Lexicon JSON remains lazy per isolate.
  const PinnedEnglishLexicon({this.dialect = EnglishDialect.american});

  /// Selected American or British lexicon and morphology behavior.
  final EnglishDialect dialect;

  EnglishLexiconData get _data => loadEnglishLexiconData(dialect);

  EnglishInflectionRules get _inflections => EnglishInflectionRules(dialect);

  @override
  BackendInfo get info => BackendInfo(
    name: 'misaki-pinned-english-lexicon',
    version: '0.9.4',
    details: <String, String>{
      'upstreamCommit': 'fba1236595f2d2bf21d414ba6e57d25256afada3',
      'dialect': dialect.name,
      'numberBehavior': 'num2words-0.5.14-clean-room',
    },
  );

  @override
  EnglishPronunciation? lookup(MisakiToken token, EnglishTokenContext context) {
    final metadata = token.metadata;
    if (metadata is! EnglishTokenMetadata) {
      throw MalformedDataException(
        'Pinned English lexicon received ${metadata.runtimeType} metadata.',
      );
    }

    var word = metadata.alias ?? token.text;
    word = word.replaceAll('‘', "'").replaceAll('’', "'");
    word = mapPython312DigitsToAscii(normalizePython312Nfkc(word));
    final lower = python312Lower(word);
    final capitalizationStress = word == lower
        ? null
        : (word == word.toUpperCase() ? 2 : 0.5);

    final lexical = _getWord(word, token.tag, capitalizationStress, context);
    if (lexical != null) {
      final withCurrency = _appendCurrency(lexical.phonemes, metadata.currency);
      return EnglishPronunciation(
        phonemes: applyEnglishStress(withCurrency, metadata.stress),
        rating: lexical.rating,
      );
    }

    if (_isNumber(word, metadata.isHead)) {
      final number = _getNumber(
        word,
        currency: metadata.currency,
        isHead: metadata.isHead,
        numberFlags: metadata.numberFlags,
      );
      if (number == null) {
        return null;
      }
      return EnglishPronunciation(
        phonemes: applyEnglishStress(number.phonemes, metadata.stress),
        rating: number.rating,
      );
    }

    if (!_allLexiconCodePoints(word)) {
      return null;
    }
    return null;
  }

  EnglishPronunciation? _getNnp(String word) {
    final phonemes = StringBuffer();
    for (final scalar in word.runes) {
      if (!isPython312AlphabeticScalar(scalar)) {
        continue;
      }
      final entry = _data.gold(String.fromCharCode(scalar).toUpperCase());
      if (entry is! EnglishSimpleLexiconEntry) {
        return null;
      }
      phonemes.write(entry.phonemes);
    }
    var result = applyEnglishStress(phonemes.toString(), 0);
    final lastSecondary = result.lastIndexOf(englishSecondaryStress);
    if (lastSecondary >= 0) {
      result =
          '${result.substring(0, lastSecondary)}$englishPrimaryStress'
          '${result.substring(lastSecondary + englishSecondaryStress.length)}';
    }
    return EnglishPronunciation(phonemes: result, rating: 3);
  }

  EnglishPronunciation? _getSpecialCase(
    String word,
    String? tag,
    num? stress,
    EnglishTokenContext context,
  ) {
    if (tag == 'ADD' && _additionalSymbols.containsKey(word)) {
      return _lookupRaw(_additionalSymbols[word]!, null, -0.5, context);
    }
    if (_symbols.containsKey(word)) {
      return _lookupRaw(_symbols[word]!, null, null, context);
    }
    if (_isDottedInitialism(word)) {
      return _getNnp(word);
    }
    if (word == 'a' || word == 'A') {
      return EnglishPronunciation(
        phonemes: tag == 'DT' ? 'ɐ' : 'ˈA',
        rating: 4,
      );
    }
    if (word == 'am' || word == 'Am' || word == 'AM') {
      if (tag?.startsWith('NN') ?? false) {
        return _getNnp(word);
      }
      if (context.futureVowel == null || word != 'am' || (stress ?? 0) > 0) {
        return EnglishPronunciation(
          phonemes: _requiredGoldSimple('am'),
          rating: 4,
        );
      }
      return const EnglishPronunciation(phonemes: 'ɐm', rating: 4);
    }
    if (word == 'an' || word == 'An' || word == 'AN') {
      if (word == 'AN' && (tag?.startsWith('NN') ?? false)) {
        return _getNnp(word);
      }
      return const EnglishPronunciation(phonemes: 'ɐn', rating: 4);
    }
    if (word == 'I' && tag == 'PRP') {
      return const EnglishPronunciation(phonemes: 'ˌI', rating: 4);
    }
    if ((word == 'by' || word == 'By' || word == 'BY') &&
        _parentTag(tag) == 'ADV') {
      return const EnglishPronunciation(phonemes: 'bˈI', rating: 4);
    }
    if (word == 'to' ||
        word == 'To' ||
        (word == 'TO' && (tag == 'TO' || tag == 'IN'))) {
      return EnglishPronunciation(
        phonemes: switch (context.futureVowel) {
          null => _requiredGoldSimple('to'),
          false => 'tə',
          true => 'tʊ',
        },
        rating: 4,
      );
    }
    if (word == 'in' || word == 'In' || (word == 'IN' && tag != 'NNP')) {
      final prefix = context.futureVowel == null || tag != 'IN' ? 'ˈ' : '';
      return EnglishPronunciation(phonemes: '$prefixɪn', rating: 4);
    }
    if (word == 'the' || word == 'The' || (word == 'THE' && tag == 'DT')) {
      return EnglishPronunciation(
        phonemes: context.futureVowel == true ? 'ði' : 'ðə',
        rating: 4,
      );
    }
    if (tag == 'IN' && _isVersusAbbreviation(word)) {
      return _lookupRaw('versus', null, null, context);
    }
    if (word == 'used' || word == 'Used' || word == 'USED') {
      final entry = _data.gold('used');
      if (entry is! EnglishContextualLexiconEntry) {
        throw const MalformedDataException(
          'Pinned English gold entry `used` must be contextual.',
        );
      }
      final key = (tag == 'VBD' || tag == 'JJ') && context.futureTo
          ? 'VBD'
          : 'DEFAULT';
      final phonemes = entry.variants[key];
      return phonemes == null
          ? null
          : EnglishPronunciation(phonemes: phonemes, rating: 4);
    }
    return null;
  }

  EnglishPronunciation? _lookupRaw(
    String sourceWord,
    String? tag,
    num? stress,
    EnglishTokenContext? context,
  ) {
    var word = sourceWord;
    var isNnp = false;
    if (word == word.toUpperCase() && _data.gold(word) == null) {
      word = python312Lower(word);
      isNnp = tag == 'NNP';
    }

    EnglishLexiconEntry? entry = _data.gold(word);
    var rating = 4;
    if (entry == null && !isNnp) {
      entry = _data.silver(word);
      rating = 3;
    }
    String? phonemes;
    switch (entry) {
      case EnglishSimpleLexiconEntry(phonemes: final value):
        phonemes = value;
      case EnglishContextualLexiconEntry(:final variants):
        String? selectedTag = tag;
        if (context?.futureVowel == null &&
            context != null &&
            variants.containsKey('None')) {
          selectedTag = 'None';
        } else if (!variants.containsKey(selectedTag)) {
          selectedTag = _parentTag(selectedTag);
        }
        phonemes = variants.containsKey(selectedTag)
            ? variants[selectedTag]
            : variants['DEFAULT'];
      case null:
        phonemes = null;
    }

    if (phonemes == null ||
        (isNnp && !phonemes.contains(englishPrimaryStress))) {
      final nnp = _getNnp(word);
      if (nnp != null) {
        return nnp;
      }
    }
    return phonemes == null
        ? null
        : EnglishPronunciation(
            phonemes: applyEnglishStress(phonemes, stress),
            rating: rating,
          );
  }

  EnglishPronunciation? _getWord(
    String sourceWord,
    String? tag,
    num? stress,
    EnglishTokenContext context,
  ) {
    final special = _getSpecialCase(sourceWord, tag, stress, context);
    if (special != null) {
      return special;
    }
    var word = sourceWord;
    final lower = python312Lower(word);
    if (_scalarLength(word) > 1 &&
        _isPythonAlphabetic(word.replaceAll("'", '')) &&
        word != lower &&
        (tag != 'NNP' || _scalarLength(word) > 7) &&
        _data.gold(word) == null &&
        _data.silver(word) == null &&
        (word == word.toUpperCase() ||
            _dropFirstScalar(word) == python312Lower(_dropFirstScalar(word))) &&
        (_data.gold(lower) != null ||
            _data.silver(lower) != null ||
            _stemS(lower, tag, stress, context) != null ||
            _stemEd(lower, tag, stress, context) != null ||
            _stemIng(lower, tag, stress, context) != null)) {
      word = lower;
    }

    if (_isKnown(word)) {
      return _lookupRaw(word, tag, stress, context);
    }
    if (word.endsWith("s'") &&
        _isKnown('${word.substring(0, word.length - 2)}\'s')) {
      return _lookupRaw(
        '${word.substring(0, word.length - 2)}\'s',
        tag,
        stress,
        context,
      );
    }
    if (word.endsWith("'") && _isKnown(word.substring(0, word.length - 1))) {
      return _lookupRaw(
        word.substring(0, word.length - 1),
        tag,
        stress,
        context,
      );
    }
    return _stemS(word, tag, stress, context) ??
        _stemEd(word, tag, stress, context) ??
        _stemIng(word, tag, stress ?? 0.5, context);
  }

  bool _isKnown(String word) {
    if (_data.gold(word) != null ||
        _symbols.containsKey(word) ||
        _data.silver(word) != null) {
      return true;
    }
    if (!_isPythonAlphabetic(word) || !_allLexiconCodePoints(word)) {
      return false;
    }
    if (_scalarLength(word) == 1) {
      return true;
    }
    if (word == word.toUpperCase() &&
        _data.gold(python312Lower(word)) != null) {
      return true;
    }
    final tail = _dropFirstScalar(word);
    return tail == tail.toUpperCase();
  }

  EnglishPronunciation? _stemS(
    String word,
    String? tag,
    num? stress,
    EnglishTokenContext? context,
  ) {
    if (_scalarLength(word) < 3 || !word.endsWith('s')) {
      return null;
    }
    String? stem;
    if (!word.endsWith('ss') && _isKnown(word.substring(0, word.length - 1))) {
      stem = word.substring(0, word.length - 1);
    } else if ((word.endsWith("'s") ||
            (_scalarLength(word) > 4 &&
                word.endsWith('es') &&
                !word.endsWith('ies'))) &&
        _isKnown(word.substring(0, word.length - 2))) {
      stem = word.substring(0, word.length - 2);
    } else if (_scalarLength(word) > 4 && word.endsWith('ies')) {
      final candidate = '${word.substring(0, word.length - 3)}y';
      if (_isKnown(candidate)) {
        stem = candidate;
      }
    }
    if (stem == null) {
      return null;
    }
    final found = _lookupRaw(stem, tag, stress, context);
    final phonemes = _inflections.appendS(found?.phonemes);
    return phonemes == null
        ? null
        : EnglishPronunciation(phonemes: phonemes, rating: found?.rating);
  }

  EnglishPronunciation? _stemEd(
    String word,
    String? tag,
    num? stress,
    EnglishTokenContext? context,
  ) {
    if (_scalarLength(word) < 4 || !word.endsWith('d')) {
      return null;
    }
    String? stem;
    if (!word.endsWith('dd') && _isKnown(word.substring(0, word.length - 1))) {
      stem = word.substring(0, word.length - 1);
    } else if (_scalarLength(word) > 4 &&
        word.endsWith('ed') &&
        !word.endsWith('eed') &&
        _isKnown(word.substring(0, word.length - 2))) {
      stem = word.substring(0, word.length - 2);
    }
    if (stem == null) {
      return null;
    }
    final found = _lookupRaw(stem, tag, stress, context);
    final phonemes = _inflections.appendEd(found?.phonemes);
    return phonemes == null
        ? null
        : EnglishPronunciation(phonemes: phonemes, rating: found?.rating);
  }

  EnglishPronunciation? _stemIng(
    String word,
    String? tag,
    num? stress,
    EnglishTokenContext? context,
  ) {
    if (_scalarLength(word) < 5 || !word.endsWith('ing')) {
      return null;
    }
    String? stem;
    if (_scalarLength(word) > 5 &&
        _isKnown(word.substring(0, word.length - 3))) {
      stem = word.substring(0, word.length - 3);
    } else {
      final withE = '${word.substring(0, word.length - 3)}e';
      if (_isKnown(withE)) {
        stem = withE;
      } else if (_scalarLength(word) > 5 &&
          _doubledIng.hasMatch(word) &&
          _isKnown(word.substring(0, word.length - 4))) {
        stem = word.substring(0, word.length - 4);
      }
    }
    if (stem == null) {
      return null;
    }
    final found = _lookupRaw(stem, tag, stress, context);
    final phonemes = _inflections.appendIng(found?.phonemes);
    return phonemes == null
        ? null
        : EnglishPronunciation(phonemes: phonemes, rating: found?.rating);
  }

  EnglishPronunciation? _getNumber(
    String sourceWord, {
    required String? currency,
    required bool isHead,
    required String numberFlags,
  }) {
    var word = sourceWord;
    final suffixMatch = _numberSuffix.firstMatch(word);
    final suffix = suffixMatch?.group(0);
    if (suffix != null) {
      word = word.substring(0, word.length - suffix.length);
    }
    final parts = <_RatedPart>[];
    if (word.startsWith('-')) {
      parts.add(_requiredLookup('minus'));
      word = word.substring(1);
    }

    void extendWords(List<String> words, {bool first = true}) {
      for (var index = 0; index < words.length; index++) {
        final item = words[index];
        if (item != 'and' || numberFlags.contains('&')) {
          if (first &&
              index == 0 &&
              words.length > 1 &&
              item == 'one' &&
              numberFlags.contains('a')) {
            parts.add(const _RatedPart('ə', 4));
          } else {
            parts.add(
              _requiredLookup(item, stress: item == 'point' ? -2 : null),
            );
          }
        } else if (numberFlags.contains('n') && parts.isNotEmpty) {
          final previous = parts.removeLast();
          parts.add(_RatedPart('${previous.phonemes}ən', previous.rating));
        }
      }
    }

    void extendInteger(String digits, {bool first = true}) => extendWords(
      _numberSpeller.cardinal(BigInt.parse(digits)),
      first: first,
    );

    if (_isAsciiDigits(word) && _ordinals.contains(suffix)) {
      extendWords(_numberSpeller.ordinal(BigInt.parse(word)));
    } else if (parts.isEmpty &&
        word.length == 4 &&
        !_currencies.containsKey(currency) &&
        _isAsciiDigits(word)) {
      extendWords(_numberSpeller.year(BigInt.parse(word)));
    } else if (!isHead && !word.contains('.')) {
      final number = word.replaceAll(',', '');
      if (number.startsWith('0') || number.length > 3) {
        for (final scalar in number.runes) {
          extendInteger(String.fromCharCode(scalar), first: false);
        }
      } else if (number.length == 3 && !number.endsWith('00')) {
        extendInteger(number[0]);
        if (number[1] == '0') {
          parts.add(_requiredLookup('O', stress: -2));
          extendInteger(number[2], first: false);
        } else {
          extendInteger(number.substring(1), first: false);
        }
      } else {
        extendInteger(number);
      }
    } else if (_countScalar(word, 0x2e) > 1 || !isHead) {
      var first = true;
      for (final number in word.replaceAll(',', '').split('.')) {
        if (number.isNotEmpty) {
          if (number.startsWith('0') ||
              (number.length != 2 &&
                  number.substring(1).runes.any((scalar) => scalar != 0x30))) {
            for (final scalar in number.runes) {
              extendInteger(String.fromCharCode(scalar), first: false);
            }
          } else {
            extendInteger(number, first: first);
          }
        }
        first = false;
      }
    } else if (_currencies.containsKey(currency) && _isCurrencyNumber(word)) {
      final units = _currencies[currency]!;
      var pairs = <(BigInt, String)>[];
      final numbers = word.replaceAll(',', '').split('.');
      for (
        var index = 0;
        index < numbers.length && index < units.length;
        index++
      ) {
        pairs.add((
          numbers[index].isEmpty ? BigInt.zero : BigInt.parse(numbers[index]),
          units[index],
        ));
      }
      if (pairs.length > 1) {
        if (pairs[1].$1 == BigInt.zero) {
          pairs = pairs.sublist(0, 1);
        } else if (pairs[0].$1 == BigInt.zero) {
          pairs = pairs.sublist(1);
        }
      }
      for (var index = 0; index < pairs.length; index++) {
        final (number, unit) = pairs[index];
        if (index > 0) {
          parts.add(_requiredLookup('and'));
        }
        extendWords(_numberSpeller.cardinal(number), first: index == 0);
        if (number.abs() != BigInt.one && unit != 'pence') {
          final plural = _stemS('${unit}s', null, null, null);
          if (plural == null) {
            return null;
          }
          parts.add(_RatedPart(plural.phonemes, plural.rating ?? 4));
        } else {
          parts.add(_requiredLookup(unit));
        }
      }
    } else {
      List<String> words;
      if (_isAsciiDigits(word)) {
        words = _numberSpeller.cardinal(BigInt.parse(word));
      } else if (!word.contains('.')) {
        final integer = BigInt.parse(word.replaceAll(',', ''));
        words = _ordinals.contains(suffix)
            ? _numberSpeller.ordinal(integer)
            : _numberSpeller.cardinal(integer);
      } else {
        final normalized = word.replaceAll(',', '');
        if (normalized.startsWith('.')) {
          words = <String>[
            'point',
            for (final scalar in normalized.substring(1).runes)
              ..._numberSpeller.cardinal(BigInt.from(scalar - 0x30)),
          ];
        } else {
          words = _numberSpeller.decimal(normalized);
        }
      }
      extendWords(words);
    }

    if (parts.isEmpty) {
      return null;
    }
    final phonemes = parts.map((part) => part.phonemes).join(' ');
    final rating = parts
        .map((part) => part.rating)
        .reduce((left, right) => left < right ? left : right);
    final suffixed = switch (suffix) {
      's' || "'s" => _inflections.appendS(phonemes),
      'ed' || "'d" => _inflections.appendEd(phonemes),
      'ing' => _inflections.appendIng(phonemes),
      _ => phonemes,
    };
    return suffixed == null
        ? null
        : EnglishPronunciation(phonemes: suffixed, rating: rating);
  }

  String _appendCurrency(String phonemes, String? currencySymbol) {
    final units = _currencies[currencySymbol];
    if (units == null) {
      return phonemes;
    }
    final currency = _stemS('${units.first}s', null, null, null)?.phonemes;
    return currency == null ? phonemes : '$phonemes $currency';
  }

  _RatedPart _requiredLookup(String word, {num? stress}) {
    final result = _lookupRaw(word, null, stress, null);
    if (result == null || result.rating == null) {
      throw MalformedDataException(
        'Pinned English lexicon is missing required number word `$word`.',
      );
    }
    return _RatedPart(result.phonemes, result.rating!);
  }

  String _requiredGoldSimple(String word) {
    final entry = _data.gold(word);
    if (entry is! EnglishSimpleLexiconEntry) {
      throw MalformedDataException(
        'Pinned English gold entry `$word` must be a simple pronunciation.',
      );
    }
    return entry.phonemes;
  }
}

const EnglishNumberSpeller _numberSpeller = EnglishNumberSpeller();

final class _RatedPart {
  const _RatedPart(this.phonemes, this.rating);

  final String phonemes;
  final int rating;
}

String? _parentTag(String? tag) {
  if (tag == null) {
    return null;
  }
  if (tag.startsWith('VB')) {
    return 'VERB';
  }
  if (tag.startsWith('NN')) {
    return 'NOUN';
  }
  if (tag.startsWith('ADV') || tag.startsWith('RB')) {
    return 'ADV';
  }
  if (tag.startsWith('ADJ') || tag.startsWith('JJ')) {
    return 'ADJ';
  }
  return tag;
}

bool _isDottedInitialism(String word) {
  final stripped = word
      .replaceFirst(RegExp(r'^\.+'), '')
      .replaceFirst(RegExp(r'\.+$'), '');
  if (!stripped.contains('.') ||
      !_isPythonAlphabetic(word.replaceAll('.', ''))) {
    return false;
  }
  var longest = 0;
  for (final part in word.split('.')) {
    final length = _scalarLength(part);
    if (length > longest) {
      longest = length;
    }
  }
  return longest < 3;
}

bool _isVersusAbbreviation(String word) {
  final lower = python312Lower(word);
  return lower == 'vs' || lower == 'vs.';
}

bool _isPythonAlphabetic(String word) =>
    word.isNotEmpty && word.runes.every(isPython312AlphabeticScalar);

bool _allLexiconCodePoints(String word) => word.runes.every(
  (scalar) =>
      scalar == 0x27 ||
      scalar == 0x2d ||
      (scalar >= 0x41 && scalar <= 0x5a) ||
      (scalar >= 0x61 && scalar <= 0x7a),
);

String _dropFirstScalar(String value) {
  final scalars = value.runes.toList(growable: false);
  return String.fromCharCodes(scalars.skip(1));
}

int _scalarLength(String value) => value.runes.length;

bool _isAsciiDigits(String value) =>
    value.isNotEmpty &&
    value.runes.every((scalar) => scalar >= 0x30 && scalar <= 0x39);

int _countScalar(String value, int scalar) =>
    value.runes.where((candidate) => candidate == scalar).length;

bool _isCurrencyNumber(String word) {
  if (!word.contains('.')) {
    return true;
  }
  if (_countScalar(word, 0x2e) > 1) {
    return false;
  }
  // Pinned Python compares a set of string digits with the integer set {0},
  // so its second condition is never true. Only one- or two-digit cents pass.
  return word.split('.')[1].length < 3;
}

bool _isNumber(String sourceWord, bool isHead) {
  if (!sourceWord.runes.any((scalar) => scalar >= 0x30 && scalar <= 0x39)) {
    return false;
  }
  var word = sourceWord;
  for (final suffix in _numberSuffixes) {
    if (word.endsWith(suffix)) {
      word = word.substring(0, word.length - suffix.length);
      break;
    }
  }
  for (var index = 0; index < word.length; index++) {
    final unit = word.codeUnitAt(index);
    if ((unit >= 0x30 && unit <= 0x39) || unit == 0x2c || unit == 0x2e) {
      continue;
    }
    if (isHead && index == 0 && unit == 0x2d) {
      continue;
    }
    return false;
  }
  return true;
}

final RegExp _doubledIng = RegExp(r'([bcdgklmnprstvxz])\1ing$|cking$');
final RegExp _numberSuffix = RegExp(r"[a-z']+$");

const Set<String> _ordinals = <String>{'st', 'nd', 'rd', 'th'};
const List<String> _numberSuffixes = <String>[
  'ing',
  "'d",
  'ed',
  "'s",
  'st',
  'nd',
  'rd',
  'th',
  's',
];
const Map<String, String> _additionalSymbols = <String, String>{
  '.': 'dot',
  '/': 'slash',
};
const Map<String, String> _symbols = <String, String>{
  '%': 'percent',
  '&': 'and',
  '+': 'plus',
  '@': 'at',
};
const Map<String, List<String>> _currencies = <String, List<String>>{
  r'$': <String>['dollar', 'cent'],
  '£': <String>['pound', 'pence'],
  '€': <String>['euro', 'cent'],
};
