// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:ffi';
import 'dart:io';

import 'package:misakid/misaki_ko.dart';
import 'package:misakid_adapter_support/file_system.dart';

import 'dictionary_identity.dart';
import 'native_bindings.dart';

/// Exact platform supported by the first MeCab-ko adapter release.
const String mecabKoSupportedPlatform = 'macos-arm64';

/// Default maximum UTF-8 input size accepted by one morphology call.
const int defaultMecabKoMaxInputBytes = 1024 * 1024;

const int _maximumConfigurableInputBytes = 64 * 1024 * 1024;

/// Explicit native MeCab-ko morphology backend for [KoreanG2pkcEngine].
///
/// Open once with [open], reuse it for synchronous conversions, then call
/// [close]. The caller supplies both resources; this package never searches
/// for or downloads a native library or dictionary.
///
/// ```dart
/// final backend = await MecabKoMorphologyBackend.open(
///   libraryPath: '/absolute/path/libmisakid_mecab_ko.dylib',
///   dictionaryPath: '/absolute/path/mecab_ko_dic/dictionary',
/// );
/// final tokens = backend.pos('안녕하세요.');
/// ```
final class MecabKoMorphologyBackend implements KoreanMorphologyBackend {
  MecabKoMorphologyBackend._({
    required MecabKoNativeAnalyzer analyzer,
    required this.info,
  }) : _analyzer = analyzer;

  /// Validates resources and opens a macOS arm64 MeCab-ko analyzer.
  static Future<MecabKoMorphologyBackend> open({
    required String libraryPath,
    required String dictionaryPath,
    int maxInputBytes = defaultMecabKoMaxInputBytes,
  }) async {
    _validateConfiguration(
      libraryPath: libraryPath,
      dictionaryPath: dictionaryPath,
      maxInputBytes: maxInputBytes,
    );
    if (!Platform.isMacOS || Abi.current() != Abi.macosArm64) {
      throw const BackendUnavailableException(
        'misakid_mecab_ko 0.1.0-dev.1 supports only macOS arm64.',
      );
    }

    final FileSystemEntityType libraryType;
    try {
      libraryType = await FileSystemEntity.type(
        libraryPath,
        followLinks: false,
      );
    } on FileSystemException catch (error) {
      throw BackendUnavailableException(
        'The configured MeCab-ko native library could not be inspected.',
        cause: error,
      );
    } on ArgumentError catch (error) {
      throw InvalidConfigurationException(
        'The configured MeCab-ko native library path is invalid.',
        cause: error,
      );
    }
    if (libraryType == FileSystemEntityType.notFound) {
      throw const BackendUnavailableException(
        'The configured MeCab-ko native library does not exist.',
      );
    }
    if (libraryType != FileSystemEntityType.file) {
      throw const InvalidConfigurationException(
        'The configured MeCab-ko native library must be a real file, not a link.',
      );
    }

    final String resolvedLibraryPath;
    final MecabKoNativeLibrary library;
    try {
      resolvedLibraryPath = await File(libraryPath).resolveSymbolicLinks();
      library = MecabKoNativeLibrary.load(resolvedLibraryPath);
    } on MecabKoNativeLibraryException catch (error) {
      throw BackendUnavailableException(error.message, cause: error);
    } on FileSystemException catch (error) {
      throw BackendUnavailableException(
        'The configured MeCab-ko native library could not be resolved.',
        cause: error,
      );
    }

    final dictionary = await MecabKoDictionarySnapshot.validate(dictionaryPath);
    MecabKoNativeAnalyzer? analyzer;
    try {
      analyzer = MecabKoNativeAnalyzer.create(
        library: library,
        dictionaryPath: dictionary.resolvedPath,
        maxInputBytes: maxInputBytes,
      );
      await dictionary.ensureUnchanged();
      final identities = library.identities;
      return MecabKoMorphologyBackend._(
        analyzer: analyzer,
        info: BackendInfo(
          name: 'python-mecab-ko',
          version: '1.3.7',
          details: <String, String>{
            'adapterVersion': identities[0]!,
            'abiVersion': mecabKoNativeAbiVersion.toString(),
            'platform': mecabKoSupportedPlatform,
            'mecabKoVersion': identities[1]!,
            'nativeSourceTreeSha256': identities[2]!,
            'nativeSourceArchiveSha256': identities[3]!,
            'nativePatchSet': identities[4]!,
            'dictionary': mecabKoDictionaryName,
            'dictionaryVersion': mecabKoDictionaryVersion,
            'dictionaryTreeSha256': identities[5]!,
          },
        ),
      );
    } on MecabKoNativeException catch (error) {
      analyzer?.close();
      throw BackendUnavailableException(
        'The validated MeCab-ko analyzer could not be initialized '
        '(native stage `${error.stage}`, code ${error.code}).',
        cause: error,
      );
    } on MecabKoNativeLibraryException catch (error) {
      analyzer?.close();
      throw BackendUnavailableException(
        'The MeCab-ko native library returned malformed initialization data.',
        cause: error,
      );
    } on Object {
      analyzer?.close();
      rethrow;
    }
  }

  final MecabKoNativeAnalyzer _analyzer;

  @override
  final BackendInfo info;

  /// Whether [close] has released the native analyzer context.
  bool get isClosed => _analyzer.isClosed;

  @override
  List<KoreanMorphologyToken> pos(String text) {
    if (isClosed) {
      throw const BackendUnavailableException(
        'The MeCab-ko analyzer is closed; open a new backend.',
      );
    }
    try {
      return List<KoreanMorphologyToken>.unmodifiable(
        _analyzer
            .analyzeRaw(text)
            .map(
              (token) =>
                  KoreanMorphologyToken(surface: token.surface, tag: token.tag),
            ),
      );
    } on MecabKoNativeException catch (error) {
      throw BackendFailureException(
        'MeCab-ko analysis failed at native stage `${error.stage}` '
        '(code ${error.code}).',
        cause: error,
      );
    } on MecabKoNativeLibraryException catch (error) {
      throw BackendFailureException(
        'MeCab-ko returned malformed native data.',
        cause: error,
      );
    }
  }

  /// Releases the native context. Calling this more than once is safe.
  void close() => _analyzer.close();
}

void _validateConfiguration({
  required String libraryPath,
  required String dictionaryPath,
  required int maxInputBytes,
}) {
  if (!isAbsoluteFilePath(libraryPath) || !isAbsoluteFilePath(dictionaryPath)) {
    throw const InvalidConfigurationException(
      'MeCab-ko library and dictionary paths must be non-empty absolute paths.',
    );
  }
  if (!isValidPathText(libraryPath) || !isValidPathText(dictionaryPath)) {
    throw const InvalidConfigurationException(
      'MeCab-ko paths must be valid Unicode without NUL and no longer than 32768 UTF-8 bytes.',
    );
  }
  if (maxInputBytes <= 0 || maxInputBytes > _maximumConfigurableInputBytes) {
    throw InvalidConfigurationException(
      'maxInputBytes must be between 1 and '
      '$_maximumConfigurableInputBytes.',
    );
  }
}
