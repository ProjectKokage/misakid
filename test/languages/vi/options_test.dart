import 'package:misakid/src/languages/vi/options.dart';
import 'package:test/test.dart';

void main() {
  test('matches pinned VIG2P defaults and tone-type forcing', () {
    const defaults = VietnameseOptions();
    expect(defaults.dialect, VietnameseDialect.north);
    expect(defaults.glottal, isFalse);
    expect(defaults.pham, isFalse);
    expect(defaults.cao, isFalse);
    expect(defaults.palatals, isFalse);
    expect(defaults.substringTokenization, isTrue);
    expect(defaults.toneType, VietnameseToneType.pham);
    expect(defaults.cleanAbbreviations, isTrue);
    expect(defaults.cleanAcronyms, isTrue);
    expect(defaults.effectivePham, isTrue);
    expect(defaults.effectiveCao, isFalse);

    const caoTone = VietnameseOptions(toneType: VietnameseToneType.cao);
    expect(caoTone.effectivePham, isFalse);
    expect(caoTone.effectiveCao, isTrue);

    const phamAndCao = VietnameseOptions(cao: true);
    expect(phamAndCao.effectivePham, isTrue);
    expect(phamAndCao.effectiveCao, isTrue);

    const caoAndPham = VietnameseOptions(
      toneType: VietnameseToneType.cao,
      pham: true,
    );
    expect(caoAndPham.effectivePham, isTrue);
    expect(caoAndPham.effectiveCao, isTrue);
  });
}
