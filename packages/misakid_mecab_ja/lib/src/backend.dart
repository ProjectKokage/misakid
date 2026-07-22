// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:misakid/misaki_ja.dart';

import 'dictionary_identity.dart';
import 'grouping.dart';
import 'kata_to_hiragana.dart';
import 'native_bindings.dart';
import 'word_membership.dart';

/// Platform supported by the legacy explicit-library [MecabJapaneseCutletBackend.open] API.
const String mecabJapaneseSupportedPlatform = 'macos-arm64';

/// Platforms targeted by the package's reproducible native-assets build hook.
///
/// This describes build availability, not the narrower set of runtime tuples
/// that have completed provisioned parity testing.
const Set<String> mecabJapaneseBundledBuildPlatforms = <String>{
  'android',
  'ios',
  'macos',
};

/// Default maximum UTF-8 input size accepted by one morphology call.
const int defaultMecabJapaneseMaxInputBytes = 1024 * 1024;

const int _maximumConfigurableInputBytes = 64 * 1024 * 1024;
const int _maximumPathUtf8Bytes = 32768;

/// Dictionary validation and compatibility contract for the native backend.
enum MecabJapaneseDictionaryProfile {
  /// Accept a caller-selected UTF-8 UniDic with a supported feature layout.
  ///
  /// The layout check does not identify the dictionary corpus: CWJ, CSJ, and
  /// custom dictionaries can share it. Output can vary between dictionaries
  /// and does not carry an exact Misaki fixture-parity claim.
  compatible,

  /// Require the exact modified unidic-py CWJ tree used by the fixtures.
  ///
  /// The complete tree hash, not its release marker, establishes identity.
  pinnedUnidicPyCwjParity,
}

/// Detected fugashi-compatible UniDic feature layout.
///
/// This describes where the projection reads `pron` and `kana`; it does not
/// identify the dictionary corpus, release, or exact resource bytes.
enum MecabJapaneseUnidicFeatureLayout {
  /// 26-field layout with `kana` at field 17.
  fields26(26),

  /// 29-field layout with `kana` at field 20.
  fields29(29);

  const MecabJapaneseUnidicFeatureLayout(this.fieldCount);

  /// Number of comma-separated fields in one known-word record.
  final int fieldCount;

  static MecabJapaneseUnidicFeatureLayout _fromFieldCount(
    int fieldCount,
  ) => switch (fieldCount) {
    26 => fields26,
    29 => fields29,
    _ => throw StateError(
      'Native initialization returned an unsupported UniDic feature layout.',
    ),
  };
}

/// One owned copy of the raw MeCab projection consumed by Cutlet.
final class MecabJapaneseRawWord {
  /// Creates one immutable raw morphology record.
  const MecabJapaneseRawWord({
    required this.surface,
    required this.pronunciation,
    required this.kana,
    required this.charType,
    required this.isUnknown,
  });

  /// Exact surface bytes decoded as UTF-8.
  final String surface;

  /// UniDic `pron`, or `null` when the feature is unavailable.
  ///
  /// A literal `*` is data and is not converted to `null`.
  final String? pronunciation;

  /// UniDic `kana`, or `null` when the schema does not provide it.
  ///
  /// A literal `*` is data and is not converted to `null`.
  final String? kana;

  /// Raw `mecab_node_t.char_type` value.
  final int charType;

  /// Whether `mecab_node_t.stat == MECAB_UNK_NODE`.
  final bool isUnknown;
}

