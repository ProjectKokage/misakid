import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:misakid/src/core/python311_case.dart';
import 'package:misakid/src/generated/python311_case_data.dart';
import 'package:test/test.dart';

void main() {
  test('matches Python expansions, supplementary case, and Final_Sigma', () {
    expect(python311Lower('İ'), 'i\u0307');
    expect(python311Upper('straße'), 'STRASSE');
    expect(python311Lower('𐐀'), '𐐨');
    expect(python311Lower('ΟΣ ΟΣΑ Σ AΣ'), 'ος οσα σ aς');
    expect(python311Lower("A'Σ AΣ'A"), "a'ς aσ'a");
  });

  test('preserves isolated UTF-16 surrogates', () {
    final input = String.fromCharCodes(<int>[0xd800, 0x41, 0xdc00]);
    expect(python311Lower(input).codeUnits, <int>[0xd800, 0x61, 0xdc00]);
    expect(python311Upper(input).codeUnits, input.codeUnits);
  });

  test('strips Python whitespace without trimming non-whitespace scalars', () {
    expect(stripPython311Whitespace('\u001c\u0085 text\u2029'), 'text');
    expect(stripPython311Whitespace('\u200btext\u200b'), '\u200btext\u200b');
    expect(
      stripRightPython311Whitespace('\u001c text\u0085\u2029'),
      '\u001c text',
    );
    expect(
      stripRightPython311Whitespace('\u200btext\u200b'),
      '\u200btext\u200b',
    );
  });

  test('matches every accepted scalar mapping and case-property record', () {
    final lowerDigest = _RecordDigest();
    final upperDigest = _RecordDigest();
    final propertyDigest = _RecordDigest();
    var records = 0;
    for (var codePoint = 0; codePoint <= 0x10ffff; codePoint++) {
      if (codePoint >= 0xd800 && codePoint <= 0xdfff) {
        continue;
      }
      final source = <int>[codePoint];
      final character = String.fromCharCode(codePoint);
      lowerDigest.add(
        source,
        python311Lower(character).runes.toList(growable: false),
      );
      upperDigest.add(
        source,
        python311Upper(character).runes.toList(growable: false),
      );
      propertyDigest.add(source, <int>[
        isPython311CasedScalar(codePoint) ? 1 : 0,
        isPython311CaseIgnorableScalar(codePoint) ? 1 : 0,
        isPython311WhitespaceScalar(codePoint) ? 1 : 0,
      ]);
      records++;
    }
    expect(records, 1112064);
    expect(lowerDigest.close(), python311LowercaseDigestSha256);
    expect(upperDigest.close(), python311UppercaseDigestSha256);
    expect(propertyDigest.close(), python311CasePropertiesDigestSha256);
  });
}

final class _RecordDigest {
  final BytesBuilder _bytes = BytesBuilder(copy: false);

  void add(List<int> source, List<int> result) {
    _addUint32(source.length);
    for (final codePoint in source) {
      _addUint32(codePoint);
    }
    _addUint32(result.length);
    for (final codePoint in result) {
      _addUint32(codePoint);
    }
  }

  String close() => sha256.convert(_bytes.takeBytes()).toString();

  void _addUint32(int value) {
    _bytes.add(<int>[
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ]);
  }
}
