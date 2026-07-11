import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:misakid/misaki.dart' show MalformedDataException;

import 'parameters.dart';

/// Decodes the exact serialized Thinc parameters from `en_core_web_sm==3.8.0`.
///
/// The caller remains responsible for reading the explicitly configured
/// `tok2vec/model` and `tagger/model` files. This decoder performs no file or
/// network access and accepts only the byte-for-byte pinned resources.
final class SpacyEnglishSerializedModelLoader {
  const SpacyEnglishSerializedModelLoader._();

  /// SHA-256 of `en_core_web_sm-3.8.0/tok2vec/model`.
  static const String tok2vecModelSha256 =
      'e84fc06eb319c94d28e460fc334e292120b01f18baa5dc8b50c977459820a090';

  /// SHA-256 of `en_core_web_sm-3.8.0/tagger/model`.
  static const String taggerModelSha256 =
      '1ec3d93f38cebe172f2b5c89d84be72856ce42c8f1a64f1699f1d98a771f36b7';

  /// Exact byte length of the pinned tok2vec resource.
  static const int tok2vecModelByteLength = 6269370;

  /// Exact byte length of the pinned tagger resource.
  static const int taggerModelByteLength = 19829;

  /// Validates and decodes the two pinned serialized model resources.
  static SpacyEnglishModelParameters decode({
    required Uint8List tok2vecModel,
    required Uint8List taggerModel,
  }) {
    _validatePinnedResource(
      bytes: tok2vecModel,
      name: 'tok2vec/model',
      expectedLength: tok2vecModelByteLength,
      expectedSha256: tok2vecModelSha256,
    );
    _validatePinnedResource(
      bytes: taggerModel,
      name: 'tagger/model',
      expectedLength: taggerModelByteLength,
      expectedSha256: taggerModelSha256,
    );

    final tok2vec = _decodeDocument(tok2vecModel, 'tok2vec/model');
    final tagger = _decodeDocument(taggerModel, 'tagger/model');
    return _buildParameters(tok2vec: tok2vec, tagger: tagger);
  }
}

void _validatePinnedResource({
  required Uint8List bytes,
  required String name,
  required int expectedLength,
  required String expectedSha256,
}) {
  if (bytes.length != expectedLength) {
    _malformed(
      '$name has ${bytes.length} bytes; the pinned en_core_web_sm==3.8.0 '
      'resource must have $expectedLength.',
    );
  }
  final actualSha256 = sha256.convert(bytes).toString();
  if (actualSha256 != expectedSha256) {
    _malformed(
      '$name has SHA-256 $actualSha256; expected $expectedSha256 for the '
      'pinned en_core_web_sm==3.8.0 resource.',
    );
  }
}

Map<Object?, Object?> _decodeDocument(Uint8List bytes, String name) {
  final decoder = _BoundedMessagePackDecoder(bytes, name);
  final value = decoder.decode();
  return _asMap(value, '$name root');
}

SpacyEnglishModelParameters _buildParameters({
  required Map<Object?, Object?> tok2vec,
  required Map<Object?, Object?> tagger,
}) {
  final tok2vecParts = _validateRoot(tok2vec, 'tok2vec/model', 65);
  final taggerParts = _validateRoot(tagger, 'tagger/model', 4);
  _validateTok2vecGraph(tok2vecParts);
  _validateTaggerGraph(taggerParts);

  const embeddingIndices = <int>[28, 30, 32, 34, 36, 38];
  final embeddings = <SpacyEmbeddingTableParameters>[];
  for (var feature = 0; feature < embeddingIndices.length; feature++) {
    final rows = SpacyEnglishModelParameters.embeddingRows[feature];
    final values = _parameterArray(
      tok2vecParts.params,
      embeddingIndices[feature],
      'E',
      <int>[rows, SpacyEnglishModelParameters.width],
      'tok2vec/model node ${embeddingIndices[feature]} E',
    );
    embeddings.add(SpacyEmbeddingTableParameters(rows: rows, values: values));
  }

  final projection = _maxoutParameters(
    parts: tok2vecParts,
    maxoutNode: 39,
    layerNormNode: 40,
    inputWidth: SpacyEnglishModelParameters.projectionInputWidth,
    label: 'tok2vec projection',
  );
  const encoderNodes = <(int, int)>[(57, 58), (59, 60), (61, 62), (63, 64)];
  final encoderLayers = <SpacyMaxoutLayerParameters>[
    for (var index = 0; index < encoderNodes.length; index++)
      _maxoutParameters(
        parts: tok2vecParts,
        maxoutNode: encoderNodes[index].$1,
        layerNormNode: encoderNodes[index].$2,
        inputWidth: SpacyEnglishModelParameters.encoderInputWidth,
        label: 'tok2vec encoder layer $index',
      ),
  ];

  final taggerWeights = _parameterArray(taggerParts.params, 3, 'W', <int>[
    SpacyEnglishModelParameters.tagCount,
    SpacyEnglishModelParameters.width,
  ], 'tagger/model node 3 W');
  final taggerBiases = _parameterArray(taggerParts.params, 3, 'b', <int>[
    SpacyEnglishModelParameters.tagCount,
  ], 'tagger/model node 3 b');
  return SpacyEnglishModelParameters(
    embeddingTables: embeddings,
    projection: projection,
    encoderLayers: encoderLayers,
    tagger: SpacyTaggerLinearParameters(
      weights: taggerWeights,
      biases: taggerBiases,
    ),
  );
}

