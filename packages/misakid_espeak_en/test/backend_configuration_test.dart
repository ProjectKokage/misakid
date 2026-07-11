import 'dart:ffi';
import 'dart:io';

import 'package:misakid_espeak_en/misakid_espeak_en.dart';
import 'package:test/test.dart';

void main() {
  test('rejects relative paths before platform or filesystem access', () async {
    await expectLater(
      EspeakEnglishBackend.open(
        adapterLibraryPath: 'adapter',
        espeakLibraryPath: '/runtime',
        dataPath: '/data',
      ),
      throwsA(isA<InvalidConfigurationException>()),
    );
    await expectLater(
      EspeakEnglishBackend.open(
        adapterLibraryPath: '/adapter',
        espeakLibraryPath: 'runtime',
        dataPath: '/data',
      ),
      throwsA(isA<InvalidConfigurationException>()),
    );
    await expectLater(
      EspeakEnglishBackend.open(
        adapterLibraryPath: '/adapter',
        espeakLibraryPath: '/runtime',
        dataPath: 'data',
      ),
      throwsA(isA<InvalidConfigurationException>()),
    );
  });

  test('rejects invalid byte limits before platform or I/O', () async {
    for (final limit in <int>[0, 64 * 1024 * 1024 + 1]) {
      await expectLater(
        EspeakEnglishBackend.open(
          adapterLibraryPath: '/adapter',
          espeakLibraryPath: '/runtime',
          dataPath: '/data',
          maxInputBytes: limit,
        ),
        throwsA(isA<InvalidConfigurationException>()),
      );
      await expectLater(
        EspeakEnglishBackend.open(
          adapterLibraryPath: '/adapter',
          espeakLibraryPath: '/runtime',
          dataPath: '/data',
          maxOutputBytes: limit,
        ),
        throwsA(isA<InvalidConfigurationException>()),
      );
    }
  });

  test(
    'unsupported platforms fail before reading configured resources',
    () async {
      await expectLater(
        EspeakEnglishBackend.open(
          adapterLibraryPath: '/definitely/missing/adapter',
          espeakLibraryPath: '/definitely/missing/runtime',
          dataPath: '/definitely/missing/data',
        ),
        throwsA(isA<BackendUnavailableException>()),
      );
    },
    skip: Platform.isMacOS && Abi.current() == Abi.macosArm64
        ? 'This host is the supported native tuple.'
        : false,
  );

  test('publishes exact external resource identities and limits', () {
    expect(espeakEnglishSupportedPlatform, 'macos-arm64');
    expect(defaultEspeakEnglishMaxInputBytes, 1024 * 1024);
    expect(defaultEspeakEnglishMaxOutputBytes, 4 * 1024 * 1024);
    expect(maximumEspeakEnglishChunksPerCall, 65536);
    expect(pinnedEspeakNgLibrarySizeBytes, 504168);
    expect(pinnedEspeakNgDataDirectoryCount, 37);
    expect(pinnedEspeakNgDataFileCount, 364);
    expect(pinnedEspeakNgDataSizeBytes, 18373365);
  });
}
