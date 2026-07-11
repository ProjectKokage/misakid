// Dart adaptation of hexgrad/misaki/misaki/g2pkc/numerals.py at
// fba1236595f2d2bf21d414ba6e57d25256afada3.
// Copied/adapted through 5Hyeons/StyleTTS2 from Kyubyong/g2pK under
// Apache-2.0. Modifications: typed pure-Dart implementation with explicit
// deterministic match collection.

import '../../core/errors.dart';
import '../../core/python312_unicode.dart';

/// Spells one comma-grouped decimal integer using pinned g2pkc number rules.
///
/// Upstream's Unicode `\d` matcher accepts every Unicode decimal digit, while
/// its digit-name tables intentionally contain ASCII keys only. That
/// observable mismatch is preserved here.
///
/// Pinned g2pkc defines positions 0 through 15. Input containing more than 16
/// comma-free digits throws [InvalidConfigurationException], preserving its
/// no-output failure boundary with an actionable typed package error. Empty
/// input, non-decimal characters, and misplaced non-comma separators throw the
/// same exception.
String spellKoreanNumber(String number, {bool sino = true}) {
  final digitsOnly = number.replaceAll(',', '');
  final digits = <String>[
    for (final scalar in digitsOnly.runes) String.fromCharCode(scalar),
  ];
  if (digits.isEmpty ||
      digitsOnly.runes.any((scalar) => !isPython312DecimalScalar(scalar))) {
    throw const InvalidConfigurationException(
      'A Korean number must contain at least one Unicode decimal digit and '
      'otherwise only commas.',
    );
  }
  if (digits.length > 16) {
    throw InvalidConfigurationException(
      'Pinned g2pkc leaves Korean numeral positions above 15 undefined; '
      'received ${digits.length} comma-free digits.',
    );
  }
  if (digitsOnly == '0') {
    return '영';
  }
  if (!sino && digitsOnly == '20') {
    return '스무';
  }

  final output = <String>[];
  for (var index = 0; index < digits.length; index++) {
    final digit = digits[index];
    final position = digits.length - index - 1;
    var name = '';
    if (sino || digits.length >= 3) {
      if (position == 0) {
        name = _sinoDigitNames[digit] ?? '';
      } else if (position == 1) {
        name = '${_sinoDigitNames[digit] ?? ''}십'.replaceFirst('일십', '십');
      }
    } else if (position == 0) {
      name = _nativeModifiers[digit] ?? '';
    } else if (position == 1) {
      name = _nativeTens[digit] ?? '';
    }

    if (digit == '0') {
      if (position % 4 == 0) {
        final start = output.length < 3 ? 0 : output.length - 3;
        if (output.sublist(start).join().isEmpty) {
          output.add('');
          continue;
        }
      } else {
        output.add('');
        continue;
      }
    }

    if (position == 2) {
      name = '${_sinoDigitNames[digit] ?? ''}백'.replaceFirst('일백', '백');
    } else if (position == 3) {
      name = '${_sinoDigitNames[digit] ?? ''}천'.replaceFirst('일천', '천');
    } else if (position == 4) {
      name = '${_sinoDigitNames[digit] ?? ''}만'.replaceFirst('일만', '만');
    } else if (position == 5) {
      name = '${_sinoDigitNames[digit] ?? ''}십'.replaceFirst('일십', '십');
    } else if (position == 6) {
      name = '${_sinoDigitNames[digit] ?? ''}백'.replaceFirst('일백', '백');
    } else if (position == 7) {
      name = '${_sinoDigitNames[digit] ?? ''}천'.replaceFirst('일천', '천');
    } else if (position == 8) {
      name = '${_sinoDigitNames[digit] ?? ''}억';
    } else if (position == 9) {
      name = '${_sinoDigitNames[digit] ?? ''}십';
    } else if (position == 10) {
      name = '${_sinoDigitNames[digit] ?? ''}백';
    } else if (position == 11) {
      name = '${_sinoDigitNames[digit] ?? ''}천';
    } else if (position == 12) {
      name = '${_sinoDigitNames[digit] ?? ''}조';
    } else if (position == 13) {
      name = '${_sinoDigitNames[digit] ?? ''}십';
    } else if (position == 14) {
      name = '${_sinoDigitNames[digit] ?? ''}백';
    } else if (position == 15) {
      name = '${_sinoDigitNames[digit] ?? ''}천';
    }
    output.add(name);
  }
  return output.join();
}

