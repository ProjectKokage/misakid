# misakid_spacy_en

Pure-Dart, offline English tokenization and part-of-speech tagging for
`misakid`, using an explicitly supplied
`en_core_web_sm==3.8.0` resource directory.

The adapter implements the exact spaCy 3.8.4 tokenizer and Thinc 8.3.4
small-model inference path selected by pinned Misaki 0.9.4. It does not invoke
Python, native code, a subprocess, or the network. It does not discover or
download a model.

## Use

```dart
import 'package:misakid_spacy_en/misakid_spacy_en.dart';

Future<void> main() async {
  final tokenizer = await PureDartSpacyEnglishTokenizerBackend.open(
    modelDirectoryPath: '/absolute/path/en_core_web_sm-3.8.0',
  );
  final engine = EnglishG2pEngine(
    tokenizer: tokenizer,
    pronunciation: const PinnedEnglishLexicon(),
  );

  final result = engine.convert('Hello world.');
  print(result.phonemes);
}
```

Use `PinnedEnglishLexicon(dialect: EnglishDialect.british)` for the British
pipeline. An optional fallback is configured separately; the sibling
`misakid_espeak_en` package supplies the reviewed eSpeak configuration.

## Tokenizer-only reuse

`en_core_web_sm==3.8.0` and `en_core_web_trf==3.8.0` contain byte-identical
tokenizer and lexical-normalization files. Compatible tagger adapters can load
only that shared pure-Dart stage:

```dart
final tokenizer = await PureDartSpacyEnglishTokenizer.open(
  modelDirectoryPath: '/absolute/path/en_core_web_trf-3.8.0',
);
final input = const EnglishInlinePreprocessor().preprocess(
  '[Misaki](/misˈɑki/) works.',
);
final tokenization = tokenizer.tokenize(input);
```

`SpacyEnglishTokenization.tokens` exposes only exact text, whitespace,
whitespace classification, and source offsets. After a compatible tagger
produces one label per record, `assembleTagged` validates ownership and length,
reapplies inline controls, and returns immutable `MisakiToken` values. This
boundary itself remains pure Dart and does not claim transformer inference.

## Required resources

Pass the extracted directory named `en_core_web_sm-3.8.0` from Explosion's
official `en_core_web_sm==3.8.0` model wheel. The adapter reads only:

- `tokenizer`
- `vocab/lookups.bin`
- `tok2vec/model`
- `tagger/model`

All four files are checked by exact byte size and SHA-256 before parsing. See
[RESOURCE_MANIFEST.md](RESOURCE_MANIFEST.md). A different model version,
retrained model, changed file, symlink, relative path, or incomplete directory
fails with a typed Misakid exception.

## Supported scope

- Dart VM on macOS, Linux, and Windows; the loader uses `dart:io`, so web is
  unsupported.
- Exact `en_core_web_sm==3.8.0`, spaCy 3.8.4 tokenizer semantics, and Thinc
  8.3.4 small-model inference.
- Pinned Misaki's American and British small-model modes, both phoneme
  renderings, inline controls, and no fallback on all listed Dart VM
  platforms. The reviewed eSpeak-fallback composition is supported only with
  the separate exact `misakid_espeak_en` macOS-arm64 tuple.
- At most 1,000,000 input Unicode scalars and 65,536 resulting spaCy tokens.

The transformer tagger (`en_core_web_trf`) and BART fallback modes are not
implemented by this package. Resource loading is asynchronous; conversion
after `open` is synchronous and deterministic.

Provisioned parity covers 146 accepted cases, 744 raw tokenizer/tagger tokens,
all token metadata, and exact final output across the six committed American,
British, no-fallback, adversarial, and eSpeak-call-replay fixtures. Normal
tests remain offline and skip provisioned model tests when the explicit model
path is absent.
