import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:misakid_fonix_en/misakid_fonix_en.dart';

Uint8List testModelBytes() => Uint8List.fromList(<int>[1, 2, 3, 4]);

Uint8List testManifestBytes({Map<String, Object?>? override}) {
  final model = testModelBytes();
  final value = <String, Object?>{
    'schemaVersion': 1,
    'modelId': 'misakid-en-us-ctc-test',
    'version': 'test-1',
    'dialect': 'en-US',
    'architecture': 'misakid-medium-conv-bigru-ctc',
    'normalization': 'none',
    'model': <String, Object?>{
      'file': 'model.onnx',
      'sizeBytes': model.length,
      'sha256': sha256.convert(model).toString(),
      'onnxIrVersion': 8,
      'opset': 17,
    },
    'contract': <String, Object?>{
      'inputName': 'grapheme_ids',
      'outputName': 'logits',
      'maximumGraphemeCodePoints': 64,
      'slotsPerGrapheme': 8,
      'maximumBatchSize': 1,
    },
    'vocabularies': <String, Object?>{
      'graphemes': <String>['<pad>', '<unk>', 'a', 'b'],
      'phonemes': <String>['<blank>', 'p', 'q'],
    },
  };
  if (override != null) {
    value.addAll(override);
  }
  return Uint8List.fromList(utf8.encode(jsonEncode(value)));
}

FonixEnglishG2pModelProfile testProfile() =>
    FonixEnglishG2pModelProfile.parse(testManifestBytes());
