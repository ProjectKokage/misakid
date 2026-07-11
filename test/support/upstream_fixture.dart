import 'dart:convert';
import 'dart:io';

import 'package:misakid/misaki.dart';

final class UpstreamFixtureFormatException implements Exception {
  const UpstreamFixtureFormatException(this.message);

  final String message;

  @override
  String toString() => 'UpstreamFixtureFormatException: $message';
}

final class UpstreamFixture {
  UpstreamFixture._({
    required this.caseId,
    required this.language,
    required this.mode,
    required this.options,
    required this.backendVersions,
    required this.backendInput,
    required this.input,
    required this.phonemes,
    required this.tokens,
    required this.errorCategory,
    required this.seed,
  });

  factory UpstreamFixture.parse(String line, {required String location}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException catch (error) {
      throw UpstreamFixtureFormatException('$location: invalid JSON: $error');
    }
    if (decoded is! Map<String, Object?>) {
      throw UpstreamFixtureFormatException(
        '$location: fixture line must be a JSON object',
      );
    }
    final map = decoded;
    _expectEqual(map, 'schemaVersion', 1, location);
    _expectEqual(map, 'upstreamRepository', misakiUpstreamRepository, location);
    _expectEqual(map, 'upstreamCommit', misakiUpstreamCommit, location);
    _expectEqual(map, 'upstreamVersion', misakiUpstreamVersion, location);

    final caseId = _optionalString(map, 'caseId', location);
    final language = _requiredString(map, 'language', location);
    final mode = _requiredString(map, 'mode', location);
    final input = _requiredString(map, 'input', location);
    final options = _requiredObject(map, 'options', location);
    final backendVersions = _requiredObject(map, 'backendVersions', location);
    final backendInput = _optionalBackendInput(map, location);
    for (final entry in backendVersions.entries) {
      if (entry.value != null && entry.value is! String) {
        throw UpstreamFixtureFormatException(
          '$location: backendVersions.${entry.key} must be a string or null',
        );
      }
    }

    final rawSeed = map['seed'];
    if (rawSeed != null && rawSeed is! int) {
      throw UpstreamFixtureFormatException(
        '$location: seed must be an integer when present',
      );
    }

    final rawError = map['error'];
    String? errorCategory;
    if (rawError != null) {
      if (rawError is! Map<String, Object?> || rawError.length != 1) {
        throw UpstreamFixtureFormatException(
          '$location: error must contain only a category',
        );
      }
      errorCategory = _requiredString(rawError, 'category', location);
    }

    final rawPhonemes = map['phonemes'];
    if (rawPhonemes != null && rawPhonemes is! String) {
      throw UpstreamFixtureFormatException(
        '$location: phonemes must be a string or null',
      );
    }
    final rawTokens = map['tokens'];
    if (rawTokens != null && rawTokens is! List<Object?>) {
      throw UpstreamFixtureFormatException(
        '$location: tokens must be an array or null',
      );
    }
    if (errorCategory == null && rawPhonemes is! String) {
      throw UpstreamFixtureFormatException(
        '$location: a successful fixture requires string phonemes',
      );
    }
    if (errorCategory != null && (rawPhonemes != null || rawTokens != null)) {
      throw UpstreamFixtureFormatException(
        '$location: a failure fixture must have null phonemes and tokens',
      );
    }

    return UpstreamFixture._(
      caseId: caseId,
      language: language,
      mode: mode,
      options: Map<String, Object?>.unmodifiable(options),
      backendVersions: Map<String, Object?>.unmodifiable(backendVersions),
      backendInput: backendInput,
      input: input,
      phonemes: rawPhonemes as String?,
      tokens: rawTokens == null
          ? null
          : List<Object?>.unmodifiable(rawTokens as List<Object?>),
      errorCategory: errorCategory,
      seed: rawSeed as int?,
    );
  }

  final String? caseId;
  final String language;
  final String mode;
  final Map<String, Object?> options;
  final Map<String, Object?> backendVersions;
  final UpstreamFixtureBackendInput? backendInput;
  final String input;
  final String? phonemes;
  final List<Object?>? tokens;
  final String? errorCategory;
  final int? seed;

  String get label => caseId ?? '$language/$mode: $input';
}

/// Base type for strict, versioned replay inputs captured by the oracle.
sealed class UpstreamFixtureBackendInput {
  const UpstreamFixtureBackendInput();
}

/// Typed pyopenjtalk frontend output captured by the pinned Python oracle.
final class PyopenjtalkFixtureBackendInput extends UpstreamFixtureBackendInput {
  PyopenjtalkFixtureBackendInput._(List<PyopenjtalkFixtureWord> words)
    : words = List<PyopenjtalkFixtureWord>.unmodifiable(words),
      super();

  /// Stable discriminator used by the fixture schema.
  static const String kind = 'pyopenjtalk.run_frontend.words';

  /// Current backend-input schema version.
  static const int schemaVersion = 1;

  /// Words returned by `pyopenjtalk.run_frontend`, in source order.
  final List<PyopenjtalkFixtureWord> words;
}

/// One complete word dictionary captured from `pyopenjtalk.run_frontend`.
final class PyopenjtalkFixtureWord {
  const PyopenjtalkFixtureWord({
    required this.surface,
    required this.partOfSpeech,
    required this.partOfSpeechGroup1,
    required this.partOfSpeechGroup2,
    required this.partOfSpeechGroup3,
    required this.conjugationType,
    required this.conjugationForm,
    required this.original,
    required this.reading,
    required this.pronunciation,
    required this.accent,
    required this.moraSize,
    required this.chainRule,
    required this.rawChainFlag,
  });

  final String surface;
  final String partOfSpeech;
  final String partOfSpeechGroup1;
  final String partOfSpeechGroup2;
  final String partOfSpeechGroup3;
  final String conjugationType;
  final String conjugationForm;
  final String original;
  final String reading;
  final String pronunciation;
  final int accent;
  final int moraSize;
  final String chainRule;
  final int rawChainFlag;
}

/// Typed preprocessing and raw-token replay input for the English fixture.
final class EnglishFixtureBackendInput extends UpstreamFixtureBackendInput {
  EnglishFixtureBackendInput._({
    required this.preprocess,
    required List<EnglishFixtureRawToken> tokens,
    required List<EnglishFixtureEspeakCall>? espeakCalls,
    required List<EnglishFixtureModelCall>? modelCalls,
  }) : tokens = List<EnglishFixtureRawToken>.unmodifiable(tokens),
       espeakCalls = espeakCalls == null
           ? null
           : List<EnglishFixtureEspeakCall>.unmodifiable(espeakCalls),
       modelCalls = modelCalls == null
           ? null
           : List<EnglishFixtureModelCall>.unmodifiable(modelCalls),
       super();

  static const String kind = 'misaki.en.G2P.preprocess-tokenize';
  static const int schemaVersion = 1;
  static const int espeakSchemaVersion = 2;
  static const int modelSchemaVersion = 3;

  final EnglishFixturePreprocess preprocess;
  final List<EnglishFixtureRawToken> tokens;

  /// Ordered raw eSpeak calls, or `null` for the no-fallback schema.
  final List<EnglishFixtureEspeakCall>? espeakCalls;

