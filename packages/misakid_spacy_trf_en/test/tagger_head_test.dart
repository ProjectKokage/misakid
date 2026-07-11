import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:misakid/misaki.dart';
import 'package:misakid_spacy_trf_en/src/resource_identity.dart';
import 'package:misakid_spacy_trf_en/src/tagger_head.dart';
import 'package:test/test.dart';

void main() {
  final provisionedRoot =
      Platform.environment['MISAKID_SPACY_TRF_EN_MODEL_DIR'] ??
      Platform.environment['MISAKI_SPACY_TRF_EN_MODEL_DIR'];
  final provisionedSkip = provisionedRoot == null
      ? 'Set MISAKID_SPACY_TRF_EN_MODEL_DIR to en_core_web_trf-3.8.0.'
      : false;

  test('pins the tagger projection dimensions', () {
    expect(spacyTransformerTagCount, 49);
    expect(spacyTransformerTaggerInputWidth, 768);
  });

  test('exact decoder rejects the wrong length and digest', () {
    expect(
      () => SpacyTransformerTaggerHead.decode(Uint8List(1)),
      throwsA(isA<MalformedDataException>()),
    );
    expect(
      () => SpacyTransformerTaggerHead.decode(
        Uint8List(spacyTransformerTaggerModelSizeBytes),
      ),
      throwsA(isA<MalformedDataException>()),
    );
  });

  test('strict decoder accepts only the pinned six-node graph', () {
    final serialized = _serializedGraph();
    expect(
      serialized.length,
      lessThanOrEqualTo(spacyTransformerTaggerModelSizeBytes),
    );

    final head = SpacyTransformerTaggerHead.decodeValidatedGraph(serialized);
    expect(head.copyWeights(), hasLength(49 * 768));
    expect(head.copyBiases(), hasLength(49));
    expect(head.weightAt(0, 0), 0);
    expect(head.weightAt(48, 767), 0);
    expect(head.biasAt(48), 0);

    final weights = head.copyWeights();
    final biases = head.copyBiases();
    weights[0] = 1;
    biases[0] = 1;
    expect(head.weightAt(0, 0), 0);
    expect(head.biasAt(0), 0);

    expect(() => head.weightAt(-1, 0), throwsRangeError);
    expect(() => head.weightAt(0, 768), throwsRangeError);
    expect(() => head.biasAt(49), throwsRangeError);
  });

  test('strict decoder rejects graph, shape, and numeric tampering', () {
    for (final serialized in <Uint8List>[
      _serializedGraph(nodeZeroName: 'softmax'),
      _serializedGraph(nodeZeroOutput: 50),
      _serializedGraph(weightShape: const <int>[48, 768]),
      _serializedGraph(nonFiniteWeight: true),
      Uint8List.fromList(<int>[0xc1]),
    ]) {
      expect(
        () => SpacyTransformerTaggerHead.decodeValidatedGraph(serialized),
        throwsA(isA<MalformedDataException>()),
      );
    }

    final valid = _serializedGraph();
    expect(
      () => SpacyTransformerTaggerHead.decodeValidatedGraph(
        Uint8List.fromList(<int>[...valid, 0]),
      ),
      throwsA(isA<MalformedDataException>()),
    );
  });

  test(
    'decodes the exact provisioned tagger head',
    () async {
      final serialized = await File(
        '$provisionedRoot${Platform.pathSeparator}tagger'
        '${Platform.pathSeparator}model',
      ).readAsBytes();
      final head = SpacyTransformerTaggerHead.decode(serialized);

      expect(head.weightAt(0, 0), closeTo(0.051202897, 1e-9));
      expect(head.weightAt(0, 767), closeTo(-0.031269807, 1e-9));
      expect(head.weightAt(48, 0), closeTo(0.024896162, 1e-9));
      expect(head.weightAt(48, 767), closeTo(-0.0077823857, 1e-9));
      expect(head.biasAt(0), closeTo(-0.020253723, 1e-9));
      expect(head.biasAt(24), closeTo(-0.0065793404, 1e-9));
      expect(head.biasAt(48), closeTo(-0.0074747535, 1e-9));
      expect(
        sha256.convert(_littleEndianBytes(head.copyWeights())).toString(),
        'e1ebf98491c0124fcb38b0e72c1d8d81ab3a72d1e33055975530bae2ba424738',
      );
      expect(
        sha256.convert(_littleEndianBytes(head.copyBiases())).toString(),
        'c57c0420c83a8ab8f34a54d5f03d4e29f789e2b6d2285a5182f58b26c0e62ba2',
      );

      final tampered = Uint8List.fromList(serialized);
      tampered[tampered.length - 1] ^= 0xff;
      expect(
        () => SpacyTransformerTaggerHead.decode(tampered),
        throwsA(isA<MalformedDataException>()),
      );
    },
    tags: 'provisioned',
    skip: provisionedSkip,
  );
}