/// Converts all annotated numeral spans using pinned g2pkc semantics.
///
/// The returned intermediate text can contain `/B` morphology markers and
/// `^` rule blockers; `KoreanG2pkcEngine` consumes them in later stages.
String convertKoreanNumerals(String input) {
  var output = input;
  final tokens = <(String, String)>{};
  for (final match in _numberPattern.allMatches(output)) {
    tokens.add((match.group(1)!, match.group(2) ?? ''));
  }
  // Upstream converts `set(re.findall(...))` in iteration order. Replacement
  // is global, so that order is observable for overlapping bare numbers and
  // bound-noun spans. Fixture generation pins CPython 3.12 with
  // PYTHONHASHSEED=0; replay its tuple hashes and set-table iteration exactly.
  for (final (number, boundNoun) in _python312Seed0SetOrder(tokens)) {
    final noun = boundNoun.trimLeft();
    final spelled = spellKoreanNumber(
      number,
      sino: !_boundNouns.contains(noun),
    );
    output = output.replaceAll('$number$boundNoun', '$spelled$noun');
  }
  for (var index = 0; index < _digitNames.length; index++) {
    output = output.replaceAll('$index', '^${_digitNames[index]}');
  }
  return output.replaceAll('십^육', '심뉵').replaceAll('백^육', '뱅뉵');
}

final RegExp _numberPattern = RegExp(
  '($python312DecimalRegExpPattern'
  '(?:$python312DecimalRegExpPattern|,)*)( ?[가-힣]+)?(?:/B)?',
  unicode: true,
);

List<(String, String)> _python312Seed0SetOrder(
  Iterable<(String, String)> values,
) {
  final table = _Python312Seed0TupleSet();
  for (final value in values) {
    table.add(value);
  }
  return table.values;
}

/// Returns the signed CPython 3.12 seed-zero hash for [value].
///
/// This internal diagnostic is not exported by `misaki_ko.dart`; it exists so
/// the observable g2pkc numeral-order compatibility code can be vector-tested.
BigInt koreanNumeralPython312Seed0StringHash(String value) =>
    _signed64(_python312StringHash(value));

/// Returns the signed CPython 3.12 seed-zero tuple hash for [value].
///
/// This internal diagnostic is not exported by `misaki_ko.dart`.
BigInt koreanNumeralPython312Seed0TupleHash((String, String) value) =>
    _signed64(_python312TupleHash(value));

/// Returns CPython 3.12 seed-zero set iteration order for distinct [values].
///
/// This internal diagnostic is not exported by `misaki_ko.dart`.
List<(String, String)> koreanNumeralPython312Seed0SetOrder(
  Iterable<(String, String)> values,
) => _python312Seed0SetOrder(values);

final class _Python312Seed0TupleSet {
  List<(String, String)?> _entries = List<(String, String)?>.filled(
    _pythonSetMinimumSize,
    null,
  );
  List<BigInt> _hashes = List<BigInt>.filled(
    _pythonSetMinimumSize,
    BigInt.zero,
  );
  int _used = 0;

  List<(String, String)> get values => <(String, String)>[
    for (final entry in _entries) ?entry,
  ];