  /// Ordered BART inference calls, or `null` for non-model schemas.
  final List<EnglishFixtureModelCall>? modelCalls;
}

/// One raw eSpeak backend call captured before Misaki postprocessing.
final class EnglishFixtureEspeakCall {
  const EnglishFixtureEspeakCall({required this.text, required this.rawPhones});

  final String text;

  /// First raw backend result, or `null` when the backend returned no results.
  final String? rawPhones;
}

/// One exact character-tokenized BART generation captured by the oracle.
final class EnglishFixtureModelCall {
  EnglishFixtureModelCall({
    required this.text,
    required List<int> inputIds,
    required List<int> generatedIds,
    required this.phonemes,
    required this.rating,
  }) : inputIds = List<int>.unmodifiable(inputIds),
       generatedIds = List<int>.unmodifiable(generatedIds);

  final String text;
  final List<int> inputIds;
  final List<int> generatedIds;
  final String phonemes;
  final int rating;
}

/// Exact values passed from English preprocessing into tokenization.
final class EnglishFixturePreprocess {
  EnglishFixturePreprocess({
    required this.applied,
    required this.text,
    required List<String> sourceWords,
    required List<EnglishFixtureFeature> features,
  }) : sourceWords = List<String>.unmodifiable(sourceWords),
       features = List<EnglishFixtureFeature>.unmodifiable(features);

  final bool applied;
  final String text;
  final List<String> sourceWords;
  final List<EnglishFixtureFeature> features;
}

/// One integer-keyed inline feature from upstream preprocessing.
final class EnglishFixtureFeature {
  const EnglishFixtureFeature({
    required this.sourceWordIndex,
    required this.value,
  });

  final int sourceWordIndex;
  final EnglishFixtureFeatureValue value;
}

/// Typed value carried by an English preprocessing feature.
sealed class EnglishFixtureFeatureValue {
  const EnglishFixtureFeatureValue();
}

final class EnglishFixtureStringFeature extends EnglishFixtureFeatureValue {
  const EnglishFixtureStringFeature(this.value);

  final String value;
}

final class EnglishFixtureIntegerFeature extends EnglishFixtureFeatureValue {
  const EnglishFixtureIntegerFeature(this.value);

  final int value;
}

final class EnglishFixtureDoubleFeature extends EnglishFixtureFeatureValue {
  const EnglishFixtureDoubleFeature(this.value);

  final double value;
}

/// One exact `MToken` snapshot returned by pinned English tokenization.
final class EnglishFixtureRawToken {
  const EnglishFixtureRawToken({
    required this.text,
    required this.tag,
    required this.whitespace,
    required this.phonemes,
    required this.startTimeSeconds,
    required this.endTimeSeconds,
    required this.metadata,
  });

  final String text;
  final String tag;
  final String whitespace;
  final String? phonemes;
  final num? startTimeSeconds;
  final num? endTimeSeconds;
  final EnglishFixtureRawMetadata metadata;
}

/// Exact `_` metadata present on an English raw tokenizer token.
final class EnglishFixtureRawMetadata {
  const EnglishFixtureRawMetadata({
    required this.isHead,
    required this.numberFlags,
    required this.precededBySpace,
    required this.stress,
    required this.rating,
  });

  final bool isHead;
  final String numberFlags;
  final bool precededBySpace;
  final num? stress;
  final int? rating;
}

/// Typed normalized morphology replay input for Japanese Cutlet mode.
final class CutletFixtureBackendInput extends UpstreamFixtureBackendInput {
  CutletFixtureBackendInput._({
    required this.normalizedText,
    required List<CutletFixtureWord> words,
  }) : words = List<CutletFixtureWord>.unmodifiable(words),
       super();

  static const String kind = 'misaki.cutlet.normalized-morphology';
  static const int schemaVersion = 1;

  final String normalizedText;
  final List<CutletFixtureWord> words;
}

/// One fugashi record plus its captured external-table grouping decision.
final class CutletFixtureWord {
  const CutletFixtureWord({
    required this.surface,
    required this.pronunciation,
    required this.kana,
    required this.hiragana,
    required this.charType,
    required this.isUnknown,
    required this.joinWithNext,
  });

  final String surface;
  final String? pronunciation;
  final String? kana;
  final String hiragana;
  final int charType;
  final bool isUnknown;
  final bool joinWithNext;
}

/// Typed MeCab POS replay input for the Korean fixture.
final class KoreanFixtureBackendInput extends UpstreamFixtureBackendInput {
  KoreanFixtureBackendInput._({
    required this.input,
    required List<KoreanFixtureCmuLookup> cmuLookups,
    required List<KoreanFixtureMorphologyToken> tokens,
  }) : cmuLookups = List<KoreanFixtureCmuLookup>.unmodifiable(cmuLookups),
       tokens = List<KoreanFixtureMorphologyToken>.unmodifiable(tokens),
       super();

  static const String kind = 'python-mecab-ko.MeCab.pos';
  static const int schemaVersion = 2;

  final String input;
  final List<KoreanFixtureCmuLookup> cmuLookups;
  final List<KoreanFixtureMorphologyToken> tokens;
}

/// One ordered normalized CMUdict lookup made by pinned g2pkc.
final class KoreanFixtureCmuLookup {
  KoreanFixtureCmuLookup({required this.key, required List<String>? arpabet})
    : arpabet = arpabet == null ? null : List<String>.unmodifiable(arpabet);

  final String key;

  /// Selected first pronunciation, or `null` for a dictionary miss.
  final List<String>? arpabet;
}

/// One exact Korean `(surface, tag)` analyzer result.
final class KoreanFixtureMorphologyToken {
  const KoreanFixtureMorphologyToken({
    required this.surface,
    required this.tag,
  });

  final String surface;
  final String tag;
}

/// Exact cn2an `an2cn` call captured for either Chinese frontend.
final class ChineseFixtureNormalization {
  const ChineseFixtureNormalization({
    required this.input,
    required this.output,
  });

  final String input;
  final String output;
}

/// Typed external-stage replay input for legacy Chinese.
final class ChineseLegacyFixtureBackendInput
    extends UpstreamFixtureBackendInput {
  ChineseLegacyFixtureBackendInput._({
    required this.normalization,
    required List<ChineseLegacyFixtureRun> runs,
  }) : runs = List<ChineseLegacyFixtureRun>.unmodifiable(runs),
       super();

  static const String kind = 'misaki.zh.legacy.external-stages';
  static const int schemaVersion = 1;

  final ChineseFixtureNormalization? normalization;
  final List<ChineseLegacyFixtureRun> runs;
}

/// One Basic-CJK run passed to `jieba.lcut(cut_all=False)`.
final class ChineseLegacyFixtureRun {
  ChineseLegacyFixtureRun({
    required this.input,
    required List<ChineseLegacyFixtureWord> words,
  }) : words = List<ChineseLegacyFixtureWord>.unmodifiable(words);

  final String input;
  final List<ChineseLegacyFixtureWord> words;
}

/// One legacy jieba word and its captured pypinyin call.
final class ChineseLegacyFixtureWord {
  const ChineseLegacyFixtureWord({required this.word, required this.pinyin});

