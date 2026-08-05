import 'dart:ffi';
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
    await expectLater(
      OpenJtalkFrontendBackend.openBundled(
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
      await expectLater(
        OpenJtalkFrontendBackend.openBundled(
          dictionaryPath: _absoluteMissingPath(suffix),
        ),
        throwsA(isA<InvalidConfigurationException>()),
      );
    }
  });

  test(
    'validates the configured input limit before touching resources',
    () async {
      for (final limit in <int>[0, 64 * 1024 * 1024 + 1]) {
        await expectLater(
          OpenJtalkFrontendBackend.open(
            libraryPath: _absoluteMissingPath('library.dylib'),
            dictionaryPath: _absoluteMissingPath('dictionary'),
            maxInputBytes: limit,
          ),
          throwsA(isA<InvalidConfigurationException>()),
        );
        await expectLater(
          OpenJtalkFrontendBackend.openBundled(
            dictionaryPath: _absoluteMissingPath('dictionary'),
            maxInputBytes: limit,
          ),
          throwsA(isA<InvalidConfigurationException>()),
        );
      }
    },
  );

  test('publishes the exact bundled target operating systems', () {
    expect(openJtalkBundledBuildPlatforms, <String>{
      'android',
      'ios',
      'linux',
      'macos',
      'windows',
    });
    expect(
      () => openJtalkBundledBuildPlatforms.add('web'),
      throwsUnsupportedError,
    );
  });

  test(
    'unsupported bundled ABI fails before reading the dictionary',
    () async {
      await expectLater(
        OpenJtalkFrontendBackend.openBundled(
          dictionaryPath: _absoluteMissingPath('open_jtalk_dictionary'),
        ),
        throwsA(isA<BackendUnavailableException>()),
      );
    },
    skip: _isBundledSupportedHost
        ? 'This host is a supported bundled native-assets tuple.'
        : false,
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

bool get _isBundledSupportedHost {
  final abi = Abi.current();
  return (Platform.isAndroid &&
          (abi == Abi.androidArm ||
              abi == Abi.androidArm64 ||
              abi == Abi.androidX64)) ||
      (Platform.isIOS && (abi == Abi.iosArm64 || abi == Abi.iosX64)) ||
      (Platform.isMacOS && (abi == Abi.macosArm64 || abi == Abi.macosX64)) ||
      (Platform.isLinux && (abi == Abi.linuxArm64 || abi == Abi.linuxX64)) ||
      (Platform.isWindows && abi == Abi.windowsX64);
}
