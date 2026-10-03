// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:ffi';
import 'dart:io';

import 'package:misakid/misaki_ja.dart';
import 'package:misakid_adapter_support/file_system.dart';

import 'dictionary_identity.dart';
import 'native_bindings.dart';

/// Exact platform supported by the first Open JTalk adapter release.
const String openJtalkSupportedPlatform = 'macos-arm64';

/// Platforms targeted by the package's reproducible native-assets build hook.
///
/// This describes build availability, not the narrower set of runtime tuples
/// that have completed provisioned parity testing.
const Set<String> openJtalkBundledBuildPlatforms = <String>{
  'android',
  'ios',
  'linux',
  'macos',
  'windows',
};

/// Default maximum UTF-8 input size accepted by one frontend call.
const int defaultOpenJtalkMaxInputBytes = 1024 * 1024;

const int _maximumConfigurableInputBytes = 64 * 1024 * 1024;

/// Explicit native Open JTalk frontend for [JapanesePyopenjtalkEngine].
///
/// Open the backend once with [open], [openBundled], or
/// [openBundledFromVerifiedInstall], reuse it for synchronous conversions,
/// and call [close] when finished. The caller supplies the dictionary; this
/// package never searches for or downloads native code or resources.
final class OpenJtalkFrontendBackend implements JapaneseFrontendBackend {
  OpenJtalkFrontendBackend._({
    required OpenJtalkNativeFrontend frontend,
    required this.info,
  }) : _frontend = frontend;

  /// Validates resources and opens a macOS arm64 Open JTalk frontend.
  static Future<OpenJtalkFrontendBackend> open({
    required String libraryPath,
    required String dictionaryPath,
    int maxInputBytes = defaultOpenJtalkMaxInputBytes,
  }) async {
    _validateConfiguration(
      libraryPath: libraryPath,
      dictionaryPath: dictionaryPath,
      maxInputBytes: maxInputBytes,
    );
    _validateSupportedPlatform();
    final FileSystemEntityType libraryType;
    try {
      libraryType = await FileSystemEntity.type(
        libraryPath,
        followLinks: false,
      );
    } on FileSystemException catch (error) {
      throw BackendUnavailableException(
        'The configured Open JTalk native library could not be inspected.',
        cause: error,
      );
    } on ArgumentError catch (error) {
      throw InvalidConfigurationException(
        'The configured Open JTalk native library path is invalid.',
        cause: error,
      );
    }
    if (libraryType == FileSystemEntityType.notFound) {
      throw const BackendUnavailableException(
        'The configured Open JTalk native library does not exist.',
      );
    }
    if (libraryType != FileSystemEntityType.file) {
      throw const InvalidConfigurationException(
        'The configured Open JTalk native library must be a real file, not a link.',
      );
    }

    final String resolvedLibraryPath;
    final OpenJtalkNativeLibrary library;
    try {
      resolvedLibraryPath = await File(libraryPath).resolveSymbolicLinks();
      library = OpenJtalkNativeLibrary.load(resolvedLibraryPath);
    } on OpenJtalkNativeLibraryException catch (error) {
      throw BackendUnavailableException(error.message, cause: error);
    } on FileSystemException catch (error) {
      throw BackendUnavailableException(
        'The configured Open JTalk native library could not be resolved.',
        cause: error,
      );
    }

    return _initialize(
      library: library,
      dictionaryPath: dictionaryPath,
      maxInputBytes: maxInputBytes,
      platform: openJtalkSupportedPlatform,
      verifyDictionaryContents: true,
    );
  }

  /// Opens the package-built native asset with an explicit dictionary path.
  ///
  /// [dictionaryPath] must point to an already materialized, validated Open
  /// JTalk 1.11 dictionary directory. Applications may copy that resource
  /// from their bundle into private application-support storage.
  static Future<OpenJtalkFrontendBackend> openBundled({
    required String dictionaryPath,
    int maxInputBytes = defaultOpenJtalkMaxInputBytes,
  }) => _openBundled(
    dictionaryPath: dictionaryPath,
    maxInputBytes: maxInputBytes,
    verifyDictionaryContents: true,
  );