  final String word;

  /// `null` is retained for a partial capture when upstream fails mid-call.
  final ChineseFixturePinyinCall? pinyin;
}

/// Typed external-stage replay input for Chinese frontend 1.1.
final class ChineseFrontendFixtureBackendInput
    extends UpstreamFixtureBackendInput {
  ChineseFrontendFixtureBackendInput._({
    required this.normalization,
    required List<ChineseFrontendFixtureCall> frontendCalls,
  }) : frontendCalls = List<ChineseFrontendFixtureCall>.unmodifiable(
         frontendCalls,
       ),
       super();

  static const String kind = 'misaki.zh.frontend-1.1.external-stages';
  static const int schemaVersion = 1;

  final ChineseFixtureNormalization? normalization;
  final List<ChineseFrontendFixtureCall> frontendCalls;
}

/// Frontend-1.1 external stages plus the accepted small-English callback.
final class ChineseFrontendEnglishFixtureBackendInput
    extends UpstreamFixtureBackendInput {
  ChineseFrontendEnglishFixtureBackendInput._({
    required this.normalization,
    required List<ChineseFrontendFixtureCall> frontendCalls,
    required this.english,
  }) : frontendCalls = List<ChineseFrontendFixtureCall>.unmodifiable(
         frontendCalls,
       ),
       super();

  static const String kind =
      'misaki.zh.frontend-1.1-en-small-no-fallback.external-stages';
  static const int schemaVersion = 2;

  final ChineseFixtureNormalization? normalization;
  final List<ChineseFrontendFixtureCall> frontendCalls;
  final ChineseFrontendEnglishFixtureConfiguration english;
}

/// Exact fixed English configuration and ordered callback trace.
final class ChineseFrontendEnglishFixtureConfiguration {
  ChineseFrontendEnglishFixtureConfiguration({
    required this.dialect,
    required this.version,
    required List<ChineseFrontendEnglishFixtureCall> calls,
  }) : calls = List<ChineseFrontendEnglishFixtureCall>.unmodifiable(calls);

  final String dialect;
  final String? version;
  final List<ChineseFrontendEnglishFixtureCall> calls;
}

/// One English callback result and its exact tokenizer replay boundary.
final class ChineseFrontendEnglishFixtureCall {
  ChineseFrontendEnglishFixtureCall({
    required this.input,
    required this.phonemes,
    required this.backendInput,
    required List<Object?> tokens,
  }) : tokens = List<Object?>.unmodifiable(tokens);

  final String input;
  final String phonemes;
  final EnglishFixtureBackendInput backendInput;
  final List<Object?> tokens;
}

/// One `ZHFrontend` call with its POS stream and ordered external calls.
final class ChineseFrontendFixtureCall {
  ChineseFrontendFixtureCall({
    required this.input,
    required List<ChineseFixturePosSegment> segmentation,
    required List<ChineseFixtureExternalCall> externalCalls,
  }) : segmentation = List<ChineseFixturePosSegment>.unmodifiable(segmentation),
       externalCalls = List<ChineseFixtureExternalCall>.unmodifiable(
         externalCalls,
       );

  final String input;
  final List<ChineseFixturePosSegment> segmentation;
  final List<ChineseFixtureExternalCall> externalCalls;
}

/// One word/POS pair returned by `jieba.posseg.lcut`.
final class ChineseFixturePosSegment {
  const ChineseFixturePosSegment({required this.word, required this.pos});

  final String word;
  final String pos;
}

/// Ordered external call made within one Chinese frontend invocation.
sealed class ChineseFixtureExternalCall {
  const ChineseFixtureExternalCall({required this.input});

  final String input;
}

/// One exact `pypinyin.lazy_pinyin` call.
final class ChineseFixturePinyinCall extends ChineseFixtureExternalCall {
  ChineseFixturePinyinCall({
    required super.input,
    required this.stage,
    required this.style,
    required List<String> output,
  }) : output = List<String>.unmodifiable(output);

  final String stage;
  final String style;
  final List<String> output;
}

/// One exact `jieba.cut_for_search` call used by tone sandhi.
final class ChineseFixtureSearchCall extends ChineseFixtureExternalCall {
  ChineseFixtureSearchCall({required super.input, required List<String> output})
    : output = List<String>.unmodifiable(output);

  final List<String> output;
}

/// Typed cleaned-text/token replay input for Vietnamese modes.
final class VietnameseFixtureBackendInput extends UpstreamFixtureBackendInput {
  VietnameseFixtureBackendInput._({
    required this.input,
    required List<String> tokens,
  }) : tokens = List<String>.unmodifiable(tokens),
       super();

  static const String kind = 'underthesea.pipeline.word_tokenize.tokenize';
  static const int schemaVersion = 1;

  /// Exact fully cleaned text passed to underthesea.
  final String input;

  /// Exact ordered raw strings returned by underthesea.
  final List<String> tokens;
}

List<UpstreamFixture> readUpstreamFixtures(File file) {
  final lines = file.readAsLinesSync();
  final fixtures = <UpstreamFixture>[];
  final caseIds = <String>{};
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    if (line.trim().isEmpty) {
      continue;
    }
    final fixture = UpstreamFixture.parse(
      line,
      location: '${file.path}:${index + 1}',
    );
    final caseId = fixture.caseId;
    if (caseId != null && !caseIds.add(caseId)) {
      throw UpstreamFixtureFormatException(
        '${file.path}:${index + 1}: duplicate caseId `$caseId`',
      );
    }
    fixtures.add(fixture);
  }
  if (fixtures.isEmpty) {
    throw UpstreamFixtureFormatException('${file.path}: fixture is empty');
  }
  return List<UpstreamFixture>.unmodifiable(fixtures);
}

void _expectEqual(
  Map<String, Object?> map,
  String key,
  Object expected,
  String location,
) {
  if (map[key] != expected) {
    throw UpstreamFixtureFormatException(
      '$location: $key must equal `$expected`',
    );
  }
}

String _requiredString(Map<String, Object?> map, String key, String location) {
  final value = map[key];
  if (value is! String) {
    throw UpstreamFixtureFormatException('$location: $key must be a string');
  }
  return value;
}

String? _optionalString(Map<String, Object?> map, String key, String location) {
  final value = map[key];
  if (value != null && value is! String) {
    throw UpstreamFixtureFormatException(
      '$location: $key must be a string when present',
    );
  }
  return value as String?;
}

Map<String, Object?> _requiredObject(
  Map<String, Object?> map,
  String key,
  String location,
) {
  final value = map[key];
  if (value is! Map<String, Object?>) {
    throw UpstreamFixtureFormatException('$location: $key must be an object');
  }
  return value;
}

int _requiredInt(Map<String, Object?> map, String key, String location) {
  final value = map[key];
  if (value is! int) {
    throw UpstreamFixtureFormatException('$location: $key must be an integer');
  }
  return value;
}

