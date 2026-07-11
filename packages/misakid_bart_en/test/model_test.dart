import 'dart:convert';
import 'dart:typed_data';

import 'package:misakid/misaki.dart';
import 'package:misakid_bart_en/src/config.dart';
import 'package:misakid_bart_en/src/model.dart';
import 'package:misakid_bart_en/src/safetensors.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

void main() {
  late BartConfig config;
  late BartModel model;
  late Map<String, Object?> expected;

  setUpAll(() {
    config = BartConfig.parse(syntheticConfigBytes());
    model = BartModel.load(
      config,
      BartSafetensors.parse(syntheticWeightsBytes()),
    );
    expected = syntheticExpected();
  });

  test('matches independent synthetic encoder and causal decoder oracle', () {
    final inputIds = _ints(expected['inputIds']);
    final encoder = model.encode(inputIds);
    expect(<int>[
      encoder.rows,
      encoder.columns,
    ], _ints(expected['encoderShape']));
    _expectClose(encoder.values, _numbers(expected['encoderValues']));

    final decoderCases = expected['decoderCases']! as List<Object?>;
    expect(decoderCases, hasLength(4));
    for (final value in decoderCases) {
      final decoderCase = value! as Map<String, Object?>;
      final logits = model.decode(
        _ints(decoderCase['decoderIds']),
        encoderOutput: encoder,
        encoderMask: List<bool>.filled(inputIds.length, true),
      );
      expect(<int>[
        logits.rows,
        logits.columns,
      ], _ints(decoderCase['logitsShape']));
      _expectClose(logits.values, _numbers(decoderCase['logitsValues']));
    }
  });

  test('matches multiple independent greedy-generation cases', () {
    final cases = expected['generationCases']! as List<Object?>;
    expect(cases, hasLength(4));
    for (final value in cases) {
      final generationCase = value! as Map<String, Object?>;
      expect(
        model.generate(
          _ints(generationCase['inputIds']),
          maximumLength: generationCase['maximumGenerationLength']! as int,
        ),
        _ints(generationCase['generatedIds']),
        reason: generationCase['input']! as String,
      );
    }
  });

  test('matches independent early-EOS termination', () {
    final earlyCase = expected['earlyEosCase']! as Map<String, Object?>;
    final earlyModel = BartModel.load(
      config,
      BartSafetensors.parse(
        syntheticWeightsBytes(weightsFile: earlyCase['weightsFile']! as String),
      ),
    );
    expect(
      earlyModel.generate(
        _ints(earlyCase['inputIds']),
        maximumLength: earlyCase['maximumGenerationLength']! as int,
      ),
      _ints(earlyCase['generatedIds']),
    );
  });

  test('rejects config-derived tensor shape mismatch', () {
    final bytes = _replaceHeaderSameLength(
      syntheticWeightsBytes(),
      '"shape":[8,4]',
      '"shape":[4,8]',
    );
    final weights = BartSafetensors.parse(bytes);
    expect(
      () => BartModel.load(config, weights),
      throwsA(isA<MalformedDataException>()),
    );
  });

  test('rejects missing and unexpected tensor names', () {
    final bytes = _replaceHeaderSameLength(
      syntheticWeightsBytes(),
      'model.shared.weight',
      'model.shared.weighx',
    );
    final weights = BartSafetensors.parse(bytes);
    expect(
      () => BartModel.load(config, weights),
      throwsA(isA<MalformedDataException>()),
    );
  });

  test('rejects finite but unsafe weight magnitude', () {
    final bytes = Uint8List.fromList(syntheticWeightsBytes());
    final headerLength = ByteData.sublistView(
      bytes,
    ).getUint64(0, Endian.little);
    ByteData.sublistView(
      bytes,
    ).setFloat32(8 + headerLength, 1e10, Endian.little);
    final weights = BartSafetensors.parse(bytes);
    expect(
      () => BartModel.load(config, weights),
      throwsA(isA<MalformedDataException>()),
    );
  });

  test('rejects out-of-range IDs and generation limits', () {
    expect(
      () => model.encode(const <int>[1, 8, 2]),
      throwsA(isA<BackendFailureException>()),
    );
    expect(
      () => model.generate(const <int>[1, 2], maximumLength: 1),
      throwsA(isA<BackendFailureException>()),
    );
  });
}

void _expectClose(Iterable<num> actual, List<double> oracle) {
  final values = actual.toList(growable: false);
  expect(values, hasLength(oracle.length));
  for (var index = 0; index < values.length; index++) {
    expect(values[index], closeTo(oracle[index], 1e-6), reason: 'value $index');
  }
}

List<int> _ints(Object? value) =>
    (value! as List<Object?>).map((item) => item! as int).toList();

List<double> _numbers(Object? value) =>
    (value! as List<Object?>).map((item) => (item! as num).toDouble()).toList();

Uint8List _replaceHeaderSameLength(
  Uint8List source,
  String before,
  String after,
) {
  expect(after.length, before.length);
  final result = Uint8List.fromList(source);
  final headerLength = ByteData.sublistView(result).getUint64(0, Endian.little);
  final header = utf8.decode(result.sublist(8, 8 + headerLength));
  expect(header.split(before), hasLength(2));
  final replacement = header.replaceFirst(before, after);
  result.setRange(8, 8 + headerLength, utf8.encode(replacement));
  return result;
}
