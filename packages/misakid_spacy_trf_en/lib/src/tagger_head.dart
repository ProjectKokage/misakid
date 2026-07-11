// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:misakid/misaki.dart';

import 'resource_identity.dart';

/// Number of Penn-tag outputs in the exact transformer tagger head.
const int spacyTransformerTagCount = 49;

/// Hidden width consumed by the exact transformer tagger head.
const int spacyTransformerTaggerInputWidth = 768;

/// Strictly decoded F32 linear head from the pinned transformer tagger graph.
final class SpacyTransformerTaggerHead {
  SpacyTransformerTaggerHead._(Float32List weights, Float32List biases)
    : _weights = Float32List.fromList(weights),
      _biases = Float32List.fromList(biases);

  final Float32List _weights;
  final Float32List _biases;

  /// Validates the exact file identity and its complete serialized graph.
  static SpacyTransformerTaggerHead decode(Uint8List serializedModel) {
    if (serializedModel.length != spacyTransformerTaggerModelSizeBytes) {
      throw MalformedDataException(
        'tagger/model has ${serializedModel.length} bytes; expected '
        '$spacyTransformerTaggerModelSizeBytes for en_core_web_trf==3.8.0.',
      );
    }
    final digest = sha256.convert(serializedModel).toString();
    if (digest != spacyTransformerTaggerModelSha256) {
      throw MalformedDataException(
        'tagger/model has SHA-256 $digest; expected '
        '$spacyTransformerTaggerModelSha256 for en_core_web_trf==3.8.0.',
      );
    }
    return decodeValidatedGraph(serializedModel);
  }

  /// Decodes an already identity-validated graph under strict bounded rules.
  ///
  /// Normal callers should use [decode]. This entry point lets a resource
  /// snapshot avoid hashing the same bytes twice and enables structural tests;
  /// it still accepts only the exact six-node graph and F32 array shapes.
  static SpacyTransformerTaggerHead decodeValidatedGraph(
    Uint8List serializedModel,
  ) {
    if (serializedModel.isEmpty ||
        serializedModel.length > spacyTransformerTaggerModelSizeBytes) {
      throw const MalformedDataException(
        'The transformer tagger graph exceeds its serialized byte bound.',
      );
    }
    final root = _asMap(
      _BoundedMessagePackDecoder(serializedModel).decode(),
      'tagger/model root',
    );
    final parts = _validateRoot(root);
    _validateGraph(parts);
    final weights = _parameterArray(
      parts.params,
      node: 4,
      name: 'W',
      expectedShape: const <int>[
        spacyTransformerTagCount,
        spacyTransformerTaggerInputWidth,
      ],
      label: 'tagger/model node 4 W',
    );
    final biases = _parameterArray(
      parts.params,
      node: 4,
      name: 'b',
      expectedShape: const <int>[spacyTransformerTagCount],
      label: 'tagger/model node 4 b',
    );
    return SpacyTransformerTaggerHead._(weights, biases);
  }

  /// Returns one row-major projection weight.
  double weightAt(int tag, int input) {
    RangeError.checkValidIndex(tag, _biases, 'tag');
    if (input < 0 || input >= spacyTransformerTaggerInputWidth) {
      throw RangeError.range(
        input,
        0,
        spacyTransformerTaggerInputWidth - 1,
        'input',
      );
    }
    return _weights[tag * spacyTransformerTaggerInputWidth + input];
  }

  /// Returns one projection bias.
  double biasAt(int tag) {
    RangeError.checkValidIndex(tag, _biases, 'tag');
    return _biases[tag];
  }

  /// Returns a defensive row-major copy of the `[49, 768]` weights.
  Float32List copyWeights() => Float32List.fromList(_weights);

  /// Returns a defensive copy of the 49 biases.
  Float32List copyBiases() => Float32List.fromList(_biases);
}