UpstreamFixtureBackendInput? _optionalBackendInput(
  Map<String, Object?> map,
  String location,
) {
  final value = map['backendInput'];
  if (value == null) {
    return null;
  }
  if (value is! Map<String, Object?>) {
    throw UpstreamFixtureFormatException(
      '$location: backendInput must be an object when present',
    );
  }
  final inputLocation = '$location: backendInput';
  final kind = _requiredString(value, 'kind', inputLocation);
  return switch (kind) {
    PyopenjtalkFixtureBackendInput.kind => _parsePyopenjtalkBackendInput(
      value,
      inputLocation,
    ),
    EnglishFixtureBackendInput.kind => _parseEnglishBackendInput(
      value,
      inputLocation,
    ),
    CutletFixtureBackendInput.kind => _parseCutletBackendInput(
      value,
      inputLocation,
    ),
    KoreanFixtureBackendInput.kind => _parseKoreanBackendInput(
      value,
      inputLocation,
    ),
    ChineseLegacyFixtureBackendInput.kind => _parseChineseLegacyBackendInput(
      value,
      inputLocation,
    ),
    ChineseFrontendFixtureBackendInput.kind =>
      _parseChineseFrontendBackendInput(value, inputLocation),
    ChineseFrontendEnglishFixtureBackendInput.kind =>
      _parseChineseFrontendEnglishBackendInput(value, inputLocation),
    VietnameseFixtureBackendInput.kind => _parseVietnameseBackendInput(
      value,
      inputLocation,
    ),
    _ => throw UpstreamFixtureFormatException(
      '$inputLocation.kind has unsupported value `$kind`',
    ),
  };
}

PyopenjtalkFixtureBackendInput _parsePyopenjtalkBackendInput(
  Map<String, Object?> value,
  String location,
) {
  _expectExactKeys(value, const <String>{
    'kind',
    'schemaVersion',
    'words',
  }, location);
  _expectEqual(value, 'kind', PyopenjtalkFixtureBackendInput.kind, location);
  _expectEqual(
    value,
    'schemaVersion',
    PyopenjtalkFixtureBackendInput.schemaVersion,
    location,
  );
  final rawWords = value['words'];
  if (rawWords is! List<Object?>) {
    throw UpstreamFixtureFormatException('$location.words must be an array');
  }
  final words = <PyopenjtalkFixtureWord>[];
  for (var index = 0; index < rawWords.length; index++) {
    final rawWord = rawWords[index];
    final wordLocation = '$location.words[$index]';
    if (rawWord is! Map<String, Object?>) {
      throw UpstreamFixtureFormatException('$wordLocation must be an object');
    }
    _expectExactKeys(rawWord, _pyopenjtalkWordKeys, wordLocation);
    words.add(
      PyopenjtalkFixtureWord(
        surface: _requiredString(rawWord, 'string', wordLocation),
        partOfSpeech: _requiredString(rawWord, 'pos', wordLocation),
        partOfSpeechGroup1: _requiredString(
          rawWord,
          'pos_group1',
          wordLocation,
        ),
        partOfSpeechGroup2: _requiredString(
          rawWord,
          'pos_group2',
          wordLocation,
        ),
        partOfSpeechGroup3: _requiredString(
          rawWord,
          'pos_group3',
          wordLocation,
        ),
        conjugationType: _requiredString(rawWord, 'ctype', wordLocation),
        conjugationForm: _requiredString(rawWord, 'cform', wordLocation),
        original: _requiredString(rawWord, 'orig', wordLocation),
        reading: _requiredString(rawWord, 'read', wordLocation),
        pronunciation: _requiredString(rawWord, 'pron', wordLocation),
        accent: _requiredInt(rawWord, 'acc', wordLocation),
        moraSize: _requiredInt(rawWord, 'mora_size', wordLocation),
        chainRule: _requiredString(rawWord, 'chain_rule', wordLocation),
        rawChainFlag: _requiredInt(rawWord, 'chain_flag', wordLocation),
      ),
    );
  }
  return PyopenjtalkFixtureBackendInput._(words);
}

