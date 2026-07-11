// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:misakid/misaki.dart';

import 'safetensors.dart';

/// Small row-major F32 matrix used by the batch-one inference graph.
final class F32Matrix {
  F32Matrix({required this.rows, required this.columns, Float32List? values})
    : values = values ?? Float32List(rows * columns) {
    if (rows <= 0 || columns <= 0 || this.values.length != rows * columns) {
      throw const MalformedDataException('Invalid internal BART matrix shape.');
    }
  }

  factory F32Matrix.fromTensor(BartTensor tensor) {
    if (tensor.shape.length != 2) {
      throw const MalformedDataException(
        'An internal BART matrix weight does not have rank two.',
      );
    }
    return F32Matrix(
      rows: tensor.shape[0],
      columns: tensor.shape[1],
      values: Float32List.fromList(tensor.values),
    );
  }

  final int rows;
  final int columns;
  final Float32List values;

  double get(int row, int column) => values[row * columns + column];

  void set(int row, int column, double value) {
    values[row * columns + column] = value;
  }
}

/// Explicit float32 rounding with a stable scalar evaluation order.
final class F32Arithmetic {
  final Float32List _scratch = Float32List(1);

  double round(double value) {
    _scratch[0] = value;
    final result = _scratch[0];
    if (!result.isFinite) {
      throw const BackendFailureException(
        'BART F32 inference produced a non-finite intermediate value.',
      );
    }
    return result;
  }

  double add(double left, double right) => round(left + right);

  double multiply(double left, double right) => round(left * right);

  double multiplyAdd(double accumulator, double left, double right) =>
      add(accumulator, multiply(left, right));
}
