import 'package:misakid/misaki_vi.dart';
import 'package:test/test.dart';

void main() {
  test('exposes the complete immutable pinned vi_syms inventory', () {
    final inventory = vietnamesePhonemeInventory();

    expect(inventory, hasLength(139));
    expect(
      inventory,
      containsAll(<String>{'ɯəj', 'ŋ͡m', 'k͡p', 'tʰ', '6', ' ', '?'}),
    );
    expect(() => inventory.add('not-pinned'), throwsUnsupportedError);
    expect(identical(inventory, vietnamesePhonemeInventory()), isTrue);
  });
}
