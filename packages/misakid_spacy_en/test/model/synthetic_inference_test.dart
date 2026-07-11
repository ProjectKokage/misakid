import 'dart:typed_data';

import 'package:misakid_spacy_en/src/model/model.dart';
import 'package:test/test.dart';

void main() {
  late SpacyEnglishTaggerModel model;

  setUpAll(() {
    model = SpacyEnglishTaggerModel(_zeroModelWithTagBias(42));
  });

  test('synthetic zero network preserves shapes and selects tagger bias', () {
    final result = model.infer(const <SpacyTokenFeatures>[
      SpacyTokenFeatures(
        norm: 0,
        prefix: 1,
        suffix: -1,
        shape: -9223372036854775808,
        spacy: 1,
        isSpace: 0,
      ),
      SpacyTokenFeatures(
        norm: 81985529216486895,
        prefix: -81985529216486896,
        suffix: 2,
        shape: 3,
        spacy: 0,
        isSpace: 1,
      ),
    ]);

    expect((result.projected.rows, result.projected.columns), (2, 96));
    expect((result.encoded.rows, result.encoded.columns), (2, 96));
    expect((result.scores.rows, result.scores.columns), (2, 50));
    expect(result.projected.toFloat32List(), everyElement(0.0));
    expect(result.encoded.toFloat32List(), everyElement(0.0));
    expect(result.tagIndices, const <int>[42, 42]);
    expect(result.tags, const <String>['VBZ', 'VBZ']);
    expect(result.scores.valueAt(0, 42), 3.0);
    expect(result.scores.valueAt(1, 0), -1.0);
  });

  test('empty input has exact matrix contracts', () {
    final result = model.infer(const <SpacyTokenFeatures>[]);
    expect((result.projected.rows, result.projected.columns), (0, 96));
    expect((result.encoded.rows, result.encoded.columns), (0, 96));
    expect((result.scores.rows, result.scores.columns), (0, 50));
    expect(result.tagIndices, isEmpty);
    expect(result.tags, isEmpty);
  });

  test('rejects a sequence beyond the explicit model bound', () {
    const feature = SpacyTokenFeatures(
      norm: 0,
      prefix: 0,
      suffix: 0,
      shape: 0,
      spacy: 0,
      isSpace: 0,
    );
    expect(
      () => model.infer(
        List<SpacyTokenFeatures>.filled(
          maximumSpacyEnglishModelTokens + 1,
          feature,
        ),
      ),
      throwsRangeError,
    );
  });

  test('parameter objects reject invalid shapes and non-finite values', () {
    expect(
      () => SpacyEmbeddingTableParameters(rows: 1, values: Float32List(95)),
      throwsArgumentError,
    );
    final nonFinite = Float32List(96)..[7] = double.nan;
    expect(
      () => SpacyEmbeddingTableParameters(rows: 1, values: nonFinite),
      throwsArgumentError,
    );
    expect(
      () => SpacyTaggerLinearParameters(
        weights: Float32List(50 * 96 - 1),
        biases: Float32List(50),
      ),
      throwsArgumentError,
    );
    final source = Float32List(96)..[0] = 1;
    final copied = SpacyEmbeddingTableParameters(rows: 1, values: source);
    source[0] = 2;
    expect(copied.valueAt(0, 0), 1);
  });

  test('fine-grained tag labels retain the exact serialized output order', () {
    expect(SpacyEnglishTaggerModel.labels, _expectedLabels);
  });
}

SpacyEnglishModelParameters _zeroModelWithTagBias(int tag) {
  final tagBiases = Float32List(SpacyEnglishModelParameters.tagCount);
  tagBiases.fillRange(0, tagBiases.length, -1);
  tagBiases[tag] = 3;
  return SpacyEnglishModelParameters(
    embeddingTables: <SpacyEmbeddingTableParameters>[
      for (final rows in SpacyEnglishModelParameters.embeddingRows)
        SpacyEmbeddingTableParameters(
          rows: rows,
          values: Float32List(rows * SpacyEnglishModelParameters.width),
        ),
    ],
    projection: _zeroMaxout(SpacyEnglishModelParameters.projectionInputWidth),
    encoderLayers: <SpacyMaxoutLayerParameters>[
      for (
        var index = 0;
        index < SpacyEnglishModelParameters.encoderDepth;
        index++
      )
        _zeroMaxout(SpacyEnglishModelParameters.encoderInputWidth),
    ],
    tagger: SpacyTaggerLinearParameters(
      weights: Float32List(
        SpacyEnglishModelParameters.tagCount *
            SpacyEnglishModelParameters.width,
      ),
      biases: tagBiases,
    ),
  );
}

SpacyMaxoutLayerParameters _zeroMaxout(int inputWidth) =>
    SpacyMaxoutLayerParameters(
      inputWidth: inputWidth,
      weights: Float32List(
        SpacyEnglishModelParameters.width *
            SpacyEnglishModelParameters.maxoutPieces *
            inputWidth,
      ),
      biases: Float32List(
        SpacyEnglishModelParameters.width *
            SpacyEnglishModelParameters.maxoutPieces,
      ),
      layerNormGain: Float32List(SpacyEnglishModelParameters.width)
        ..fillRange(0, SpacyEnglishModelParameters.width, 1),
      layerNormBias: Float32List(SpacyEnglishModelParameters.width),
    );

const List<String> _expectedLabels = <String>[
  r'$',
  "''",
  ',',
  '-LRB-',
  '-RRB-',
  '.',
  ':',
  'ADD',
  'AFX',
  'CC',
  'CD',
  'DT',
  'EX',
  'FW',
  'HYPH',
  'IN',
  'JJ',
  'JJR',
  'JJS',
  'LS',
  'MD',
  'NFP',
  'NN',
  'NNP',
  'NNPS',
  'NNS',
  'PDT',
  'POS',
  'PRP',
  r'PRP$',
  'RB',
  'RBR',
  'RBS',
  'RP',
  'SYM',
  'TO',
  'UH',
  'VB',
  'VBD',
  'VBG',
  'VBN',
  'VBP',
  'VBZ',
  'WDT',
  'WP',
  r'WP$',
  'WRB',
  'XX',
  '_SP',
  '``',
];