EnglishFixtureBackendInput _parseEnglishBackendInput(
  Map<String, Object?> value,
  String location,
) {
  _expectEqual(value, 'kind', EnglishFixtureBackendInput.kind, location);
  final schemaVersion = _requiredInt(value, 'schemaVersion', location);
  final List<EnglishFixtureEspeakCall>? espeakCalls;
  final List<EnglishFixtureModelCall>? modelCalls;
  switch (schemaVersion) {
    case EnglishFixtureBackendInput.schemaVersion:
      _expectExactKeys(value, const <String>{
        'kind',
        'preprocess',
        'schemaVersion',
        'tokens',
      }, location);
      espeakCalls = null;
      modelCalls = null;
      break;
    case EnglishFixtureBackendInput.espeakSchemaVersion:
      _expectExactKeys(value, const <String>{
        'espeakCalls',
        'kind',
        'preprocess',
        'schemaVersion',
        'tokens',
      }, location);
      final rawCalls = _requiredList(value, 'espeakCalls', location);
      final parsedCalls = <EnglishFixtureEspeakCall>[];
      for (var index = 0; index < rawCalls.length; index++) {
        final rawCall = rawCalls[index];
        final callLocation = '$location.espeakCalls[$index]';
        if (rawCall is! Map<String, Object?>) {
          throw UpstreamFixtureFormatException(
            '$callLocation must be an object',
          );
        }
        _expectExactKeys(rawCall, const <String>{
          'rawPhones',
          'text',
        }, callLocation);
        parsedCalls.add(
          EnglishFixtureEspeakCall(
            text: _requiredString(rawCall, 'text', callLocation),
            rawPhones: _requiredNullableString(
              rawCall,
              'rawPhones',
              callLocation,
            ),
          ),
        );
      }
      espeakCalls = parsedCalls;
      modelCalls = null;
      break;
    case EnglishFixtureBackendInput.modelSchemaVersion:
      _expectExactKeys(value, const <String>{
        'kind',
        'modelCalls',
        'preprocess',
        'schemaVersion',
        'tokens',
      }, location);
      final rawCalls = _requiredList(value, 'modelCalls', location);
      final parsedCalls = <EnglishFixtureModelCall>[];
      for (var index = 0; index < rawCalls.length; index++) {
        final rawCall = rawCalls[index];
        final callLocation = '$location.modelCalls[$index]';
        if (rawCall is! Map<String, Object?>) {
          throw UpstreamFixtureFormatException(
            '$callLocation must be an object',
          );
        }
        _expectExactKeys(rawCall, const <String>{
          'generatedIds',
          'inputIds',
          'phonemes',
          'rating',
          'text',
        }, callLocation);
        final text = _requiredString(rawCall, 'text', callLocation);
        final inputIds = _requiredNonNegativeIntList(
          rawCall,
          'inputIds',
          callLocation,
        );
        final generatedIds = _requiredNonNegativeIntList(
          rawCall,
          'generatedIds',
          callLocation,
        );
        if (text.isEmpty ||
            inputIds.length != text.runes.length + 2 ||
            inputIds.first != 1 ||
            inputIds.last != 2) {
          throw UpstreamFixtureFormatException(
            '$callLocation.inputIds must contain one ID per grapheme between '
            'BOS 1 and EOS 2',
          );
        }
        if (generatedIds.isEmpty) {
          throw UpstreamFixtureFormatException(
            '$callLocation.generatedIds must not be empty',
          );
        }
        final rating = _requiredInt(rawCall, 'rating', callLocation);
        if (rating != 1) {
          throw UpstreamFixtureFormatException(
            '$callLocation.rating must equal pinned value 1',
          );
        }
        parsedCalls.add(
          EnglishFixtureModelCall(
            text: text,
            inputIds: inputIds,
            generatedIds: generatedIds,
            phonemes: _requiredString(rawCall, 'phonemes', callLocation),
            rating: rating,
          ),
        );
      }
      espeakCalls = null;
      modelCalls = parsedCalls;
      break;
    default:
      throw UpstreamFixtureFormatException(
        '$location.schemaVersion must equal '
        '${EnglishFixtureBackendInput.schemaVersion} or '
        '${EnglishFixtureBackendInput.espeakSchemaVersion} or '
        '${EnglishFixtureBackendInput.modelSchemaVersion}',
      );
  }

  final rawPreprocess = _requiredObject(value, 'preprocess', location);
  final preprocessLocation = '$location.preprocess';
  _expectExactKeys(rawPreprocess, const <String>{
    'applied',
    'features',
    'sourceWords',
    'text',
  }, preprocessLocation);
  final applied = _requiredBool(rawPreprocess, 'applied', preprocessLocation);
  final text = _requiredString(rawPreprocess, 'text', preprocessLocation);
  final rawSourceWords = _requiredList(
    rawPreprocess,
    'sourceWords',
    preprocessLocation,
  );
  final sourceWords = <String>[];
  for (var index = 0; index < rawSourceWords.length; index++) {
    final word = rawSourceWords[index];
    if (word is! String) {
      throw UpstreamFixtureFormatException(
        '$preprocessLocation.sourceWords[$index] must be a string',
      );
    }
    sourceWords.add(word);
  }

  final rawFeatures = _requiredList(
    rawPreprocess,
    'features',
    preprocessLocation,
  );
  final features = <EnglishFixtureFeature>[];
  var previousFeatureIndex = -1;
  for (var index = 0; index < rawFeatures.length; index++) {
    final rawFeature = rawFeatures[index];
    final featureLocation = '$preprocessLocation.features[$index]';
    if (rawFeature is! Map<String, Object?>) {
      throw UpstreamFixtureFormatException(
        '$featureLocation must be an object',
      );
    }
    _expectExactKeys(rawFeature, const <String>{
      'sourceWordIndex',
      'value',
    }, featureLocation);
    final sourceWordIndex = _requiredInt(
      rawFeature,
      'sourceWordIndex',
      featureLocation,
    );
    if (sourceWordIndex <= previousFeatureIndex ||
        sourceWordIndex < 0 ||
        sourceWordIndex >= sourceWords.length) {
      throw UpstreamFixtureFormatException(
        '$featureLocation.sourceWordIndex must be strictly increasing and '
        'refer to sourceWords',
      );
    }
    previousFeatureIndex = sourceWordIndex;
    final rawFeatureValue = rawFeature['value'];
    final EnglishFixtureFeatureValue featureValue;
    if (rawFeatureValue is String) {
      featureValue = EnglishFixtureStringFeature(rawFeatureValue);
    } else if (rawFeatureValue is int) {
      featureValue = EnglishFixtureIntegerFeature(rawFeatureValue);
    } else if (rawFeatureValue is double &&
        (rawFeatureValue == -0.5 || rawFeatureValue == 0.5)) {
      featureValue = EnglishFixtureDoubleFeature(rawFeatureValue);
    } else {
      throw UpstreamFixtureFormatException(
        '$featureLocation.value must be a string, integer, -0.5, or 0.5',
      );
    }
    features.add(
      EnglishFixtureFeature(
        sourceWordIndex: sourceWordIndex,
        value: featureValue,
      ),
    );
  }

  final rawTokens = _requiredList(value, 'tokens', location);
  final tokens = <EnglishFixtureRawToken>[];
  for (var index = 0; index < rawTokens.length; index++) {
    final rawToken = rawTokens[index];
    final tokenLocation = '$location.tokens[$index]';
    if (rawToken is! Map<String, Object?>) {
      throw UpstreamFixtureFormatException('$tokenLocation must be an object');
    }
    _expectExactKeys(rawToken, _englishRawTokenKeys, tokenLocation);
    final rawMetadata = _requiredObject(rawToken, '_', tokenLocation);
    final metadataLocation = '$tokenLocation._';
    final metadataKeys = rawMetadata.keys.toSet();
    if (!metadataKeys.containsAll(_englishMetadataRequiredKeys) ||
        !_englishMetadataAllowedKeys.containsAll(metadataKeys)) {
      throw UpstreamFixtureFormatException(
        '$metadataLocation has invalid keys ${metadataKeys.toList()..sort()}',
      );
    }
    final stress = rawMetadata.containsKey('stress')
        ? _requiredNumber(rawMetadata, 'stress', metadataLocation)
        : null;
    final rating = rawMetadata.containsKey('rating')
        ? _requiredInt(rawMetadata, 'rating', metadataLocation)
        : null;
    tokens.add(
      EnglishFixtureRawToken(
        text: _requiredString(rawToken, 'text', tokenLocation),
        tag: _requiredString(rawToken, 'tag', tokenLocation),
        whitespace: _requiredString(rawToken, 'whitespace', tokenLocation),
        phonemes: _requiredNullableString(rawToken, 'phonemes', tokenLocation),
        startTimeSeconds: _requiredNullableNumber(
          rawToken,
          'start_ts',
          tokenLocation,
        ),
        endTimeSeconds: _requiredNullableNumber(
          rawToken,
          'end_ts',
          tokenLocation,
        ),
        metadata: EnglishFixtureRawMetadata(
          isHead: _requiredBool(rawMetadata, 'is_head', metadataLocation),
          numberFlags: _requiredString(
            rawMetadata,
            'num_flags',
            metadataLocation,
          ),
          precededBySpace: _requiredBool(
            rawMetadata,
            'prespace',
            metadataLocation,
          ),
          stress: stress,
          rating: rating,
        ),
      ),
    );
  }

  return EnglishFixtureBackendInput._(
    preprocess: EnglishFixturePreprocess(
      applied: applied,
      text: text,
      sourceWords: sourceWords,
      features: features,
    ),
    tokens: tokens,
    espeakCalls: espeakCalls,
    modelCalls: modelCalls,
  );
}

