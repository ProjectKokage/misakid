// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:typed_data';

import 'package:misakid/misaki.dart';

const Set<String> _allowedConfigKeys = <String>{
  'activation_dropout',
  'activation_function',
  'architectures',
  'attention_dropout',
  'bos_token_id',
  'classifier_dropout',
  'd_model',
  'decoder_attention_heads',
  'decoder_ffn_dim',
  'decoder_layerdrop',
  'decoder_layers',
  'decoder_start_token_id',
  'dropout',
  'encoder_attention_heads',
  'encoder_ffn_dim',
  'encoder_layerdrop',
  'encoder_layers',
  'eos_token_id',
  'forced_eos_token_id',
  'grapheme_chars',
  'id2label',
  'init_std',
  'is_encoder_decoder',
  'label2id',
  'layer_norm_eps',
  'max_position_embeddings',
  'model_type',
  'num_hidden_layers',
  'pad_token_id',
  'phoneme_chars',
  'scale_embedding',
  'torch_dtype',
  'transformers_version',
  'use_cache',
  'vocab_size',
};

/// Validated narrow BART architecture configuration.
final class BartConfig {
  BartConfig._({
    required this.dModel,
    required this.encoderAttentionHeads,
    required this.decoderAttentionHeads,
    required this.encoderFfnDim,
    required this.decoderFfnDim,
    required this.maxPositionEmbeddings,
    required this.vocabSize,
    required this.graphemeCharacters,
    required this.phonemeCharacters,
    required this.layerNormEpsilon,
  });

  final int dModel;
  final int encoderAttentionHeads;
  final int decoderAttentionHeads;
  final int encoderFfnDim;
  final int decoderFfnDim;
  final int maxPositionEmbeddings;
  final int vocabSize;
  final List<int> graphemeCharacters;
  final List<int> phonemeCharacters;
  final double layerNormEpsilon;

  /// Parses and validates the exact supported architecture profile.
  factory BartConfig.parse(Uint8List bytes) {
    try {
      final value = decodeStrictJson(utf8.decode(bytes, allowMalformed: false));
      if (value is! Map<String, Object?>) {
        throw const MalformedDataException(
          'The BART configuration must be a JSON object.',
        );
      }
      return _parseConfig(value);
    } on MisakiException {
      rethrow;
    } on FormatException catch (error) {
      throw MalformedDataException(
        'The BART configuration is not valid UTF-8 JSON.',
        cause: error,
      );
    }
  }
}

BartConfig _parseConfig(Map<String, Object?> value) {
  final unknown = value.keys.where((key) => !_allowedConfigKeys.contains(key));
  if (unknown.isNotEmpty) {
    throw MalformedDataException(
      'The BART configuration contains unsupported keys: ${unknown.join(', ')}.',
    );
  }
  _requireExactString(value, 'model_type', 'bart');
  _requireExactString(value, 'activation_function', 'gelu');
  _requireExactString(value, 'torch_dtype', 'float32');
  _requireExactBool(value, 'is_encoder_decoder', true);
  _requireExactBool(value, 'scale_embedding', false);
  _requireExactInt(value, 'encoder_layers', 1);
  _requireExactInt(value, 'decoder_layers', 1);
  if (value.containsKey('num_hidden_layers')) {
    _requireExactInt(value, 'num_hidden_layers', 1);
  }
  _requireExactInt(value, 'pad_token_id', 0);
  _requireExactInt(value, 'bos_token_id', 1);
  _requireExactInt(value, 'eos_token_id', 2);
  _requireExactInt(value, 'decoder_start_token_id', 1);
  _requireExactInt(value, 'forced_eos_token_id', 2);
  for (final key in <String>[
    'activation_dropout',
    'attention_dropout',
    'classifier_dropout',
    'decoder_layerdrop',
    'dropout',
    'encoder_layerdrop',
  ]) {
    _validateOptionalNumber(value, key, minimum: 0, maximum: 1);
  }
  _validateOptionalNumber(value, 'init_std', minimum: 0, maximum: 1);
  _validateOptionalBool(value, 'use_cache');
  _validateOptionalString(value, 'transformers_version');
  _validateOptionalStringMap(value, 'id2label', valuesAreIntegers: false);
  _validateOptionalStringMap(value, 'label2id', valuesAreIntegers: true);
  final architectures = value['architectures'];
  if (architectures is! List<Object?> ||
      architectures.length != 1 ||
      architectures.single != 'BartForConditionalGeneration') {
    throw const MalformedDataException(
      'The BART configuration must declare only BartForConditionalGeneration.',
    );
  }

  final dModel = _boundedInt(value, 'd_model', minimum: 1, maximum: 128);
  final encoderHeads = _boundedInt(
    value,
    'encoder_attention_heads',
    minimum: 1,
    maximum: 8,
  );
  final decoderHeads = _boundedInt(
    value,
    'decoder_attention_heads',
    minimum: 1,
    maximum: 8,
  );
  if (dModel % encoderHeads != 0 || dModel % decoderHeads != 0) {
    throw const MalformedDataException(
      'BART attention head counts must divide d_model.',
    );
  }
  final encoderFfn = _boundedInt(
    value,
    'encoder_ffn_dim',
    minimum: 1,
    maximum: 1024,
  );
  final decoderFfn = _boundedInt(
    value,
    'decoder_ffn_dim',
    minimum: 1,
    maximum: 1024,
  );
  final maxPositions = _boundedInt(
    value,
    'max_position_embeddings',
    minimum: 4,
    maximum: 64,
  );
  final vocabSize = _boundedInt(value, 'vocab_size', minimum: 5, maximum: 256);
  final graphemes = _requiredScalarString(value, 'grapheme_chars');
  final phonemes = _requiredScalarString(value, 'phoneme_chars');
  if (graphemes.length < 4 || graphemes.length > vocabSize) {
    throw const MalformedDataException(
      'BART grapheme_chars must contain between 4 and vocab_size scalars.',
    );
  }
  if (phonemes.length < 4 || phonemes.length > vocabSize) {
    throw const MalformedDataException(
      'BART phoneme_chars must contain between 4 and vocab_size scalars.',
    );
  }
  _validateSpecialCharacterTable(graphemes, 'grapheme_chars');
  _validateSpecialCharacterTable(phonemes, 'phoneme_chars');
  final epsilonValue = value['layer_norm_eps'];
  if (epsilonValue != null &&
      (epsilonValue is! num || epsilonValue.toDouble() != 1e-5)) {
    throw const MalformedDataException(
      'BART layer_norm_eps, when present, must equal the fixed 1e-5 runtime value.',
    );
  }
  return BartConfig._(
    dModel: dModel,
    encoderAttentionHeads: encoderHeads,
    decoderAttentionHeads: decoderHeads,
    encoderFfnDim: encoderFfn,
    decoderFfnDim: decoderFfn,
    maxPositionEmbeddings: maxPositions,
    vocabSize: vocabSize,
    graphemeCharacters: List<int>.unmodifiable(graphemes),
    phonemeCharacters: List<int>.unmodifiable(phonemes),
    layerNormEpsilon: 1e-5,
  );
}

