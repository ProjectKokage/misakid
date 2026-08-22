import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:misakid/misaki.dart';

const int _maximumManifestBytes = 256 * 1024;
const int _maximumModelBytes = 32 * 1024 * 1024;
const int _maximumLogitBytes = 2 * 1024 * 1024;
const String _architecture = 'misakid-conv-ctc-v1';
const String _dialect = 'en-US';
const String _normalization = 'none';
const String _modelFile = 'model.onnx';
const String _inputName = 'grapheme_ids';
const String _outputName = 'logits';
const String _graphemePad = '<pad>';
const String _graphemeUnknown = '<unk>';
const String _phonemeBlank = '<blank>';
const int _maximumGraphemeCodePoints = 64;
const int _slotsPerGrapheme = 8;
const int _maximumBatchSize = 1;

/// Closed, immutable runtime contract for one en-US neural G2P graph.
final class FonixEnglishG2pModelProfile {
  FonixEnglishG2pModelProfile._({
    required this.modelId,
    required this.version,
    required this.modelSizeBytes,
    required this.modelSha256,
    required this.onnxIrVersion,
    required this.opset,
    required List<String> graphemeVocabulary,
    required List<String> phonemeVocabulary,
  }) : graphemeVocabulary = List<String>.unmodifiable(graphemeVocabulary),
       phonemeVocabulary = List<String>.unmodifiable(phonemeVocabulary),
       graphemeIds = Map<int, int>.unmodifiable(<int, int>{
         for (var index = 2; index < graphemeVocabulary.length; index++)
           graphemeVocabulary[index].runes.single: index,
       });

  /// Parses and validates a schema-1 runtime manifest.
  factory FonixEnglishG2pModelProfile.parse(Uint8List manifestBytes) {
    if (manifestBytes.isEmpty || manifestBytes.length > _maximumManifestBytes) {
      throw const MalformedDataException(
        'The English G2P manifest has an invalid byte length.',
      );
    }

    late final Object? decoded;
    try {
      decoded = decodeStrictJson(
        utf8.decode(manifestBytes, allowMalformed: false),
      );
    } on FormatException catch (error) {
      throw MalformedDataException(
        'The English G2P manifest is not valid UTF-8 JSON.',
        cause: error,
      );
    }
    final root = _object(decoded, 'manifest');
    _expectKeys(root, const <String>{
      'schemaVersion',
      'modelId',
      'version',
      'dialect',
      'architecture',
      'normalization',
      'model',
      'contract',
      'vocabularies',
    }, 'manifest');
    if (_integer(root, 'schemaVersion') != 1) {
      throw const MalformedDataException(
        'The English G2P manifest schema is unsupported.',
      );
    }
    final modelId = _safeIdentifier(root, 'modelId');
    final version = _safeText(root, 'version', maximumBytes: 64);
    if (_string(root, 'dialect') != _dialect ||
        _string(root, 'architecture') != _architecture ||
        _string(root, 'normalization') != _normalization) {
      throw const MalformedDataException(
        'The English G2P language or architecture contract is unsupported.',
      );
    }

    final model = _childObject(root, 'model');
    _expectKeys(model, const <String>{
      'file',
      'sizeBytes',
      'sha256',
      'onnxIrVersion',
      'opset',
    }, 'model');
    if (_string(model, 'file') != _modelFile) {
      throw const MalformedDataException(
        'The English G2P model file identity is unsupported.',
      );
    }
    final modelSizeBytes = _boundedInteger(
      model,
      'sizeBytes',
      minimum: 1,
      maximum: _maximumModelBytes,
    );
    final modelSha256 = _sha256(model, 'sha256');
    final onnxIrVersion = _boundedInteger(
      model,
      'onnxIrVersion',
      minimum: 1,
      maximum: 10,
    );
    final opset = _integer(model, 'opset');
    if (opset != 17) {
      throw const MalformedDataException(
        'The English G2P ONNX opset is unsupported.',
      );
    }

    final contract = _childObject(root, 'contract');
    _expectKeys(contract, const <String>{
      'inputName',
      'outputName',
      'maximumGraphemeCodePoints',
      'slotsPerGrapheme',
      'maximumBatchSize',
    }, 'contract');
    if (_string(contract, 'inputName') != _inputName ||
        _string(contract, 'outputName') != _outputName ||
        _integer(contract, 'maximumGraphemeCodePoints') !=
            _maximumGraphemeCodePoints ||
        _integer(contract, 'slotsPerGrapheme') != _slotsPerGrapheme ||
        _integer(contract, 'maximumBatchSize') != _maximumBatchSize) {
      throw const MalformedDataException(
        'The English G2P tensor or resource contract is unsupported.',
      );
    }

    final vocabularies = _childObject(root, 'vocabularies');
    _expectKeys(vocabularies, const <String>{
      'graphemes',
      'phonemes',
    }, 'vocabularies');
    final graphemes = _symbolList(
      vocabularies,
      'graphemes',
      reserved: const <String>[_graphemePad, _graphemeUnknown],
      maximumLength: 1024,
    );
    final phonemes = _symbolList(
      vocabularies,
      'phonemes',
      reserved: const <String>[_phonemeBlank],
      maximumLength: 128,
    );
    final maximumLogitElements =
        _maximumGraphemeCodePoints * _slotsPerGrapheme * phonemes.length;
    if (maximumLogitElements >
        _maximumLogitBytes ~/ Float32List.bytesPerElement) {
      throw const MalformedDataException(
        'The English G2P output exceeds the worker message bound.',
      );
    }

    return FonixEnglishG2pModelProfile._(
      modelId: modelId,
      version: version,
      modelSizeBytes: modelSizeBytes,
      modelSha256: modelSha256,
      onnxIrVersion: onnxIrVersion,
      opset: opset,
      graphemeVocabulary: graphemes,
      phonemeVocabulary: phonemes,
    );
  }

