import 'package:misakid/misaki_ja.dart';

void main() {
  final result = JapaneseCutletEngine(
    backend: _FixedCutletMorphology(),
  ).convert('猫');

  print(result.phonemes); // neko
}

/// A fixed-record example, not a production fugashi/MeCab adapter.
final class _FixedCutletMorphology implements JapaneseCutletMorphologyBackend {
  @override
  final BackendInfo info = BackendInfo(
    name: 'fixed-cutlet-example',
    version: '1',
  );

  @override
  List<JapaneseCutletMorphologyWord> analyze(String normalizedText) {
    if (normalizedText != '猫') {
      throw StateError('The fixed example only contains its documented case.');
    }
    return const <JapaneseCutletMorphologyWord>[
      JapaneseCutletMorphologyWord(
        surface: '猫',
        hiragana: 'ねこ',
        charType: 2,
        isUnknown: false,
      ),
    ];
  }
}
