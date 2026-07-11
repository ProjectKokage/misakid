// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const int _expectedModelBytes = 497343046;
const String _expectedModelSha256 =
    '2b7061c623f424486e5dddcff79276927127cee339cc6a9d26d87837c3e6074a';
const int _expectedTensorCount = 149;
const int _expectedTensorBytes = 496220160;
const int _expectedTensorElements = 124055040;

Future<void> main(List<String> arguments) async {
  final root = File.fromUri(Platform.script).parent.parent;
  var manifest = File('${root.path}/tool/native_tensor_manifest.json');
  var output = File('${root.path}/native/src/generated_tensor_manifest.h');
  var accept = false;
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    switch (argument) {
      case '--manifest':
        manifest = File(_next(arguments, ++index, argument));
      case '--output':
        output = File(_next(arguments, ++index, argument));
      case '--accept':
        accept = true;
      case '--check':
        accept = false;
      default:
        _usage('Unknown argument: $argument');
    }
  }

  final manifestBytes = await manifest.readAsBytes();
  final rootValue = _stringMap(
    jsonDecode(utf8.decode(manifestBytes, allowMalformed: false)),
    'manifest root',
  );
  final records = _validateManifest(rootValue);
  final tagger = _validateTagger(rootValue);
  final manifestDigest = sha256.convert(manifestBytes).toString();
  final generated = utf8.encode(_render(records, tagger, manifestDigest));

  if (accept) {
    await output.parent.create(recursive: true);
    final temporary = File('${output.path}.tmp.$pid');
    try {
      await temporary.writeAsBytes(generated, flush: true);
      await temporary.rename(output.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
    stdout.writeln(
      'generated ${output.path} from ${manifest.path} '
      '(sha256:$manifestDigest)',
    );
    return;
  }

  if (!await output.exists() ||
      !_equal(await output.readAsBytes(), generated)) {
    stderr.writeln(
      'Generated native tensor header differs. Review the canonical manifest '
      'and run with --accept.',
    );
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'verified ${records.length} native tensor records '
    '(manifest sha256:$manifestDigest)',
  );
}

List<_TensorRecord> _validateManifest(Map<String, Object?> root) {
  _exactKeys(root, <String>{
    'artifact',
    'pieceEncoder',
    'runtimeVersions',
    'schemaVersion',
    'tagger',
    'transformer',
  }, 'manifest root');
  _expect(root['schemaVersion'], 1, 'schemaVersion');
  final artifact = _stringMap(root['artifact'], 'artifact');
  _expect(artifact['distribution'], 'en-core-web-trf', 'artifact distribution');
  _expect(artifact['version'], '3.8.0', 'artifact version');
  final resources = _stringMap(artifact['resources'], 'artifact resources');
  final modelResource = _stringMap(
    resources['transformer/model'],
    'transformer/model resource',
  );
  _expect(modelResource['sizeBytes'], _expectedModelBytes, 'model byte length');
  _expect(modelResource['sha256'], _expectedModelSha256, 'model SHA-256');

  final transformer = _stringMap(root['transformer'], 'transformer');
  for (final expected in <String, int>{
    'attentionHeads': 12,
    'batchSizeSpans': 384,
    'elementCount': _expectedTensorElements,
    'feedForwardWidth': 3072,
    'hiddenWidth': 768,
    'layerCount': 12,
    'maximumModelPieces': 512,
    'positionEmbeddingCount': 514,
    'stride': 104,
    'tensorByteCount': _expectedTensorBytes,
    'tensorCount': _expectedTensorCount,
    'vocabularySize': 50265,
    'window': 144,
  }.entries) {
    _expect(transformer[expected.key], expected.value, expected.key);
  }
  _expect(transformer['layerNormEpsilon'], 0.00001, 'layerNormEpsilon');

  final rawRecords = _list(transformer['tensors'], 'transformer tensors');
  if (rawRecords.length != _expectedTensorCount) {
    _fail('Transformer tensor count differs from $_expectedTensorCount.');
  }
  final names = <String>{};
  final expectedNames = _expectedTensorNames();
  var totalBytes = 0;
  var totalElements = 0;
  final records = <_TensorRecord>[];
  for (var index = 0; index < rawRecords.length; index++) {
    final value = _stringMap(rawRecords[index], 'tensor $index');
    _exactKeys(value, <String>{
      'byteLength',
      'byteOffset',
      'dtype',
      'name',
      'sha256',
      'shape',
      'storagePath',
    }, 'tensor $index');
    final name = _string(value['name'], 'tensor $index name');
    final offset = _integer(value['byteOffset'], 'tensor $index byteOffset');
    final length = _integer(value['byteLength'], 'tensor $index byteLength');
    final digest = _string(value['sha256'], 'tensor $index SHA-256');
    final storagePath = _string(
      value['storagePath'],
      'tensor $index storagePath',
    );
    final shape = <int>[
      for (final dimension in _list(value['shape'], 'tensor $index shape'))
        _integer(dimension, 'tensor $index shape dimension'),
    ];
    if (name != expectedNames[index] ||
        !names.add(name) ||
        value['dtype'] != 'F32_LE' ||
        digest.length != 64 ||
        !_lowerHex.hasMatch(digest) ||
        storagePath != 'archive/data/$index' ||
        offset < 0 ||
        length <= 0 ||
        offset > _expectedModelBytes - length ||
        shape.isEmpty ||
        shape.any((dimension) => dimension <= 0)) {
      _fail('Tensor $index is malformed.');
    }
    var elements = 1;
    for (final dimension in shape) {
      elements *= dimension;
    }
    if (elements * 4 != length) {
      _fail('Tensor $index byte length does not match its F32 shape.');
    }
    records.add(
      _TensorRecord(name: name, offset: offset, length: length, sha256: digest),
    );
    totalBytes += length;
    totalElements += elements;
  }
  if (totalBytes != _expectedTensorBytes ||
      totalElements != _expectedTensorElements) {
    _fail('Transformer tensor totals are malformed.');
  }
  return records;
}

List<String> _expectedTensorNames() {
  final result = <String>[
    'curated_encoder.embeddings.inner.word_embeddings.weight',
    'curated_encoder.embeddings.inner.token_type_embeddings.weight',
    'curated_encoder.embeddings.inner.position_embeddings.weight',
    'curated_encoder.embeddings.inner.layer_norm.weight',
    'curated_encoder.embeddings.inner.layer_norm.bias',
  ];
  const suffixes = <String>[
    'mha.input.weight',
    'mha.input.bias',
    'mha.output.weight',
    'mha.output.bias',
    'attn_output_layernorm.weight',
    'attn_output_layernorm.bias',
    'ffn.intermediate.weight',
    'ffn.intermediate.bias',
    'ffn.output.weight',
    'ffn.output.bias',
    'ffn_output_layernorm.weight',
    'ffn_output_layernorm.bias',
  ];
  for (var layer = 0; layer < 12; layer++) {
    for (final suffix in suffixes) {
      result.add('curated_encoder.layers.$layer.$suffix');
    }
  }
  return result;
}

_TaggerDigests _validateTagger(Map<String, Object?> root) {
  final tagger = _stringMap(root['tagger'], 'tagger');
  _expect(tagger['normalizeScores'], false, 'tagger normalizeScores');
  _expect(
    tagger['pooling'],
    'mean over each spaCy token\'s final-layer pieces',
    'tagger pooling',
  );
  final labels = _list(tagger['labels'], 'tagger labels');
  if (labels.length != 49 || labels.any((label) => label is! String)) {
    _fail('Tagger labels are malformed.');
  }
  final tensors = _list(tagger['tensors'], 'tagger tensors');
  if (tensors.length != 2) _fail('Tagger tensor count is malformed.');
  String validate(int index, String name, int byteLength, List<int> shape) {
    final tensor = _stringMap(tensors[index], 'tagger tensor $index');
    _exactKeys(tensor, <String>{
      'byteLength',
      'dtype',
      'name',
      'sha256',
      'shape',
    }, 'tagger tensor $index');
    _expect(tensor['name'], name, 'tagger tensor $index name');
    _expect(tensor['dtype'], 'F32_LE', 'tagger tensor $index dtype');
    _expect(
      tensor['byteLength'],
      byteLength,
      'tagger tensor $index byteLength',
    );
    final actualShape = <int>[
      for (final value in _list(tensor['shape'], 'tagger tensor $index shape'))
        _integer(value, 'tagger tensor $index shape dimension'),
    ];
    if (!_equal(actualShape, shape)) {
      _fail('Tagger tensor $index shape is malformed.');
    }
    final digest = _string(tensor['sha256'], 'tagger tensor $index SHA-256');
    if (digest.length != 64 || !_lowerHex.hasMatch(digest)) {
      _fail('Tagger tensor $index SHA-256 is malformed.');
    }
    return digest;
  }

  return _TaggerDigests(
    weights: validate(0, 'W', 150528, const <int>[49, 768]),
    biases: validate(1, 'b', 196, const <int>[49]),
  );
}

String _render(
  List<_TensorRecord> records,
  _TaggerDigests tagger,
  String manifestDigest,
) {
  final output = StringBuffer()
    ..writeln('// Copyright 2026 the misakid contributors.')
    ..writeln('// SPDX-License-Identifier: Apache-2.0')
    ..writeln('//')
    ..writeln('// GENERATED FILE. DO NOT EDIT.')
    ..writeln('// Generator: tool/generate_native_tensor_manifest.dart')
    ..writeln('// Canonical input: tool/native_tensor_manifest.json')
    ..writeln('// Canonical input SHA-256: $manifestDigest')
    ..writeln()
    ..writeln('#ifndef MISAKID_SPACY_TRF_EN_GENERATED_TENSOR_MANIFEST_H_')
    ..writeln('#define MISAKID_SPACY_TRF_EN_GENERATED_TENSOR_MANIFEST_H_')
    ..writeln()
    ..writeln('#include <array>')
    ..writeln('#include <cstddef>')
    ..writeln('#include <cstdint>')
    ..writeln()
    ..writeln('namespace misakid_spacy_trf_en_generated {')
    ..writeln('struct TensorRecord {')
    ..writeln('  const char *name;')
    ..writeln('  uint64_t byte_offset;')
    ..writeln('  uint64_t byte_length;')
    ..writeln('  const char *sha256;')
    ..writeln('};')
    ..writeln()
    ..writeln('inline constexpr uint64_t kModelByteLength = ')
    ..writeln('    ${_expectedModelBytes}ULL;')
    ..writeln('inline constexpr char kModelSha256[] =')
    ..writeln('    "$_expectedModelSha256";')
    ..writeln('inline constexpr char kManifestSha256[] =')
    ..writeln('    "$manifestDigest";')
    ..writeln('inline constexpr char kTaggerWeightSha256[] =')
    ..writeln('    "${tagger.weights}";')
    ..writeln('inline constexpr char kTaggerBiasSha256[] =')
    ..writeln('    "${tagger.biases}";')
    ..writeln('inline constexpr uint64_t kTensorByteCount = ')
    ..writeln('    ${_expectedTensorBytes}ULL;')
    ..writeln('inline constexpr std::array<TensorRecord, ${records.length}>')
    ..writeln('    kTensorRecords = {{');
  for (final record in records) {
    output
      ..writeln('        {"${_cppEscape(record.name)}",')
      ..writeln('         ${record.offset}ULL, ${record.length}ULL,')
      ..writeln('         "${record.sha256}"},');
  }
  output
    ..writeln('    }};')
    ..writeln('} // namespace misakid_spacy_trf_en_generated')
    ..writeln()
    ..writeln('#endif // MISAKID_SPACY_TRF_EN_GENERATED_TENSOR_MANIFEST_H_');
  return output.toString();
}

String _next(List<String> arguments, int index, String option) {
  if (index >= arguments.length) _usage('Missing value for $option.');
  return arguments[index];
}

Never _usage(String message) {
  stderr.writeln(message);
  stderr.writeln(
    'Usage: dart run tool/generate_native_tensor_manifest.dart '
    '[--manifest <json>] [--output <header>] [--check|--accept]',
  );
  exit(64);
}

Map<String, Object?> _stringMap(Object? value, String location) {
  if (value is! Map<Object?, Object?> ||
      value.keys.any((key) => key is! String)) {
    _fail('$location is not a string-keyed object.');
  }
  return value.cast<String, Object?>();
}

List<Object?> _list(Object? value, String location) {
  if (value is! List<Object?>) _fail('$location is not an array.');
  return value;
}

String _string(Object? value, String location) {
  if (value is! String) _fail('$location is not a string.');
  return value;
}

int _integer(Object? value, String location) {
  if (value is! int) _fail('$location is not an integer.');
  return value;
}

void _expect(Object? actual, Object expected, String location) {
  if (actual != expected) _fail('$location has an unexpected value.');
}

void _exactKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String location,
) {
  if (value.keys.toSet().difference(expected).isNotEmpty ||
      expected.difference(value.keys.toSet()).isNotEmpty) {
    _fail('$location has unexpected fields.');
  }
}

Never _fail(String message) => throw FormatException(message);

bool _equal(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

String _cppEscape(String value) => value
    .replaceAll(r'\', r'\\')
    .replaceAll('"', r'\"')
    .replaceAll('\n', r'\n')
    .replaceAll('\r', r'\r');

final RegExp _lowerHex = RegExp(r'^[0-9a-f]+$');

final class _TensorRecord {
  const _TensorRecord({
    required this.name,
    required this.offset,
    required this.length,
    required this.sha256,
  });

  final String name;
  final int offset;
  final int length;
  final String sha256;
}

final class _TaggerDigests {
  const _TaggerDigests({required this.weights, required this.biases});

  final String weights;
  final String biases;
}
