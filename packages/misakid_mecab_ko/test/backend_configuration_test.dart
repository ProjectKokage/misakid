import 'dart:io';

import 'package:misakid_mecab_ko/misakid_mecab_ko.dart';
import 'package:test/test.dart';

void main() {
  test('requires explicit absolute paths', () async {
    await expectLater(
      MecabKoMorphologyBackend.open(
        libraryPath: 'relative.dylib',
        dictionaryPath: 'relative-dictionary',
      ),
      throwsA(isA<InvalidConfigurationException>()),
    );
  });

  test('rejects malformed path text before filesystem access', () async {
    for (final suffix in <String>[
      'bad\u0000path',
      String.fromCharCode(0xD800),
    ]) {
      await expectLater(
        MecabKoMorphologyBackend.open(
          libraryPath: _absoluteMissingPath(suffix),
          dictionaryPath: _absoluteMissingPath('dictionary'),
        ),
        throwsA(isA<InvalidConfigurationException>()),
      );
    }
  });

  test('validates the input limit before touching resources', () async {
    for (final maxInputBytes in <int>[0, 64 * 1024 * 1024 + 1]) {
      await expectLater(
        MecabKoMorphologyBackend.open(
          libraryPath: _absoluteMissingPath('library.dylib'),
          dictionaryPath: _absoluteMissingPath('dictionary'),
          maxInputBytes: maxInputBytes,
        ),
        throwsA(isA<InvalidConfigurationException>()),
      );
    }
  });

  test('reports a missing explicit library as unavailable', () async {
    await expectLater(
      MecabKoMorphologyBackend.open(
        libraryPath: _absoluteMissingPath('misakid_mecab_ko.dylib'),
        dictionaryPath: _absoluteMissingPath('dictionary'),
      ),
      throwsA(isA<BackendUnavailableException>()),
    );
  });
}

String _absoluteMissingPath(String name) => Platform.isWindows
    ? 'C:\\definitely-missing\\$name'
    : '/definitely-missing/$name';