  /// Stable model identifier from the runtime manifest.
  final String modelId;

  /// Stable model revision or training-run identifier.
  final String version;

  /// Exact ONNX byte length.
  final int modelSizeBytes;

  /// Exact lowercase SHA-256 of the ONNX bytes.
  final String modelSha256;

  /// Declared ONNX IR version.
  final int onnxIrVersion;

  /// Declared default ONNX opset.
  final int opset;

  /// Ordered grapheme IDs, including pad and unknown at indices zero and one.
  final List<String> graphemeVocabulary;

  /// Ordered CTC output IDs, including blank at index zero.
  final List<String> phonemeVocabulary;

  /// Unicode-scalar-to-input-ID map for all non-reserved graphemes.
  final Map<int, int> graphemeIds;

  /// Fixed ONNX input name.
  String get inputName => _inputName;

  /// Fixed ONNX output name.
  String get outputName => _outputName;

  /// Maximum accepted input length in Unicode scalars.
  int get maximumGraphemeCodePoints => _maximumGraphemeCodePoints;

  /// Number of CTC time slots emitted per input grapheme.
  int get slotsPerGrapheme => _slotsPerGrapheme;

  /// Maximum copied logits bytes for a valid request.
  int get maximumLogitBytes => _maximumLogitBytes;

  /// Verifies model bytes before they are copied into Fonix.
  void validateModelBytes(Uint8List bytes) {
    if (bytes.length != modelSizeBytes ||
        sha256.convert(bytes).toString() != modelSha256) {
      throw const MalformedDataException(
        'The English G2P model does not match its manifest identity.',
      );
    }
  }
}

Map<String, Object?> _object(Object? value, String location) {
  if (value is! Map<String, Object?>) {
    throw MalformedDataException(
      'The English G2P $location must be a JSON object.',
    );
  }
  return value;
}

Map<String, Object?> _childObject(Map<String, Object?> parent, String key) =>
    _object(parent[key], key);

void _expectKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String location,
) {
  final actual = value.keys.toSet();
  if (actual.length != expected.length || !actual.containsAll(expected)) {
    throw MalformedDataException(
      'The English G2P $location has an incompatible key set.',
    );
  }
}

String _string(Map<String, Object?> value, String key) {
  final result = value[key];
  if (result is! String) {
    throw MalformedDataException(
      'The English G2P $key field must be a string.',
    );
  }
  return result;
}

String _safeIdentifier(Map<String, Object?> value, String key) {
  final result = _safeText(value, key, maximumBytes: 128);
  if (!RegExp(r'^[a-z0-9][a-z0-9._-]*$').hasMatch(result)) {
    throw MalformedDataException(
      'The English G2P $key field is not a safe identifier.',
    );
  }
  return result;
}

String _safeText(
  Map<String, Object?> value,
  String key, {
  required int maximumBytes,
}) {
  final result = _string(value, key);
  if (result.isEmpty ||
      !_wellFormedUtf16(result) ||
      utf8.encode(result).length > maximumBytes ||
      result.runes.any((codePoint) => codePoint < 0x20 || codePoint == 0x7f)) {
    throw MalformedDataException(
      'The English G2P $key field is not bounded safe text.',
    );
  }
  return result;
}

int _integer(Map<String, Object?> value, String key) {
  final result = value[key];
  if (result is! int) {
    throw MalformedDataException(
      'The English G2P $key field must be an integer.',
    );
  }
  return result;
}

int _boundedInteger(
  Map<String, Object?> value,
  String key, {
  required int minimum,
  required int maximum,
}) {
  final result = _integer(value, key);
  if (result < minimum || result > maximum) {
    throw MalformedDataException(
      'The English G2P $key field is outside its supported range.',
    );
  }
  return result;
}

String _sha256(Map<String, Object?> value, String key) {
  final result = _string(value, key);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(result)) {
    throw MalformedDataException(
      'The English G2P $key field is not a lowercase SHA-256.',
    );
  }
  return result;
}

List<String> _symbolList(
  Map<String, Object?> value,
  String key, {
  required List<String> reserved,
  required int maximumLength,
}) {
  final raw = value[key];
  if (raw is! List<Object?> ||
      raw.length <= reserved.length ||
      raw.length > maximumLength) {
    throw MalformedDataException(
      'The English G2P $key vocabulary has an invalid length.',
    );
  }
  final result = <String>[];
  final seen = <String>{};
  for (var index = 0; index < raw.length; index++) {
    final symbol = raw[index];
    if (symbol is! String ||
        !_wellFormedUtf16(symbol) ||
        (index < reserved.length
            ? symbol != reserved[index]
            : symbol.runes.length != 1) ||
        !seen.add(symbol)) {
      throw MalformedDataException(
        'The English G2P $key vocabulary contains an invalid symbol.',
      );
    }
    result.add(symbol);
  }
  return List<String>.unmodifiable(result);
}

bool _wellFormedUtf16(String value) {
  final units = value.codeUnits;
  for (var index = 0; index < units.length; index++) {
    final unit = units[index];
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (index + 1 >= units.length ||
          units[index + 1] < 0xdc00 ||
          units[index + 1] > 0xdfff) {
        return false;
      }
      index++;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return false;
    }
  }
  return true;
}
