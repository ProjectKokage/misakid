import 'dart:convert';
import 'dart:typed_data';

import 'package:misakid_spacy_en/src/tokenizer/config.dart';
import 'package:misakid_spacy_en/src/tokenizer/hash.dart';
import 'package:misakid_spacy_en/src/tokenizer/token.dart';
import 'package:misakid_spacy_en/src/tokenizer/tokenizer.dart';
import 'package:test/test.dart';

void main() {
  late SpacyTokenizerConfig config;
  late SpacyTokenizer tokenizer;

  setUpAll(() {
    config = SpacyTokenizerConfig.decode(
      tokenizerBytes: _encode(_syntheticTokenizerResource()),
      vocabLookupsBytes: _encode(<Object?, Object?>{
        'lexeme_norm': <Object?, Object?>{spacyStringId('buses'): 'busses'},
      }),
    );
    tokenizer = SpacyTokenizer(config);
  });

  test('MurmurHash64A and StringStore symbols match spaCy 3.8.4', () {
    expect(spacyHashString(''), -4132994306676857636);
    expect(spacyHashString('a'), -6544885072357012694);
    expect(spacyHashString('hello'), 5983625672228268878);
    expect(spacyHashString('Hello'), -2669438365559520065);
    expect(spacyHashString('😀'), -4546137833720672511);
    expect(spacyHashString('𐐀'), 492027492781394499);
    expect(spacyHashString('café'), 32833993555699147);
    expect(spacyStringId(''), 0);
    expect(spacyStringId('X'), 101);
    expect(spacyStringId('aux'), 405);
    expect(spacyStringId('_'), 456);
    expect(spacyStringId('DEPRECATED276'), 379);
  });

  test('loads exact exception structure and norm lookups', () {
    expect(config.exceptions, hasLength(9));
    expect(config.exceptions["can't"]!.map((token) => token.orth), <String>[
      'ca',
      "n't",
    ]);
    expect(config.lexemeNorm('buses'), 'busses');
    expect(config.lexemeNorm('Hello'), 'hello');
    expect(config.lexemeNorm('“'), '"');
    expect(config.lexemeNorm('”'), '"');
    expect(config.lexemeNorm('’'), "'");
    expect(config.lexemeNorm('…'), '...');
    expect(config.lexemeNorm('€'), r'$');
  });

  test('preserves ASCII and non-ASCII whitespace like tokenizer.pyx', () {
    expect(
      _surface(tokenizer.tokenize('Hello\tworld\nagain  ')),
      <(String, String)>[
        ('Hello', ''),
        ('\t', ''),
        ('world', ''),
        ('\n', ''),
        ('again', ' '),
        (' ', ''),
      ],
    );
    final unicode = tokenizer.tokenize('hello\x1cworld\u00a0again');
    expect(_surface(unicode), <(String, String)>[
      ('hello', ''),
      ('\x1c', ''),
      ('world', ''),
      ('\u00a0', ''),
      ('again', ''),
    ]);
    expect(unicode[1].isSpace, 1);
    expect(unicode[3].isSpace, 1);
    expect(unicode[3].norm, '  ');
  });

  test('applies affixes and expands multi-token special cases', () {
    final tokens = tokenizer.tokenize("(can't) 10a.m. °C.");
    expect(_surface(tokens), <(String, String)>[
      ('(', ''),
      ('ca', ''),
      ("n't", ''),
      (')', ' '),
      ('10', ''),
      ('a.m.', ' '),
      ('°', ''),
      ('C', ''),
      ('.', ''),
    ]);
    expect(tokens.map((token) => token.norm), <String>[
      '(',
      'can',
      'not',
      ')',
      '10',
      'a.m.',
      '°',
      'c',
      '.',
    ]);
  });

  test('keeps Unicode URLs whole with Python shorthand semantics', () {
    for (final value in <String>[
      'αβ://例え.テスト',
      'café@example.com',
      'http://x.example/é?q=λ',
    ]) {
      expect(tokenizer.tokenize(value).single.text, value);
    }
  });

  test('splits infixes but protects a whole URL before infix search', () {
    expect(
      _surface(tokenizer.tokenize('mother-in-law example.com/path')),
      <(String, String)>[
        ('mother', ''),
        ('-', ''),
        ('in', ''),
        ('-', ''),
        ('law', ' '),
        ('example.com/path', ''),
      ],
    );
  });

  test('derives exact lexical IDs, shape, SPACY, space, and offsets', () {
    final tokens = tokenizer.tokenize('Hello X ① ½');
    final hello = tokens.first;
    expect(hello.orthId, -2669438365559520065);
    expect(hello.normId, 5983625672228268878);
    expect(hello.prefixId, -9095990006690799107);
    expect(hello.suffixId, 7819752793552135697);
    expect(hello.shapeId, -2374649066819379754);
    expect(hello.spacy, 1);
    expect(hello.isSpace, 0);
    expect(hello.startOffsetUtf16, 0);
    expect(hello.endOffsetUtf16, 5);
    expect(tokens[1].orthId, 101);
    expect(tokens[1].shapeId, 101);
    expect(tokens[2].shapeId, spacyStringId('d'));
    expect(tokens[3].shapeId, spacyStringId('½'));
    expect(tokens.map((token) => token.startOffsetUtf16), <int>[0, 6, 8, 10]);
  });

  test('keeps supplementary scalars and combining marks aligned', () {
    final tokens = tokenizer.tokenize('𐐀́ Á̧ 😀⃝');
    expect(_surface(tokens), <(String, String)>[
      ('𐐀́', ' '),
      ('Á̧', ' '),
      ('😀⃝', ''),
    ]);
    expect(tokens.map((token) => token.startOffsetUtf16), <int>[0, 4, 8]);
    expect(tokens.map((token) => token.endOffsetUtf16), <int>[3, 7, 11]);
  });

  test('rejects malformed tokenizer schemas before regex execution', () {
    final root = _syntheticTokenizerResource();
    root.remove('exceptions');
    expect(
      () => SpacyTokenizerConfig.decode(tokenizerBytes: _encode(root)),
      throwsFormatException,
    );

    final badException = _syntheticTokenizerResource();
    badException['exceptions'] = <Object?, Object?>{
      'bad': <Object?>[
        <Object?, Object?>{65: 'different'},
      ],
    };
    expect(
      () => SpacyTokenizerConfig.decode(tokenizerBytes: _encode(badException)),
      throwsFormatException,
    );
  });
}

