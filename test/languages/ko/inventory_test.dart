import 'package:misakid/misaki_ko.dart';
import 'package:test/test.dart';

void main() {
  test('exposes all and only modern conjoining Jamo', () {
    final inventory = koreanPhonemeInventory();

    expect(inventory, hasLength(67));
    expect(inventory, <String>{
      for (var scalar = 0x1100; scalar <= 0x1112; scalar++)
        String.fromCharCode(scalar),
      for (var scalar = 0x1161; scalar <= 0x1175; scalar++)
        String.fromCharCode(scalar),
      for (var scalar = 0x11A8; scalar <= 0x11C2; scalar++)
        String.fromCharCode(scalar),
    });
  });

  test('returns an immutable shared inventory', () {
    final inventory = koreanPhonemeInventory();

    expect(identical(inventory, koreanPhonemeInventory()), isTrue);
    expect(() => inventory.add('x'), throwsUnsupportedError);
  });
}