Uint8List _serializedGraph({
  String nodeZeroName = 'last_transformer_layer_listener>>with_array(softmax)',
  int nodeZeroOutput = 49,
  List<int> weightShape = const <int>[49, 768],
  bool nonFiniteWeight = false,
}) {
  final weightData = Uint8List(49 * 768 * Float32List.bytesPerElement);
  if (nonFiniteWeight) {
    ByteData.sublistView(weightData).setUint32(0, 0x7fc00000, Endian.little);
  }
  final biasData = Uint8List(49 * Float32List.bytesPerElement);
  final root = <Object?, Object?>{
    'nodes': <Object?>[
      _node(
        0,
        nodeZeroName,
        <String, int>{'nO': nodeZeroOutput},
        <String, int>{'tok2vec': 1, 'softmax': 4, 'output_layer': 4},
      ),
      _node(
        1,
        'last_transformer_layer_listener',
        <String, int>{'nO': 768},
        <String, int>{'pooling': 5},
      ),
      _node(2, 'with_array(softmax)', <String, int>{
        'nO': 49,
        'nI': 768,
      }, <String, int>{}),
      _node(3, 'with_ragged_last_layer', <String, int>{}, <String, int>{}),
      _node(4, 'softmax', <String, int>{'nO': 49, 'nI': 768}, <String, int>{}),
      _node(5, 'reduce_mean', <String, int>{}, <String, int>{}),
    ],
    'attrs': <Object?>[
      <String, Object?>{},
      <String, Object?>{
        'grad_factor': Uint8List.fromList(<int>[
          0xcb,
          0x3f,
          0xf0,
          0,
          0,
          0,
          0,
          0,
          0,
        ]),
        '_upstream_name': Uint8List.fromList(<int>[
          0xab,
          ...utf8.encode('transformer'),
        ]),
        '_TRANSFORMER_LISTENER': Uint8List.fromList(<int>[0xc3]),
        '_USE_DOC_ANNOTATIONS_FOR_PREDICTION': Uint8List.fromList(<int>[0xc3]),
        '_REQUIRES_ALL_LAYER_OUTPUTS': Uint8List.fromList(<int>[0xc2]),
        '_state': Uint8List(0),
      },
      <String, Object?>{
        'pad': Uint8List.fromList(<int>[0]),
      },
      <String, Object?>{},
      <String, Object?>{
        'softmax_normalize': Uint8List.fromList(<int>[0xc2]),
        'softmax_temperature': Uint8List.fromList(<int>[
          0xcb,
          0x3f,
          0xf0,
          0,
          0,
          0,
          0,
          0,
          0,
        ]),
      },
      <String, Object?>{},
    ],
    'params': <Object?>[
      <String, Object?>{},
      <String, Object?>{},
      <String, Object?>{},
      <String, Object?>{},
      <String, Object?>{
        'W': _numpyArray(weightShape, weightData),
        'b': _numpyArray(const <int>[49], biasData),
      },
      <String, Object?>{},
    ],
    'shims': <Object?>[
      <Object?>[],
      <Object?>[],
      <Object?>[],
      <Object?>[],
      <Object?>[],
      <Object?>[],
    ],
  };
  return _encodeMessagePack(root);
}