/// Explicit native MeCab/UniDic backend for [JapaneseCutletEngine].
///
/// [analyzeRaw] exposes the exact native projection. [analyze] additionally
/// applies jaconv 0.4.0 Katakana conversion and the pinned Cutlet longest-match
/// grouping algorithm through the injected [wordMembership]. Open methods use
/// [MecabJapaneseDictionaryProfile.compatible] unless the caller explicitly
/// selects the strict fixture-parity profile.
///
/// Opening throws [InvalidConfigurationException] for invalid caller options,
/// [BackendUnavailableException] when the selected native/resource tuple
/// cannot initialize, and [MalformedDataException] for malformed or
/// identity-mismatched data. Calls after successful initialization throw
/// [BackendFailureException] when native analysis fails.
final class MecabJapaneseCutletBackend
    implements JapaneseCutletMorphologyBackend {
  MecabJapaneseCutletBackend._({
    required MecabJapaneseNativeAnalyzer analyzer,
    required this.wordMembership,
    required this.dictionaryProfile,
    required this.dictionaryFeatureLayout,
    required this.info,
  }) : _analyzer = analyzer;

  /// Validates and opens explicit macOS arm64 native and UniDic resources.
  static Future<MecabJapaneseCutletBackend> open({
    required String libraryPath,
    required String dictionaryPath,
    required String wordListPath,
    MecabJapaneseDictionaryProfile dictionaryProfile =
        MecabJapaneseDictionaryProfile.compatible,
    int maxInputBytes = defaultMecabJapaneseMaxInputBytes,
  }) async {
    _validateConfiguration(
      libraryPath: libraryPath,
      dictionaryPath: dictionaryPath,
      maxInputBytes: maxInputBytes,
    );
    _validateSupportedPlatform();
    final wordMembership = await PinnedMisakiCutletWordMembership.open(
      wordListPath,
    );
    return openWithMembership(
      libraryPath: libraryPath,
      dictionaryPath: dictionaryPath,
      wordMembership: wordMembership,
      dictionaryProfile: dictionaryProfile,
      maxInputBytes: maxInputBytes,
    );
  }

  /// Opens the package-built native asset with mobile-friendly word-list bytes.
  ///
  /// [dictionaryPath] must point to an already materialized UniDic directory.
  /// Mobile applications commonly copy that resource from their app bundle or
  /// model store into application support storage.
  static Future<MecabJapaneseCutletBackend> openBundled({
    required String dictionaryPath,
    required Uint8List wordListBytes,
    MecabJapaneseDictionaryProfile dictionaryProfile =
        MecabJapaneseDictionaryProfile.compatible,
    int maxInputBytes = defaultMecabJapaneseMaxInputBytes,
  }) async {
    _validateBundledConfiguration(
      dictionaryPath: dictionaryPath,
      maxInputBytes: maxInputBytes,
    );
    _validateBundledSupportedPlatform();
    final wordMembership = PinnedMisakiCutletWordMembership.fromBytes(
      wordListBytes,
    );
    return openBundledWithMembership(
      dictionaryPath: dictionaryPath,
      wordMembership: wordMembership,
      dictionaryProfile: dictionaryProfile,
      maxInputBytes: maxInputBytes,
    );
  }

  /// Opens the package-built native asset with an injected grouping resource.
  static Future<MecabJapaneseCutletBackend> openBundledWithMembership({
    required String dictionaryPath,
    required JapaneseCutletWordMembership wordMembership,
    MecabJapaneseDictionaryProfile dictionaryProfile =
        MecabJapaneseDictionaryProfile.compatible,
    int maxInputBytes = defaultMecabJapaneseMaxInputBytes,
  }) async {
    _validateBundledConfiguration(
      dictionaryPath: dictionaryPath,
      maxInputBytes: maxInputBytes,
    );
    _validateBundledSupportedPlatform();

    final MecabJapaneseNativeLibrary library;
    try {
      library = MecabJapaneseNativeLibrary.loadBundled();
    } on MecabJapaneseNativeLibraryException catch (error) {
      throw BackendUnavailableException(error.message, cause: error);
    }
    return _initialize(
      library: library,
      dictionaryPath: dictionaryPath,
      wordMembership: wordMembership,
      dictionaryProfile: dictionaryProfile,
      maxInputBytes: maxInputBytes,
      platform: _bundledPlatformLabel(),
    );
  }

  /// Opens with an explicitly supplied alternative licensed membership.
  static Future<MecabJapaneseCutletBackend> openWithMembership({
    required String libraryPath,
    required String dictionaryPath,
    required JapaneseCutletWordMembership wordMembership,
    MecabJapaneseDictionaryProfile dictionaryProfile =
        MecabJapaneseDictionaryProfile.compatible,
    int maxInputBytes = defaultMecabJapaneseMaxInputBytes,
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
        'The configured Japanese MeCab native library could not be inspected.',
        cause: error,
      );
    } on ArgumentError catch (error) {
      throw InvalidConfigurationException(
        'The configured Japanese MeCab native library path is invalid.',
        cause: error,
      );
    }
    if (libraryType == FileSystemEntityType.notFound) {
      throw const BackendUnavailableException(
        'The configured Japanese MeCab native library does not exist.',
      );
    }
    if (libraryType != FileSystemEntityType.file) {
      throw const InvalidConfigurationException(
        'The configured Japanese MeCab native library must be a real file, not a link.',
      );
    }

    final String resolvedLibraryPath;
    final MecabJapaneseNativeLibrary library;
    try {
      resolvedLibraryPath = await File(libraryPath).resolveSymbolicLinks();
      library = MecabJapaneseNativeLibrary.load(resolvedLibraryPath);
    } on MecabJapaneseNativeLibraryException catch (error) {
      throw BackendUnavailableException(error.message, cause: error);
    } on FileSystemException catch (error) {
      throw BackendUnavailableException(
        'The configured Japanese MeCab native library could not be resolved.',
        cause: error,
      );
    }

    return _initialize(
      library: library,
      dictionaryPath: dictionaryPath,
      wordMembership: wordMembership,
      dictionaryProfile: dictionaryProfile,
      maxInputBytes: maxInputBytes,
      platform: mecabJapaneseSupportedPlatform,
    );
  }

  static Future<MecabJapaneseCutletBackend> _initialize({
    required MecabJapaneseNativeLibrary library,
    required String dictionaryPath,
    required JapaneseCutletWordMembership wordMembership,
    required MecabJapaneseDictionaryProfile dictionaryProfile,
    required int maxInputBytes,
    required String platform,
  }) async {
    final Future<UnidicDictionarySnapshot> dictionaryValidation =
        switch (dictionaryProfile) {
          MecabJapaneseDictionaryProfile.compatible =>
            CompatibleUnidicSnapshot.validate(dictionaryPath),
          MecabJapaneseDictionaryProfile.pinnedUnidicPyCwjParity =>
            PinnedUnidicPyCwjSnapshot.validate(dictionaryPath),
        };
    final dictionary = await dictionaryValidation;
    MecabJapaneseNativeAnalyzer? analyzer;
    try {
      analyzer = MecabJapaneseNativeAnalyzer.create(
        library: library,
        dictionaryPath: dictionary.resolvedPath,
        maxInputBytes: maxInputBytes,
      );
      await dictionary.ensureUnchanged();
      final identities = library.identities;
      final isParityProfile =
          dictionaryProfile ==
          MecabJapaneseDictionaryProfile.pinnedUnidicPyCwjParity;
      final dictionaryFeatureLayout =
          MecabJapaneseUnidicFeatureLayout._fromFieldCount(
            analyzer.featureFieldCount,
          );
      final details = <String, String>{
        'adapterVersion': identities[0]!,
        'abiVersion': mecabJapaneseNativeAbiVersion.toString(),
        'platform': platform,
        'mecabVersion': identities[1]!,
        'nativeSourceTreeSha256': identities[2]!,
        'nativeSourceSdistSha256': identities[3]!,
        'nativeBuildProfile': identities[4]!,
        'dictionary': 'unidic',
        'dictionaryProfile': isParityProfile
            ? 'pinned-unidic-py-cwj-parity'
            : 'compatible',
        'dictionaryCorpus': isParityProfile
            ? pinnedUnidicPyCwjCorpus
            : 'unknown',
        'dictionaryDistribution': isParityProfile
            ? pinnedUnidicPyCwjDistribution
            : 'unknown',
        'dictionaryIdentity': isParityProfile
            ? 'verified-tree-sha256'
            : 'unverified',
        'dictionaryFeatureFieldCount': dictionaryFeatureLayout.fieldCount
            .toString(),
        'dictionaryFeatureLayoutSupport': identities[5]!,
        'referenceFugashiVersion': '1.4.0',
        'jaconvVersion': '0.4.0',
        'wordMembership': wordMembership.info.name,
        'wordMembershipVersion': wordMembership.info.version,
      };
      if (isParityProfile) {
        details['dictionaryReleaseMarker'] = pinnedUnidicPyCwjReleaseMarker;
        details['dictionaryTreeSha256'] = pinnedUnidicPyCwjTreeSha256;
      }
      return MecabJapaneseCutletBackend._(
        analyzer: analyzer,
        wordMembership: wordMembership,
        dictionaryProfile: dictionaryProfile,
        dictionaryFeatureLayout: dictionaryFeatureLayout,
        info: BackendInfo(
          name: 'mecab-unidic-cutlet',
          version: identities[1]!,
          details: details,
        ),
      );
    } on MecabJapaneseNativeException catch (error) {
      analyzer?.close();
      throw BackendUnavailableException(
        'The validated Japanese MeCab analyzer could not be initialized '
        '(native stage `${error.stage}`, code ${error.code}).',
        cause: error,
      );
    } on MecabJapaneseNativeLibraryException catch (error) {
      analyzer?.close();
      throw BackendUnavailableException(
        'The Japanese MeCab native library returned malformed initialization data.',
        cause: error,
      );
    } on Object {
      analyzer?.close();
      rethrow;
    }
  }

  final MecabJapaneseNativeAnalyzer _analyzer;

  /// Exact grouping membership supplied by the caller.
  final JapaneseCutletWordMembership wordMembership;

  /// Dictionary validation contract selected during initialization.
  final MecabJapaneseDictionaryProfile dictionaryProfile;

  /// Feature layout detected from the live dictionary during initialization.
  ///
  /// This is a parsing capability, not a CWJ/CSJ or release identity.
  final MecabJapaneseUnidicFeatureLayout dictionaryFeatureLayout;

  @override
  final BackendInfo info;

  /// Whether [close] has released the native analyzer context.
  bool get isClosed => _analyzer.isClosed;

  /// Returns owned raw MeCab records before reading selection or grouping.
  List<MecabJapaneseRawWord> analyzeRaw(String normalizedText) {
    if (isClosed) {
      throw const BackendUnavailableException(
        'The Japanese MeCab analyzer is closed; open a new backend.',
      );
    }
    try {
      return List<MecabJapaneseRawWord>.unmodifiable(
        _analyzer
            .analyzeRaw(normalizedText)
            .map(
              (word) => MecabJapaneseRawWord(
                surface: word.surface,
                pronunciation: word.pronunciation,
                kana: word.kana,
                charType: word.charType,
                isUnknown: word.isUnknown,
              ),
            ),
      );
    } on MecabJapaneseNativeException catch (error) {
      throw BackendFailureException(
        'Japanese MeCab analysis failed at native stage `${error.stage}` '
        '(code ${error.code}).',
        cause: error,
      );
    } on MecabJapaneseNativeLibraryException catch (error) {
      throw BackendFailureException(
        'Japanese MeCab returned malformed native data.',
        cause: error,
      );
    }
  }

  @override
  List<JapaneseCutletMorphologyWord> analyze(String normalizedText) {
    final rawWords = analyzeRaw(normalizedText);
    final words = <JapaneseCutletMorphologyWord>[
      for (final raw in rawWords)
        JapaneseCutletMorphologyWord(
          surface: raw.surface,
          hiragana: cutletKataToHiragana(_selectReading(raw)),
          charType: raw.charType,
          isUnknown: raw.isUnknown,
        ),
    ];
    try {
      return applyJapaneseCutletLongestGrouping(words, wordMembership);
    } on MisakiException {
      rethrow;
    } on Exception catch (error) {
      throw BackendFailureException(
        'Japanese Cutlet word membership ${wordMembership.info} failed.',
        cause: error,
      );
    }
  }

  /// Releases the native context. Calling this repeatedly is safe.
  void close() => _analyzer.close();
}

