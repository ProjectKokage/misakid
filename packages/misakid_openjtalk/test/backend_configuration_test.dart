import 'dart:io';

import 'package:misakid/misaki.dart';
import 'package:misakid_openjtalk/misakid_openjtalk.dart';
import 'package:misakid_openjtalk/src/dictionary_identity.dart';
import 'package:test/test.dart';

void main() {
  test('requires explicit absolute paths', () async {
    await expectLater(
      OpenJtalkFrontendBackend.open(
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
        OpenJtalkFrontendBackend.open(
          libraryPath: _absoluteMissingPath(suffix),
          dictionaryPath: _absoluteMissingPath('dictionary'),
        ),
        throwsA(isA<InvalidConfigurationException>()),
      );
    }
  });

  test(
    'validates the configured input limit before touching resources',
    () async {
      await expectLater(
        OpenJtalkFrontendBackend.open(
          libraryPath: _absoluteMissingPath('library.dylib'),
          dictionaryPath: _absoluteMissingPath('dictionary'),
          maxInputBytes: 0,
        ),
        throwsA(isA<InvalidConfigurationException>()),
      );
      await expectLater(
        OpenJtalkFrontendBackend.open(
          libraryPath: _absoluteMissingPath('library.dylib'),
          dictionaryPath: _absoluteMissingPath('dictionary'),
          maxInputBytes: 64 * 1024 * 1024 + 1,
        ),
        throwsA(isA<InvalidConfigurationException>()),
      );
    },
  );

  test('reports a missing explicit library as unavailable', () async {
    await expectLater(
      OpenJtalkFrontendBackend.open(
        libraryPath: _absoluteMissingPath('misakid_openjtalk.dylib'),
        dictionaryPath: _absoluteMissingPath('open_jtalk_dictionary'),
      ),
      throwsA(isA<BackendUnavailableException>()),
    );
  });

  test('dictionary validation rejects missing and malformed trees', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'misakid-openjtalk-invalid-dictionary-',
    );
    try {
      await File('${temporary.path}/unexpected').writeAsString('invalid');
      await expectLater(
        OpenJtalkDictionarySnapshot.validate(temporary.path),
        throwsA(isA<MalformedDataException>()),
      );
      await expectLater(
        OpenJtalkDictionarySnapshot.validate(
          '${temporary.path}/does-not-exist',
        ),
        throwsA(isA<BackendUnavailableException>()),
      );
    } finally {
      await temporary.delete(recursive: true);
    }
  });
}

String _absoluteMissingPath(String name) => Platform.isWindows
    ? 'C:\\definitely-missing\\$name'
    : '/definitely-missing/$name';
