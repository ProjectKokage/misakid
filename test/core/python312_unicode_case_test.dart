import 'package:misakid/src/core/python312_unicode.dart';
import 'package:test/test.dart';

void main() {
  test('CPython 3.12 lowercase mappings are host-independent', () {
    expect(python312Lower('Hello'), 'hello');
    expect(python312Lower('İ'), 'i\u0307');
    expect(python312Lower('𐐀'), '𐐨');
    expect(python312Lower('Ꭰ'), 'ꭰ');
    expect(python312Lower('ΟΣ'), 'ος');
    expect(python312Lower('ΟΣΑ'), 'οσα');
    expect(python312Lower('AΣ\u0301'), 'aς\u0301');
    expect(python312Lower('AΣ\u0301B'), 'aσ\u0301b');
    expect(python312Lower('\u{1c89}'), '\u{1c89}');
  });

  test('isolated UTF-16 surrogates are preserved', () {
    final source = String.fromCharCodes(<int>[0xd800, 0x41, 0xdc00]);
    expect(python312Lower(source).codeUnits, <int>[0xd800, 0x61, 0xdc00]);
  });
}
