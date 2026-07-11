import 'dart:typed_data';

/// Parameters for one exact 96-wide spaCy hash-embedding table.
final class SpacyEmbeddingTableParameters {
  /// Copies and validates one row-major embedding [values] array.
  SpacyEmbeddingTableParameters({
    required this.rows,
    required Float32List values,
  }) : _values = _copyFinite(values, 'embedding values') {
    if (rows <= 0) {
      throw RangeError.range(rows, 1, null, 'rows');
    }
    final expected = rows * SpacyEnglishModelParameters.width;
    if (_values.length != expected) {
      throw ArgumentError.value(
        _values.length,
        'values.length',
        'expected $rows x ${SpacyEnglishModelParameters.width} = $expected',
      );
    }
  }

  /// Number of hash buckets in this table.
  final int rows;

  final Float32List _values;

  /// Reads one immutable parameter value.
  double valueAt(int row, int column) {
    RangeError.checkValidIndex(row, this, 'row', rows);
    RangeError.checkValidIndex(
      column,
      this,
      'column',
      SpacyEnglishModelParameters.width,
    );
    return _values[row * SpacyEnglishModelParameters.width + column];
  }
}

/// Parameters for a 96-output, three-piece maxout followed by layer norm.
final class SpacyMaxoutLayerParameters {
  /// Copies and validates row-major maxout and layer-normalization parameters.
  SpacyMaxoutLayerParameters({
    required this.inputWidth,
    required Float32List weights,
    required Float32List biases,
    required Float32List layerNormGain,
    required Float32List layerNormBias,
  }) : _weights = _copyFinite(weights, 'maxout weights'),
       _biases = _copyFinite(biases, 'maxout biases'),
       _layerNormGain = _copyFinite(layerNormGain, 'layer-norm gain'),
       _layerNormBias = _copyFinite(layerNormBias, 'layer-norm bias') {
    if (inputWidth <= 0) {
      throw RangeError.range(inputWidth, 1, null, 'inputWidth');
    }
    _requireLength(
      _weights,
      SpacyEnglishModelParameters.width *
          SpacyEnglishModelParameters.maxoutPieces *
          inputWidth,
      'weights',
    );
    _requireLength(
      _biases,
      SpacyEnglishModelParameters.width *
          SpacyEnglishModelParameters.maxoutPieces,
      'biases',
    );
    _requireLength(
      _layerNormGain,
      SpacyEnglishModelParameters.width,
      'layerNormGain',
    );
    _requireLength(
      _layerNormBias,
      SpacyEnglishModelParameters.width,
      'layerNormBias',
    );
  }

  /// Input width expected by this affine maxout layer.
  final int inputWidth;

  final Float32List _weights;
  final Float32List _biases;
  final Float32List _layerNormGain;
  final Float32List _layerNormBias;

  /// Reads `W[output, piece, input]` from the immutable parameter copy.
  double weightAt(int output, int piece, int input) {
    _checkOutputPieceInput(output, piece, input);
    return _weights[(output * SpacyEnglishModelParameters.maxoutPieces +
                piece) *
            inputWidth +
        input];
  }

  /// Reads `b[output, piece]` from the immutable parameter copy.
  double biasAt(int output, int piece) {
    _checkOutputPiece(output, piece);
    return _biases[output * SpacyEnglishModelParameters.maxoutPieces + piece];
  }

  /// Reads the layer-normalization gain for one output dimension.
  double layerNormGainAt(int output) {
    RangeError.checkValidIndex(
      output,
      this,
      'output',
      SpacyEnglishModelParameters.width,
    );
    return _layerNormGain[output];
  }

  /// Reads the layer-normalization bias for one output dimension.
  double layerNormBiasAt(int output) {
    RangeError.checkValidIndex(
      output,
      this,
      'output',
      SpacyEnglishModelParameters.width,
    );
    return _layerNormBias[output];
  }

  void _checkOutputPieceInput(int output, int piece, int input) {
    _checkOutputPiece(output, piece);
    RangeError.checkValidIndex(input, this, 'input', inputWidth);
  }

  void _checkOutputPiece(int output, int piece) {
    RangeError.checkValidIndex(
      output,
      this,
      'output',
      SpacyEnglishModelParameters.width,
    );
    RangeError.checkValidIndex(
      piece,
      this,
      'piece',
      SpacyEnglishModelParameters.maxoutPieces,
    );
  }
}

/// Parameters for the final unnormalized 50-by-96 tagger projection.
final class SpacyTaggerLinearParameters {
  /// Copies and validates the final row-major [weights] and [biases].
  SpacyTaggerLinearParameters({
    required Float32List weights,
    required Float32List biases,
  }) : _weights = _copyFinite(weights, 'tagger weights'),
       _biases = _copyFinite(biases, 'tagger biases') {
    _requireLength(
      _weights,
      SpacyEnglishModelParameters.tagCount * SpacyEnglishModelParameters.width,
      'weights',
    );
    _requireLength(_biases, SpacyEnglishModelParameters.tagCount, 'biases');
  }

