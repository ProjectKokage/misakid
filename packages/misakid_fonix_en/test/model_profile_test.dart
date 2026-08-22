import 'dart:convert';
import 'dart:typed_data';

import 'package:misakid_fonix_en/misakid_fonix_en.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

void main() {
  test('parses the exact closed en-US CTC profile', () {
    final profile = testProfile();

    expect(profile.modelId, 'misakid-en-us-ctc-test');
    expect(profile.version, 'test-1');
    expect(profile.modelSizeBytes, 4);
    expect(profile.onnxIrVersion, 8);
    expect(profile.opset, 17);
    expect(profile.inputName, 'grapheme_ids');
    expect(profile.outputName, 'logits');
    expect(profile.maximumGraphemeCodePoints, 64);
    expect(profile.slotsPerGrapheme, 8);
    expect(profile.graphemeIds, <int, int>{0x61: 2, 0x62: 3});
    expect(() => profile.graphemeVocabulary.add('c'), throwsUnsupportedError);
    profile.validateModelBytes(testModelBytes());
  });

  test('rejects identity mismatch, unknown keys, and contract drift', () {
    final profile = testProfile();
    expect(
      () => profile.validateModelBytes(Uint8List.fromList(<int>[1, 2, 3, 5])),
      throwsA(isA<MalformedDataException>()),
    );

    final extra = testManifestBytes(override: <String, Object?>{'extra': true});
    expect(
      () => FonixEnglishG2pModelProfile.parse(extra),
      throwsA(isA<MalformedDataException>()),
    );

    final decoded =
        jsonDecode(utf8.decode(testManifestBytes())) as Map<String, Object?>;
    final contract = decoded['contract']! as Map<String, Object?>;
    contract['slotsPerGrapheme'] = 7;
    expect(
      () => FonixEnglishG2pModelProfile.parse(
        Uint8List.fromList(utf8.encode(jsonEncode(decoded))),
      ),
      throwsA(isA<MalformedDataException>()),
    );
  });

  test('rejects malformed vocabularies and oversized manifests', () {
    final decoded =
        jsonDecode(utf8.decode(testManifestBytes())) as Map<String, Object?>;
    final vocabularies = decoded['vocabularies']! as Map<String, Object?>;
    vocabularies['phonemes'] = <String>['<blank>', 'p', 'p'];
    expect(
      () => FonixEnglishG2pModelProfile.parse(
        Uint8List.fromList(utf8.encode(jsonEncode(decoded))),
      ),
      throwsA(isA<MalformedDataException>()),
    );
    expect(
      () => FonixEnglishG2pModelProfile.parse(Uint8List(256 * 1024 + 1)),
      throwsA(isA<MalformedDataException>()),
    );
  });

  test('rejects duplicate manifest keys before interpretation', () {
    final source = utf8
        .decode(testManifestBytes())
        .replaceFirst(
          '"schemaVersion":1',
          '"schemaVersion":1,"schemaVersion":1',
        );
    expect(
      () => FonixEnglishG2pModelProfile.parse(
        Uint8List.fromList(utf8.encode(source)),
      ),
      throwsA(isA<MalformedDataException>()),
    );
  });
}
