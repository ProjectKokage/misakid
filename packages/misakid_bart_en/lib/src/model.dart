// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:misakid/misaki.dart';

import 'config.dart';
import 'matrix.dart';
import 'safetensors.dart';

const double _maximumAbsoluteWeight = 1000;

/// Deterministic batch-one, one-layer BART conditional-generation graph.
final class BartModel {
  BartModel._({required this.config, required Map<String, BartTensor> tensors})
    : _tensors = tensors,
      _matrixTensors = Map<String, F32Matrix>.unmodifiable(<String, F32Matrix>{
        for (final entry in tensors.entries)
          if (entry.value.shape.length == 2)
            entry.key: F32Matrix.fromTensor(entry.value),
      }),
      _shared = F32Matrix.fromTensor(tensors['model.shared.weight']!),
      _encoderPositions = F32Matrix.fromTensor(
        tensors['model.encoder.embed_positions.weight']!,
      ),
      _decoderPositions = F32Matrix.fromTensor(
        tensors['model.decoder.embed_positions.weight']!,
      ),
      _finalLogitsBias = tensors['final_logits_bias']!.values;

  /// Validates the exact name/shape whitelist and creates a reusable model.
  factory BartModel.load(BartConfig config, BartSafetensors weights) {
    final expected = _expectedShapes(config);
    final actualNames = weights.tensors.keys.toSet();
    final expectedNames = expected.keys.toSet();
    if (actualNames.length != expectedNames.length ||
        !actualNames.containsAll(expectedNames)) {
      final missing = expectedNames.difference(actualNames).toList()..sort();
      final unexpected = actualNames.difference(expectedNames).toList()..sort();
      throw MalformedDataException(
        'The BART tensor-name whitelist does not match '
        '(missing: ${missing.join(', ')}, unexpected: ${unexpected.join(', ')}).',
      );
    }
    for (final entry in expected.entries) {
      final tensor = weights.tensors[entry.key]!;
      final actual = tensor.shape;
      if (!_sameShape(actual, entry.value)) {
        throw MalformedDataException(
          'BART tensor `${entry.key}` has shape $actual; expected ${entry.value}.',
        );
      }
      if (tensor.values.any((value) => value.abs() > _maximumAbsoluteWeight)) {
        throw MalformedDataException(
          'BART tensor `${entry.key}` exceeds the supported absolute weight bound.',
        );
      }
    }
    return BartModel._(config: config, tensors: weights.tensors);
  }

  final BartConfig config;
  final Map<String, BartTensor> _tensors;
  final Map<String, F32Matrix> _matrixTensors;
  final F32Matrix _shared;
  final F32Matrix _encoderPositions;
  final F32Matrix _decoderPositions;
  final Float32List _finalLogitsBias;
  final F32Arithmetic _f32 = F32Arithmetic();

  /// Returns full generated IDs, including decoder start and terminal EOS.
  List<int> generate(List<int> inputIds, {required int maximumLength}) {
    if (maximumLength < 2 || maximumLength > config.maxPositionEmbeddings) {
      throw BackendFailureException(
        'BART generation length must be between 2 and ${config.maxPositionEmbeddings}.',
      );
    }
    final encoder = encode(inputIds);
    final encoderMask = inputIds.map((id) => id != 0).toList(growable: false);
    final decoderIds = <int>[1];
    while (decoderIds.length < maximumLength) {
      final next = decoderIds.length == maximumLength - 1
          ? 2
          : _argmax(
              decode(
                decoderIds,
                encoderOutput: encoder,
                encoderMask: encoderMask,
              ),
            );
      decoderIds.add(next);
      if (next == 2) break;
    }
    return List<int>.unmodifiable(decoderIds);
  }

