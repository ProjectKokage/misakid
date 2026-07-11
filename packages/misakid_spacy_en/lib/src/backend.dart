// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:misakid/misaki_en.dart';

import 'alignment.dart';
import 'model/model.dart';
import 'resource_identity.dart';
import 'resource_loader_stub.dart'
    if (dart.library.io) 'resource_loader_io.dart'
    as resource_loader;
import 'tokenizer/config.dart';
import 'tokenizer/token.dart';
import 'tokenizer/tokenizer.dart';

/// Pinned spaCy `Language.max_length` in Unicode scalars.
const int maximumSpacyEnglishInputScalars = 1000000;

/// Maximum tokens accepted by one pure-Dart tagger inference call.
const int maximumSpacyEnglishTokens = maximumSpacyEnglishModelTokens;

/// One exact spaCy tokenizer record exposed to compatible tagger adapters.
final class SpacyEnglishRawToken {
  const SpacyEnglishRawToken._({
    required this.text,
    required this.whitespace,
    required this.isSpace,
    required this.startOffsetUtf16,
    required this.endOffsetUtf16,
  });

  /// Exact source token text.
  final String text;

  /// Exact `Token.whitespace_`, either empty or one ASCII space.
  final String whitespace;

  /// Whether CPython 3.12 considers every scalar in [text] whitespace.
  final bool isSpace;

  /// Inclusive UTF-16 offset in the preprocessed source.
  final int startOffsetUtf16;

  /// Exclusive UTF-16 offset in the preprocessed source.
  final int endOffsetUtf16;
}

/// Immutable output from [PureDartSpacyEnglishTokenizer.tokenize].
///
/// This value is also an opaque capability: tagged assembly accepts it only
/// with the exact tokenizer and [EnglishPreprocessResult] that created it.
final class SpacyEnglishTokenization {
  SpacyEnglishTokenization._({
    required Object owner,
    required EnglishPreprocessResult input,
    required List<SpacyTokenizerToken> rawTokens,
  }) : _owner = owner,
       _input = input,
       _rawTokens = List<SpacyTokenizerToken>.unmodifiable(rawTokens),
       tokens = List<SpacyEnglishRawToken>.unmodifiable(
         rawTokens.map(
           (token) => SpacyEnglishRawToken._(
             text: token.text,
             whitespace: token.whitespace,
             isSpace: token.isSpace != 0,
             startOffsetUtf16: token.startOffsetUtf16,
             endOffsetUtf16: token.endOffsetUtf16,
           ),
         ),
       );

  /// Exact ordered public tokenizer records.
  final List<SpacyEnglishRawToken> tokens;

  final Object _owner;
  final EnglishPreprocessResult _input;
  final List<SpacyTokenizerToken> _rawTokens;
}

/// Pure-Dart tokenizer-only boundary shared by the pinned English models.
///
/// The small and transformer model packages contain byte-identical tokenizer
/// resources. [open] validates only those two files and never loads a tagger,
/// invokes Python, calls native code, discovers resources, or uses a network.
final class PureDartSpacyEnglishTokenizer {
  PureDartSpacyEnglishTokenizer._(this._tokenizer);

  /// Opens the exact tokenizer below an explicit small or transformer root.
  static Future<PureDartSpacyEnglishTokenizer> open({
    required String modelDirectoryPath,
  }) async {
    final loaded = await resource_loader.loadSpacyEnglishTokenizerResources(
      modelDirectoryPath,
    );
    final result = _fromResources(loaded.resources);
    await loaded.ensureUnchanged();
    return result;
  }

  /// Creates a tokenizer from exact caller-supplied serialized resources.
  ///
  /// Both inputs are defensively copied before their pinned sizes, SHA-256
  /// identities, and schemas are validated. This path performs no file,
  /// platform, process, or network access.
  factory PureDartSpacyEnglishTokenizer.fromResources({
    required Uint8List tokenizerBytes,
    required Uint8List vocabLookupsBytes,
  }) => _fromResources(
    SpacyEnglishTokenizerResources(
      tokenizerBytes: tokenizerBytes,
      vocabLookupsBytes: vocabLookupsBytes,
    ),
  );

