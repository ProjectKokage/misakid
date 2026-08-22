import 'dart:typed_data';

import 'package:misakid/misaki.dart';

import 'model_profile.dart';

/// Copied logits returned by the narrow inference boundary.
final class EnglishCtcLogits {
  EnglishCtcLogits({required Iterable<int> shape, required Float32List values})
    : shape = List<int>.unmodifiable(shape),
      values = Float32List.fromList(values).asUnmodifiableView();

  /// Exact tensor shape.
  final List<int> shape;

  /// Copied row-major float32 values.
  final Float32List values;
}

/// Bounded Unicode encoding and deterministic greedy CTC decoding.
final class EnglishCtcCodec {
  /// Creates a codec for one validated [profile].
  const EnglishCtcCodec(this.profile);

  /// Exact model contract.
  final FonixEnglishG2pModelProfile profile;

  /// Encodes one non-empty token without normalization or silent substitution.
  Int64List encode(String text) {
    if (!_wellFormedUtf16(text)) {
      throw const BackendFailureException(
        'English neural G2P received malformed UTF-16 input.',
      );
    }
    final codePoints = text.runes.toList(growable: false);
    if (codePoints.isEmpty ||
        codePoints.length > profile.maximumGraphemeCodePoints) {
      throw BackendFailureException(
        'English neural G2P input must contain 1..'
        '${profile.maximumGraphemeCodePoints} Unicode scalars.',
      );
    }
    final encoded = Int64List(codePoints.length);
    for (var index = 0; index < codePoints.length; index++) {
      final codePoint = codePoints[index];
      final id = profile.graphemeIds[codePoint];
      if (id == null) {
        throw BackendFailureException(
          'English neural G2P does not support grapheme '
          '${_formatCodePoint(codePoint)}.',
        );
      }
      encoded[index] = id;
    }
    return encoded;
  }

  /// Greedily decodes one exact float32 CTC logit tensor.
  String decode(EnglishCtcLogits logits, {required int inputLength}) {
    final vocabulary = profile.phonemeVocabulary;
    final expectedSteps = inputLength * profile.slotsPerGrapheme;
    final shape = logits.shape;
    if (inputLength < 1 ||
        inputLength > profile.maximumGraphemeCodePoints ||
        shape.length != 3 ||
        shape[0] != 1 ||
        shape[1] != expectedSteps ||
        shape[2] != vocabulary.length ||
        logits.values.length != expectedSteps * vocabulary.length) {
      throw const BackendFailureException(
        'English neural G2P returned an incompatible logits tensor.',
      );
    }

    final output = StringBuffer();
    var previousId = -1;
    for (var step = 0; step < expectedSteps; step++) {
      final offset = step * vocabulary.length;
      var maximumId = 0;
      var maximum = logits.values[offset];
      if (!maximum.isFinite) {
        throw const BackendFailureException(
          'English neural G2P returned non-finite logits.',
        );
      }
      for (var id = 1; id < vocabulary.length; id++) {
        final value = logits.values[offset + id];
        if (!value.isFinite) {
          throw const BackendFailureException(
            'English neural G2P returned non-finite logits.',
          );
        }
        if (value > maximum) {
          maximum = value;
          maximumId = id;
        }
      }
      if (maximumId != 0 && maximumId != previousId) {
        output.write(vocabulary[maximumId]);
      }
      previousId = maximumId;
    }
    final result = output.toString();
    if (result.isEmpty) {
      throw const BackendFailureException(
        'English neural G2P returned an empty pronunciation.',
      );
    }
    return result;
  }
}

String _formatCodePoint(int value) {
  final width = value <= 0xffff ? 4 : 6;
  return 'U+${value.toRadixString(16).toUpperCase().padLeft(width, '0')}';
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
