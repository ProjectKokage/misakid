import 'dart:convert';
import 'dart:typed_data';

import 'package:misakid/misaki.dart';
import 'package:misakid_bart_en/src/safetensors.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

void main() {
  test('parses all committed synthetic F32 tensors', () {
    final parsed = BartSafetensors.parse(syntheticWeightsBytes());
    expect(parsed.tensors, hasLength(50));
    expect(parsed.tensors['model.shared.weight']!.shape, <int>[8, 4]);
    expect(parsed.tensors['final_logits_bias']!.shape, <int>[1, 8]);
  });

  test('rejects duplicate top-level and nested header keys', () {
    final data = ByteData(4)..setFloat32(0, 1, Endian.little);
    for (final header in <String>[
      '{"a":{"dtype":"F32","shape":[1],"data_offsets":[0,4]},'
          '"a":{"dtype":"F32","shape":[1],"data_offsets":[0,4]}}',
      '{"a":{"dtype":"F32","dtype":"F32","shape":[1],'
          '"data_offsets":[0,4]}}',
    ]) {
      expect(
        () =>
            BartSafetensors.parse(_resource(header, data.buffer.asUint8List())),
        throwsA(isA<MalformedDataException>()),
      );
    }
  });

  test('rejects dtype, gaps, shape mismatch, and non-finite values', () {
    final finite = ByteData(8)
      ..setFloat32(0, 1, Endian.little)
      ..setFloat32(4, 2, Endian.little);
    final cases = <(String, Uint8List)>[
      (
        '{"a":{"dtype":"F16","shape":[2],"data_offsets":[0,8]}}',
        finite.buffer.asUint8List(),
      ),
      (
        '{"a":{"dtype":"F32","shape":[1],"data_offsets":[4,8]}}',
        finite.buffer.asUint8List(),
      ),
      (
        '{"a":{"dtype":"F32","shape":[1],"data_offsets":[0,8]}}',
        finite.buffer.asUint8List(),
      ),
      (
        '{"a":{"dtype":"F32","shape":[1],"data_offsets":[0,4]}}',
        (ByteData(
          4,
        )..setFloat32(0, double.nan, Endian.little)).buffer.asUint8List(),
      ),
    ];
    for (final (header, data) in cases) {
      expect(
        () => BartSafetensors.parse(_resource(header, data)),
        throwsA(isA<MalformedDataException>()),
        reason: header,
      );
    }
  });

  test('rejects an oversized 64-bit header length before allocation', () {
    final bytes = Uint8List(10);
    final prefix = ByteData.sublistView(bytes)
      ..setUint32(0, 1, Endian.little)
      ..setUint32(4, 1, Endian.little);
    expect(prefix.getUint32(4, Endian.little), 1);
    expect(
      () => BartSafetensors.parse(bytes),
      throwsA(isA<MalformedDataException>()),
    );
  });
}

Uint8List _resource(String header, Uint8List data) {
  final headerBytes = utf8.encode(header);
  final result = Uint8List(8 + headerBytes.length + data.length);
  ByteData.sublistView(result).setUint64(0, headerBytes.length, Endian.little);
  result.setRange(8, 8 + headerBytes.length, headerBytes);
  result.setRange(8 + headerBytes.length, result.length, data);
  return result;
}
