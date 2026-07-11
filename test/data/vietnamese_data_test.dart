import 'package:misakid/src/generated/vietnamese_cleaner_tables.dart';
import 'package:misakid/src/generated/vietnamese_phonology_data.dart';
import 'package:misakid/src/languages/vi/data.dart';
import 'package:test/test.dart';

void main() {
  test('loads exact immutable Vietnamese cleaner dictionaries once', () {
    final data = loadVietnameseCleanerData();

    expect(data.acronyms, hasLength(3098));
    expect(data.symbols, hasLength(62));
    expect(data.teencode, hasLength(482));
    expect(data.acronyms['BHXH'], 'bảo hiểm xã hội');
    expect(data.teencode['ko'], 'không');
    expect(identical(data, loadVietnameseCleanerData()), isTrue);
    expect(() => data.acronyms['new'] = 'value', throwsUnsupportedError);
  });

  test('retains the complete pinned phonology and cleaner inventories', () {
    expect(vietnameseOnsets, hasLength(31));
    expect(vietnameseNuclei, hasLength(158));
    expect(vietnameseOffglides, hasLength(125));
    expect(vietnameseOnglides, hasLength(105));
    expect(vietnameseOnoffglides, hasLength(59));
    expect(vietnameseCodas, hasLength(9));
    expect(vietnameseToneByCharacter, hasLength(60));
    expect(vietnameseGi, hasLength(5));
    expect(vietnameseQu, hasLength(6));
    expect(vietnameseEnglishLetterNames, hasLength(27));
    expect(vietnameseLetterNames, hasLength(33));
    expect(vietnameseSymbols, hasLength(139));

    expect(vietnameseBaseAbbreviations, hasLength(8));
    expect(vietnameseSpelledAcronyms, hasLength(47));
    expect(vietnameseBaseAcronyms, hasLength(81));
    expect(vietnameseNonUppercaseExceptions, hasLength(1));
    expect(vietnameseBaseCurrencies, hasLength(13));
    expect(vietnameseCleanerLetterNames, hasLength(24));
    expect(vietnameseMeasurements, hasLength(38));
    expect(vietnameseCharacterSet.runes, hasLength(194));
  });
}