_SerializedTaggerParts _validateRoot(Map<Object?, Object?> root) {
  _expectStringKeys(root, const <String>{
    'nodes',
    'attrs',
    'params',
    'shims',
  }, 'tagger/model root');
  final nodes = _asList(root['nodes'], 'tagger/model nodes');
  final attrs = _asList(root['attrs'], 'tagger/model attrs');
  final params = _asList(root['params'], 'tagger/model params');
  final shims = _asList(root['shims'], 'tagger/model shims');
  for (final entry in <(String, List<Object?>)>[
    ('nodes', nodes),
    ('attrs', attrs),
    ('params', params),
    ('shims', shims),
  ]) {
    if (entry.$2.length != 6) {
      _malformed(
        'tagger/model ${entry.$1} has ${entry.$2.length} entries; expected 6.',
      );
    }
  }
  for (var index = 0; index < 6; index++) {
    final node = _asMap(nodes[index], 'tagger/model node $index');
    _expectStringKeys(node, const <String>{
      'index',
      'name',
      'dims',
      'refs',
    }, 'tagger/model node $index');
    _expectInt(node['index'], index, 'tagger/model node $index index');
    _asString(node['name'], 'tagger/model node $index name');
    _asStringMap(node['dims'], 'tagger/model node $index dims');
    _asStringMap(node['refs'], 'tagger/model node $index refs');
    _asStringMap(attrs[index], 'tagger/model attrs $index');
    _asStringMap(params[index], 'tagger/model params $index');
    if (_asList(shims[index], 'tagger/model shims $index').isNotEmpty) {
      _malformed('tagger/model node $index unexpectedly contains a shim.');
    }
  }
  return _SerializedTaggerParts(nodes: nodes, attrs: attrs, params: params);
}

void _validateGraph(_SerializedTaggerParts parts) {
  _expectNode(
    parts,
    index: 0,
    name: 'last_transformer_layer_listener>>with_array(softmax)',
    dims: const <String, int>{'nO': 49},
    refs: const <String, int>{'tok2vec': 1, 'softmax': 4, 'output_layer': 4},
  );
  _expectNode(
    parts,
    index: 1,
    name: 'last_transformer_layer_listener',
    dims: const <String, int>{'nO': 768},
    refs: const <String, int>{'pooling': 5},
  );
  _expectNode(
    parts,
    index: 2,
    name: 'with_array(softmax)',
    dims: const <String, int>{'nO': 49, 'nI': 768},
    refs: const <String, int>{},
  );
  _expectNode(
    parts,
    index: 3,
    name: 'with_ragged_last_layer',
    dims: const <String, int>{},
    refs: const <String, int>{},
  );
  _expectNode(
    parts,
    index: 4,
    name: 'softmax',
    dims: const <String, int>{'nO': 49, 'nI': 768},
    refs: const <String, int>{},
  );
  _expectNode(
    parts,
    index: 5,
    name: 'reduce_mean',
    dims: const <String, int>{},
    refs: const <String, int>{},
  );

  _expectAttributes(parts.attrs, 0, const <String, List<int>>{});
  _expectAttributes(parts.attrs, 1, const <String, List<int>>{
    'grad_factor': <int>[0xcb, 0x3f, 0xf0, 0, 0, 0, 0, 0, 0],
    '_upstream_name': <int>[
      0xab,
      0x74,
      0x72,
      0x61,
      0x6e,
      0x73,
      0x66,
      0x6f,
      0x72,
      0x6d,
      0x65,
      0x72,
    ],
    '_TRANSFORMER_LISTENER': <int>[0xc3],
    '_USE_DOC_ANNOTATIONS_FOR_PREDICTION': <int>[0xc3],
    '_REQUIRES_ALL_LAYER_OUTPUTS': <int>[0xc2],
    '_state': <int>[],
  });
  _expectAttributes(parts.attrs, 2, const <String, List<int>>{
    'pad': <int>[0x00],
  });
  _expectAttributes(parts.attrs, 3, const <String, List<int>>{});
  _expectAttributes(parts.attrs, 4, const <String, List<int>>{
    'softmax_normalize': <int>[0xc2],
    'softmax_temperature': <int>[0xcb, 0x3f, 0xf0, 0, 0, 0, 0, 0, 0],
  });
  _expectAttributes(parts.attrs, 5, const <String, List<int>>{});

  for (var index = 0; index < parts.params.length; index++) {
    final params = _asMap(parts.params[index], 'tagger/model params $index');
    final expected = index == 4 ? const <String>{'W', 'b'} : const <String>{};
    _expectStringKeys(params, expected, 'tagger/model params $index');
  }
}