  static PureDartSpacyEnglishTokenizer _fromResources(
    SpacyEnglishTokenizerResources resources,
  ) {
    try {
      validateSpacyEnglishTokenizerResources(resources);
      return PureDartSpacyEnglishTokenizer._(
        SpacyTokenizer(
          SpacyTokenizerConfig.decode(
            tokenizerBytes: resources.tokenizerBytes,
            vocabLookupsBytes: resources.vocabLookupsBytes,
          ),
        ),
      );
    } on MisakiException {
      rethrow;
    } on FormatException catch (error) {
      throw MalformedDataException(
        'The pinned spaCy English tokenizer resources are malformed.',
        cause: error,
      );
    } on ArgumentError catch (error) {
      throw MalformedDataException(
        'The pinned spaCy English tokenizer resources are incompatible.',
        cause: error,
      );
    } on StateError catch (error) {
      throw MalformedDataException(
        'The pinned spaCy English generated tokenizer data are malformed.',
        cause: error,
      );
    }
  }

  final SpacyTokenizer _tokenizer;
  final Object _owner = Object();

  /// Tokenizes one preprocessed input without assigning POS tags.
  SpacyEnglishTokenization tokenize(EnglishPreprocessResult input) {
    if (_pythonScalarLength(input.text) > maximumSpacyEnglishInputScalars) {
      throw const BackendFailureException(
        'English input exceeds spaCy\'s pinned 1,000,000-scalar limit.',
      );
    }
    final rawTokens = _tokenizer.tokenize(input.text);
    return SpacyEnglishTokenization._(
      owner: _owner,
      input: input,
      rawTokens: rawTokens,
    );
  }

  /// Combines exact tokenizer records with one POS tag per token.
  ///
  /// Every tag must belong to the label inventory shared by the pinned small
  /// and transformer English models.
  ///
  /// Inline controls are applied only after token/tag lengths and source
  /// ownership are validated, preserving the pinned alignment behavior.
  List<MisakiToken> assembleTagged({
    required EnglishPreprocessResult input,
    required SpacyEnglishTokenization tokenization,
    required List<String> tags,
  }) {
    if (!identical(tokenization._owner, _owner) ||
        !identical(tokenization._input, input)) {
      throw const InvalidConfigurationException(
        'The spaCy tokenization must come from this tokenizer and input.',
      );
    }
    if (tags.length != tokenization._rawTokens.length) {
      throw InvalidConfigurationException(
        'The spaCy tagger returned ${tags.length} tags for '
        '${tokenization._rawTokens.length} tokenizer records.',
      );
    }
    for (final tag in tags) {
      if (!_spacyEnglishTagLabels.contains(tag)) {
        throw const InvalidConfigurationException(
          'Each spaCy POS tag must belong to the pinned English model inventory.',
        );
      }
    }

    var tokens = <MisakiToken>[
      for (var index = 0; index < tokenization._rawTokens.length; index++)
        MisakiToken(
          text: tokenization._rawTokens[index].text,
          tag: tags[index],
          whitespace: tokenization._rawTokens[index].whitespace,
          metadata: const EnglishTokenMetadata(isHead: true),
        ),
    ];
    if (input.controls.isNotEmpty) {
      tokens = _applyInlineControls(input, tokenization._rawTokens, tokens);
    }
    return List<MisakiToken>.unmodifiable(tokens);
  }
}

