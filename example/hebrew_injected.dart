import 'package:misakid/misaki_he.dart';

void main() {
  final backend = _FixedHebrewBackend();
  final result = HebrewG2pEngine(backend: backend).convert('שָׁלוֹם עוֹלָם');

  print(result.phonemes); // ʃalˈom olˈam
}

/// A fixed-record example, not a production Mishkal adapter.
final class _FixedHebrewBackend implements HebrewPhonemizerBackend {
  @override
  final BackendInfo info = BackendInfo(
    name: 'fixed-hebrew-example',
    version: '1',
  );

  @override
  Set<String> phonemeInventory() => <String>{'a', 'l', 'm', 'o', 'ʃ', 'ˈ'};

  @override
  String phonemize(
    String text, {
    required bool preservePunctuation,
    required bool preserveStress,
  }) {
    if (text != 'שָׁלוֹם עוֹלָם' || !preservePunctuation || !preserveStress) {
      throw StateError('The fixed example only contains its documented case.');
    }
    return 'ʃalˈom olˈam';
  }
}
