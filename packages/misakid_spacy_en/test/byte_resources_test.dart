import 'dart:io';
import 'dart:typed_data';

import 'package:misakid_spacy_en/misakid_spacy_en.dart';
import 'package:misakid_spacy_en/src/resource_identity.dart';
import 'package:test/test.dart';

void main() {
  test('owned resource buffers are copied and immutable', () {
    final tokenizer = Uint8List.fromList(<int>[1, 2]);
    final lookups = Uint8List.fromList(<int>[3, 4]);
    final tok2vec = Uint8List.fromList(<int>[5, 6]);
    final tagger = Uint8List.fromList(<int>[7, 8]);
    final resources = SpacyEnglishModelResources(
      tokenizerBytes: tokenizer,
      vocabLookupsBytes: lookups,
      tok2vecModelBytes: tok2vec,
      taggerModelBytes: tagger,
    );

    tokenizer[0] = 9;
    lookups[0] = 9;
    tok2vec[0] = 9;
    tagger[0] = 9;

    expect(resources.tokenizer.tokenizerBytes, <int>[1, 2]);
    expect(resources.tokenizer.vocabLookupsBytes, <int>[3, 4]);
    expect(resources.tok2vecModelBytes, <int>[5, 6]);
    expect(resources.taggerModelBytes, <int>[7, 8]);
    expect(
      () => resources.tokenizer.tokenizerBytes[0] = 0,
      throwsUnsupportedError,
    );
    expect(() => resources.tok2vecModelBytes[0] = 0, throwsUnsupportedError);
  });

  test('byte-backed backend rejects an incorrect resource size', () {
    expect(
      () => PureDartSpacyEnglishTokenizerBackend.fromResources(
        tokenizerBytes: Uint8List(0),
        vocabLookupsBytes: Uint8List(0),
        tok2vecModelBytes: Uint8List(0),
        taggerModelBytes: Uint8List(0),
      ),
      throwsA(
        isA<MalformedDataException>().having(
          (error) => error.message,
          'message',
          allOf(contains('tokenizer'), contains('expected 77066')),
        ),
      ),
    );
  });

  test('byte-backed backend rejects a size-correct checksum mismatch', () {
    expect(
      () => PureDartSpacyEnglishTokenizerBackend.fromResources(
        tokenizerBytes: Uint8List(spacyEnglishTokenizerSizeBytes),
        vocabLookupsBytes: Uint8List(0),
        tok2vecModelBytes: Uint8List(0),
        taggerModelBytes: Uint8List(0),
      ),
      throwsA(
        isA<MalformedDataException>().having(
          (error) => error.message,
          'message',
          allOf(contains('tokenizer'), contains('SHA-256')),
        ),
      ),
    );
  });

  test('byte-backed production surface directly imports no dart:io', () {
    for (final path in <String>[
      'lib/src/backend.dart',
      'lib/src/resource_identity.dart',
      'lib/src/resource_loader_stub.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        isNot(contains("import 'dart:io';")),
        reason: path,
      );
    }
  });
}