List<(String, String)> _surface(List<SpacyTokenizerToken> tokens) =>
    tokens.map((token) => (token.text, token.whitespace)).toList();

Map<Object?, Object?> _syntheticTokenizerResource() => <Object?, Object?>{
  'prefix_search': r'^\(|^\[',
  'suffix_search': r'\)$|\]$|\.$',
  'infix_finditer': r'(?<=[A-Za-z])-(?=[A-Za-z])',
  'token_match': null,
  'url_match': r'(?u)^(?:[\w\+\-\.]{2,})://\S+$|^(?:\S+@)?\S+\.\S+$',
  'exceptions': <Object?, Object?>{
    '\t': <Object?>[
      <Object?, Object?>{65: '\t'},
    ],
    '\n': <Object?>[
      <Object?, Object?>{65: '\n'},
    ],
    ' ': <Object?>[
      <Object?, Object?>{65: ' '},
    ],
    '\u00a0': <Object?>[
      <Object?, Object?>{65: '\u00a0', 67: '  '},
    ],
    "can't": <Object?>[
      <Object?, Object?>{65: 'ca', 67: 'can'},
      <Object?, Object?>{65: "n't", 67: 'not'},
    ],
    '10a.m.': <Object?>[
      <Object?, Object?>{65: '10'},
      <Object?, Object?>{65: 'a.m.', 67: 'a.m.'},
    ],
    '°C.': <Object?>[
      <Object?, Object?>{65: '°'},
      <Object?, Object?>{65: 'C'},
      <Object?, Object?>{65: '.'},
    ],
    '[': <Object?>[
      <Object?, Object?>{65: '['},
    ],
    ']': <Object?>[
      <Object?, Object?>{65: ']'},
    ],
  },
  'faster_heuristics': true,
};

Uint8List _encode(Object? value) {
  final output = BytesBuilder(copy: false);
  _writeValue(output, value);
  return output.takeBytes();
}

void _writeValue(BytesBuilder output, Object? value) {
  switch (value) {
    case null:
      output.addByte(0xc0);
    case bool value:
      output.addByte(value ? 0xc3 : 0xc2);
    case int value when value >= 0 && value <= 0x7f:
      output.addByte(value);
    case int value:
      output.addByte(0xd3);
      final data = ByteData(8)..setInt64(0, value, Endian.big);
      output.add(data.buffer.asUint8List());
    case String value:
      final bytes = utf8.encode(value);
      if (bytes.length > 0xff) {
        throw ArgumentError.value(value, 'value', 'test string is too long');
      }
      output
        ..addByte(0xd9)
        ..addByte(bytes.length)
        ..add(bytes);
    case List<Object?> value:
      if (value.length > 15) {
        throw ArgumentError.value(value.length, 'value', 'test list is long');
      }
      output.addByte(0x90 | value.length);
      for (final item in value) {
        _writeValue(output, item);
      }
    case Map<Object?, Object?> value:
      if (value.length > 15) {
        throw ArgumentError.value(value.length, 'value', 'test map is long');
      }
      output.addByte(0x80 | value.length);
      for (final entry in value.entries) {
        _writeValue(output, entry.key);
        _writeValue(output, entry.value);
      }
    default:
      throw ArgumentError.value(value, 'value', 'unsupported test value');
  }
}
