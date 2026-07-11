import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:misakid/misaki_ja.dart';
import 'package:test/test.dart';

void main() {
  test('exposes exact immutable source-derived inventories by mode', () {
    final cutlet = japanesePhonemeInventory(JapanesePhonemeMode.cutlet);
    final pyopenjtalk = japanesePhonemeInventory(
      JapanesePhonemeMode.pyopenjtalk,
    );

    _expectExactInventory(
      cutlet,
      canonical: 'abdehijkmnopstvzçŋɕɡɨɯɲɴɸɾʔʣʥʦʨʲːβᵝ',
      sha256Digest:
          'a6bb834a9a42e5be9793a6e22a9a4a4cd05816f5c4dd0f591072c7c2762ca0c1',
    );
    _expectExactInventory(
      pyopenjtalk,
      canonical: 'GKabdefghijkmnoprstuvwzçƫɕɲɴʔʥʦʨːᶀᶁᶃᶄᶆᶈᶉ',
      sha256Digest:
          'ce47368c5d534cc7a2d6b227a76e742def832b2165dedef10f8488e9f5a4c7f6',
    );

    expect(cutlet, hasLength(35));
    expect(pyopenjtalk, hasLength(40));
    expect(cutlet, containsAll(<String>{'ɡ', 'ɯ', 'ʔ', 'ŋ', 'ɴ', 'ː'}));
    expect(
      pyopenjtalk,
      containsAll(<String>{'G', 'K', 'g', 'u', 'ʔ', 'ɴ', 'ː'}),
    );
    expect(cutlet, isNot(contains(anyOf('.', '—', '❓'))));
    expect(pyopenjtalk, isNot(contains(anyOf('_', '-', '^', '❓'))));
    expect(() => cutlet.add('x'), throwsUnsupportedError);
    expect(() => pyopenjtalk.add('x'), throwsUnsupportedError);
    expect(
      identical(cutlet, japanesePhonemeInventory(JapanesePhonemeMode.cutlet)),
      isTrue,
    );
    expect(
      identical(
        pyopenjtalk,
        japanesePhonemeInventory(JapanesePhonemeMode.pyopenjtalk),
      ),
      isTrue,
    );
  });
}

void _expectExactInventory(
  Set<String> actual, {
  required String canonical,
  required String sha256Digest,
}) {
  expect(actual.every((symbol) => symbol.runes.length == 1), isTrue);
  final sorted = actual.toList(growable: false)..sort();
  expect(sorted.join(), canonical);
  expect(sha256.convert(utf8.encode(canonical)).toString(), sha256Digest);
}
