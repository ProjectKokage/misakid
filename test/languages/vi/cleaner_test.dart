import 'package:misakid/src/languages/vi/cleaner.dart';
import 'package:misakid/src/languages/vi/options.dart';
import 'package:test/test.dart';

void main() {
  test('matches pinned basic whitespace and NFC behavior', () {
    const cleaner = VietnameseCleaner(options: VietnameseOptions());
    expect(cleaner.clean('  Xin  chào !  '), 'xin chào!');
    expect(cleaner.clean('XIN CHÀO\nBẠN'), 'xin chào\nbạn');
    expect(cleaner.clean('e\u0302'), 'ê');
    expect(cleaner.clean('Ａ ①'), 'ａ ①');
    expect(cleaner.clean('\u001cXin\u0085'), 'xin');
  });

  test('uses captured Python 3.11.15 expansion and supplementary mappings', () {
    const cleaner = VietnameseCleaner(options: VietnameseOptions());

    expect(cleaner.clean('İ 𐐀'), 'i\u0307 𐐨');
  });

  test('preserves abbreviation and acronym toggles independently', () {
    expect(
      const VietnameseCleaner(
        options: VietnameseOptions(),
      ).clean('ko bit j TP.HCM và VN AI GPU NASA'),
      'không biết chây thành phố hồ chí minh và việt nam '
      'ây ai g pê u nasa',
    );
    expect(
      const VietnameseCleaner(
        options: VietnameseOptions(
          cleanAbbreviations: false,
          cleanAcronyms: false,
        ),
      ).clean('ko bit j TP.HCM và VN AI GPU NASA'),
      'ko bit chây tp.hcm và vn ai gpu nasa',
    );
  });

  test('normalizes licensed symbols, units, currencies, and letters', () {
    const cleaner = VietnameseCleaner(options: VietnameseOptions());
    expect(cleaner.clean('100%'), 'một trăm phần trăm');
    expect(
      cleaner.clean('2kg 3km/h 5GB'),
      'hai ki lô gam ba ki lô mét trên giờ năm gi ga bai',
    );
    expect(
      cleaner.clean(r'$5 10 USD 20₫'),
      'đô la năm mười đô la hai mươi đồng',
    );
    expect(cleaner.clean('chữ A chữ cái X'), 'chữ ây chữ cái ít');
  });

  test('normalizes dates, time, multiplication, ranges, and ordinals', () {
    const cleaner = VietnameseCleaner(options: VietnameseOptions());
    expect(
      cleaner.clean('01/02/2024 12:30 1x2 từ 3-5'),
      'ngày một tháng hai năm hai nghìn không trăm hai mươi bốn '
      'mười hai giờ ba mươi phút một nhân hai từ ba đến năm',
    );
    expect(cleaner.clean('thứ 1 hạng 4'), 'thứ nhất hạng tư');
    expect(cleaner.clean('IV XIV XL'), 'bốn mười bốn xl');
  });

  test('preserves pinned URL, slash, hyphen, and inline-control cleaning', () {
    const cleaner = VietnameseCleaner(options: VietnameseOptions());
    expect(cleaner.clean('a.com b.gov.vn'), 'ây chấm com bê chấm gov.việt nam');
    expect(cleaner.clean('a/b-c'), 'ây trên b c');
    expect(cleaner.clean('[xin](/CUSTOM/)'), '[xin] (trên custom trên)');
  });

  test('preserves corpus-level cleaner quirks from the pinned black box', () {
    const cleaner = VietnameseCleaner(options: VietnameseOptions());
    expect(
      cleaner.clean('0 15 21 105 123456 +84908123456'),
      'không mười lăm hai mươi mốt triệu một trăm lẻ năm '
      'nghìn một trăm hai mươi ba 4 năm mươi sáu '
      'cộng tám bốn chín không tám một hai ba bốn năm sáu',
    );
    expect(
      cleaner.clean(r'12kg 3,5km $20 50€'),
      'mười hai ki lô gam ba mươi lăm ki lô mét '
      'đô la hai mươi năm mươi ê rô',
    );
    expect(
      cleaner.clean('10/07/2026 08:30:05 tháng 4'),
      'ngày mười tháng bảy năm hai nghìn không trăm hai mươi sáu '
      'tám giờ ba mươi phút năm giây tháng tư',
    );
  });
}
