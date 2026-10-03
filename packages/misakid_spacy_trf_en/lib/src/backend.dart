// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:misakid_adapter_support/file_system.dart';
import 'package:misakid_spacy_en/misakid_spacy_en.dart';

import 'native_bindings.dart';
import 'resource_identity.dart';
import 'tagger_head.dart';
import 'transformer/byte_bpe.dart';

/// Exact native platform supported by the first transformer adapter release.
const String spacyTransformerSupportedPlatform = 'macos-arm64';

/// Default maximum marked pieces accepted by one conversion.
const int defaultSpacyTransformerMaxPieces = 4096;

/// Largest public piece limit accepted by this synchronous adapter.
const int maximumConfigurableSpacyTransformerPieces = 16384;

/// Penn Treebank labels emitted by the exact transformer tagger head.
const List<String> spacyTransformerTagLabels = <String>[
  r'$',
  "''",
  ',',
  '-LRB-',
  '-RRB-',
  '.',
  ':',
  'ADD',
  'AFX',
  'CC',
  'CD',
  'DT',
  'EX',
  'FW',
  'HYPH',
  'IN',
  'JJ',
  'JJR',
  'JJS',
  'LS',
  'MD',
  'NFP',
  'NN',
  'NNP',
  'NNPS',
  'NNS',
  'PDT',
  'POS',
  'PRP',
  r'PRP$',
  'RB',
  'RBR',
  'RBS',
  'RP',
  'SYM',
  'TO',
  'UH',
  'VB',
  'VBD',
  'VBG',
  'VBN',
  'VBP',
  'VBZ',
  'WDT',
  'WP',
  r'WP$',
  'WRB',
  'XX',
  '``',
];