CutletFixtureBackendInput _parseCutletBackendInput(
  Map<String, Object?> value,
  String location,
) {
  _expectExactKeys(value, const <String>{
    'kind',
    'normalizedText',
    'schemaVersion',
    'words',
  }, location);
  _expectEqual(value, 'kind', CutletFixtureBackendInput.kind, location);
  _expectEqual(
    value,
    'schemaVersion',
    CutletFixtureBackendInput.schemaVersion,
    location,
  );
  final rawWords = _requiredList(value, 'words', location);
  final words = <CutletFixtureWord>[];
  for (var index = 0; index < rawWords.length; index++) {
    final rawWord = rawWords[index];
    final wordLocation = '$location.words[$index]';
    if (rawWord is! Map<String, Object?>) {
      throw UpstreamFixtureFormatException('$wordLocation must be an object');
    }
    _expectExactKeys(rawWord, const <String>{
      'charType',
      'hiragana',
      'isUnknown',
      'joinWithNext',
      'kana',
      'pronunciation',
      'surface',
    }, wordLocation);
    final surface = _requiredString(rawWord, 'surface', wordLocation);
    final charType = _requiredInt(rawWord, 'charType', wordLocation);
    final joinWithNext = _requiredBool(rawWord, 'joinWithNext', wordLocation);
    if (surface.isEmpty) {
      throw UpstreamFixtureFormatException(
        '$wordLocation.surface must not be empty',
      );
    }
    if (charType < 0) {
      throw UpstreamFixtureFormatException(
        '$wordLocation.charType must be non-negative',
      );
    }
    if (joinWithNext && index + 1 == rawWords.length) {
      throw UpstreamFixtureFormatException(
        '$wordLocation.joinWithNext cannot target past the end',
      );
    }
    final hiragana = _requiredString(rawWord, 'hiragana', wordLocation);
    if (hiragana.isEmpty) {
      throw UpstreamFixtureFormatException(
        '$wordLocation.hiragana must not be empty',
      );
    }
    words.add(
      CutletFixtureWord(
        surface: surface,
        pronunciation: _requiredNullableString(
          rawWord,
          'pronunciation',
          wordLocation,
        ),
        kana: _requiredNullableString(rawWord, 'kana', wordLocation),
        hiragana: hiragana,
        charType: charType,
        isUnknown: _requiredBool(rawWord, 'isUnknown', wordLocation),
        joinWithNext: joinWithNext,
      ),
    );
  }
  for (var index = 0; index + 1 < words.length; index++) {
    final word = words[index];
    if (word.joinWithNext &&
        _cutletEffectiveCharType(word) !=
            _cutletEffectiveCharType(words[index + 1])) {
      throw UpstreamFixtureFormatException(
        '$location.words[$index].joinWithNext must target the same effective '
        'charType',
      );
    }
  }
  return CutletFixtureBackendInput._(
    normalizedText: _requiredString(value, 'normalizedText', location),
    words: words,
  );
}

int _cutletEffectiveCharType(CutletFixtureWord word) =>
    word.charType == 7 || !word.isUnknown ? 6 : word.charType;

KoreanFixtureBackendInput _parseKoreanBackendInput(
  Map<String, Object?> value,
  String location,
) {
  _expectExactKeys(value, const <String>{
    'cmuLookups',
    'input',
    'kind',
    'schemaVersion',
    'tokens',
  }, location);
  _expectEqual(value, 'kind', KoreanFixtureBackendInput.kind, location);
  _expectEqual(
    value,
    'schemaVersion',
    KoreanFixtureBackendInput.schemaVersion,
    location,
  );
  final rawLookups = _requiredList(value, 'cmuLookups', location);
  final lookups = <KoreanFixtureCmuLookup>[];
  for (var index = 0; index < rawLookups.length; index++) {
    final rawLookup = rawLookups[index];
    final lookupLocation = '$location.cmuLookups[$index]';
    if (rawLookup is! Map<String, Object?>) {
      throw UpstreamFixtureFormatException('$lookupLocation must be an object');
    }
    _expectExactKeys(rawLookup, const <String>{
      'arpabet',
      'key',
    }, lookupLocation);
    final key = _requiredString(rawLookup, 'key', lookupLocation);
    if (key.isEmpty ||
        key != key.toLowerCase() ||
        key.runes.any((scalar) => scalar < 0x61 || scalar > 0x7a)) {
      throw UpstreamFixtureFormatException(
        '$lookupLocation.key must be normalized lowercase ASCII',
      );
    }
    final rawArpabet = rawLookup['arpabet'];
    List<String>? arpabet;
    if (rawArpabet != null) {
      if (rawArpabet is! List<Object?> ||
          rawArpabet.isEmpty ||
          rawArpabet.any((symbol) => symbol is! String || symbol.isEmpty)) {
        throw UpstreamFixtureFormatException(
          '$lookupLocation.arpabet must be null or a non-empty string array',
        );
      }
      arpabet = rawArpabet.cast<String>();
    }
    lookups.add(KoreanFixtureCmuLookup(key: key, arpabet: arpabet));
  }
  final rawTokens = _requiredList(value, 'tokens', location);
  final tokens = <KoreanFixtureMorphologyToken>[];
  for (var index = 0; index < rawTokens.length; index++) {
    final rawToken = rawTokens[index];
    final tokenLocation = '$location.tokens[$index]';
    if (rawToken is! Map<String, Object?>) {
      throw UpstreamFixtureFormatException('$tokenLocation must be an object');
    }
    _expectExactKeys(rawToken, const <String>{'surface', 'tag'}, tokenLocation);
    tokens.add(
      KoreanFixtureMorphologyToken(
        surface: _requiredString(rawToken, 'surface', tokenLocation),
        tag: _requiredString(rawToken, 'tag', tokenLocation),
      ),
    );
  }
  return KoreanFixtureBackendInput._(
    input: _requiredString(value, 'input', location),
    cmuLookups: lookups,
    tokens: tokens,
  );
}

ChineseLegacyFixtureBackendInput _parseChineseLegacyBackendInput(
  Map<String, Object?> value,
  String location,
) {
  _expectExactKeys(value, const <String>{
    'kind',
    'normalization',
    'runs',
    'schemaVersion',
  }, location);
  _expectEqual(value, 'kind', ChineseLegacyFixtureBackendInput.kind, location);
  _expectEqual(
    value,
    'schemaVersion',
    ChineseLegacyFixtureBackendInput.schemaVersion,
    location,
  );
  final rawRuns = _requiredList(value, 'runs', location);
  final runs = <ChineseLegacyFixtureRun>[];
  for (var runIndex = 0; runIndex < rawRuns.length; runIndex++) {
    final rawRun = rawRuns[runIndex];
    final runLocation = '$location.runs[$runIndex]';
    if (rawRun is! Map<String, Object?>) {
      throw UpstreamFixtureFormatException('$runLocation must be an object');
    }
    _expectExactKeys(rawRun, const <String>{'input', 'words'}, runLocation);
    final rawWords = _requiredList(rawRun, 'words', runLocation);
    final words = <ChineseLegacyFixtureWord>[];
    for (var wordIndex = 0; wordIndex < rawWords.length; wordIndex++) {
      final rawWord = rawWords[wordIndex];
      final wordLocation = '$runLocation.words[$wordIndex]';
      if (rawWord is! Map<String, Object?>) {
        throw UpstreamFixtureFormatException('$wordLocation must be an object');
      }
      _expectExactKeys(rawWord, const <String>{'pinyin', 'word'}, wordLocation);
      final rawPinyin = rawWord['pinyin'];
      words.add(
        ChineseLegacyFixtureWord(
          word: _requiredString(rawWord, 'word', wordLocation),
          pinyin: rawPinyin == null
              ? null
              : _parseChinesePinyinCall(
                  rawPinyin,
                  '$wordLocation.pinyin',
                  allowedStages: const <String>{'legacy-word'},
                  allowedStyles: const <String>{'tone3'},
                ),
        ),
      );
    }
    runs.add(
      ChineseLegacyFixtureRun(
        input: _requiredString(rawRun, 'input', runLocation),
        words: words,
      ),
    );
  }
  return ChineseLegacyFixtureBackendInput._(
    normalization: _parseChineseNormalization(
      value['normalization'],
      '$location.normalization',
    ),
    runs: runs,
  );
}

