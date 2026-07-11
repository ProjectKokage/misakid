import 'package:misakid/src/languages/en/subtokenizer.dart';
import 'package:test/test.dart';

void main() {
  test('returns an unmodifiable list', () {
    final result = subtokenizeEnglish('hello');

    expect(result, <String>['hello']);
    expect(() => result.add('world'), throwsUnsupportedError);
    expect(subtokenizeEnglish(''), isEmpty);
  });

  group('apostrophe alternations', () {
    final cases = <(String, List<String>)>[
      ("'hello", <String>["'", 'hello']),
      ("hello'", <String>['hello', "'"]),
      ("''hello''", <String>["''", 'hello', "''"]),
      ("a'b", <String>["a'b"]),
      ("a''b", <String>['a', "''", 'b']),
      ("rock'n'roll", <String>["rock'n'r", 'oll']),
      ("d'Artagnan", <String>["d'A", 'rtagnan']),
      ('can’t', <String>['can’t']),
      ('‘quoted’', <String>['‘', 'quoted', '’']),
      ('‘‘smart’’', <String>['‘‘', 'smart', '’’']),
      ("a'b'", <String>["a'b", "'"]),
      ("a'''b", <String>['a', "'''", 'b']),
      ('‘’"', <String>['‘’', '"']),
    ];

    for (final (input, expected) in cases) {
      test(input, () => expect(subtokenizeEnglish(input), expected));
    }
  });

  group('uppercase and mixed-case boundaries', () {
    final cases = <(String, List<String>)>[
      ('camelCase', <String>['camel', 'Case']),
      ('HTTPServer', <String>['HTTPServer']),
      ('XMLHttpRequest', <String>['XMLHttp', 'Request']),
      ('fooBARBaz', <String>['foo', 'BARBaz']),
      ('lowerUPPER', <String>['lower', 'UPPER']),
      ('AbC', <String>['Ab', 'C']),
      ('abCdeF', <String>['ab', 'Cde', 'F']),
      ("foo'barBaz", <String>["foo'b", 'ar', 'Baz']),
      ("a'bC", <String>["a'b", 'C']),
      ('ǅuro', <String>['ǅuro']),
      ('aǅB', <String>['aǅB']),
    ];

    for (final (input, expected) in cases) {
      test(input, () => expect(subtokenizeEnglish(input), expected));
    }
  });

  group('numeric alternation and malformed runs', () {
    final cases = <(String, List<String>)>[
      ('123', <String>['123']),
      ('-123', <String>['-123']),
      ('x-123', <String>['x', '-', '123']),
      ('+123', <String>['+', '123']),
      ('–123', <String>['–', '123']),
      ('1,234.56', <String>['1,234.56']),
      ('-.5', <String>['-.5']),
      ('.5', <String>['.5']),
      (',123', <String>[',123']),
      ('1.2,3', <String>['1.2,3']),
      ('1,,2', <String>['1', ',', ',2']),
      ('1.,2', <String>['1', '.', ',2']),
      ('12.', <String>['12', '.']),
      ('--1', <String>['--', '1']),
      ('-_12', <String>['-_', '12']),
    ];

    for (final (input, expected) in cases) {
      test(input, () => expect(subtokenizeEnglish(input), expected));
    }
  });

  group('runs, punctuation, and other scalars', () {
    final cases = <(String, List<String>)>[
      ('foo--bar__baz', <String>['foo', '--', 'bar', '__', 'baz']),
      ('-abc', <String>['-', 'abc']),
      ('abc_', <String>['abc', '_']),
      ('hello, world!', <String>['hello', ',', ' ', 'world', '!']),
      ('A_B-C.D,1', <String>['A', '_', 'B', '-', 'C', '.', 'D', ',1']),
      ('...', <String>['.', '.', '.']),
      ('[]{}', <String>['[', ']', '{', '}']),
      ('foo\u200dbar', <String>['foo', '\u200d', 'bar']),
      ('😀A😀', <String>['😀', 'A', '😀']),
      ('²3', <String>['²', '3']),
      ('Ⅷx', <String>['Ⅷ', 'x']),
      ('a·b', <String>['a', '·', 'b']),
    ];

    for (final (input, expected) in cases) {
      test(input, () => expect(subtokenizeEnglish(input), expected));
    }
  });

  group('normalization forms and non-Latin letter categories', () {
    final cases = <(String, List<String>)>[
      ('café', <String>['café']),
      ('cafe\u0301', <String>['cafe', '\u0301']),
      ('e\u0301Mail', <String>['e', '\u0301', 'Mail']),
      ('Αθήνα', <String>['Αθήνα']),
      ('άλφαΒήτα', <String>['άλφα', 'Βήτα']),
      ('Москва', <String>['Москва']),
      ('моёСлово', <String>['моё', 'Слово']),
      ('العربية', <String>['العربية']),
      ('עברית', <String>['עברית']),
      ('漢字かなカナ', <String>['漢字かなカナ']),
    ];

    for (final (input, expected) in cases) {
      test(input, () => expect(subtokenizeEnglish(input), expected));
    }
  });

  group('supplementary and width-form properties', () {
    test('handles supplementary case and decimal properties', () {
      expect(subtokenizeEnglish('𐐀𐐁𐐨'), <String>['𐐀', '𐐁𐐨']);
      expect(subtokenizeEnglish('𐐨𐐀'), <String>['𐐨', '𐐀']);
      expect(subtokenizeEnglish('𐒠𐒩'), <String>['𐒠𐒩']);
    });

    test('handles full-width letters, digits, and punctuation distinctly', () {
      expect(subtokenizeEnglish('ＡＢｃ'), <String>['Ａ', 'Ｂｃ']);
      expect(subtokenizeEnglish('ａｂＣ'), <String>['ａｂ', 'Ｃ']);
      expect(subtokenizeEnglish('１２３'), <String>['１２３']);
      expect(subtokenizeEnglish('１，２'), <String>['１', '，', '２']);
    });

    test('uses regex 2024.11.6 Unicode property additions', () {
      final cyrillic = String.fromCharCodes(<int>[0x1c89, 0x1c89, 0x1c8a]);
      final cyrillicTail = String.fromCharCodes(<int>[0x1c89, 0x1c8a]);
      final garayDigits = String.fromCharCodes(<int>[0x10d40, 0x10d41]);
      final garay = String.fromCharCodes(<int>[0x10d50, 0x10d50, 0x10d70]);
      final garayTail = String.fromCharCodes(<int>[0x10d50, 0x10d70]);

      expect(subtokenizeEnglish(cyrillic), <String>[
        String.fromCharCode(0x1c89),
        cyrillicTail,
      ]);
      expect(subtokenizeEnglish(garayDigits), <String>[garayDigits]);
      expect(subtokenizeEnglish(garay), <String>[
        String.fromCharCode(0x10d50),
        garayTail,
      ]);
    });
  });
}