  final Float32List _weights;
  final Float32List _biases;

  /// Reads `W[tag, input]` from the immutable parameter copy.
  double weightAt(int tag, int input) {
    RangeError.checkValidIndex(
      tag,
      this,
      'tag',
      SpacyEnglishModelParameters.tagCount,
    );
    RangeError.checkValidIndex(
      input,
      this,
      'input',
      SpacyEnglishModelParameters.width,
    );
    return _weights[tag * SpacyEnglishModelParameters.width + input];
  }

  /// Reads the bias for one tag index.
  double biasAt(int tag) {
    RangeError.checkValidIndex(
      tag,
      this,
      'tag',
      SpacyEnglishModelParameters.tagCount,
    );
    return _biases[tag];
  }
}

/// Immutable, shape-validated parameters for `en_core_web_sm==3.8.0`.
final class SpacyEnglishModelParameters {
  /// Creates the exact pinned tok2vec and tagger parameter tuple.
  SpacyEnglishModelParameters({
    required List<SpacyEmbeddingTableParameters> embeddingTables,
    required this.projection,
    required List<SpacyMaxoutLayerParameters> encoderLayers,
    required this.tagger,
  }) : embeddingTables = List<SpacyEmbeddingTableParameters>.unmodifiable(
         embeddingTables,
       ),
       encoderLayers = List<SpacyMaxoutLayerParameters>.unmodifiable(
         encoderLayers,
       ) {
    if (this.embeddingTables.length != embeddingRows.length) {
      throw ArgumentError.value(
        this.embeddingTables.length,
        'embeddingTables.length',
        'expected ${embeddingRows.length}',
      );
    }
    for (var index = 0; index < embeddingRows.length; index++) {
      if (this.embeddingTables[index].rows != embeddingRows[index]) {
        throw ArgumentError.value(
          this.embeddingTables[index].rows,
          'embeddingTables[$index].rows',
          'expected ${embeddingRows[index]}',
        );
      }
    }
    if (projection.inputWidth != projectionInputWidth) {
      throw ArgumentError.value(
        projection.inputWidth,
        'projection.inputWidth',
        'expected $projectionInputWidth',
      );
    }
    if (this.encoderLayers.length != encoderDepth) {
      throw ArgumentError.value(
        this.encoderLayers.length,
        'encoderLayers.length',
        'expected $encoderDepth',
      );
    }
    for (var index = 0; index < this.encoderLayers.length; index++) {
      if (this.encoderLayers[index].inputWidth != encoderInputWidth) {
        throw ArgumentError.value(
          this.encoderLayers[index].inputWidth,
          'encoderLayers[$index].inputWidth',
          'expected $encoderInputWidth',
        );
      }
    }
  }

  /// Tok2vec vector width.
  static const int width = 96;

  /// Number of maxout pieces per output.
  static const int maxoutPieces = 3;

  /// Exact row counts for NORM, PREFIX, SUFFIX, SHAPE, SPACY, and IS_SPACE.
  static const List<int> embeddingRows = <int>[5000, 1000, 2500, 2500, 50, 50];

  /// Exact per-attribute hash seeds.
  static const List<int> embeddingSeeds = <int>[8, 9, 10, 11, 12, 13];

  /// Concatenated input width of the embedding projection.
  static const int projectionInputWidth = width * 6;

  /// Input width after concatenating previous, current, and next vectors.
  static const int encoderInputWidth = width * 3;

  /// Number of residual convolutional encoder layers.
  static const int encoderDepth = 4;

  /// Number of zero rows placed at each sequence edge.
  static const int encoderEdgePadding = encoderDepth;

  /// Exact number of fine-grained English tags.
  static const int tagCount = 50;

  /// Six hash-embedding tables in feature-column order.
  final List<SpacyEmbeddingTableParameters> embeddingTables;

  /// Initial 576-to-96 maxout and layer-normalization projection.
  final SpacyMaxoutLayerParameters projection;

  /// Four 288-to-96 residual maxout and layer-normalization layers.
  final List<SpacyMaxoutLayerParameters> encoderLayers;

  /// Final unnormalized 50-by-96 tagger projection.
  final SpacyTaggerLinearParameters tagger;
}

Float32List _copyFinite(Float32List source, String name) {
  final result = Float32List.fromList(source);
  for (var index = 0; index < result.length; index++) {
    if (!result[index].isFinite) {
      throw ArgumentError.value(
        result[index],
        '$name[$index]',
        'must be finite',
      );
    }
  }
  return result;
}

void _requireLength(Float32List values, int expected, String name) {
  if (values.length != expected) {
    throw ArgumentError.value(
      values.length,
      '$name.length',
      'expected $expected',
    );
  }
}