SpacyMaxoutLayerParameters _maxoutParameters({
  required _SerializedModelParts parts,
  required int maxoutNode,
  required int layerNormNode,
  required int inputWidth,
  required String label,
}) => SpacyMaxoutLayerParameters(
  inputWidth: inputWidth,
  weights: _parameterArray(parts.params, maxoutNode, 'W', <int>[
    SpacyEnglishModelParameters.width,
    SpacyEnglishModelParameters.maxoutPieces,
    inputWidth,
  ], '$label maxout W'),
  biases: _parameterArray(parts.params, maxoutNode, 'b', <int>[
    SpacyEnglishModelParameters.width,
    SpacyEnglishModelParameters.maxoutPieces,
  ], '$label maxout b'),
  layerNormGain: _parameterArray(parts.params, layerNormNode, 'G', <int>[
    SpacyEnglishModelParameters.width,
  ], '$label layernorm G'),
  layerNormBias: _parameterArray(parts.params, layerNormNode, 'b', <int>[
    SpacyEnglishModelParameters.width,
  ], '$label layernorm b'),
);

_SerializedModelParts _validateRoot(
  Map<Object?, Object?> root,
  String label,
  int expectedNodeCount,
) {
  _expectStringKeys(root, const <String>{
    'nodes',
    'attrs',
    'params',
    'shims',
  }, label);
  final nodes = _asList(root['nodes'], '$label nodes');
  final attrs = _asList(root['attrs'], '$label attrs');
  final params = _asList(root['params'], '$label params');
  final shims = _asList(root['shims'], '$label shims');
  for (final entry in <(String, List<Object?>)>[
    ('nodes', nodes),
    ('attrs', attrs),
    ('params', params),
    ('shims', shims),
  ]) {
    if (entry.$2.length != expectedNodeCount) {
      _malformed(
        '$label ${entry.$1} has ${entry.$2.length} entries; '
        'expected $expectedNodeCount.',
      );
    }
  }
  for (var index = 0; index < expectedNodeCount; index++) {
    final node = _asMap(nodes[index], '$label node $index');
    _expectStringKeys(node, const <String>{
      'index',
      'name',
      'dims',
      'refs',
    }, '$label node $index');
    _expectInt(node['index'], index, '$label node $index index');
    _asString(node['name'], '$label node $index name');
    _asStringMap(node['dims'], '$label node $index dims');
    _asStringMap(node['refs'], '$label node $index refs');
    _asStringMap(attrs[index], '$label attrs $index');
    _asStringMap(params[index], '$label params $index');
    final nodeShims = _asList(shims[index], '$label shims $index');
    if (nodeShims.isNotEmpty) {
      _malformed('$label node $index unexpectedly contains a shim.');
    }
  }
  return _SerializedModelParts(nodes: nodes, attrs: attrs, params: params);
}

