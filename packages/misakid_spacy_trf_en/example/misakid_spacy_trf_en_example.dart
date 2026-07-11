import 'dart:io';

import 'package:misakid_spacy_trf_en/misakid_spacy_trf_en.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run example/misakid_spacy_trf_en_example.dart '
      '<en_core_web_trf-model-directory> <native-library>',
    );
    exitCode = 64;
    return;
  }

  final tokenizer = await NativeSpacyTransformerEnglishTokenizerBackend.open(
    modelDirectoryPath: arguments[0],
    nativeLibraryPath: arguments[1],
  );
  try {
    final engine = EnglishG2pEngine(
      tokenizer: tokenizer,
      pronunciation: const PinnedEnglishLexicon(),
    );
    stdout.writeln(engine.convert('Hello from Misakid.').phonemes);
  } finally {
    tokenizer.close();
  }
}
