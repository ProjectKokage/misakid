import 'package:misakid/misaki_en.dart';

void main() {
  final result = EnglishG2pEngine(
    tokenizer: _FixedEnglishTokenizer(),
    pronunciation: const PinnedEnglishLexicon(),
  ).convert('hello');

  print(result.phonemes); // həlˈO
}

/// A fixed-record example, not a production spaCy adapter.
final class _FixedEnglishTokenizer implements EnglishTokenizerBackend {
  @override
  final BackendInfo info = BackendInfo(
    name: 'fixed-english-example',
    version: '1',
  );

  @override
  List<MisakiToken> tokenize(EnglishPreprocessResult input) {
    if (input.text != 'hello') {
      throw StateError('The fixed example only contains its documented case.');
    }
    return const <MisakiToken>[
      MisakiToken(
        text: 'hello',
        tag: 'UH',
        whitespace: '',
        metadata: EnglishTokenMetadata(isHead: true),
      ),
    ];
  }
}