String _selectReading(MecabJapaneseRawWord word) {
  final pronunciation = word.pronunciation;
  if (pronunciation != null && pronunciation.isNotEmpty) return pronunciation;
  final kana = word.kana;
  if (kana != null && kana.isNotEmpty) return kana;
  return word.surface;
}

void _validateConfiguration({
  required String libraryPath,
  required String dictionaryPath,
  required int maxInputBytes,
}) {
  if (!_isAbsolutePath(libraryPath) || !_isAbsolutePath(dictionaryPath)) {
    throw const InvalidConfigurationException(
      'Japanese MeCab library and dictionary paths must be non-empty absolute paths.',
    );
  }
  if (!_isValidPathText(libraryPath) || !_isValidPathText(dictionaryPath)) {
    throw const InvalidConfigurationException(
      'Japanese MeCab paths must be valid Unicode without NUL and no longer than 32768 UTF-8 bytes.',
    );
  }
  _validateInputLimit(maxInputBytes);
}

void _validateBundledConfiguration({
  required String dictionaryPath,
  required int maxInputBytes,
}) {
  if (!_isAbsolutePath(dictionaryPath)) {
    throw const InvalidConfigurationException(
      'The Japanese MeCab dictionary path must be a non-empty absolute path.',
    );
  }
  if (!_isValidPathText(dictionaryPath)) {
    throw const InvalidConfigurationException(
      'The Japanese MeCab dictionary path must be valid Unicode without NUL '
      'and no longer than 32768 UTF-8 bytes.',
    );
  }
  _validateInputLimit(maxInputBytes);
}

void _validateInputLimit(int maxInputBytes) {
  if (maxInputBytes <= 0 || maxInputBytes > _maximumConfigurableInputBytes) {
    throw InvalidConfigurationException(
      'maxInputBytes must be between 1 and $_maximumConfigurableInputBytes.',
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
      (Platform.isMacOS && (abi == Abi.macosArm64 || abi == Abi.macosX64));
  if (!supported) {
    throw BackendUnavailableException(
      'The bundled Japanese MeCab native asset does not support ${abi.toString()}.',
    );
  }
}

String _bundledPlatformLabel() => 'native-assets-${Abi.current()}';

void _validateSupportedPlatform() {
  if (!Platform.isMacOS || Abi.current() != Abi.macosArm64) {
    throw const BackendUnavailableException(
      'The explicit-library Japanese MeCab adapter supports only macOS arm64.',
    );
  }
}

bool _isAbsolutePath(String path) {
  if (path.isEmpty) return false;
  if (!Platform.isWindows) return path.startsWith('/');
  return RegExp(r'^(?:[A-Za-z]:[\\/]|\\\\)').hasMatch(path);
}

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