  void add((String, String) value) {
    final hash = _python312TupleHash(value);
    final mask = _entries.length - 1;
    var index = (hash & BigInt.from(mask)).toInt();
    var perturb = hash;

    while (true) {
      final initialIndex = index;
      var probes = index + _pythonSetLinearProbes <= mask
          ? _pythonSetLinearProbes
          : 0;
      while (true) {
        final entry = _entries[index];
        if (entry == null) {
          _entries[index] = value;
          _hashes[index] = hash;
          _used++;
          if (_used * 5 >= mask * 3) {
            _resize(_used * 4);
          }
          return;
        }
        if (_hashes[index] == hash && entry == value) {
          return;
        }
        if (probes == 0) {
          break;
        }
        probes--;
        index++;
      }
      perturb >>= _pythonSetPerturbShift;
      index =
          ((BigInt.from(initialIndex * 5 + 1) + perturb) & BigInt.from(mask))
              .toInt();
    }
  }

  void _resize(int minimumUsed) {
    var newSize = _pythonSetMinimumSize;
    while (newSize <= minimumUsed) {
      newSize <<= 1;
    }
    final oldEntries = _entries;
    final oldHashes = _hashes;
    _entries = List<(String, String)?>.filled(newSize, null);
    _hashes = List<BigInt>.filled(newSize, BigInt.zero);
    for (var index = 0; index < oldEntries.length; index++) {
      final entry = oldEntries[index];
      if (entry != null) {
        _insertClean(entry, oldHashes[index]);
      }
    }
  }

  void _insertClean((String, String) value, BigInt hash) {
    final mask = _entries.length - 1;
    var index = (hash & BigInt.from(mask)).toInt();
    var perturb = hash;
    while (true) {
      final initialIndex = index;
      var probes = index + _pythonSetLinearProbes <= mask
          ? _pythonSetLinearProbes
          : 0;
      while (true) {
        if (_entries[index] == null) {
          _entries[index] = value;
          _hashes[index] = hash;
          return;
        }
        if (probes == 0) {
          break;
        }
        probes--;
        index++;
      }
      perturb >>= _pythonSetPerturbShift;
      index =
          ((BigInt.from(initialIndex * 5 + 1) + perturb) & BigInt.from(mask))
              .toInt();
    }
  }
}

BigInt _python312TupleHash((String, String) value) {
  var accumulator = _tuplePrime5;
  for (final item in <String>[value.$1, value.$2]) {
    final lane = _python312StringHash(item);
    accumulator = _unsigned64(accumulator + lane * _tuplePrime2);
    accumulator = _rotateLeft64(accumulator, 31);
    accumulator = _unsigned64(accumulator * _tuplePrime1);
  }
  accumulator = _unsigned64(
    accumulator + (BigInt.from(2) ^ (_tuplePrime5 ^ BigInt.from(3527539))),
  );
  return accumulator == _unsigned64Mask ? BigInt.from(1546275796) : accumulator;
}

BigInt _python312StringHash(String value) {
  if (value.isEmpty) {
    return BigInt.zero;
  }
  final scalars = value.runes.toList(growable: false);
  final maximumScalar = scalars.reduce(
    (left, right) => left > right ? left : right,
  );
  final unitSize = maximumScalar <= 0xFF
      ? 1
      : maximumScalar <= 0xFFFF
      ? 2
      : 4;
  final bytes = <int>[];
  for (final scalar in scalars) {
    for (var byte = 0; byte < unitSize; byte++) {
      bytes.add((scalar >> (byte * 8)) & 0xFF);
    }
  }
  final hash = _sipHash13(bytes);
  return hash == _unsigned64Mask ? _unsigned64Mask - BigInt.one : hash;
}

