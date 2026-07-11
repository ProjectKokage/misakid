import 'package:misakid_mecab_ko/misakid_mecab_ko.dart';

Future<void> main() async {
  final morphology = await MecabKoMorphologyBackend.open(
    libraryPath: '/absolute/path/libmisakid_mecab_ko.dylib',
    dictionaryPath: '/absolute/path/mecab_ko_dic/dictionary',
  );
  final cmu = await CmuDictionaryPronunciationProvider.open(
    '/absolute/path/cmudict/cmudict',
  );
  try {
    final engine = KoreanG2pkcEngine(
      morphology: morphology,
      cmuPronunciations: cmu,
    );
    print(engine.convert('안녕하세요.').phonemes);
  } finally {
    morphology.close();
  }
}
