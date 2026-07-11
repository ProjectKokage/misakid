import 'package:misakid/misaki_en.dart';
import 'package:test/test.dart';

void main() {
  test('exposes exact frozen inventories by dialect and version', () {
    final americanLegacy = englishPhonemeInventory(
      dialect: EnglishDialect.american,
    );
    final americanV2 = englishPhonemeInventory(
      dialect: EnglishDialect.american,
      version: EnglishPhonemeVersion.v2,
    );
    final britishLegacy = englishPhonemeInventory(
      dialect: EnglishDialect.british,
    );
    final britishV2 = englishPhonemeInventory(
      dialect: EnglishDialect.british,
      version: EnglishPhonemeVersion.v2,
    );

    expect(americanLegacy, hasLength(45));
    expect(americanV2, hasLength(46));
    expect(britishLegacy, hasLength(45));
    expect(britishV2, britishLegacy);
    expect(americanLegacy, contains('T'));
    expect(americanLegacy, isNot(contains(anyOf('ɾ', 'ʔ'))));
    expect(americanV2, containsAll(<String>['ɾ', 'ʔ']));
    expect(americanV2, isNot(contains('T')));
    expect(britishV2, containsAll(<String>['Q', 'a', 'ɒ', 'ː']));
    expect(() => americanV2.add('x'), throwsUnsupportedError);
  });
}