BigInt _sipHash13(List<int> bytes) {
  final state = <BigInt>[
    BigInt.parse('736f6d6570736575', radix: 16),
    BigInt.parse('646f72616e646f6d', radix: 16),
    BigInt.parse('6c7967656e657261', radix: 16),
    BigInt.parse('7465646279746573', radix: 16),
  ];
  var offset = 0;
  while (offset + 8 <= bytes.length) {
    final lane = _littleEndianLane(bytes, offset, 8);
    state[3] ^= lane;
    _sipRound(state);
    state[0] ^= lane;
    offset += 8;
  }
  var finalLane = _unsigned64(BigInt.from(bytes.length) << 56);
  final remainder = bytes.length - offset;
  finalLane |= _littleEndianLane(bytes, offset, remainder);
  state[3] ^= finalLane;
  _sipRound(state);
  state[0] ^= finalLane;
  state[2] ^= BigInt.from(0xFF);
  _sipRound(state);
  _sipRound(state);
  _sipRound(state);
  return _unsigned64(state[0] ^ state[1] ^ state[2] ^ state[3]);
}

BigInt _littleEndianLane(List<int> bytes, int offset, int length) {
  var result = BigInt.zero;
  for (var index = 0; index < length; index++) {
    result |= BigInt.from(bytes[offset + index]) << (index * 8);
  }
  return result;
}

void _sipRound(List<BigInt> state) {
  state[0] = _unsigned64(state[0] + state[1]);
  state[1] = _rotateLeft64(state[1], 13) ^ state[0];
  state[0] = _rotateLeft64(state[0], 32);
  state[2] = _unsigned64(state[2] + state[3]);
  state[3] = _rotateLeft64(state[3], 16) ^ state[2];
  state[0] = _unsigned64(state[0] + state[3]);
  state[3] = _rotateLeft64(state[3], 21) ^ state[0];
  state[2] = _unsigned64(state[2] + state[1]);
  state[1] = _rotateLeft64(state[1], 17) ^ state[2];
  state[2] = _rotateLeft64(state[2], 32);
}

BigInt _rotateLeft64(BigInt value, int distance) =>
    _unsigned64((value << distance) | (value >> (64 - distance)));

BigInt _unsigned64(BigInt value) => value & _unsigned64Mask;

BigInt _signed64(BigInt value) =>
    value > _signed64Maximum ? value - (BigInt.one << 64) : value;

const int _pythonSetMinimumSize = 8;
const int _pythonSetLinearProbes = 9;
const int _pythonSetPerturbShift = 5;
final BigInt _unsigned64Mask = (BigInt.one << 64) - BigInt.one;
final BigInt _signed64Maximum = (BigInt.one << 63) - BigInt.one;
final BigInt _tuplePrime1 = BigInt.parse('11400714785074694791');
final BigInt _tuplePrime2 = BigInt.parse('14029467366897019727');
final BigInt _tuplePrime5 = BigInt.parse('2870177450012600261');

const String _digitNames = '영일이삼사오육칠팔구';

const Map<String, String> _sinoDigitNames = <String, String>{
  '1': '^일',
  '2': '^이',
  '3': '^삼',
  '4': '^사',
  '5': '^오',
  '6': '^육',
  '7': '^칠',
  '8': '^팔',
  '9': '^구',
};

const Map<String, String> _nativeModifiers = <String, String>{
  '1': '한',
  '2': '두',
  '3': '세',
  '4': '네',
  '5': '다섯',
  '6': '^여섯',
  '7': '일곱',
  '8': '^여덟',
  '9': '아홉',
};

const Map<String, String> _nativeTens = <String, String>{
  '1': '열',
  '2': '스물',
  '3': '서른',
  '4': '마흔',
  '5': '쉰',
  '6': '예순',
  '7': '일흔',
  '8': '여든',
  '9': '아흔',
};

const Set<String> _boundNouns = <String>{
  '군데',
  '권',
  '개',
  '그루',
  '닢',
  '두',
  '마리',
  '모',
  '모금',
  '뭇',
  '발',
  '발짝',
  '방',
  '번',
  '벌',
  '보루',
  '살',
  '수',
  '술',
  '시',
  '쌈',
  '움큼',
  '정',
  '짝',
  '채',
  '척',
  '첩',
  '축',
  '켤레',
  '톨',
  '통',
  '가지',
  '배',
  '시간',
  '명',
  '줄',
  '곳',
};