ChineseFrontendFixtureBackendInput _parseChineseFrontendBackendInput(
  Map<String, Object?> value,
  String location,
) {
  _expectExactKeys(value, const <String>{
    'frontendCalls',
    'kind',
    'normalization',
    'schemaVersion',
  }, location);
  _expectEqual(
    value,
    'kind',
    ChineseFrontendFixtureBackendInput.kind,
    location,
  );
  _expectEqual(
    value,
    'schemaVersion',
    ChineseFrontendFixtureBackendInput.schemaVersion,
    location,
  );
  final rawCalls = _requiredList(value, 'frontendCalls', location);
  final calls = <ChineseFrontendFixtureCall>[];
  for (var callIndex = 0; callIndex < rawCalls.length; callIndex++) {
    final rawCall = rawCalls[callIndex];
    final callLocation = '$location.frontendCalls[$callIndex]';
    if (rawCall is! Map<String, Object?>) {
      throw UpstreamFixtureFormatException('$callLocation must be an object');
    }
    _expectExactKeys(rawCall, const <String>{
      'externalCalls',
      'input',
      'segmentation',
    }, callLocation);
    final rawSegments = _requiredList(rawCall, 'segmentation', callLocation);
    final segments = <ChineseFixturePosSegment>[];
    for (var index = 0; index < rawSegments.length; index++) {
      final rawSegment = rawSegments[index];
      final segmentLocation = '$callLocation.segmentation[$index]';
      if (rawSegment is! Map<String, Object?>) {
        throw UpstreamFixtureFormatException(
          '$segmentLocation must be an object',
        );
      }
      _expectExactKeys(rawSegment, const <String>{
        'pos',
        'word',
      }, segmentLocation);
      segments.add(
        ChineseFixturePosSegment(
          word: _requiredString(rawSegment, 'word', segmentLocation),
          pos: _requiredString(rawSegment, 'pos', segmentLocation),
        ),
      );
    }
    final rawExternalCalls = _requiredList(
      rawCall,
      'externalCalls',
      callLocation,
    );
    final externalCalls = <ChineseFixtureExternalCall>[];
    for (var index = 0; index < rawExternalCalls.length; index++) {
      final rawExternalCall = rawExternalCalls[index];
      final externalLocation = '$callLocation.externalCalls[$index]';
      if (rawExternalCall is! Map<String, Object?>) {
        throw UpstreamFixtureFormatException(
          '$externalLocation must be an object',
        );
      }
      final kind = _requiredString(rawExternalCall, 'kind', externalLocation);
      externalCalls.add(switch (kind) {
        'pypinyin.lazy_pinyin' => _parseChinesePinyinCall(
          rawExternalCall,
          externalLocation,
          allowedStages: const <String>{'frontend-render', 'tone-premerge'},
          allowedStyles: const <String>{'finals-tone3', 'initials'},
        ),
        'jieba.cut_for_search' => _parseChineseSearchCall(
          rawExternalCall,
          externalLocation,
        ),
        _ => throw UpstreamFixtureFormatException(
          '$externalLocation.kind has unsupported value `$kind`',
        ),
      });
    }
    calls.add(
      ChineseFrontendFixtureCall(
        input: _requiredString(rawCall, 'input', callLocation),
        segmentation: segments,
        externalCalls: externalCalls,
      ),
    );
  }
  return ChineseFrontendFixtureBackendInput._(
    normalization: _parseChineseNormalization(
      value['normalization'],
      '$location.normalization',
    ),
    frontendCalls: calls,
  );
}

ChineseFrontendEnglishFixtureBackendInput
_parseChineseFrontendEnglishBackendInput(
  Map<String, Object?> value,
  String location,
) {
  _expectExactKeys(value, const <String>{
    'english',
    'frontendCalls',
    'kind',
    'normalization',
    'schemaVersion',
  }, location);
  _expectEqual(
    value,
    'kind',
    ChineseFrontendEnglishFixtureBackendInput.kind,
    location,
  );
  _expectEqual(
    value,
    'schemaVersion',
    ChineseFrontendEnglishFixtureBackendInput.schemaVersion,
    location,
  );

  final frontend = _parseChineseFrontendBackendInput(<String, Object?>{
    'frontendCalls': value['frontendCalls'],
    'kind': ChineseFrontendFixtureBackendInput.kind,
    'normalization': value['normalization'],
    'schemaVersion': ChineseFrontendFixtureBackendInput.schemaVersion,
  }, '$location.chineseStages');

  final rawEnglish = value['english'];
  if (rawEnglish is! Map<String, Object?>) {
    throw UpstreamFixtureFormatException('$location.english must be an object');
  }
  final englishLocation = '$location.english';
  _expectExactKeys(rawEnglish, const <String>{
    'calls',
    'dialect',
    'fallback',
    'model',
    'preprocess',
    'version',
  }, englishLocation);
  final dialect = _requiredString(rawEnglish, 'dialect', englishLocation);
  if (dialect != 'american' && dialect != 'british') {
    throw UpstreamFixtureFormatException(
      '$englishLocation.dialect must be american or british',
    );
  }
  final version = _requiredNullableString(
    rawEnglish,
    'version',
    englishLocation,
  );
  if (version != null && version != '2.0') {
    throw UpstreamFixtureFormatException(
      '$englishLocation.version must be null or 2.0',
    );
  }
  _expectEqual(rawEnglish, 'fallback', 'none', englishLocation);
  _expectEqual(rawEnglish, 'model', 'en_core_web_sm', englishLocation);
  _expectEqual(rawEnglish, 'preprocess', true, englishLocation);

  final rawCalls = _requiredList(rawEnglish, 'calls', englishLocation);
  final calls = <ChineseFrontendEnglishFixtureCall>[];
  for (var index = 0; index < rawCalls.length; index++) {
    final rawCall = rawCalls[index];
    final callLocation = '$englishLocation.calls[$index]';
    if (rawCall is! Map<String, Object?>) {
      throw UpstreamFixtureFormatException('$callLocation must be an object');
    }
    _expectExactKeys(rawCall, const <String>{
      'backendInput',
      'input',
      'phonemes',
      'tokens',
    }, callLocation);
    final rawBackendInput = rawCall['backendInput'];
    if (rawBackendInput is! Map<String, Object?>) {
      throw UpstreamFixtureFormatException(
        '$callLocation.backendInput must be an object',
      );
    }
    final backendInput = _parseEnglishBackendInput(
      rawBackendInput,
      '$callLocation.backendInput',
    );
    if (backendInput.espeakCalls != null || backendInput.modelCalls != null) {
      throw UpstreamFixtureFormatException(
        '$callLocation.backendInput must use the no-fallback schema',
      );
    }
    final tokens = _requiredList(rawCall, 'tokens', callLocation);
    for (var tokenIndex = 0; tokenIndex < tokens.length; tokenIndex++) {
      if (tokens[tokenIndex] is! Map<String, Object?>) {
        throw UpstreamFixtureFormatException(
          '$callLocation.tokens[$tokenIndex] must be an object',
        );
      }
    }
    calls.add(
      ChineseFrontendEnglishFixtureCall(
        input: _requiredString(rawCall, 'input', callLocation),
        phonemes: _requiredString(rawCall, 'phonemes', callLocation),
        backendInput: backendInput,
        tokens: tokens,
      ),
    );
  }

  return ChineseFrontendEnglishFixtureBackendInput._(
    normalization: frontend.normalization,
    frontendCalls: frontend.frontendCalls,
    english: ChineseFrontendEnglishFixtureConfiguration(
      dialect: dialect,
      version: version,
      calls: calls,
    ),
  );
}