  /// Opens the bundled native asset from a caller-verified dictionary install.
  ///
  /// Use this only when the exact dictionary sizes and SHA-256 identities were
  /// checked in app-private staging before an atomic directory rename. This
  /// path checks the pinned file structure and sizes and detects changes during
  /// native open, but it does not hash the installed files again.
  static Future<OpenJtalkFrontendBackend> openBundledFromVerifiedInstall({
    required String dictionaryPath,
    int maxInputBytes = defaultOpenJtalkMaxInputBytes,
  }) => _openBundled(
    dictionaryPath: dictionaryPath,
    maxInputBytes: maxInputBytes,
    verifyDictionaryContents: false,
  );

  static Future<OpenJtalkFrontendBackend> _openBundled({
    required String dictionaryPath,
    required int maxInputBytes,
    required bool verifyDictionaryContents,
  }) async {
    _validateBundledConfiguration(
      dictionaryPath: dictionaryPath,
      maxInputBytes: maxInputBytes,
    );
    _validateBundledSupportedPlatform();

    final OpenJtalkNativeLibrary library;
    try {
      library = OpenJtalkNativeLibrary.loadBundled();
    } on OpenJtalkNativeLibraryException catch (error) {
      throw BackendUnavailableException(error.message, cause: error);
    }
    return _initialize(
      library: library,
      dictionaryPath: dictionaryPath,
      maxInputBytes: maxInputBytes,
      platform: _bundledPlatformLabel(),
      verifyDictionaryContents: verifyDictionaryContents,
    );
  }

  static Future<OpenJtalkFrontendBackend> _initialize({
    required OpenJtalkNativeLibrary library,
    required String dictionaryPath,
    required int maxInputBytes,
    required String platform,
    required bool verifyDictionaryContents,
  }) async {
    final dictionary = verifyDictionaryContents
        ? await OpenJtalkDictionarySnapshot.validate(dictionaryPath)
        : await OpenJtalkDictionarySnapshot.fromVerifiedInstall(dictionaryPath);
    OpenJtalkNativeFrontend? frontend;
    try {
      frontend = OpenJtalkNativeFrontend.create(
        library: library,
        dictionaryPath: dictionary.resolvedPath,
        maxInputBytes: maxInputBytes,
      );
      await dictionary.ensureUnchanged();
      final identities = library.identities;
      return OpenJtalkFrontendBackend._(
        frontend: frontend,
        info: BackendInfo(
          name: 'pyopenjtalk',
          version: identities[1]!,
          details: <String, String>{
            'adapterVersion': identities[0]!,
            'abiVersion': openJtalkNativeAbiVersion.toString(),
            'platform': platform,
            'openJtalkVersion': identities[2]!,
            'nativeSourceTreeSha256': identities[3]!,
            'nativeSourceSdistSha256': identities[4]!,
            'nativePatchSet': identities[5]!,
            'dictionary': openJtalkDictionaryName,
            'dictionaryTreeSha256': identities[6]!,
          },
        ),
      );
    } on OpenJtalkNativeException catch (error) {
      frontend?.close();
      throw BackendUnavailableException(
        'The validated Open JTalk frontend could not be initialized '
        '(native stage `${error.stage}`, code ${error.code}).',
        cause: error,
      );
    } on OpenJtalkNativeLibraryException catch (error) {
      frontend?.close();
      throw BackendUnavailableException(
        'The Open JTalk native library returned malformed initialization data.',
        cause: error,
      );
    } on Object {
      frontend?.close();
      rethrow;
    }
  }

  final OpenJtalkNativeFrontend _frontend;

  @override
  final BackendInfo info;

  /// Whether [close] has released the native frontend context.
  bool get isClosed => _frontend.isClosed;

