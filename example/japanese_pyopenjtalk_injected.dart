import 'package:misakid/misaki_ja.dart';

void main() {
  final result = JapanesePyopenjtalkEngine(
    backend: _FixedJapaneseFrontend(),
  ).convert('猫');

  print(result.phonemes); // neko^^__
}

/// A fixed-record example, not a production pyopenjtalk adapter.
final class _FixedJapaneseFrontend implements JapaneseFrontendBackend {
  @override
  final BackendInfo info = BackendInfo(
    name: 'fixed-pyopenjtalk-example',
    version: '1',
  );

  @override
  List<JapaneseFrontendWord> analyze(String text) {
    if (text != '猫') {
      throw StateError('The fixed example only contains its documented case.');
    }
    return const <JapaneseFrontendWord>[
      JapaneseFrontendWord(
        surface: '猫',
        partOfSpeech: '名詞',
        pronunciation: 'ネコ',
        accent: 1,
        moraSize: 2,
        chainFlag: false,
      ),
    ];
  }
}