ChineseFixtureNormalization? _parseChineseNormalization(
  Object? value,
  String location,
) {
  if (value == null) {
    return null;
  }
  if (value is! Map<String, Object?>) {
    throw UpstreamFixtureFormatException('$location must be an object or null');
  }
  _expectExactKeys(value, const <String>{'input', 'mode', 'output'}, location);
  _expectEqual(value, 'mode', 'an2cn', location);
  return ChineseFixtureNormalization(
    input: _requiredString(value, 'input', location),
    output: _requiredString(value, 'output', location),
  );
}

ChineseFixturePinyinCall _parseChinesePinyinCall(
  Object? value,
  String location, {
  required Set<String> allowedStages,
  required Set<String> allowedStyles,
}) {
  if (value is! Map<String, Object?>) {
    throw UpstreamFixtureFormatException('$location must be an object');
  }
  _expectExactKeys(value, const <String>{
    'input',
    'kind',
    'neutralToneWithFive',
    'output',
    'stage',
    'style',
  }, location);
  _expectEqual(value, 'kind', 'pypinyin.lazy_pinyin', location);
  _expectEqual(value, 'neutralToneWithFive', true, location);
  final stage = _requiredString(value, 'stage', location);
  final style = _requiredString(value, 'style', location);
  if (!allowedStages.contains(stage) || !allowedStyles.contains(style)) {
    throw UpstreamFixtureFormatException(
      '$location has unsupported stage/style `$stage`/`$style`',
    );
  }
  return ChineseFixturePinyinCall(
    input: _requiredString(value, 'input', location),
    stage: stage,
    style: style,
    output: _requiredStringList(value, 'output', location),
  );
}

ChineseFixtureSearchCall _parseChineseSearchCall(
  Map<String, Object?> value,
  String location,
) {
  _expectExactKeys(value, const <String>{
    'input',
    'kind',
    'output',
    'stage',
  }, location);
  _expectEqual(value, 'kind', 'jieba.cut_for_search', location);
  _expectEqual(value, 'stage', 'tone-sandhi', location);
  return ChineseFixtureSearchCall(
    input: _requiredString(value, 'input', location),
    output: _requiredStringList(value, 'output', location),
  );
}

VietnameseFixtureBackendInput _parseVietnameseBackendInput(
  Map<String, Object?> value,
  String location,
) {
  _expectExactKeys(value, const <String>{
    'input',
    'kind',
    'schemaVersion',
    'tokens',
  }, location);
  _expectEqual(value, 'kind', VietnameseFixtureBackendInput.kind, location);
  _expectEqual(
    value,
    'schemaVersion',
    VietnameseFixtureBackendInput.schemaVersion,
    location,
  );
  final rawTokens = _requiredList(value, 'tokens', location);
  final tokens = <String>[];
  for (var index = 0; index < rawTokens.length; index++) {
    final token = rawTokens[index];
    if (token is! String || token.isEmpty) {
      throw UpstreamFixtureFormatException(
        '$location.tokens[$index] must be a non-empty string',
      );
    }
    tokens.add(token);
  }
  return VietnameseFixtureBackendInput._(
    input: _requiredString(value, 'input', location),
    tokens: tokens,
  );
}

bool _requiredBool(Map<String, Object?> map, String key, String location) {
  final value = map[key];
  if (value is! bool) {
    throw UpstreamFixtureFormatException('$location.$key must be a boolean');
  }
  return value;
}

num _requiredNumber(Map<String, Object?> map, String key, String location) {
  final value = map[key];
  if (value is! num) {
    throw UpstreamFixtureFormatException('$location.$key must be a number');
  }
  return value;
}

String? _requiredNullableString(
  Map<String, Object?> map,
  String key,
  String location,
) {
  final value = map[key];
  if (value != null && value is! String) {
    throw UpstreamFixtureFormatException(
      '$location.$key must be a string or null',
    );
  }
  return value as String?;
}

num? _requiredNullableNumber(
  Map<String, Object?> map,
  String key,
  String location,
) {
  final value = map[key];
  if (value != null && value is! num) {
    throw UpstreamFixtureFormatException(
      '$location.$key must be a number or null',
    );
  }
  return value as num?;
}

List<Object?> _requiredList(
  Map<String, Object?> map,
  String key,
  String location,
) {
  final value = map[key];
  if (value is! List<Object?>) {
    throw UpstreamFixtureFormatException('$location.$key must be an array');
  }
  return value;
}

List<String> _requiredStringList(
  Map<String, Object?> map,
  String key,
  String location,
) {
  final values = _requiredList(map, key, location);
  if (values.any((value) => value is! String)) {
    throw UpstreamFixtureFormatException(
      '$location.$key must contain only strings',
    );
  }
  return values.cast<String>();
}

List<int> _requiredNonNegativeIntList(
  Map<String, Object?> map,
  String key,
  String location,
) {
  final values = _requiredList(map, key, location);
  final result = <int>[];
  for (var index = 0; index < values.length; index++) {
    final value = values[index];
    if (value is! int || value < 0) {
      throw UpstreamFixtureFormatException(
        '$location.$key[$index] must be a non-negative integer',
      );
    }
    result.add(value);
  }
  return result;
}

void _expectExactKeys(
  Map<String, Object?> map,
  Set<String> expected,
  String location,
) {
  final actual = map.keys.toSet();
  if (!actual.containsAll(expected) || !expected.containsAll(actual)) {
    final sortedExpected = expected.toList()..sort();
    final sortedActual = actual.toList()..sort();
    throw UpstreamFixtureFormatException(
      '$location must contain exactly $sortedExpected, got $sortedActual',
    );
  }
}

const Set<String> _pyopenjtalkWordKeys = <String>{
  'acc',
  'cform',
  'chain_flag',
  'chain_rule',
  'ctype',
  'mora_size',
  'orig',
  'pos',
  'pos_group1',
  'pos_group2',
  'pos_group3',
  'pron',
  'read',
  'string',
};

const Set<String> _englishRawTokenKeys = <String>{
  '_',
  'end_ts',
  'phonemes',
  'start_ts',
  'tag',
  'text',
  'whitespace',
};

const Set<String> _englishMetadataRequiredKeys = <String>{
  'is_head',
  'num_flags',
  'prespace',
};

const Set<String> _englishMetadataAllowedKeys = <String>{
  ..._englishMetadataRequiredKeys,
  'rating',
  'stress',
};
