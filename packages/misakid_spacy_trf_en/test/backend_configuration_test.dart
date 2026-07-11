import 'dart:io';

import 'package:misakid_spacy_trf_en/misakid_spacy_trf_en.dart';
import 'package:test/test.dart';

void main() {
  test('rejects invalid native paths and public piece limits', () async {
    for (final path in <String>[
      'libmisakid_spacy_trf_en.dylib',
      '${Directory.systemTemp.path}\u0000model',
      '${Directory.systemTemp.path}\uD800model',
    ]) {
      await expectLater(
        NativeSpacyTransformerEnglishTokenizerBackend.open(
          modelDirectoryPath: Directory.systemTemp.path,
          nativeLibraryPath: path,
        ),
        throwsA(isA<InvalidConfigurationException>()),
        reason: path.codeUnits.toString(),
      );
    }

    for (final value in <int>[
      1,
      maximumConfigurableSpacyTransformerPieces + 1,
    ]) {
      await expectLater(
        NativeSpacyTransformerEnglishTokenizerBackend.open(
          modelDirectoryPath: Directory.systemTemp.path,
          nativeLibraryPath: '${Directory.systemTemp.path}/native.dylib',
          maxPieces: value,
        ),
        throwsA(isA<InvalidConfigurationException>()),
      );
    }
  });

  test('reports a missing native library before reading model resources', () {
    final missing =
        '${Directory.systemTemp.path}/missing-misakid-spacy-trf-en.dylib';
    expect(
      NativeSpacyTransformerEnglishTokenizerBackend.open(
        modelDirectoryPath: '${Directory.systemTemp.path}/missing-model',
        nativeLibraryPath: missing,
      ),
      throwsA(isA<BackendUnavailableException>()),
    );
  });
}
