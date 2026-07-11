import 'package:misakid/src/core/errors.dart';
import 'package:misakid/src/languages/vi/number_speller.dart';
import 'package:test/test.dart';

void main() {
  const speller = VietnameseNumberSpeller();

  test('matches black-box unit, tens, and hundreds outputs', () {
    expect(speller.spell('0'), 'không');
    expect(speller.spell('15'), 'mười lăm');
    expect(speller.spell('21'), 'hai mươi mốt');
    expect(speller.spell('24'), 'hai mươi bốn');
    expect(speller.spell('101'), 'một trăm lẻ một');
    expect(speller.spell('105'), 'một trăm lẻ năm');
  });

  test('matches black-box group and zero-padding quirks', () {
    expect(speller.spell('1000'), 'một nghìn không trăm');
    expect(
      speller.spell('1000001'),
      'một triệu không trăm nghìn không trăm lẻ một',
    );
    expect(speller.spell('00001'), 'nghìn không trăm lẻ một');
    expect(speller.spell('01000'), 'lẻ một nghìn không trăm');
    expect(
      speller.spell('1000000000000'),
      'không trăm tỷ không trăm triệu không trăm nghìn không trăm',
    );
    expect(speller.spell('1001'), 'một nghìn không trăm lẻ một');
    expect(speller.spell('1010'), 'một nghìn không trăm mười');
    expect(
      speller.spell('1001001'),
      'một triệu không trăm lẻ một nghìn không trăm lẻ một',
    );
    expect(
      speller.spell('999999999999'),
      'chín trăm chín mươi chín tỷ '
      'chín trăm chín mươi chín triệu '
      'chín trăm chín mươi chín nghìn '
      'chín trăm chín mươi chín',
    );
  });

  test('matches separator and digit-by-digit phone behavior', () {
    expect(speller.spell('0,5'), 'lẻ năm');
    expect(
      speller.spell('12.345.678'),
      'mười hai triệu ba trăm bốn mươi lăm nghìn '
      'sáu trăm bảy mươi tám',
    );
    expect(speller.spell('-15'), 'mười lăm');
    expect(speller.spell('1,25'), 'một trăm hai mươi lăm');
    expect(
      speller.spellDigits('+84901234567'),
      'không chín không một hai ba bốn năm sáu bảy',
    );
  });

  test('uses a typed error outside the observed ASCII domain', () {
    expect(
      () => speller.spell('abc'),
      throwsA(isA<InvalidConfigurationException>()),
    );
  });
}
