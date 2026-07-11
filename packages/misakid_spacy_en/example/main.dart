import 'package:misakid_spacy_en/misakid_spacy_en.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    throw ArgumentError('Pass the absolute en_core_web_sm-3.8.0 directory.');
  }
  final tokenizer = await PureDartSpacyEnglishTokenizerBackend.open(
    modelDirectoryPath: arguments.single,
  );
  final engine = EnglishG2pEngine(
    tokenizer: tokenizer,
    pronunciation: const PinnedEnglishLexicon(),
  );
  final result = engine.convert('Hello world.');
  print(result.phonemes);
}
