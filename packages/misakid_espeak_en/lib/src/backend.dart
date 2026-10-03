// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:ffi';
import 'dart:io';

import 'package:misakid/misaki_en.dart';

import 'native_bindings.dart';
import 'phonemizer_contract.dart';
import 'resource_identity.dart';

/// Exact platform supported by this first adapter configuration.
const String espeakEnglishSupportedPlatform = 'macos-arm64';

/// Default maximum UTF-8 input size for one fallback call.
const int defaultEspeakEnglishMaxInputBytes = 1024 * 1024;

/// Default maximum UTF-8 output size for one direct eSpeak chunk.
const int defaultEspeakEnglishMaxOutputBytes = 4 * 1024 * 1024;

const int _maximumConfigurableBytes = 64 * 1024 * 1024;
const int _maximumPathUtf8Bytes = 32768;

/// Explicit macOS-arm64 eSpeak NG provider for [EnglishEspeakFallback].
///
/// The package-owned [adapterLibraryPath] is a small Apache-2.0 owned-result
/// shim. [espeakLibraryPath] and [dataPath] identify caller-owned GPL eSpeak NG
/// resources that are validated exactly and never discovered or downloaded.
/// A public call exceeding [maximumEspeakEnglishChunksPerCall] punctuation
/// chunks or native eSpeak clauses fails with [BackendFailureException].
final class EspeakEnglishBackend implements EnglishEspeakBackend {
  EspeakEnglishBackend._({
    required EspeakEnglishNativeContext native,
    required this.info,
  }) : _native = native;

  /// Validates all explicit resources and initializes the owned-result shim.
  static Future<EspeakEnglishBackend> open({
    required String adapterLibraryPath,
    required String espeakLibraryPath,
    required String dataPath,
    int maxInputBytes = defaultEspeakEnglishMaxInputBytes,
    int maxOutputBytes = defaultEspeakEnglishMaxOutputBytes,
  }) async {
    _validateConfiguration(
      adapterLibraryPath: adapterLibraryPath,
      espeakLibraryPath: espeakLibraryPath,
      dataPath: dataPath,
      maxInputBytes: maxInputBytes,
      maxOutputBytes: maxOutputBytes,
    );
    if (!Platform.isMacOS || Abi.current() != Abi.macosArm64) {
      throw const BackendUnavailableException(
        'misakid_espeak_en 0.1.0-dev.1 supports only macOS arm64.',
      );
    }
    final adapterType = await FileSystemEntity.type(
      adapterLibraryPath,
      followLinks: false,
    );
    if (adapterType == FileSystemEntityType.notFound) {
      throw const BackendUnavailableException(
        'The configured misakid eSpeak adapter library does not exist.',
      );
    }
    if (adapterType != FileSystemEntityType.file) {
      throw const InvalidConfigurationException(
        'The misakid eSpeak adapter library must be a real file, not a link.',
      );
    }

    final String resolvedAdapter;
    final EspeakEnglishNativeLibrary library;
    try {
      resolvedAdapter = await File(adapterLibraryPath).resolveSymbolicLinks();
      library = EspeakEnglishNativeLibrary.load(resolvedAdapter);
    } on EspeakEnglishNativeLibraryException catch (error) {
      throw BackendUnavailableException(error.message, cause: error);
    } on FileSystemException catch (error) {
      throw BackendUnavailableException(
        'The configured misakid eSpeak adapter library could not be resolved.',
        cause: error,
      );
    }

    final resources = await EspeakResourceSnapshot.validate(
      libraryPath: espeakLibraryPath,
      dataPath: dataPath,
    );
    EspeakEnglishNativeContext? native;
    try {
      native = EspeakEnglishNativeContext.create(
        library: library,
        runtimeLibraryPath: resources.libraryPath,
        dataPath: resources.dataPath,
        maxInputBytes: maxInputBytes,
        maxOutputBytes: maxOutputBytes,
      );
      await resources.ensureUnchanged();
      final identities = library.identities;
      return EspeakEnglishBackend._(
        native: native,
        info: BackendInfo(
          name: 'espeak-ng',
          version: identities[1]!,
          details: <String, String>{
            'adapterVersion': identities[0]!,
            'abiVersion': espeakEnglishNativeAbiVersion.toString(),
            'platform': espeakEnglishSupportedPlatform,
            'librarySha256': identities[2]!,
            'libraryBytes': pinnedEspeakNgLibrarySizeBytes.toString(),
            'dataTreeSha256': identities[3]!,
            'dataDirectories': pinnedEspeakNgDataDirectoryCount.toString(),
            'dataFiles': pinnedEspeakNgDataFileCount.toString(),
            'dataBytes': pinnedEspeakNgDataSizeBytes.toString(),
            'contract': identities[4]!,
            'nativePatchSet': identities[5]!,
            'chunkLimit': maximumEspeakEnglishChunksPerCall.toString(),
          },
        ),
      );
    } on EspeakEnglishNativeException catch (error) {
      native?.close();
      throw BackendUnavailableException(
        'The validated eSpeak NG runtime could not initialize '
        '(native stage `${error.stage}`, code ${error.code}).',
        cause: error,
      );
    } on EspeakEnglishNativeLibraryException catch (error) {
      native?.close();
      throw BackendUnavailableException(
        'The eSpeak NG native library returned malformed initialization data.',
        cause: error,
      );
    } on Object {
      native?.close();
      rethrow;
    }
  }