  @override
  List<JapaneseFrontendWord> analyze(String text) {
    if (isClosed) {
      throw const BackendUnavailableException(
        'The Open JTalk frontend is closed; open a new backend.',
      );
    }
    try {
      final rawWords = _frontend.analyzeRaw(text);
      return List<JapaneseFrontendWord>.unmodifiable(
        rawWords.map(
          (word) => JapaneseFrontendWord(
            surface: word.surface,
            partOfSpeech: word.partOfSpeech,
            pronunciation: word.pronunciation,
            accent: word.accent,
            moraSize: word.moraSize,
            chainFlag: word.rawChainFlag == 1,
          ),
        ),
      );
    } on OpenJtalkNativeException catch (error) {
      throw BackendFailureException(
        'Open JTalk analysis failed at native stage `${error.stage}` '
        '(code ${error.code}).',
        cause: error,
      );
    } on OpenJtalkNativeLibraryException catch (error) {
      throw BackendFailureException(
        'Open JTalk returned malformed native data.',
        cause: error,
      );
    }
  }

  /// Releases the native context. Calling this more than once is safe.
  void close() => _frontend.close();
}

void _validateConfiguration({
  required String libraryPath,
  required String dictionaryPath,
  required int maxInputBytes,
}) {
  if (!isAbsoluteFilePath(libraryPath) || !isAbsoluteFilePath(dictionaryPath)) {
    throw const InvalidConfigurationException(
      'Open JTalk library and dictionary paths must be non-empty absolute paths.',
    );
  }
  if (!isValidPathText(libraryPath) || !isValidPathText(dictionaryPath)) {
    throw const InvalidConfigurationException(
      'Open JTalk paths must be valid Unicode without NUL and no longer than 32768 UTF-8 bytes.',
    );
  }
  _validateInputLimit(maxInputBytes);
}

void _validateBundledConfiguration({
  required String dictionaryPath,
  required int maxInputBytes,
}) {
  if (!isAbsoluteFilePath(dictionaryPath)) {
    throw const InvalidConfigurationException(
      'The Open JTalk dictionary path must be a non-empty absolute path.',
    );
  }
  if (!isValidPathText(dictionaryPath)) {
    throw const InvalidConfigurationException(
      'The Open JTalk dictionary path must be valid Unicode without NUL and '
      'no longer than 32768 UTF-8 bytes.',
    );
  }
  _validateInputLimit(maxInputBytes);
}

void _validateInputLimit(int maxInputBytes) {
  if (maxInputBytes <= 0 || maxInputBytes > _maximumConfigurableInputBytes) {
    throw InvalidConfigurationException(
      'maxInputBytes must be between 1 and '
      '$_maximumConfigurableInputBytes.',
    );
  }
}

void _validateBundledSupportedPlatform() {
  final abi = Abi.current();
  final supported =
      (Platform.isAndroid &&
          (abi == Abi.androidArm ||
              abi == Abi.androidArm64 ||
              abi == Abi.androidX64)) ||
      (Platform.isIOS && (abi == Abi.iosArm64 || abi == Abi.iosX64)) ||
      (Platform.isMacOS && (abi == Abi.macosArm64 || abi == Abi.macosX64)) ||
      (Platform.isLinux && (abi == Abi.linuxArm64 || abi == Abi.linuxX64)) ||
      (Platform.isWindows && abi == Abi.windowsX64);
  if (!supported) {
    throw BackendUnavailableException(
      'The bundled Open JTalk native asset does not support ${abi.toString()}.',
    );
  }
}

String _bundledPlatformLabel() => 'native-assets-${Abi.current()}';

void _validateSupportedPlatform() {
  if (!Platform.isMacOS || Abi.current() != Abi.macosArm64) {
    throw const BackendUnavailableException(
      'misakid_openjtalk 0.1.0-dev.2 supports only macOS arm64.',
    );
  }
}