  /// Computes encoder hidden states for one token-ID sequence.
  F32Matrix encode(List<int> inputIds) {
    _validateIds(inputIds, label: 'encoder');
    var hidden = _embed(inputIds, _encoderPositions);
    hidden = _layerNorm(
      hidden,
      _tensor1('model.encoder.layernorm_embedding.weight'),
      _tensor1('model.encoder.layernorm_embedding.bias'),
    );
    final mask = inputIds.map((id) => id != 0).toList(growable: false);
    final residualAttention = hidden;
    final attention = _attention(
      query: hidden,
      key: hidden,
      value: hidden,
      heads: config.encoderAttentionHeads,
      prefix: 'model.encoder.layers.0.self_attn',
      keyMask: mask,
      causal: false,
    );
    hidden = _layerNorm(
      _add(residualAttention, attention),
      _tensor1('model.encoder.layers.0.self_attn_layer_norm.weight'),
      _tensor1('model.encoder.layers.0.self_attn_layer_norm.bias'),
    );
    final residualFeedForward = hidden;
    hidden = _linear(
      hidden,
      _tensor2('model.encoder.layers.0.fc1.weight'),
      _tensor1('model.encoder.layers.0.fc1.bias'),
    );
    hidden = _gelu(hidden);
    hidden = _linear(
      hidden,
      _tensor2('model.encoder.layers.0.fc2.weight'),
      _tensor1('model.encoder.layers.0.fc2.bias'),
    );
    return _layerNorm(
      _add(residualFeedForward, hidden),
      _tensor1('model.encoder.layers.0.final_layer_norm.weight'),
      _tensor1('model.encoder.layers.0.final_layer_norm.bias'),
    );
  }

  /// Computes vocabulary logits for every current decoder position.
  F32Matrix decode(
    List<int> decoderIds, {
    required F32Matrix encoderOutput,
    required List<bool> encoderMask,
  }) {
    _validateIds(decoderIds, label: 'decoder');
    if (encoderOutput.columns != config.dModel ||
        encoderMask.length != encoderOutput.rows ||
        !encoderMask.any((value) => value)) {
      throw const BackendFailureException(
        'BART encoder output or attention mask is invalid.',
      );
    }
    var hidden = _embed(decoderIds, _decoderPositions);
    hidden = _layerNorm(
      hidden,
      _tensor1('model.decoder.layernorm_embedding.weight'),
      _tensor1('model.decoder.layernorm_embedding.bias'),
    );

    final residualSelfAttention = hidden;
    hidden = _attention(
      query: hidden,
      key: hidden,
      value: hidden,
      heads: config.decoderAttentionHeads,
      prefix: 'model.decoder.layers.0.self_attn',
      keyMask: List<bool>.filled(hidden.rows, true, growable: false),
      causal: true,
    );
    hidden = _layerNorm(
      _add(residualSelfAttention, hidden),
      _tensor1('model.decoder.layers.0.self_attn_layer_norm.weight'),
      _tensor1('model.decoder.layers.0.self_attn_layer_norm.bias'),
    );

    final residualCrossAttention = hidden;
    hidden = _attention(
      query: hidden,
      key: encoderOutput,
      value: encoderOutput,
      heads: config.decoderAttentionHeads,
      prefix: 'model.decoder.layers.0.encoder_attn',
      keyMask: encoderMask,
      causal: false,
    );
    hidden = _layerNorm(
      _add(residualCrossAttention, hidden),
      _tensor1('model.decoder.layers.0.encoder_attn_layer_norm.weight'),
      _tensor1('model.decoder.layers.0.encoder_attn_layer_norm.bias'),
    );

    final residualFeedForward = hidden;
    hidden = _linear(
      hidden,
      _tensor2('model.decoder.layers.0.fc1.weight'),
      _tensor1('model.decoder.layers.0.fc1.bias'),
    );
    hidden = _gelu(hidden);
    hidden = _linear(
      hidden,
      _tensor2('model.decoder.layers.0.fc2.weight'),
      _tensor1('model.decoder.layers.0.fc2.bias'),
    );
    hidden = _layerNorm(
      _add(residualFeedForward, hidden),
      _tensor1('model.decoder.layers.0.final_layer_norm.weight'),
      _tensor1('model.decoder.layers.0.final_layer_norm.bias'),
    );
    return _languageModelHead(hidden);
  }

