import 'dart:convert';
import 'dart:typed_data';

import 'package:misakid/misaki.dart';
import 'package:misakid_bart_en/src/config.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

void main() {
  test('parses the exact synthetic one-layer architecture', () {
    final config = BartConfig.parse(syntheticConfigBytes());
    expect(config.dModel, 4);
    expect(config.encoderAttentionHeads, 2);
    expect(config.decoderAttentionHeads, 2);
    expect(config.encoderFfnDim, 6);
    expect(config.maxPositionEmbeddings, 8);
    expect(config.vocabSize, 8);
    expect(config.graphemeCharacters, '____abc?'.runes);
    expect(config.phonemeCharacters, '____ABC?'.runes);
    expect(config.layerNormEpsilon, 1e-5);
  });

  test('rejects duplicate keys before interpreting the configuration', () {
    final text = utf8.decode(syntheticConfigBytes());
    final duplicate = text.replaceFirst(
      '"d_model": 4,',
      '"d_model": 4,\n  "d_model": 4,',
    );
    expect(
      () => BartConfig.parse(Uint8List.fromList(utf8.encode(duplicate))),
      throwsA(isA<MalformedDataException>()),
    );
  });

  test('rejects unknown keys and unsupported architecture values', () {
    final source =
        jsonDecode(utf8.decode(syntheticConfigBytes())) as Map<String, Object?>;
    for (final mutation in <void Function(Map<String, Object?>)>[
      (value) => value['unknown'] = true,
      (value) => value['encoder_layers'] = 2,
      (value) => value['torch_dtype'] = 'float16',
      (value) => value['layer_norm_eps'] = 1e-6,
      (value) => value['encoder_attention_heads'] = 3,
    ]) {
      final value = Map<String, Object?>.from(source);
      mutation(value);
      expect(
        () => BartConfig.parse(
          Uint8List.fromList(utf8.encode(jsonEncode(value))),
        ),
        throwsA(isA<MalformedDataException>()),
      );
    }
  });

  test('requires special placeholders and unique model scalars', () {
    final source =
        jsonDecode(utf8.decode(syntheticConfigBytes())) as Map<String, Object?>;
    for (final graphemes in <String>['___xabc?', '____aac?', '_____bc?']) {
      final value = Map<String, Object?>.from(source)
        ..['grapheme_chars'] = graphemes;
      expect(
        () => BartConfig.parse(
          Uint8List.fromList(utf8.encode(jsonEncode(value))),
        ),
        throwsA(isA<MalformedDataException>()),
      );
    }
    final invalidPhonemes = Map<String, Object?>.from(source)
      ..['phoneme_chars'] = '____AAC?';
    expect(
      () => BartConfig.parse(
        Uint8List.fromList(utf8.encode(jsonEncode(invalidPhonemes))),
      ),
      throwsA(isA<MalformedDataException>()),
    );
  });
}