Map<String, Object?> _node(
  int index,
  String name,
  Map<String, int> dims,
  Map<String, int> refs,
) => <String, Object?>{
  'index': index,
  'name': name,
  'dims': dims,
  'refs': refs,
};

Map<Object?, Object?> _numpyArray(List<int> shape, Uint8List data) =>
    <Object?, Object?>{
      _binaryKey('nd'): true,
      _binaryKey('type'): '<f4',
      _binaryKey('kind'): Uint8List(0),
      _binaryKey('shape'): shape,
      _binaryKey('data'): data,
    };

Uint8List _binaryKey(String value) => Uint8List.fromList(utf8.encode(value));

Uint8List _littleEndianBytes(Float32List values) {
  final bytes = Uint8List(values.length * Float32List.bytesPerElement);
  final data = ByteData.sublistView(bytes);
  for (var index = 0; index < values.length; index++) {
    data.setFloat32(
      index * Float32List.bytesPerElement,
      values[index],
      Endian.little,
    );
  }
  return bytes;
}

Uint8List _encodeMessagePack(Object? value) {
  final builder = BytesBuilder(copy: false);
  _writeValue(builder, value);
  return builder.takeBytes();
}

void _writeValue(BytesBuilder builder, Object? value) {
  if (value == null) {
    builder.addByte(0xc0);
  } else if (value is bool) {
    builder.addByte(value ? 0xc3 : 0xc2);
  } else if (value is int) {
    _writeInteger(builder, value);
  } else if (value is String) {
    _writeString(builder, value);
  } else if (value is Uint8List) {
    _writeBinary(builder, value);
  } else if (value is List<Object?>) {
    _writeArrayHeader(builder, value.length);
    for (final item in value) {
      _writeValue(builder, item);
    }
  } else if (value is Map<Object?, Object?>) {
    _writeMapHeader(builder, value.length);
    for (final entry in value.entries) {
      _writeValue(builder, entry.key);
      _writeValue(builder, entry.value);
    }
  } else {
    throw ArgumentError.value(value, 'value', 'Unsupported test value.');
  }
}

void _writeInteger(BytesBuilder builder, int value) {
  if (value < 0 || value > 0xffff) {
    throw RangeError.range(value, 0, 0xffff, 'value');
  }
  if (value <= 0x7f) {
    builder.addByte(value);
  } else if (value <= 0xff) {
    builder
      ..addByte(0xcc)
      ..addByte(value);
  } else {
    builder.addByte(0xcd);
    _writeUint16(builder, value);
  }
}

void _writeString(BytesBuilder builder, String value) {
  final bytes = utf8.encode(value);
  if (bytes.length <= 31) {
    builder.addByte(0xa0 | bytes.length);
  } else if (bytes.length <= 0xff) {
    builder
      ..addByte(0xd9)
      ..addByte(bytes.length);
  } else {
    builder.addByte(0xda);
    _writeUint16(builder, bytes.length);
  }
  builder.add(bytes);
}

void _writeBinary(BytesBuilder builder, Uint8List value) {
  if (value.length <= 0xff) {
    builder
      ..addByte(0xc4)
      ..addByte(value.length);
  } else if (value.length <= 0xffff) {
    builder.addByte(0xc5);
    _writeUint16(builder, value.length);
  } else {
    builder.addByte(0xc6);
    _writeUint32(builder, value.length);
  }
  builder.add(value);
}

void _writeArrayHeader(BytesBuilder builder, int length) {
  if (length <= 15) {
    builder.addByte(0x90 | length);
  } else {
    builder.addByte(0xdc);
    _writeUint16(builder, length);
  }
}

void _writeMapHeader(BytesBuilder builder, int length) {
  if (length <= 15) {
    builder.addByte(0x80 | length);
  } else {
    builder.addByte(0xde);
    _writeUint16(builder, length);
  }
}

void _writeUint16(BytesBuilder builder, int value) {
  final data = ByteData(2)..setUint16(0, value, Endian.big);
  builder.add(data.buffer.asUint8List());
}

void _writeUint32(BytesBuilder builder, int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.big);
  builder.add(data.buffer.asUint8List());
}
