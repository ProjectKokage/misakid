// Exact string-ID primitives used by spaCy 3.8.4.
//
// MurmurHash64A is public-domain code by Austin Appleby. This Dart expression
// of the algorithm operates on UTF-8 bytes and uses spaCy's fixed seed 1.

import 'dart:convert';

/// Computes spaCy's unsigned `hash_string` result as signed 64-bit Dart bits.
///
/// spaCy hashes UTF-8 with MurmurHash64A and seed `1`. Values whose high bit is
/// set are negative in Dart so every possible `uint64` remains representable.
int spacyHashString(String value) => _murmurHash64A(utf8.encode(value), 1);

/// Returns the ID assigned by spaCy 3.8.4's `StringStore`.
///
/// Reserved symbol spellings use their small enum IDs; all other non-empty
/// strings use [spacyHashString].
int spacyStringId(String value) {
  if (value.isEmpty) {
    return 0;
  }
  final fixed = _fixedSymbolIds[value];
  if (fixed != null) {
    return fixed;
  }
  if (value.length == 6 && value.startsWith('FLAG')) {
    final number = int.tryParse(value.substring(4));
    if (number != null && number >= 19 && number <= 63) {
      return number;
    }
  }
  if (value.length == 13 && value.startsWith('DEPRECATED')) {
    final number = int.tryParse(value.substring(10));
    if (number != null && number >= 1 && number <= 276) {
      return 103 + number;
    }
  }
  return spacyHashString(value);
}

int _murmurHash64A(List<int> bytes, int seed) {
  final length = bytes.length;
  var hash =
      (BigInt.from(seed) ^ (BigInt.from(length) * _murmurMultiplier)) &
      _uint64Mask;
  var offset = 0;
  while (offset + 8 <= length) {
    var block = BigInt.zero;
    for (var index = 0; index < 8; index++) {
      block |= BigInt.from(bytes[offset + index]) << (index * 8);
    }
    block = (block * _murmurMultiplier) & _uint64Mask;
    block ^= block >> 47;
    block = (block * _murmurMultiplier) & _uint64Mask;
    hash ^= block;
    hash = (hash * _murmurMultiplier) & _uint64Mask;
    offset += 8;
  }

  final remaining = length - offset;
  for (var index = 0; index < remaining; index++) {
    hash ^= BigInt.from(bytes[offset + index]) << (index * 8);
  }
  if (remaining != 0) {
    hash = (hash * _murmurMultiplier) & _uint64Mask;
  }
  hash ^= hash >> 47;
  hash = (hash * _murmurMultiplier) & _uint64Mask;
  hash ^= hash >> 47;
  hash &= _uint64Mask;
  if ((hash & _uint64SignBit) != BigInt.zero) {
    hash -= _uint64Modulus;
  }
  return hash.toInt();
}

final BigInt _murmurMultiplier = BigInt.parse('c6a4a7935bd1e995', radix: 16);
final BigInt _uint64Modulus = BigInt.one << 64;
final BigInt _uint64Mask = _uint64Modulus - BigInt.one;
final BigInt _uint64SignBit = BigInt.one << 63;

// Compact transcription of spaCy 3.8.4's symbols.pyx. FLAG19..FLAG63 and
// DEPRECATED001..DEPRECATED276 are recognized algorithmically above.
const Map<String, int> _fixedSymbolIds = <String, int>{
  'IS_ALPHA': 1,
  'IS_ASCII': 2,
  'IS_DIGIT': 3,
  'IS_LOWER': 4,
  'IS_PUNCT': 5,
  'IS_SPACE': 6,
  'IS_TITLE': 7,
  'IS_UPPER': 8,
  'LIKE_URL': 9,
  'LIKE_NUM': 10,
  'LIKE_EMAIL': 11,
  'IS_STOP': 12,
  'IS_OOV_DEPRECATED': 13,
  'IS_BRACKET': 14,
  'IS_QUOTE': 15,
  'IS_LEFT_PUNCT': 16,
  'IS_RIGHT_PUNCT': 17,
  'IS_CURRENCY': 18,
  'ID': 64,
  'ORTH': 65,
  'LOWER': 66,
  'NORM': 67,
  'SHAPE': 68,
  'PREFIX': 69,
  'SUFFIX': 70,
  'LENGTH': 71,
  'CLUSTER': 72,
  'LEMMA': 73,
  'POS': 74,
  'TAG': 75,
  'DEP': 76,
  'ENT_IOB': 77,
  'ENT_TYPE': 78,
  'HEAD': 79,
  'SENT_START': 80,
  'SPACY': 81,
  'PROB': 82,
  'LANG': 83,
  'ADJ': 84,
  'ADP': 85,
  'ADV': 86,
  'AUX': 87,
  'CONJ': 88,
  'CCONJ': 89,
  'DET': 90,
  'INTJ': 91,
  'NOUN': 92,
  'NUM': 93,
  'PART': 94,
  'PRON': 95,
  'PROPN': 96,
  'PUNCT': 97,
  'SCONJ': 98,
  'SYM': 99,
  'VERB': 100,
  'X': 101,
  'EOL': 102,
  'SPACE': 103,
  'PERSON': 380,
  'NORP': 381,
  'FACILITY': 382,
  'ORG': 383,
  'GPE': 384,
  'LOC': 385,
  'PRODUCT': 386,
  'EVENT': 387,
  'WORK_OF_ART': 388,
  'LANGUAGE': 389,
  'LAW': 390,
  'DATE': 391,
  'TIME': 392,
  'PERCENT': 393,
  'MONEY': 394,
  'QUANTITY': 395,
  'ORDINAL': 396,
  'CARDINAL': 397,
  'acomp': 398,
  'advcl': 399,
  'advmod': 400,
  'agent': 401,
  'amod': 402,
  'appos': 403,
  'attr': 404,
  'aux': 405,
  'auxpass': 406,
  'cc': 407,
  'ccomp': 408,
  'complm': 409,
  'conj': 410,
  'cop': 411,
  'csubj': 412,
  'csubjpass': 413,
  'dep': 414,
  'det': 415,
  'dobj': 416,
  'expl': 417,
  'hmod': 418,
  'hyph': 419,
  'infmod': 420,
  'intj': 421,
  'iobj': 422,
  'mark': 423,
  'meta': 424,
  'neg': 425,
  'nmod': 426,
  'nn': 427,
  'npadvmod': 428,
  'nsubj': 429,
  'nsubjpass': 430,
  'num': 431,
  'number': 432,
  'oprd': 433,
  'obj': 434,
  'obl': 435,
  'parataxis': 436,
  'partmod': 437,
  'pcomp': 438,
  'pobj': 439,
  'poss': 440,
  'possessive': 441,
  'preconj': 442,
  'prep': 443,
  'prt': 444,
  'punct': 445,
  'quantmod': 446,
  'relcl': 447,
  'rcmod': 448,
  'root': 449,
  'xcomp': 450,
  'acl': 451,
  'ENT_KB_ID': 452,
  'MORPH': 453,
  'ENT_ID': 454,
  'IDX': 455,
  '_': 456,
};