void _validateOptionalNumber(
  Map<String, Object?> value,
  String key, {
  required double minimum,
  required double maximum,
}) {
  if (!value.containsKey(key)) return;
  final candidate = value[key];
  if (candidate is! num ||
      !candidate.toDouble().isFinite ||
      candidate.toDouble() < minimum ||
      candidate.toDouble() > maximum) {
    throw MalformedDataException(
      'BART configuration `$key` must be numeric from $minimum through $maximum.',
    );
  }
}

void _validateOptionalBool(Map<String, Object?> value, String key) {
  if (value.containsKey(key) && value[key] is! bool) {
    throw MalformedDataException('BART configuration `$key` must be boolean.');
  }
}

void _validateOptionalString(Map<String, Object?> value, String key) {
  if (!value.containsKey(key)) return;
  final candidate = value[key];
  if (candidate is! String || candidate.isEmpty || candidate.length > 128) {
    throw MalformedDataException(
      'BART configuration `$key` must be a bounded non-empty string.',
    );
  }
}

void _validateOptionalStringMap(
  Map<String, Object?> value,
  String key, {
  required bool valuesAreIntegers,
}) {
  if (!value.containsKey(key)) return;
  final candidate = value[key];
  if (candidate is! Map<String, Object?> || candidate.length > 256) {
    throw MalformedDataException(
      'BART configuration `$key` must be a bounded JSON object.',
    );
  }
  for (final entry in candidate.entries) {
    final validValue = valuesAreIntegers
        ? entry.value is int
        : entry.value is String;
    if (entry.key.isEmpty || entry.key.length > 128 || !validValue) {
      throw MalformedDataException(
        'BART configuration `$key` contains an invalid label mapping.',
      );
    }
  }
}

void _validateSpecialCharacterTable(List<int> values, String name) {
  if (values.take(4).any((value) => value != 0x5F)) {
    throw MalformedDataException(
      'BART configuration `$name` must start with four underscore placeholders.',
    );
  }
  final modelValues = values.skip(4).toList(growable: false);
  if (modelValues.contains(0x5F) ||
      modelValues.toSet().length != modelValues.length) {
    throw MalformedDataException(
      'BART configuration `$name` must contain unique non-placeholder model scalars.',
    );
  }
}

void _requireExactString(
  Map<String, Object?> value,
  String key,
  String expected,
) {
  if (value[key] != expected) {
    throw MalformedDataException(
      'BART configuration `$key` must be `$expected`.',
    );
  }
}

void _requireExactBool(Map<String, Object?> value, String key, bool expected) {
  if (value[key] != expected) {
    throw MalformedDataException(
      'BART configuration `$key` must be $expected.',
    );
  }
}

void _requireExactInt(Map<String, Object?> value, String key, int expected) {
  if (value[key] != expected) {
    throw MalformedDataException(
      'BART configuration `$key` must be $expected.',
    );
  }
}

int _boundedInt(
  Map<String, Object?> value,
  String key, {
  required int minimum,
  required int maximum,
}) {
  final result = value[key];
  if (result is! int || result < minimum || result > maximum) {
    throw MalformedDataException(
      'BART configuration `$key` must be an integer from $minimum through $maximum.',
    );
  }
  return result;
}

List<int> _requiredScalarString(Map<String, Object?> value, String key) {
  final text = value[key];
  if (text is! String || text.isEmpty || !_hasOnlyUnicodeScalars(text)) {
    throw MalformedDataException(
      'BART configuration `$key` must be a non-empty Unicode scalar string.',
    );
  }
  return text.runes.toList(growable: false);
}

bool _hasOnlyUnicodeScalars(String value) {
  final units = value.codeUnits;
  for (var index = 0; index < units.length; index++) {
    final unit = units[index];
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (index + 1 >= units.length ||
          units[index + 1] < 0xDC00 ||
          units[index + 1] > 0xDFFF) {
        return false;
      }
      index++;
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      return false;
    }
  }
  return true;
}