/// Pure-Dart tokenizer and tagger for the exact small English model.
///
/// [open] accepts only the reviewed `en_core_web_sm==3.8.0` tokenizer,
/// lookup, tok2vec, and tagger files below an explicit model directory. It
/// performs no discovery, download, Python invocation, or native call.
///
/// ```dart
/// final tokenizer = await PureDartSpacyEnglishTokenizerBackend.open(
///   modelDirectoryPath: '/absolute/path/en_core_web_sm-3.8.0',
/// );
/// final engine = EnglishG2pEngine(
///   tokenizer: tokenizer,
///   pronunciation: const PinnedEnglishLexicon(),
/// );
/// final result = engine.convert('Hello world.');
/// ```
final class PureDartSpacyEnglishTokenizerBackend
    implements EnglishTokenizerBackend {
  PureDartSpacyEnglishTokenizerBackend._({
    required PureDartSpacyEnglishTokenizer tokenizer,
    required SpacyEnglishTaggerModel tagger,
    required this.info,
  }) : _tokenizer = tokenizer,
       _tagger = tagger;

  /// Validates and loads the exact `en_core_web_sm==3.8.0` resource subset.
  static Future<PureDartSpacyEnglishTokenizerBackend> open({
    required String modelDirectoryPath,
  }) async {
    final loaded = await resource_loader.loadSpacyEnglishModelResources(
      modelDirectoryPath,
    );
    final result = _fromResources(loaded.resources);
    await loaded.ensureUnchanged();
    return result;
  }

  /// Creates the exact small-model backend from serialized resource bytes.
  ///
  /// The four inputs are defensively copied before their pinned sizes, SHA-256
  /// identities, tokenizer schema, and model graph schema are validated. This
  /// path performs no file, platform, process, or network access.
  factory PureDartSpacyEnglishTokenizerBackend.fromResources({
    required Uint8List tokenizerBytes,
    required Uint8List vocabLookupsBytes,
    required Uint8List tok2vecModelBytes,
    required Uint8List taggerModelBytes,
  }) => _fromResources(
    SpacyEnglishModelResources(
      tokenizerBytes: tokenizerBytes,
      vocabLookupsBytes: vocabLookupsBytes,
      tok2vecModelBytes: tok2vecModelBytes,
      taggerModelBytes: taggerModelBytes,
    ),
  );

  static PureDartSpacyEnglishTokenizerBackend _fromResources(
    SpacyEnglishModelResources resources,
  ) {
    try {
      validateSpacyEnglishModelResources(resources);
      final config = SpacyTokenizerConfig.decode(
        tokenizerBytes: resources.tokenizer.tokenizerBytes,
        vocabLookupsBytes: resources.tokenizer.vocabLookupsBytes,
      );
      final tokenizer = PureDartSpacyEnglishTokenizer._(SpacyTokenizer(config));
      final parameters = SpacyEnglishSerializedModelLoader.decode(
        tok2vecModel: resources.tok2vecModelBytes,
        taggerModel: resources.taggerModelBytes,
      );
      return PureDartSpacyEnglishTokenizerBackend._(
        tokenizer: tokenizer,
        tagger: SpacyEnglishTaggerModel(parameters),
        info: BackendInfo(
          name: 'pure-dart-spacy-en-core-web-sm',
          version: '3.8.0',
          details: const <String, String>{
            'implementation': 'pure-dart',
            'spacyBehavior': '3.8.4',
            'thincBehavior': '8.3.4',
            'tokenizerSha256': spacyEnglishTokenizerSha256,
            'vocabLookupsSha256': spacyEnglishVocabLookupsSha256,
            'tok2vecModelSha256': spacyEnglishTok2vecModelSha256,
            'taggerModelSha256': spacyEnglishTaggerModelSha256,
          },
        ),
      );
    } on MisakiException {
      rethrow;
    } on FormatException catch (error) {
      throw MalformedDataException(
        'The pinned en_core_web_sm tokenizer resources are malformed.',
        cause: error,
      );
    } on ArgumentError catch (error) {
      throw MalformedDataException(
        'The pinned en_core_web_sm model parameters are incompatible.',
        cause: error,
      );
    } on StateError catch (error) {
      throw MalformedDataException(
        'The pinned en_core_web_sm generated data are malformed.',
        cause: error,
      );
    }
  }

  final PureDartSpacyEnglishTokenizer _tokenizer;
  final SpacyEnglishTaggerModel _tagger;

  @override
  final BackendInfo info;

  @override
  List<MisakiToken> tokenize(EnglishPreprocessResult input) {
    final tokenization = _tokenizer.tokenize(input);
    final rawTokens = tokenization._rawTokens;
    if (rawTokens.length > maximumSpacyEnglishTokens) {
      throw BackendFailureException(
        'English tokenization produced ${rawTokens.length} tokens; the '
        'pure-Dart tagger limit is $maximumSpacyEnglishTokens.',
      );
    }
    final inference = _tagger.infer(<SpacyTokenFeatures>[
      for (final token in rawTokens)
        SpacyTokenFeatures(
          norm: token.normId,
          prefix: token.prefixId,
          suffix: token.suffixId,
          shape: token.shapeId,
          spacy: token.spacy,
          isSpace: token.isSpace,
        ),
    ]);
    return _tokenizer.assembleTagged(
      input: input,
      tokenization: tokenization,
      tags: inference.tags,
    );
  }
}