  void _validateIds(List<int> ids, {required String label}) {
    if (ids.isEmpty || ids.length > config.maxPositionEmbeddings) {
      throw BackendFailureException(
        'The BART $label sequence length is outside the configured positional bound.',
      );
    }
    if (ids.any((id) => id < 0 || id >= config.vocabSize)) {
      throw BackendFailureException(
        'The BART $label sequence contains an out-of-vocabulary token ID.',
      );
    }
  }

  F32Matrix _embed(List<int> ids, F32Matrix positions) {
    final result = F32Matrix(rows: ids.length, columns: config.dModel);
    for (var row = 0; row < ids.length; row++) {
      for (var column = 0; column < config.dModel; column++) {
        result.set(
          row,
          column,
          _f32.add(
            _shared.get(ids[row], column),
            positions.get(row + 2, column),
          ),
        );
      }
    }
    return result;
  }

  F32Matrix _attention({
    required F32Matrix query,
    required F32Matrix key,
    required F32Matrix value,
    required int heads,
    required String prefix,
    required List<bool> keyMask,
    required bool causal,
  }) {
    if (key.rows != value.rows ||
        key.columns != config.dModel ||
        value.columns != config.dModel ||
        query.columns != config.dModel ||
        keyMask.length != key.rows) {
      throw const BackendFailureException(
        'Invalid internal BART attention shape.',
      );
    }
    final projectedQuery = _linear(
      query,
      _tensor2('$prefix.q_proj.weight'),
      _tensor1('$prefix.q_proj.bias'),
    );
    final projectedKey = _linear(
      key,
      _tensor2('$prefix.k_proj.weight'),
      _tensor1('$prefix.k_proj.bias'),
    );
    final projectedValue = _linear(
      value,
      _tensor2('$prefix.v_proj.weight'),
      _tensor1('$prefix.v_proj.bias'),
    );
    final result = F32Matrix(rows: query.rows, columns: config.dModel);
    final headDimension = config.dModel ~/ heads;
    final scale = _f32.round(1 / math.sqrt(headDimension));
    for (var index = 0; index < projectedQuery.values.length; index++) {
      projectedQuery.values[index] = _f32.multiply(
        projectedQuery.values[index],
        scale,
      );
    }
    final scores = Float32List(key.rows);
    final probabilities = Float32List(key.rows);
    for (var queryRow = 0; queryRow < query.rows; queryRow++) {
      for (var head = 0; head < heads; head++) {
        final headOffset = head * headDimension;
        var maximum = -double.infinity;
        for (var keyRow = 0; keyRow < key.rows; keyRow++) {
          if (!keyMask[keyRow] || (causal && keyRow > queryRow)) {
            scores[keyRow] = -double.infinity;
            continue;
          }
          var dot = 0.0;
          for (var offset = 0; offset < headDimension; offset++) {
            dot = _f32.multiplyAdd(
              dot,
              projectedQuery.get(queryRow, headOffset + offset),
              projectedKey.get(keyRow, headOffset + offset),
            );
          }
          scores[keyRow] = dot;
          if (dot > maximum) maximum = dot;
        }
        var denominator = 0.0;
        for (var keyRow = 0; keyRow < key.rows; keyRow++) {
          final score = scores[keyRow];
          if (!score.isFinite) {
            probabilities[keyRow] = 0;
            continue;
          }
          final exponent = _f32.round(math.exp(_f32.add(score, -maximum)));
          probabilities[keyRow] = exponent;
          denominator = _f32.add(denominator, exponent);
        }
        if (denominator == 0 || !denominator.isFinite) {
          throw const BackendFailureException(
            'BART attention normalization produced no finite probability.',
          );
        }
        for (var keyRow = 0; keyRow < key.rows; keyRow++) {
          probabilities[keyRow] = _f32.round(
            probabilities[keyRow] / denominator,
          );
        }
        for (var offset = 0; offset < headDimension; offset++) {
          var weighted = 0.0;
          for (var keyRow = 0; keyRow < key.rows; keyRow++) {
            weighted = _f32.multiplyAdd(
              weighted,
              probabilities[keyRow],
              projectedValue.get(keyRow, headOffset + offset),
            );
          }
          result.set(queryRow, headOffset + offset, weighted);
        }
      }
    }
    return _linear(
      result,
      _tensor2('$prefix.out_proj.weight'),
      _tensor1('$prefix.out_proj.bias'),
    );
  }

