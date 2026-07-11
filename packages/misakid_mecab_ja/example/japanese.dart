import 'dart:io';

import 'package:misakid_mecab_ja/misakid_mecab_ja.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    throw ArgumentError('Expected UniDic-directory and ja_words.txt paths.');
  }
  final backend = await MecabJapaneseCutletBackend.openBundled(
    dictionaryPath: arguments[0],
    wordListBytes: await File(arguments[1]).readAsBytes(),
  );
  try {
    final engine = JapaneseCutletEngine(backend: backend);
    final chunks = KokoroNonEnglishG2pFrontend(engine: engine).convert('日本語です');
    if (chunks.isEmpty || chunks.single.phonemes.isEmpty) {
      throw StateError('The example unexpectedly produced no phonemes.');
    }
  } finally {
    backend.close();
  }
}
