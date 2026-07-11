import 'dart:io';
import 'dart:typed_data';

import 'package:misakid_spacy_en/misakid_spacy_en.dart'
    show PureDartSpacyEnglishTokenizer;
import 'package:misakid_spacy_trf_en/misakid_spacy_trf_en.dart';
import 'package:test/test.dart';

const _payloadOffset = 416;

void main() {
  final modelDirectory =
      Platform.environment['MISAKID_SPACY_TRF_EN_MODEL_DIR'] ??
      Platform.environment['MISAKID_SPACY_EN_TRF_MODEL_DIR'];
  final skipReason = modelDirectory == null
      ? 'Set MISAKID_SPACY_TRF_EN_MODEL_DIR to en_core_web_trf-3.8.0.'
      : false;

  group(
    'provisioned exact transformer byte-BPE',
    () {
      late SpacyTransformerByteBpe processor;

      setUpAll(() {
        final model = File('$modelDirectory/transformer/model');
        final stream = model.openSync();
        try {
          stream.setPositionSync(_payloadOffset);
          final payload = stream.readSync(
            spacyTransformerByteBpePayloadByteLength,
          );
          if (payload.length != spacyTransformerByteBpePayloadByteLength) {
            throw StateError('Could not read the complete byte-BPE payload.');
          }
          processor = SpacyTransformerByteBpe.decodePinnedPayload(
            Uint8List.fromList(payload),
          );
        } finally {
          stream.closeSync();
        }
      });

      test('matches the inspector oracle vectors exactly', () {
        expect(processor.encodeAsPieces('Hello world!'), <String>[
          'Hello',
          'Ġworld',
          '!',
        ]);
        expect(processor.encodeAsIds('Hello world!'), <int>[31414, 232, 328]);
        expect(processor.encodeAsPieces(' café'), <String>['ĠcafÃ©']);
        expect(processor.encodeAsIds(' café'), <int>[26059]);
        expect(processor.encodeAsPieces(' 😀'), <String>['ĠðŁĺ', 'Ģ']);
        expect(processor.encodeAsIds(' 😀'), <int>[17841, 7471]);
      });

      test('integrates with the shared exact tokenizer boundary', () async {
        final tokenizer = await PureDartSpacyEnglishTokenizer.open(
          modelDirectoryPath: modelDirectory!,
        );
        final input = const EnglishInlinePreprocessor().preprocess(
          'Hello world!',
        );
        final sequence = processor.encodeTokenization(
          tokenizer.tokenize(input),
        );

        expect(sequence.pieceIds, <int>[0, 31414, 232, 328, 2]);
        expect(sequence.tokenPieceLengths, <int>[1, 1, 1]);
        expect(sequence.sourceTokenIndices, <int>[0, 1, 2]);
        expect(sequence.raggedLengths, <int>[1, 1, 1, 1, 1]);
      });
    },
    skip: skipReason,
    tags: 'provisioned',
  );
}