  F32Matrix _linear(F32Matrix input, F32Matrix weight, Float32List bias) {
    if (weight.columns != input.columns || bias.length != weight.rows) {
      throw const BackendFailureException(
        'Invalid internal BART linear shape.',
      );
    }
    final result = F32Matrix(rows: input.rows, columns: weight.rows);
    for (var row = 0; row < input.rows; row++) {
      for (var output = 0; output < weight.rows; output++) {
        var sum = bias[output];
        for (var inputColumn = 0; inputColumn < input.columns; inputColumn++) {
          sum = _f32.multiplyAdd(
            sum,
            input.get(row, inputColumn),
            weight.get(output, inputColumn),
          );
        }
        result.set(row, output, sum);
      }
    }
    return result;
  }

  F32Matrix _layerNorm(F32Matrix input, Float32List weight, Float32List bias) {
    if (weight.length != input.columns || bias.length != input.columns) {
      throw const BackendFailureException(
        'Invalid internal BART layer-normalization shape.',
      );
    }
    final result = F32Matrix(rows: input.rows, columns: input.columns);
    for (var row = 0; row < input.rows; row++) {
      var sum = 0.0;
      for (var column = 0; column < input.columns; column++) {
        sum = _f32.add(sum, input.get(row, column));
      }
      final mean = _f32.round(sum / input.columns);
      var squaredSum = 0.0;
      for (var column = 0; column < input.columns; column++) {
        final difference = _f32.add(input.get(row, column), -mean);
        squaredSum = _f32.multiplyAdd(squaredSum, difference, difference);
      }
      final variance = _f32.round(squaredSum / input.columns);
      final inverseStandardDeviation = _f32.round(
        1 / math.sqrt(_f32.add(variance, config.layerNormEpsilon)),
      );
      for (var column = 0; column < input.columns; column++) {
        final normalized = _f32.multiply(
          _f32.add(input.get(row, column), -mean),
          inverseStandardDeviation,
        );
        result.set(
          row,
          column,
          _f32.add(_f32.multiply(normalized, weight[column]), bias[column]),
        );
      }
    }
    return result;
  }

  F32Matrix _gelu(F32Matrix input) {
    final result = F32Matrix(rows: input.rows, columns: input.columns);
    for (var index = 0; index < input.values.length; index++) {
      final value = input.values[index];
      final probability = _f32.round(0.5 * (1 + _erf(value / math.sqrt2)));
      result.values[index] = _f32.multiply(value, probability);
    }
    return result;
  }

  F32Matrix _add(F32Matrix left, F32Matrix right) {
    if (left.rows != right.rows || left.columns != right.columns) {
      throw const BackendFailureException(
        'Invalid internal BART residual shape.',
      );
    }
    final result = F32Matrix(rows: left.rows, columns: left.columns);
    for (var index = 0; index < left.values.length; index++) {
      result.values[index] = _f32.add(left.values[index], right.values[index]);
    }
    return result;
  }

  F32Matrix _languageModelHead(F32Matrix hidden) {
    final result = F32Matrix(rows: hidden.rows, columns: config.vocabSize);
    for (var row = 0; row < hidden.rows; row++) {
      for (var token = 0; token < config.vocabSize; token++) {
        var sum = _finalLogitsBias[token];
        for (var column = 0; column < config.dModel; column++) {
          sum = _f32.multiplyAdd(
            sum,
            hidden.get(row, column),
            _shared.get(token, column),
          );
        }
        result.set(row, token, sum);
      }
    }
    return result;
  }

  int _argmax(F32Matrix logits) {
    final row = logits.rows - 1;
    var selected = 0;
    var maximum = logits.get(row, 0);
    for (var token = 1; token < logits.columns; token++) {
      final value = logits.get(row, token);
      if (value > maximum) {
        maximum = value;
        selected = token;
      }
    }
    return selected;
  }

  Float32List _tensor1(String name) => _tensors[name]!.values;

  F32Matrix _tensor2(String name) => _matrixTensors[name]!;
}