void _expectNode(
  _SerializedTaggerParts parts, {
  required int index,
  required String name,
  required Map<String, int> dims,
  required Map<String, int> refs,
}) {
  final node = _asStringMap(parts.nodes[index], 'tagger/model node $index');
  if (_asString(node['name'], 'tagger/model node $index name') != name) {
    _malformed('tagger/model node $index does not have the pinned name.');
  }
  _expectExactIntMap(
    _asStringMap(node['dims'], 'tagger/model node $index dims'),
    dims,
    'tagger/model node $index dims',
  );
  _expectExactIntMap(
    _asStringMap(node['refs'], 'tagger/model node $index refs'),
    refs,
    'tagger/model node $index refs',
  );
}

void _expectExactIntMap(
  Map<String, Object?> actual,
  Map<String, int> expected,
  String label,
) {
  if (!_setsEqual(actual.keys.toSet(), expected.keys.toSet())) {
    _malformed(
      '$label has keys ${actual.keys.toSet()}; expected ${expected.keys.toSet()}.',
    );
  }
  for (final entry in expected.entries) {
    _expectInt(actual[entry.key], entry.value, '$label ${entry.key}');
  }
}

void _expectAttributes(
  List<Object?> attrs,
  int node,
  Map<String, List<int>> expected,
) {
  final actual = _asStringMap(attrs[node], 'tagger/model attrs $node');
  if (!_setsEqual(actual.keys.toSet(), expected.keys.toSet())) {
    _malformed(
      'tagger/model attrs $node has keys ${actual.keys.toSet()}; expected ${expected.keys.toSet()}.',
    );
  }
  for (final entry in expected.entries) {
    final value = _asBytes(
      actual[entry.key],
      'tagger/model attrs $node ${entry.key}',
    );
    if (!_bytesEqual(value, entry.value)) {
      _malformed(
        'tagger/model attrs $node ${entry.key} is not the pinned value.',
      );
    }
  }
}

Float32List _parameterArray(
  List<Object?> allParams, {
  required int node,
  required String name,
  required List<int> expectedShape,
  required String label,
}) {
  final params = _asStringMap(allParams[node], 'tagger/model params $node');
  final encoded = _asMap(params[name], label);
  _expectBinaryKeys(encoded, const <String>{
    'nd',
    'type',
    'kind',
    'shape',
    'data',
  }, label);
  if (_getBinaryKey(encoded, 'nd', label) != true) {
    _malformed('$label is not encoded as a NumPy ndarray.');
  }
  final type = _asString(_getBinaryKey(encoded, 'type', label), '$label type');
  final kind = _asBytes(_getBinaryKey(encoded, 'kind', label), '$label kind');
  if (type != '<f4' || kind.isNotEmpty) {
    _malformed('$label is not a C-contiguous little-endian float32 array.');
  }
  final rawShape = _asList(
    _getBinaryKey(encoded, 'shape', label),
    '$label shape',
  );
  final shape = <int>[
    for (var index = 0; index < rawShape.length; index++)
      _asInt(rawShape[index], '$label shape[$index]'),
  ];
  if (!_intListsEqual(shape, expectedShape)) {
    _malformed('$label has shape $shape; expected $expectedShape.');
  }
  var valueCount = 1;
  for (final dimension in expectedShape) {
    valueCount *= dimension;
  }
  final data = _asBytes(_getBinaryKey(encoded, 'data', label), '$label data');
  final expectedBytes = valueCount * Float32List.bytesPerElement;
  if (data.length != expectedBytes) {
    _malformed(
      '$label contains ${data.length} data bytes; $expectedBytes are required.',
    );
  }
  final byteData = ByteData.sublistView(data);
  final values = Float32List(valueCount);
  for (var index = 0; index < valueCount; index++) {
    final value = byteData.getFloat32(
      index * Float32List.bytesPerElement,
      Endian.little,
    );
    if (!value.isFinite) {
      _malformed('$label contains a non-finite value at index $index.');
    }
    values[index] = value;
  }
  return values;
}

Object? _getBinaryKey(Map<Object?, Object?> map, String name, String label) {
  final expected = utf8.encode(name);
  Object? result;
  var found = false;
  for (final entry in map.entries) {
    final key = entry.key;
    if (key is Uint8List && _bytesEqual(key, expected)) {
      if (found) _malformed('$label repeats binary key $name.');
      found = true;
      result = entry.value;
    }
  }
  if (!found) _malformed('$label is missing binary key $name.');
  return result;
}

