// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:typed_data';

import 'package:misakid/misaki.dart';

const int _maximumSafetensorsHeaderBytes = 1024 * 1024;
const int _maximumSafetensorsTensorCount = 128;
const int _maximumSafetensorsRank = 4;

/// Immutable, decoded float32 tensor.
final class BartTensor {
  BartTensor._({required List<int> shape, required Float32List values})
    : shape = List<int>.unmodifiable(shape),
      values = Float32List.fromList(values);

  /// Tensor dimensions in row-major order.
  final List<int> shape;

  /// Little-endian F32 values decoded into host-independent Dart values.
  final Float32List values;
}

/// Strict bounded parser for the F32 subset used by the BART adapter.
final class BartSafetensors {
  BartSafetensors._(Map<String, BartTensor> tensors)
    : tensors = Map<String, BartTensor>.unmodifiable(tensors);

  /// Exact tensor table. Metadata is validated but intentionally not exposed.
  final Map<String, BartTensor> tensors;

  /// Parses one already size-bounded safetensors resource.
  factory BartSafetensors.parse(Uint8List bytes) {
    try {
      return BartSafetensors._(_parse(bytes));
    } on MisakiException {
      rethrow;
    } on FormatException catch (error) {
      throw MalformedDataException(
        'The BART safetensors header is not valid UTF-8 JSON.',
        cause: error,
      );
    } on RangeError catch (error) {
      throw MalformedDataException(
        'The BART safetensors resource contains an out-of-range value.',
        cause: error,
      );
    }
  }
}

Map<String, BartTensor> _parse(Uint8List bytes) {
  if (bytes.length < 10) {
    throw const MalformedDataException(
      'The BART safetensors resource is too short.',
    );
  }
  final prefix = ByteData.sublistView(bytes, 0, 8);
  final low = prefix.getUint32(0, Endian.little);
  final high = prefix.getUint32(4, Endian.little);
  if (high != 0 || low < 2 || low > _maximumSafetensorsHeaderBytes) {
    throw const MalformedDataException(
      'The BART safetensors header length is outside the supported bound.',
    );
  }
  final dataStart = 8 + low;
  if (dataStart > bytes.length) {
    throw const MalformedDataException(
      'The BART safetensors header extends beyond the resource.',
    );
  }
  final headerText = utf8.decode(
    bytes.sublist(8, dataStart),
    allowMalformed: false,
  );
  final decoded = decodeStrictJson(headerText);
  if (decoded is! Map<String, Object?>) {
    throw const MalformedDataException(
      'The BART safetensors header must be a JSON object.',
    );
  }
  if (decoded.length > _maximumSafetensorsTensorCount + 1) {
    throw const MalformedDataException(
      'The BART safetensors header declares too many tensors.',
    );
  }

  final declarations = <_TensorDeclaration>[];
  for (final entry in decoded.entries) {
    if (entry.key == '__metadata__') {
      _validateMetadata(entry.value);
      continue;
    }
    if (entry.key.isEmpty ||
        entry.key.length > 256 ||
        entry.key.contains('\u0000')) {
      throw const MalformedDataException(
        'The BART safetensors resource has an invalid tensor name.',
      );
    }
    final declaration = _parseDeclaration(entry.key, entry.value);
    declarations.add(declaration);
  }
  if (declarations.isEmpty ||
      declarations.length > _maximumSafetensorsTensorCount) {
    throw const MalformedDataException(
      'The BART safetensors resource has no tensors or too many tensors.',
    );
  }

  declarations.sort((left, right) => left.start.compareTo(right.start));
  var cursor = 0;
  for (final declaration in declarations) {
    if (declaration.start != cursor || declaration.end < declaration.start) {
      throw const MalformedDataException(
        'BART safetensors tensor ranges must be contiguous and non-overlapping.',
      );
    }
    final elementCount = _elementCount(declaration.shape);
    if (declaration.end - declaration.start != elementCount * 4) {
      throw MalformedDataException(
        'BART tensor `${declaration.name}` has a byte length that does not match its shape.',
      );
    }
    cursor = declaration.end;
  }
  if (cursor != bytes.length - dataStart) {
    throw const MalformedDataException(
      'The BART safetensors data section contains undeclared bytes.',
    );
  }

  final result = <String, BartTensor>{};
  final data = ByteData.sublistView(bytes, dataStart);
  for (final declaration in declarations) {
    final count = _elementCount(declaration.shape);
    final values = Float32List(count);
    for (var index = 0; index < count; index++) {
      final value = data.getFloat32(
        declaration.start + index * 4,
        Endian.little,
      );
      if (!value.isFinite) {
        throw MalformedDataException(
          'BART tensor `${declaration.name}` contains a non-finite value.',
        );
      }
      values[index] = value;
    }
    result[declaration.name] = BartTensor._(
      shape: declaration.shape,
      values: values,
    );
  }
  return result;
}

void _validateMetadata(Object? value) {
  if (value is! Map<String, Object?> ||
      value.entries.any(
        (entry) =>
            entry.key.isEmpty ||
            entry.key.length > 256 ||
            entry.value is! String ||
            (entry.value! as String).length > 4096,
      )) {
    throw const MalformedDataException(
      'BART safetensors metadata must contain bounded string pairs.',
    );
  }
}

_TensorDeclaration _parseDeclaration(String name, Object? value) {
  if (value is! Map<String, Object?> ||
      value.length != 3 ||
      !value.containsKey('dtype') ||
      !value.containsKey('shape') ||
      !value.containsKey('data_offsets')) {
    throw MalformedDataException(
      'BART tensor `$name` must declare only dtype, shape, and data_offsets.',
    );
  }
  if (value['dtype'] != 'F32') {
    throw MalformedDataException('BART tensor `$name` must use F32 storage.');
  }
  final shapeValue = value['shape'];
  if (shapeValue is! List<Object?> ||
      shapeValue.isEmpty ||
      shapeValue.length > _maximumSafetensorsRank) {
    throw MalformedDataException(
      'BART tensor `$name` has an unsupported rank.',
    );
  }
  final shape = <int>[];
  for (final dimension in shapeValue) {
    if (dimension is! int || dimension <= 0) {
      throw MalformedDataException(
        'BART tensor `$name` has an invalid shape dimension.',
      );
    }
    shape.add(dimension);
  }
  _elementCount(shape);

  final offsets = value['data_offsets'];
  if (offsets is! List<Object?> ||
      offsets.length != 2 ||
      offsets[0] is! int ||
      offsets[1] is! int) {
    throw MalformedDataException(
      'BART tensor `$name` has invalid data offsets.',
    );
  }
  final start = offsets[0]! as int;
  final end = offsets[1]! as int;
  if (start < 0 || end < start) {
    throw MalformedDataException(
      'BART tensor `$name` has negative or reversed data offsets.',
    );
  }
  return _TensorDeclaration(name: name, shape: shape, start: start, end: end);
}

int _elementCount(List<int> shape) {
  var result = 1;
  for (final dimension in shape) {
    if (result > 0x3FFFFFFF ~/ dimension) {
      throw const MalformedDataException(
        'A BART tensor shape exceeds the supported element bound.',
      );
    }
    result *= dimension;
  }
  return result;
}

final class _TensorDeclaration {
  const _TensorDeclaration({
    required this.name,
    required this.shape,
    required this.start,
    required this.end,
  });

  final String name;
  final List<int> shape;
  final int start;
  final int end;
}