  final EspeakEnglishNativeContext _native;

  @override
  final BackendInfo info;

  /// Whether [close] released the native context.
  bool get isClosed => _native.isClosed;

  @override
  String? phonemize(String text, {required EnglishDialect dialect}) {
    if (isClosed) {
      throw const BackendUnavailableException(
        'The eSpeak English backend is closed; open a new backend.',
      );
    }
    try {
      _native.validateInput(text);
      final result = phonemizeEnglishLikePinnedPhonemizer(
        text: text,
        dialect: dialect,
        phonemizeChunk: _native.phonemizeChunk,
      );
      if (result != null) _native.validateOutput(result);
      return result;
    } on EspeakEnglishNativeException catch (error) {
      throw BackendFailureException(
        'eSpeak English phonemization failed at native stage '
        '`${error.stage}` (code ${error.code}).',
        cause: error,
      );
    } on EspeakEnglishNativeLibraryException catch (error) {
      throw BackendFailureException(
        'eSpeak English returned malformed native data.',
        cause: error,
      );
    }
  }

  /// Releases the native context. Repeated calls are safe.
  void close() => _native.close();
}

void _validateConfiguration({
  required String adapterLibraryPath,
  required String espeakLibraryPath,
  required String dataPath,
  required int maxInputBytes,
  required int maxOutputBytes,
}) {
  for (final path in <String>[
    adapterLibraryPath,
    espeakLibraryPath,
    dataPath,
  ]) {
    if (!_isAbsolutePath(path)) {
      throw const InvalidConfigurationException(
        'All eSpeak adapter and resource paths must be non-empty absolute paths.',
      );
    }
    if (!_isValidPathText(path)) {
      throw const InvalidConfigurationException(
        'eSpeak paths must be valid Unicode without NUL and no longer than 32768 UTF-8 bytes.',
      );
    }
  }
  if (maxInputBytes <= 0 || maxInputBytes > _maximumConfigurableBytes) {
    throw InvalidConfigurationException(
      'maxInputBytes must be between 1 and $_maximumConfigurableBytes.',
    );
  }
  if (maxOutputBytes <= 0 || maxOutputBytes > _maximumConfigurableBytes) {
    throw InvalidConfigurationException(
      'maxOutputBytes must be between 1 and $_maximumConfigurableBytes.',
    );
  }
}

bool _isAbsolutePath(String path) => path.isNotEmpty && path.startsWith('/');

bool _isValidPathText(String path) {
  var utf8Bytes = 0;
  final units = path.codeUnits;
  for (var index = 0; index < units.length; index++) {
    final unit = units[index];
    if (unit == 0) return false;
    if (unit <= 0x7F) {
      utf8Bytes++;
    } else if (unit <= 0x7FF) {
      utf8Bytes += 2;
    } else if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (index + 1 >= units.length ||
          units[index + 1] < 0xDC00 ||
          units[index + 1] > 0xDFFF) {
        return false;
      }
      utf8Bytes += 4;
      index++;
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      return false;
    } else {
      utf8Bytes += 3;
    }
    if (utf8Bytes > _maximumPathUtf8Bytes) return false;
  }
  return true;
}