void _validateTok2vecGraph(_SerializedModelParts parts) {
  _expectNode(
    parts,
    index: 0,
    namePrefix: 'extract_features>>list2ragged>>with_array(',
    dims: const <String, int?>{'nO': 96},
  );
  _expectNode(
    parts,
    index: 2,
    namePrefix:
        'with_array(residual(expand_window>>maxout>>layernorm>>dropout)',
    dims: const <String, int?>{'nO': 96, 'nI': null},
  );
  _expectNode(
    parts,
    index: 3,
    exactName: 'extract_features',
    dims: const <String, int?>{},
  );
  _expectNode(
    parts,
    index: 39,
    exactName: 'maxout',
    dims: const <String, int?>{'nO': 96, 'nI': 576, 'nP': 3},
  );
  _expectNode(
    parts,
    index: 40,
    exactName: 'layernorm',
    dims: const <String, int?>{'nI': 96, 'nO': 96},
  );

  const embeddingNodes = <int>[28, 30, 32, 34, 36, 38];
  for (var feature = 0; feature < embeddingNodes.length; feature++) {
    final node = embeddingNodes[feature];
    _expectNode(
      parts,
      index: node,
      exactName: 'hashembed',
      dims: <String, int?>{
        'nO': 96,
        'nV': SpacyEnglishModelParameters.embeddingRows[feature],
        'nI': null,
      },
    );
    _expectAttributeBytes(parts.attrs, node, 'column', <int>[feature]);
    _expectAttributeBytes(parts.attrs, node, 'seed', <int>[
      SpacyEnglishModelParameters.embeddingSeeds[feature],
    ]);
    _expectAttributeBytes(parts.attrs, node, 'dropout_rate', const <int>[
      0xcb,
      0x3f,
      0xb9,
      0x99,
      0x99,
      0x99,
      0x99,
      0x99,
      0x9a,
    ]);
    _expectParamKeys(parts.params, node, const <String>{'E'});
  }

  const encoderNodes = <(int, int)>[(57, 58), (59, 60), (61, 62), (63, 64)];
  for (final nodes in encoderNodes) {
    _expectNode(
      parts,
      index: nodes.$1,
      exactName: 'maxout',
      dims: const <String, int?>{'nO': 96, 'nI': 288, 'nP': 3},
    );
    _expectNode(
      parts,
      index: nodes.$2,
      exactName: 'layernorm',
      dims: const <String, int?>{'nI': 96, 'nO': 96},
    );
    _expectParamKeys(parts.params, nodes.$1, const <String>{'W', 'b'});
    _expectParamKeys(parts.params, nodes.$2, const <String>{'G', 'b'});
  }
  _expectParamKeys(parts.params, 39, const <String>{'W', 'b'});
  _expectParamKeys(parts.params, 40, const <String>{'G', 'b'});

  const nonEmptyParams = <int>{
    28,
    30,
    32,
    34,
    36,
    38,
    39,
    40,
    57,
    58,
    59,
    60,
    61,
    62,
    63,
    64,
  };
  _expectOnlyParamNodes(parts.params, nonEmptyParams, 'tok2vec/model');

  _expectAttributeBytes(parts.attrs, 2, 'pad', const <int>[0x04]);
  _expectAttributeBytes(parts.attrs, 3, 'columns', const <int>[
    0x96,
    0xa4,
    0x4e,
    0x4f,
    0x52,
    0x4d,
    0xa6,
    0x50,
    0x52,
    0x45,
    0x46,
    0x49,
    0x58,
    0xa6,
    0x53,
    0x55,
    0x46,
    0x46,
    0x49,
    0x58,
    0xa5,
    0x53,
    0x48,
    0x41,
    0x50,
    0x45,
    0xa5,
    0x53,
    0x50,
    0x41,
    0x43,
    0x59,
    0xa8,
    0x49,
    0x53,
    0x5f,
    0x53,
    0x50,
    0x41,
    0x43,
    0x45,
  ]);
}

void _validateTaggerGraph(_SerializedModelParts parts) {
  _expectNode(
    parts,
    index: 0,
    exactName: 'tok2vec-listener>>with_array(softmax)',
    dims: const <String, int?>{'nO': 50},
  );
  _expectNode(
    parts,
    index: 1,
    exactName: 'tok2vec-listener',
    dims: const <String, int?>{'nO': 96},
  );
  _expectNode(
    parts,
    index: 2,
    exactName: 'with_array(softmax)',
    dims: const <String, int?>{'nO': 50, 'nI': 96},
  );
  _expectNode(
    parts,
    index: 3,
    exactName: 'softmax',
    dims: const <String, int?>{'nO': 50, 'nI': 96},
  );
  _expectParamKeys(parts.params, 3, const <String>{'W', 'b'});
  _expectOnlyParamNodes(parts.params, const <int>{3}, 'tagger/model');
  _expectAttributeBytes(parts.attrs, 2, 'pad', const <int>[0x00]);
  _expectAttributeBytes(parts.attrs, 3, 'softmax_normalize', const <int>[0xc2]);
  _expectAttributeBytes(parts.attrs, 3, 'softmax_temperature', const <int>[
    0xcb,
    0x3f,
    0xf0,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
  ]);
}

void _expectNode(
  _SerializedModelParts parts, {
  required int index,
  required Map<String, int?> dims,
  String? exactName,
  String? namePrefix,
}) {
  final node = _asStringMap(parts.nodes[index], 'model node $index');
  final name = _asString(node['name'], 'model node $index name');
  if (exactName != null && name != exactName) {
    _malformed('Model node $index is named $name; expected $exactName.');
  }
  if (namePrefix != null && !name.startsWith(namePrefix)) {
    _malformed(
      'Model node $index is named $name; expected prefix $namePrefix.',
    );
  }
  final actualDims = _asStringMap(node['dims'], 'model node $index dims');
  _expectNullableIntMap(actualDims, dims, 'model node $index dims');
}

