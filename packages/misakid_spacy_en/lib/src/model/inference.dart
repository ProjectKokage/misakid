import 'dart:typed_data';

import 'murmur_hash.dart';
import 'parameters.dart';

/// Maximum token count accepted by one inference call.
const int maximumSpacyEnglishModelTokens = 65536;

/// Six exact uint64 lexical feature bit patterns for one spaCy token.
final class SpacyTokenFeatures {
  /// Creates one feature row in NORM, PREFIX, SUFFIX, SHAPE, SPACY, IS_SPACE
  /// order.
  const SpacyTokenFeatures({
    required this.norm,
    required this.prefix,
    required this.suffix,
    required this.shape,
    required this.spacy,
    required this.isSpace,
  });

  /// spaCy NORM string-store ID bit pattern.
  final int norm;

  /// spaCy PREFIX string-store ID bit pattern.
  final int prefix;

  /// spaCy SUFFIX string-store ID bit pattern.
  final int suffix;

  /// spaCy SHAPE string-store ID bit pattern.
  final int shape;

  /// spaCy SPACY boolean feature ID bit pattern.
  final int spacy;

  /// spaCy IS_SPACE boolean feature ID bit pattern.
  final int isSpace;

  int _at(int index) => switch (index) {
    0 => norm,
    1 => prefix,
    2 => suffix,
    3 => shape,
    4 => spacy,
    5 => isSpace,
    _ => throw RangeError.index(index, this, 'index', null, 6),
  };
}

/// Immutable row-major float32 matrix returned by model inference.
final class SpacyFloat32Matrix {
  SpacyFloat32Matrix._(this.rows, this.columns, Float32List values)
    : _values = values;

  /// Row count.
  final int rows;

  /// Column count.
  final int columns;

  final Float32List _values;

  /// Reads one matrix value.
  double valueAt(int row, int column) {
    RangeError.checkValidIndex(row, this, 'row', rows);
    RangeError.checkValidIndex(column, this, 'column', columns);
    return _values[row * columns + column];
  }

  /// Returns a defensive float32 copy of one row.
  Float32List rowValues(int row) {
    RangeError.checkValidIndex(row, this, 'row', rows);
    final start = row * columns;
    return Float32List.fromList(_values.sublist(start, start + columns));
  }

  /// Returns a defensive row-major float32 copy.
  Float32List toFloat32List() => Float32List.fromList(_values);
}

/// Exact intermediate vectors and tags from one inference call.
final class SpacyEnglishInferenceResult {
  SpacyEnglishInferenceResult._({
    required this.projected,
    required this.encoded,
    required this.scores,
    required List<int> tagIndices,
    required List<String> tags,
  }) : tagIndices = List<int>.unmodifiable(tagIndices),
       tags = List<String>.unmodifiable(tags);

  /// Output of the six-table concat/maxout/layer-normalization stage.
  final SpacyFloat32Matrix projected;

  /// Output of the four residual window-encoder layers.
  final SpacyFloat32Matrix encoded;

  /// Unnormalized 50-wide tagger scores.
  final SpacyFloat32Matrix scores;

  /// Argmax tag indices in source-token order.
  final List<int> tagIndices;

  /// Fine-grained spaCy tag labels in source-token order.
  final List<String> tags;
}

/// Pure-Dart inference for the exact pinned small English tok2vec and tagger.
final class SpacyEnglishTaggerModel {
  /// Creates a reusable inference engine over immutable [parameters].
  const SpacyEnglishTaggerModel(this.parameters);