Map<String, List<int>> _expectedShapes(BartConfig config) {
  final d = config.dModel;
  final expected = <String, List<int>>{
    'model.shared.weight': <int>[config.vocabSize, d],
    'model.encoder.embed_positions.weight': <int>[
      config.maxPositionEmbeddings + 2,
      d,
    ],
    'model.decoder.embed_positions.weight': <int>[
      config.maxPositionEmbeddings + 2,
      d,
    ],
    'model.encoder.layernorm_embedding.weight': <int>[d],
    'model.encoder.layernorm_embedding.bias': <int>[d],
    'model.decoder.layernorm_embedding.weight': <int>[d],
    'model.decoder.layernorm_embedding.bias': <int>[d],
    'final_logits_bias': <int>[1, config.vocabSize],
  };
  _addAttentionShapes(
    expected,
    prefix: 'model.encoder.layers.0.self_attn',
    dModel: d,
  );
  _addLayerNormShape(
    expected,
    prefix: 'model.encoder.layers.0.self_attn_layer_norm',
    dModel: d,
  );
  _addFeedForwardShapes(
    expected,
    prefix: 'model.encoder.layers.0',
    dModel: d,
    ffnDimension: config.encoderFfnDim,
  );
  _addLayerNormShape(
    expected,
    prefix: 'model.encoder.layers.0.final_layer_norm',
    dModel: d,
  );
  _addAttentionShapes(
    expected,
    prefix: 'model.decoder.layers.0.self_attn',
    dModel: d,
  );
  _addLayerNormShape(
    expected,
    prefix: 'model.decoder.layers.0.self_attn_layer_norm',
    dModel: d,
  );
  _addAttentionShapes(
    expected,
    prefix: 'model.decoder.layers.0.encoder_attn',
    dModel: d,
  );
  _addLayerNormShape(
    expected,
    prefix: 'model.decoder.layers.0.encoder_attn_layer_norm',
    dModel: d,
  );
  _addFeedForwardShapes(
    expected,
    prefix: 'model.decoder.layers.0',
    dModel: d,
    ffnDimension: config.decoderFfnDim,
  );
  _addLayerNormShape(
    expected,
    prefix: 'model.decoder.layers.0.final_layer_norm',
    dModel: d,
  );
  return expected;
}

void _addAttentionShapes(
  Map<String, List<int>> result, {
  required String prefix,
  required int dModel,
}) {
  for (final projection in <String>['q_proj', 'k_proj', 'v_proj', 'out_proj']) {
    result['$prefix.$projection.weight'] = <int>[dModel, dModel];
    result['$prefix.$projection.bias'] = <int>[dModel];
  }
}

void _addFeedForwardShapes(
  Map<String, List<int>> result, {
  required String prefix,
  required int dModel,
  required int ffnDimension,
}) {
  result['$prefix.fc1.weight'] = <int>[ffnDimension, dModel];
  result['$prefix.fc1.bias'] = <int>[ffnDimension];
  result['$prefix.fc2.weight'] = <int>[dModel, ffnDimension];
  result['$prefix.fc2.bias'] = <int>[dModel];
}

void _addLayerNormShape(
  Map<String, List<int>> result, {
  required String prefix,
  required int dModel,
}) {
  result['$prefix.weight'] = <int>[dModel];
  result['$prefix.bias'] = <int>[dModel];
}

bool _sameShape(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

// Abramowitz and Stegun 7.1.26. The maximum approximation error is below
// 1.5e-7; model-weight parity is intentionally not claimed yet.
double _erf(double value) {
  final sign = value < 0 ? -1.0 : 1.0;
  final magnitude = value.abs();
  final t = 1 / (1 + 0.3275911 * magnitude);
  var polynomial = 1.061405429;
  polynomial = -1.453152027 + t * polynomial;
  polynomial = 1.421413741 + t * polynomial;
  polynomial = -0.284496736 + t * polynomial;
  polynomial = 0.254829592 + t * polynomial;
  final approximation = 1 - polynomial * t * math.exp(-magnitude * magnitude);
  return sign * approximation;
}