void _expectBinaryKeys(
  Map<Object?, Object?> map,
  Set<String> expected,
  String label,
) {
  final actual = <String>{};
  for (final key in map.keys) {
    if (key is! Uint8List) _malformed('$label contains a non-binary key.');
    late final String decoded;
    try {
      decoded = utf8.decode(key, allowMalformed: false);
    } on FormatException {
      _malformed('$label contains a malformed binary key.');
    }
    if (!actual.add(decoded)) _malformed('$label repeats binary key $decoded.');
  }
  if (!_setsEqual(actual, expected)) {
    _malformed('$label has binary keys $actual; expected $expected.');
  }
}

void _expectStringKeys(
  Map<Object?, Object?> map,
  Set<String> expected,
  String label,
) {
  final actual = <String>{};
  for (final key in map.keys) {
    if (key is! String) _malformed('$label contains a non-string key.');
    if (!actual.add(key)) _malformed('$label repeats key $key.');
  }
  if (!_setsEqual(actual, expected)) {
    _malformed('$label has keys $actual; expected $expected.');
  }
}

Map<String, Object?> _asStringMap(Object? value, String label) {
  final map = _asMap(value, label);
  final result = <String, Object?>{};
  for (final entry in map.entries) {
    final key = entry.key;
    if (key is! String) _malformed('$label contains a non-string key.');
    if (result.containsKey(key)) _malformed('$label repeats key $key.');
    result[key] = entry.value;
  }
  return result;
}

Map<Object?, Object?> _asMap(Object? value, String label) {
  if (value is! Map<Object?, Object?>) _malformed('$label is not a map.');
  return value;
}

List<Object?> _asList(Object? value, String label) {
  if (value is! List<Object?>) _malformed('$label is not a list.');
  return value;
}

Uint8List _asBytes(Object? value, String label) {
  if (value is! Uint8List) _malformed('$label is not binary data.');
  return value;
}

String _asString(Object? value, String label) {
  if (value is! String) _malformed('$label is not a string.');
  return value;
}

int _asInt(Object? value, String label) {
  if (value is! int) _malformed('$label is not an integer.');
  return value;
}

void _expectInt(Object? value, int expected, String label) {
  final actual = _asInt(value, label);
  if (actual != expected) _malformed('$label is $actual; expected $expected.');
}

bool _setsEqual<T>(Set<T> left, Set<T> right) =>
    left.length == right.length && left.containsAll(right);

bool _intListsEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

Never _malformed(String message) => throw MalformedDataException(message);

final class _SerializedTaggerParts {
  const _SerializedTaggerParts({
    required this.nodes,
    required this.attrs,
    required this.params,
  });

  final List<Object?> nodes;
  final List<Object?> attrs;
  final List<Object?> params;
}

/// Reviewed MessagePack/numpy subset adapted from the small-model loader.
final class _BoundedMessagePackDecoder {
  _BoundedMessagePackDecoder(this._bytes)
    : _data = ByteData.sublistView(_bytes);

  static const int _maximumDepth = 32;
  static const int _maximumCollectionLength = 1000;
  static const int _maximumObjectCount = 10000;
  static const int _maximumStringBytes = 4096;
  static const int _maximumBinaryBytes =
      spacyTransformerTagCount *
      spacyTransformerTaggerInputWidth *
      Float32List.bytesPerElement;

  final Uint8List _bytes;
  final ByteData _data;
  var _offset = 0;
  var _objectCount = 0;

  Object? decode() {
    final result = _readValue(0);
    if (_offset != _bytes.length) {
      _fail('contains ${_bytes.length - _offset} trailing bytes');
    }
    return result;
  }

