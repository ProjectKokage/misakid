import 'dart:io';

import 'package:misakid_spacy_en/misakid_spacy_en.dart';
import 'package:test/test.dart';

void main() {
  test('rejects relative, NUL, and malformed-Unicode model paths', () async {
    for (final path in <String>[
      'en_core_web_sm-3.8.0',
      '${Directory.systemTemp.path}\u0000model',
      '${Directory.systemTemp.path}\uD800model',
    ]) {
      await expectLater(
        PureDartSpacyEnglishTokenizerBackend.open(modelDirectoryPath: path),
        throwsA(isA<InvalidConfigurationException>()),
        reason: path.codeUnits.toString(),
      );
      await expectLater(
        PureDartSpacyEnglishTokenizer.open(modelDirectoryPath: path),
        throwsA(isA<InvalidConfigurationException>()),
        reason: 'tokenizer-only ${path.codeUnits}',
      );
    }
  });

  test('distinguishes a missing model from a non-directory path', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'misakid-spacy-config-',
    );
    addTearDown(() => temporary.delete(recursive: true));

    await expectLater(
      PureDartSpacyEnglishTokenizerBackend.open(
        modelDirectoryPath: '${temporary.path}/missing',
      ),
      throwsA(isA<BackendUnavailableException>()),
    );
    await expectLater(
      PureDartSpacyEnglishTokenizer.open(
        modelDirectoryPath: '${temporary.path}/missing',
      ),
      throwsA(isA<BackendUnavailableException>()),
    );

    final file = File('${temporary.path}/model-file');
    await file.writeAsString('not a model');
    await expectLater(
      PureDartSpacyEnglishTokenizerBackend.open(modelDirectoryPath: file.path),
      throwsA(isA<InvalidConfigurationException>()),
    );
  });
}
