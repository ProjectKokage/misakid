import 'dart:io';
import 'dart:typed_data';

import 'package:misakid/misaki.dart';
import 'package:misakid_spacy_en/src/model/model.dart';
import 'package:test/test.dart';

void main() {
  final modelDirectory =
      Platform.environment['MISAKID_SPACY_EN_MODEL_DIR'] ??
      Platform.environment['MISAKI_SPACY_EN_MODEL_DIR'];
  final provisionedSkip = modelDirectory == null
      ? 'Set MISAKID_SPACY_EN_MODEL_DIR to en_core_web_sm-3.8.0.'
      : false;

  test('loads the pinned tok2vec and tagger parameter graphs', () {
    final tok2vec = File('$modelDirectory/tok2vec/model').readAsBytesSync();
    final tagger = File('$modelDirectory/tagger/model').readAsBytesSync();
    final parameters = SpacyEnglishSerializedModelLoader.decode(
      tok2vecModel: tok2vec,
      taggerModel: tagger,
    );

    expect(parameters.embeddingTables, hasLength(6));
    expect(parameters.embeddingTables[0].valueAt(0, 0), -0.03724152594804764);
    expect(parameters.projection.weightAt(0, 0, 0), -0.2694340944290161);
    expect(parameters.encoderLayers[3].biasAt(0, 0), -0.1033342182636261);
    expect(parameters.tagger.weightAt(0, 0), -0.5866965651512146);
    expect(parameters.tagger.biasAt(49), -0.6870549917221069);
  }, skip: provisionedSkip);

  test('rejects a model whose pinned bytes were modified', () {
    final tok2vec = File('$modelDirectory/tok2vec/model').readAsBytesSync();
    final tagger = Uint8List.fromList(
      File('$modelDirectory/tagger/model').readAsBytesSync(),
    );
    tagger[tagger.length - 1] ^= 1;

    expect(
      () => SpacyEnglishSerializedModelLoader.decode(
        tok2vecModel: tok2vec,
        taggerModel: tagger,
      ),
      throwsA(
        isA<MalformedDataException>().having(
          (error) => error.message,
          'message',
          contains('SHA-256'),
        ),
      ),
    );
  }, skip: provisionedSkip);
}