  Object? _readValue(int depth) {
    if (depth > _maximumDepth) _fail('exceeds maximum nesting depth');
    _objectCount++;
    if (_objectCount > _maximumObjectCount) _fail('contains too many values');
    final marker = _readUint8();
    if (marker <= 0x7f) return marker;
    if (marker >= 0xe0) return marker - 0x100;
    if (marker >= 0xa0 && marker <= 0xbf) {
      return _readString(marker & 0x1f);
    }
    if (marker >= 0x90 && marker <= 0x9f) {
      return _readArray(marker & 0x0f, depth);
    }
    if (marker >= 0x80 && marker <= 0x8f) {
      return _readMap(marker & 0x0f, depth);
    }
    return switch (marker) {
      0xc0 => null,
      0xc2 => false,
      0xc3 => true,
      0xc4 => _readBinary(_readUint8()),
      0xc5 => _readBinary(_readUint16()),
      0xc6 => _readBinary(_readUint32()),
      0xca => _readFloat32(),
      0xcb => _readFloat64(),
      0xcc => _readUint8(),
      0xcd => _readUint16(),
      0xce => _readUint32(),
      0xcf => _readUint64(),
      0xd0 => _readInt8(),
      0xd1 => _readInt16(),
      0xd2 => _readInt32(),
      0xd3 => _readInt64(),
      0xd9 => _readString(_readUint8()),
      0xda => _readString(_readUint16()),
      0xdb => _readString(_readUint32()),
      0xdc => _readArray(_readUint16(), depth),
      0xdd => _readArray(_readUint32(), depth),
      0xde => _readMap(_readUint16(), depth),
      0xdf => _readMap(_readUint32(), depth),
      _ => _unsupported(marker),
    };
  }

  List<Object?> _readArray(int length, int depth) {
    _validateCollectionLength(length, 'array');
    return <Object?>[
      for (var index = 0; index < length; index++) _readValue(depth + 1),
    ];
  }

  Map<Object?, Object?> _readMap(int length, int depth) {
    _validateCollectionLength(length, 'map');
    final result = <Object?, Object?>{};
    for (var index = 0; index < length; index++) {
      final key = _readValue(depth + 1);
      if (key is! String && key is! int && key is! Uint8List) {
        _fail('contains a map key of unsupported type ${key.runtimeType}');
      }
      for (final existing in result.keys) {
        if (_equivalentKeys(existing, key)) {
          _fail('contains a duplicate map key');
        }
      }
      result[key] = _readValue(depth + 1);
    }
    return result;
  }

  bool _equivalentKeys(Object? left, Object? right) {
    if (left is Uint8List && right is Uint8List) {
      return _bytesEqual(left, right);
    }
    return left == right;
  }

  String _readString(int length) {
    if (length > _maximumStringBytes) _fail('contains an oversized string');
    final bytes = _readBytes(length);
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      _fail('contains malformed UTF-8');
    }
  }

  Uint8List _readBinary(int length) {
    if (length > _maximumBinaryBytes) _fail('contains oversized binary data');
    return Uint8List.fromList(_readBytes(length));
  }

  Never _unsupported(int marker) => _fail(
    'uses unsupported MessagePack marker 0x${marker.toRadixString(16)}',
  );

  void _validateCollectionLength(int length, String type) {
    if (length > _maximumCollectionLength) {
      _fail('contains an oversized $type');
    }
  }

  Uint8List _readBytes(int length) {
    _require(length);
    final result = Uint8List.sublistView(_bytes, _offset, _offset + length);
    _offset += length;
    return result;
  }

  int _readUint8() {
    _require(1);
    return _data.getUint8(_offset++);
  }

  int _readInt8() {
    _require(1);
    final value = _data.getInt8(_offset);
    _offset++;
    return value;
  }

  int _readUint16() => _readNumber(2, _data.getUint16);
  int _readUint32() => _readNumber(4, _data.getUint32);
  int _readUint64() => _readNumber(8, _data.getUint64);
  int _readInt16() => _readNumber(2, _data.getInt16);
  int _readInt32() => _readNumber(4, _data.getInt32);
  int _readInt64() => _readNumber(8, _data.getInt64);

  int _readNumber(
    int byteLength,
    int Function(int offset, [Endian endian]) reader,
  ) {
    _require(byteLength);
    final value = reader(_offset, Endian.big);
    _offset += byteLength;
    return value;
  }

  double _readFloat32() {
    _require(4);
    final value = _data.getFloat32(_offset, Endian.big);
    _offset += 4;
    if (!value.isFinite) _fail('contains a non-finite float32');
    return value;
  }

  double _readFloat64() {
    _require(8);
    final value = _data.getFloat64(_offset, Endian.big);
    _offset += 8;
    if (!value.isFinite) _fail('contains a non-finite float64');
    return value;
  }

  void _require(int byteLength) {
    if (byteLength < 0 || byteLength > _bytes.length - _offset) {
      _fail('ends unexpectedly at byte $_offset');
    }
  }

  Never _fail(String message) => _malformed('tagger/model $message.');
}