  /// Exact `en_core_web_sm==3.8.0` tag labels in model-output order.
  static const List<String> labels = <String>[
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

  /// Shape-validated model parameters.
  final SpacyEnglishModelParameters parameters;

  /// Runs deterministic float32 inference for one token sequence.
  SpacyEnglishInferenceResult infer(List<SpacyTokenFeatures> features) {
    if (features.length > maximumSpacyEnglishModelTokens) {
      throw RangeError.range(
        features.length,
        0,
        maximumSpacyEnglishModelTokens,
        'features.length',
      );
    }
    if (features.isEmpty) {
      return SpacyEnglishInferenceResult._(
        projected: SpacyFloat32Matrix._(
          0,
          SpacyEnglishModelParameters.width,
          Float32List(0),
        ),
        encoded: SpacyFloat32Matrix._(
          0,
          SpacyEnglishModelParameters.width,
          Float32List(0),
        ),
        scores: SpacyFloat32Matrix._(
          0,
          SpacyEnglishModelParameters.tagCount,
          Float32List(0),
        ),
        tagIndices: const <int>[],
        tags: const <String>[],
      );
    }

    final arithmetic = _Float32Arithmetic();
    final projectedValues = _projectFeatures(features, arithmetic);
    final encodedValues = _encode(projectedValues, features.length, arithmetic);
    final scoresValues = _score(encodedValues, features.length, arithmetic);
    final tagIndices = _argmaxTags(scoresValues, features.length);
    return SpacyEnglishInferenceResult._(
      projected: SpacyFloat32Matrix._(
        features.length,
        SpacyEnglishModelParameters.width,
        projectedValues,
      ),
      encoded: SpacyFloat32Matrix._(
        features.length,
        SpacyEnglishModelParameters.width,
        encodedValues,
      ),
      scores: SpacyFloat32Matrix._(
        features.length,
        SpacyEnglishModelParameters.tagCount,
        scoresValues,
      ),
      tagIndices: tagIndices,
      tags: <String>[for (final index in tagIndices) labels[index]],
    );
  }

  Float32List _projectFeatures(
    List<SpacyTokenFeatures> features,
    _Float32Arithmetic arithmetic,
  ) {
    final tokenCount = features.length;
    final concatenated = Float32List(
      tokenCount * SpacyEnglishModelParameters.projectionInputWidth,
    );
    for (var tokenIndex = 0; tokenIndex < tokenCount; tokenIndex++) {
      final feature = features[tokenIndex];
      for (
        var attribute = 0;
        attribute < SpacyEnglishModelParameters.embeddingRows.length;
        attribute++
      ) {
        final table = parameters.embeddingTables[attribute];
        final keys = murmurHash3X86_128Uint64(
          feature._at(attribute),
          SpacyEnglishModelParameters.embeddingSeeds[attribute],
        );
        final outputOffset =
            tokenIndex * SpacyEnglishModelParameters.projectionInputWidth +
            attribute * SpacyEnglishModelParameters.width;
        for (
          var column = 0;
          column < SpacyEnglishModelParameters.width;
          column++
        ) {
          var sum = 0.0;
          for (final key in keys) {
            sum = arithmetic.add(sum, table.valueAt(key % table.rows, column));
          }
          concatenated[outputOffset + column] = sum;
        }
      }
    }
    return _maxoutLayer(
      concatenated,
      tokenCount,
      parameters.projection,
      arithmetic,
    );
  }

  Float32List _encode(
    Float32List projected,
    int tokenCount,
    _Float32Arithmetic arithmetic,
  ) {
    const padding = SpacyEnglishModelParameters.encoderEdgePadding;
    final paddedRows = tokenCount + 2 * padding;
    var current = Float32List(paddedRows * SpacyEnglishModelParameters.width);
    current.setRange(
      padding * SpacyEnglishModelParameters.width,
      (padding + tokenCount) * SpacyEnglishModelParameters.width,
      projected,
    );

    for (final layer in parameters.encoderLayers) {
      final expanded = Float32List(
        paddedRows * SpacyEnglishModelParameters.encoderInputWidth,
      );
      for (var row = 0; row < paddedRows; row++) {
        final expandedOffset =
            row * SpacyEnglishModelParameters.encoderInputWidth;
        for (var relative = -1; relative <= 1; relative++) {
          final sourceRow = row + relative;
          if (sourceRow < 0 || sourceRow >= paddedRows) continue;
          final sourceOffset = sourceRow * SpacyEnglishModelParameters.width;
          final targetOffset =
              expandedOffset +
              (relative + 1) * SpacyEnglishModelParameters.width;
          expanded.setRange(
            targetOffset,
            targetOffset + SpacyEnglishModelParameters.width,
            current,
            sourceOffset,
          );
        }
      }
      final transformed = _maxoutLayer(expanded, paddedRows, layer, arithmetic);
      for (var index = 0; index < current.length; index++) {
        current[index] = arithmetic.add(current[index], transformed[index]);
      }
    }

    final result = Float32List(tokenCount * SpacyEnglishModelParameters.width);
    result.setRange(
      0,
      result.length,
      current,
      padding * SpacyEnglishModelParameters.width,
    );
    return result;
  }

  Float32List _score(
    Float32List encoded,
    int tokenCount,
    _Float32Arithmetic arithmetic,
  ) {
    final result = Float32List(
      tokenCount * SpacyEnglishModelParameters.tagCount,
    );
    for (var row = 0; row < tokenCount; row++) {
      final inputOffset = row * SpacyEnglishModelParameters.width;
      final outputOffset = row * SpacyEnglishModelParameters.tagCount;
      for (var tag = 0; tag < SpacyEnglishModelParameters.tagCount; tag++) {
        var sum = 0.0;
        for (
          var input = 0;
          input < SpacyEnglishModelParameters.width;
          input++
        ) {
          sum = arithmetic.multiplyAdd(
            sum,
            encoded[inputOffset + input],
            parameters.tagger.weightAt(tag, input),
          );
        }
        result[outputOffset + tag] = arithmetic.add(
          sum,
          parameters.tagger.biasAt(tag),
        );
      }
    }
    return result;
  }

  List<int> _argmaxTags(Float32List scores, int tokenCount) {
    final result = <int>[];
    for (var row = 0; row < tokenCount; row++) {
      final offset = row * SpacyEnglishModelParameters.tagCount;
      var bestIndex = 0;
      var bestValue = scores[offset];
      for (var tag = 1; tag < SpacyEnglishModelParameters.tagCount; tag++) {
        final value = scores[offset + tag];
        if (value > bestValue) {
          bestValue = value;
          bestIndex = tag;
        }
      }
      result.add(bestIndex);
    }
    return result;
  }
}

Float32List _maxoutLayer(
  Float32List input,
  int rows,
  SpacyMaxoutLayerParameters parameters,
  _Float32Arithmetic arithmetic,
) {
  if (input.length != rows * parameters.inputWidth) {
    throw StateError(
      'Maxout input has ${input.length} values; '
      '${rows * parameters.inputWidth} are required.',
    );
  }
  final maxout = Float32List(rows * SpacyEnglishModelParameters.width);
  for (var row = 0; row < rows; row++) {
    final inputOffset = row * parameters.inputWidth;
    final outputOffset = row * SpacyEnglishModelParameters.width;
    for (var output = 0; output < SpacyEnglishModelParameters.width; output++) {
      var best = double.negativeInfinity;
      for (
        var piece = 0;
        piece < SpacyEnglishModelParameters.maxoutPieces;
        piece++
      ) {
        var sum = 0.0;
        for (
          var inputIndex = 0;
          inputIndex < parameters.inputWidth;
          inputIndex++
        ) {
          sum = arithmetic.multiplyAdd(
            sum,
            input[inputOffset + inputIndex],
            parameters.weightAt(output, piece, inputIndex),
          );
        }
        sum = arithmetic.add(sum, parameters.biasAt(output, piece));
        if (piece == 0 || sum > best) best = sum;
      }
      maxout[outputOffset + output] = best;
    }
  }
  return _layerNormalize(maxout, rows, parameters, arithmetic);
}

Float32List _layerNormalize(
  Float32List input,
  int rows,
  SpacyMaxoutLayerParameters parameters,
  _Float32Arithmetic arithmetic,
) {
  final result = Float32List(input.length);
  for (var row = 0; row < rows; row++) {
    final offset = row * SpacyEnglishModelParameters.width;
    var sum = 0.0;
    for (var column = 0; column < SpacyEnglishModelParameters.width; column++) {
      sum = arithmetic.add(sum, input[offset + column]);
    }
    final mean = arithmetic.divide(sum, SpacyEnglishModelParameters.width);

    var squaredSum = 0.0;
    for (var column = 0; column < SpacyEnglishModelParameters.width; column++) {
      final distance = arithmetic.subtract(input[offset + column], mean);
      squaredSum = arithmetic.add(
        squaredSum,
        arithmetic.multiply(distance, distance),
      );
    }
    var variance = arithmetic.divide(
      squaredSum,
      SpacyEnglishModelParameters.width,
    );
    variance = arithmetic.add(variance, 1e-8);
    final inverseStandardDeviation = arithmetic.inverseSquareRoot(variance);

    for (var column = 0; column < SpacyEnglishModelParameters.width; column++) {
      final normalized = arithmetic.multiply(
        arithmetic.subtract(input[offset + column], mean),
        inverseStandardDeviation,
      );
      result[offset + column] = arithmetic.add(
        arithmetic.multiply(normalized, parameters.layerNormGainAt(column)),
        parameters.layerNormBiasAt(column),
      );
    }
  }
  return result;
}

final class _Float32Arithmetic {
  final Float32List _scratch = Float32List(1);

  double round(double value) {
    _scratch[0] = value;
    return _scratch[0];
  }

  double add(double left, double right) => round(left + right);

  double subtract(double left, double right) => round(left - right);

  double multiply(double left, double right) => round(left * right);

  double divide(double left, num right) => round(left / right);

  double multiplyAdd(double accumulator, double left, double right) =>
      add(accumulator, multiply(left, right));

  double inverseSquareRoot(double value) =>
      Float32x4(value, value, value, value).sqrt().reciprocal().x;
}