/// Exact `en_core_web_trf==3.8.0` tokenizer/tagger for macOS arm64.
///
/// Tokenization and byte-BPE run in Dart. The caller-supplied native library
/// uses Accelerate for the 12-layer RoBERTa graph and invokes neither Python
/// nor Torch. Both paths and [maxPieces] are explicit; this class performs no
/// discovery, download, subprocess invocation, or network access.
///
/// ```dart
/// final tokenizer =
///     await NativeSpacyTransformerEnglishTokenizerBackend.open(
///       modelDirectoryPath: '/absolute/path/en_core_web_trf-3.8.0',
///       nativeLibraryPath: '/absolute/path/libmisakid_spacy_trf_en.dylib',
///     );
/// try {
///   final result = EnglishG2pEngine(
///     tokenizer: tokenizer,
///     pronunciation: const PinnedEnglishLexicon(),
///   ).convert('Hello.');
///   print(result.phonemes);
/// } finally {
///   tokenizer.close();
/// }
/// ```
final class NativeSpacyTransformerEnglishTokenizerBackend
    implements EnglishTokenizerBackend {
  NativeSpacyTransformerEnglishTokenizerBackend._({
    required PureDartSpacyEnglishTokenizer tokenizer,
    required SpacyTransformerByteBpe byteBpe,
    required SpacyTransformerNativeContext native,
    required this.maxPieces,
    required this.info,
  }) : _tokenizer = tokenizer,
       _byteBpe = byteBpe,
       _native = native;

  /// Validates and opens the exact transformer resources and native library.
  static Future<NativeSpacyTransformerEnglishTokenizerBackend> open({
    required String modelDirectoryPath,
    required String nativeLibraryPath,
    int maxPieces = defaultSpacyTransformerMaxPieces,
  }) async {
    _validateConfiguration(
      nativeLibraryPath: nativeLibraryPath,
      maxPieces: maxPieces,
    );
    if (!Platform.isMacOS || Abi.current() != Abi.macosArm64) {
      throw const BackendUnavailableException(
        'misakid_spacy_trf_en 0.1.0-dev.1 supports only macOS arm64.',
      );
    }

    final libraryPath = await _canonicalNativeLibrary(nativeLibraryPath);
    final SpacyTransformerNativeLibrary library;
    try {
      library = SpacyTransformerNativeLibrary.load(libraryPath);
    } on SpacyTransformerNativeLibraryException catch (error) {
      throw BackendUnavailableException(
        'The configured English transformer native library is incompatible.',
        cause: error,
      );
    }

    final resources = await SpacyTransformerResourceSnapshot.validate(
      modelDirectoryPath,
    );
    SpacyTransformerNativeContext? native;
    try {
      final tokenizer = await PureDartSpacyEnglishTokenizer.open(
        modelDirectoryPath: resources.modelDirectoryPath,
      );
      final byteBpe = SpacyTransformerByteBpe.decodePinnedPayload(
        resources.byteBpeBytes,
      );
      final tagger = SpacyTransformerTaggerHead.decode(
        resources.taggerModelBytes,
      );
      native = SpacyTransformerNativeContext.create(
        library: library,
        transformerModelPath: resources.transformerModelPath,
        taggerWeights: tagger.copyWeights(),
        taggerBiases: tagger.copyBiases(),
      );
      await resources.ensureUnchanged();
      final identities = library.identities;
      return NativeSpacyTransformerEnglishTokenizerBackend._(
        tokenizer: tokenizer,
        byteBpe: byteBpe,
        native: native,
        maxPieces: maxPieces,
        info: BackendInfo(
          name: 'native-accelerate-spacy-en-core-web-trf',
          version: spacyTransformerModelVersion,
          details: <String, String>{
            'adapterVersion': identities[0]!,
            'abiVersion': spacyTransformerNativeAbiVersion.toString(),
            'implementation': 'dart-byte-bpe+native-accelerate',
            'platform': spacyTransformerSupportedPlatform,
            'spacyBehavior': '3.8.4',
            'regexBehavior': '2024.11.6',
            'modelSha256': spacyTransformerModelSha256,
            'taggerModelSha256': spacyTransformerTaggerModelSha256,
            'tensorManifestSha256': identities[3]!,
          },
        ),
      );
    } on SpacyTransformerNativeException catch (error) {
      native?.close();
      throw BackendUnavailableException(
        'The validated English transformer could not be initialized at '
        'native stage `${error.stage}` (code ${error.code}).',
        cause: error,
      );
    } on SpacyTransformerNativeLibraryException catch (error) {
      native?.close();
      throw BackendUnavailableException(
        'The English transformer native library returned malformed data.',
        cause: error,
      );
    } on Object {
      native?.close();
      rethrow;
    }
  }

  final PureDartSpacyEnglishTokenizer _tokenizer;
  final SpacyTransformerByteBpe _byteBpe;
  final SpacyTransformerNativeContext _native;

  /// Maximum marked BPE pieces accepted by [tokenize].
  final int maxPieces;

  @override
  final BackendInfo info;

  /// Whether [close] released this backend's native context.
  bool get isClosed => _native.isClosed;

  @override
  List<MisakiToken> tokenize(EnglishPreprocessResult input) {
    if (isClosed) {
      throw const BackendUnavailableException(
        'The English transformer backend is closed; open a new backend.',
      );
    }
    final tokenization = _tokenizer.tokenize(input);
    final sequence = _byteBpe.encodeTokenization(
      tokenization,
      maxPieces: maxPieces,
    );

    final tags = List<String>.filled(
      tokenization.tokens.length,
      spacyTransformerTagLabels[23],
      growable: false,
    );
    if (sequence.tokenPieceLengths.isNotEmpty) {
      final Uint16List indices;
      try {
        indices = _native.infer(
          pieceIds: Uint32List.fromList(sequence.pieceIds),
          tokenPieceLengths: Uint32List.fromList(sequence.tokenPieceLengths),
        );
      } on SpacyTransformerNativeException catch (error) {
        throw BackendFailureException(
          'English transformer inference failed at native stage '
          '`${error.stage}` (code ${error.code}).',
          cause: error,
        );
      } on SpacyTransformerNativeLibraryException catch (error) {
        throw BackendFailureException(
          'The English transformer native library returned malformed output.',
          cause: error,
        );
      }
      if (indices.length != sequence.sourceTokenIndices.length) {
        throw const BackendFailureException(
          'English transformer inference returned an invalid tag alignment.',
        );
      }
      for (var index = 0; index < indices.length; index++) {
        tags[sequence.sourceTokenIndices[index]] =
            spacyTransformerTagLabels[indices[index]];
      }
    }
    return _tokenizer.assembleTagged(
      input: input,
      tokenization: tokenization,
      tags: tags,
    );
  }

  /// Releases the native context. Calling this more than once is safe.
  void close() => _native.close();
}

void _validateConfiguration({
  required String nativeLibraryPath,
  required int maxPieces,
}) {
  if (!isAbsoluteFilePath(nativeLibraryPath) ||
      !isValidPathText(nativeLibraryPath)) {
    throw const InvalidConfigurationException(
      'The transformer native library must be a valid non-empty absolute path '
      'without NUL and no longer than 32768 UTF-8 bytes.',
    );
  }
  if (maxPieces < 2 || maxPieces > maximumConfigurableSpacyTransformerPieces) {
    throw InvalidConfigurationException(
      'maxPieces must be between 2 and '
      '$maximumConfigurableSpacyTransformerPieces.',
    );
  }
}

Future<String> _canonicalNativeLibrary(String path) async {
  try {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw const BackendUnavailableException(
        'The configured English transformer native library does not exist.',
      );
    }
    if (type != FileSystemEntityType.file) {
      throw const InvalidConfigurationException(
        'The English transformer native library must be a real file, not a link.',
      );
    }
    final resolved = await File(path).resolveSymbolicLinks();
    if (resolved != path) {
      throw const InvalidConfigurationException(
        'The English transformer native library path must be canonical.',
      );
    }
    return resolved;
  } on MisakiException {
    rethrow;
  } on FileSystemException catch (error) {
    throw BackendUnavailableException(
      'The configured English transformer native library could not be inspected.',
      cause: error,
    );
  } on ArgumentError catch (error) {
    throw InvalidConfigurationException(
      'The configured English transformer native library path is invalid.',
      cause: error,
    );
  }
}