void _expectParamKeys(List<Object?> params, int node, Set<String> expected) =>
    _expectStringKeys(
      _asMap(params[node], 'model params $node'),
      expected,
      'model params $node',
    );

void _expectOnlyParamNodes(
  List<Object?> params,
  Set<int> expectedNonEmpty,
  String label,
) {
  for (var index = 0; index < params.length; index++) {
    final map = _asMap(params[index], '$label params $index');
    if (map.isNotEmpty != expectedNonEmpty.contains(index)) {
      _malformed('$label has unexpected parameter ownership at node $index.');
    }
  }
}

void _expectAttributeBytes(
  List<Object?> attrs,
  int node,
  String name,
  List<int> expected,
) {
  final map = _asStringMap(attrs[node], 'model attrs $node');
  final actual = _asBytes(map[name], 'model attrs $node $name');
  if (!_bytesEqual(actual, expected)) {
    _malformed('Model node $node attribute $name is not the pinned value.');
  }
}

Float32List _parameterArray(
  List<Object?> allParams,
  int node,
  String name,
  List<int> expectedShape,
  String label,
) {
  final params = _asStringMap(allParams[node], 'model params $node');
  final encoded = _asMap(params[name], label);
  _expectBinaryKeys(encoded, const <String>{
    'nd',
    'type',
    'kind',
    'shape',
    'data',
  }, label);
  final isNd = _getBinaryKey(encoded, 'nd', label);
  if (isNd != true) {
    _malformed('$label is not encoded as a NumPy ndarray.');
  }
  final type = _asString(_getBinaryKey(encoded, 'type', label), '$label type');
  final kind = _asBytes(_getBinaryKey(encoded, 'kind', label), '$label kind');
  if (type != '<f4' || kind.isNotEmpty) {
    _malformed('$label is not a C-contiguous little-endian float32 array.');
  }
  final shapeValues = _asList(
    _getBinaryKey(encoded, 'shape', label),
    '$label shape',
  );
  final shape = <int>[
    for (var index = 0; index < shapeValues.length; index++)
      _asInt(shapeValues[index], '$label shape[$index]'),
  ];
  if (!_intListsEqual(shape, expectedShape)) {
    _malformed('$label has shape $shape; expected $expectedShape.');
  }
  var valueCount = 1;
  for (final dimension in expectedShape) {
    valueCount *= dimension;
  }
  final data = _asBytes(_getBinaryKey(encoded, 'data', label), '$label data');
  if (data.length != valueCount * Float32List.bytesPerElement) {
    _malformed(
      '$label contains ${data.length} data bytes; '
      '${valueCount * Float32List.bytesPerElement} are required.',
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
    if (key is! Uint8List) {
      _malformed('$label contains a non-binary key.');
    }
    final decoded = utf8.decode(key, allowMalformed: false);
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

void _expectNullableIntMap(
  Map<String, Object?> actual,
  Map<String, int?> expected,
  String label,
) {
  if (!_setsEqual(actual.keys.toSet(), expected.keys.toSet())) {
    _malformed(
      '$label has keys ${actual.keys.toSet()}; expected ${expected.keys.toSet()}.',
    );
  }
  for (final entry in expected.entries) {
    final value = actual[entry.key];
    if (entry.value == null) {
      if (value != null) _malformed('$label ${entry.key} must be null.');
    } else {
      _expectInt(value, entry.value!, '$label ${entry.key}');
    }
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

final class _SerializedModelParts {
  const _SerializedModelParts({
    required this.nodes,
    required this.attrs,
    required this.params,
  });

  final List<Object?> nodes;
  final List<Object?> attrs;
  final List<Object?> params;
}

final class _BoundedMessagePackDecoder {
  _BoundedMessagePackDecoder(this._bytes, this._label)
    : _data = ByteData.sublistView(_bytes);

  static const int _maximumDepth = 32;
  static const int _maximumCollectionLength = 100000;
  static const int _maximumObjectCount = 1000000;
  static const int _maximumStringBytes = 1048576;
  static const int _maximumBinaryBytes = 8388608;

  final Uint8List _bytes;
  final String _label;
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
    if (byteLength < 0 || _offset + byteLength > _bytes.length) {
      _fail('ends unexpectedly at byte $_offset');
    }
  }

  Never _fail(String message) => _malformed('$_label $message.');
}