final Set<String> _spacyEnglishTagLabels = Set<String>.unmodifiable(
  SpacyEnglishTaggerModel.labels,
);

List<MisakiToken> _applyInlineControls(
  EnglishPreprocessResult input,
  List<SpacyTokenizerToken> rawTokens,
  List<MisakiToken> tokens,
) {
  final List<int> alignment;
  try {
    alignment = flattenedSpacyY2xAlignment(input.sourceWords, <String>[
      for (final token in rawTokens) token.text,
    ]);
  } on FormatException catch (error) {
    throw BackendFailureException(
      'The pure-Dart spaCy backend could not align English inline controls.',
      cause: error,
    );
  }
  final result = List<MisakiToken>.of(tokens);
  for (final entry in input.controls.entries) {
    var occurrence = 0;
    for (
      var flattenedIndex = 0;
      flattenedIndex < alignment.length;
      flattenedIndex++
    ) {
      if (alignment[flattenedIndex] != entry.key) {
        continue;
      }
      final controlOccurrence = occurrence++;
      if (flattenedIndex >= result.length) {
        continue;
      }
      final token = result[flattenedIndex];
      final metadata = token.metadata! as EnglishTokenMetadata;
      result[flattenedIndex] = switch (entry.value) {
        EnglishStressControl(:final stress) => _copyToken(
          token,
          metadata: _copyMetadata(metadata, stress: stress),
        ),
        EnglishPronunciationControl(:final phonemes) => _copyToken(
          token,
          phonemes: controlOccurrence == 0 ? phonemes : '',
          metadata: _copyMetadata(
            metadata,
            isHead: controlOccurrence == 0,
            rating: 5,
          ),
        ),
        EnglishNumberFlagsControl(:final flags) => _copyToken(
          token,
          metadata: _copyMetadata(metadata, numberFlags: flags),
        ),
      };
    }
  }
  return result;
}

MisakiToken _copyToken(
  MisakiToken source, {
  String? phonemes,
  required EnglishTokenMetadata metadata,
}) => MisakiToken(
  text: source.text,
  tag: source.tag,
  whitespace: source.whitespace,
  phonemes: phonemes ?? source.phonemes,
  startTimeSeconds: source.startTimeSeconds,
  endTimeSeconds: source.endTimeSeconds,
  metadata: metadata,
);

EnglishTokenMetadata _copyMetadata(
  EnglishTokenMetadata source, {
  bool? isHead,
  num? stress,
  String? numberFlags,
  int? rating,
}) => EnglishTokenMetadata(
  isHead: isHead ?? source.isHead,
  alias: source.alias,
  stress: stress ?? source.stress,
  currency: source.currency,
  numberFlags: numberFlags ?? source.numberFlags,
  precededBySpace: source.precededBySpace,
  rating: rating ?? source.rating,
);

int _pythonScalarLength(String text) {
  var length = 0;
  final units = text.codeUnits;
  for (var index = 0; index < units.length; index++) {
    final first = units[index];
    if (first >= 0xd800 &&
        first <= 0xdbff &&
        index + 1 < units.length &&
        units[index + 1] >= 0xdc00 &&
        units[index + 1] <= 0xdfff) {
      index++;
    }
    length++;
  }
  return length;
}
