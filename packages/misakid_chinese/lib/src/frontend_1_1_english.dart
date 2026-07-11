// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'package:misakid/misaki_en.dart';
import 'package:misakid/misaki_zh.dart';

/// Pinned frontend-1.1 composition with an injected English tokenizer.
///
/// This is the exact upstream `en_callable` shape used by the accepted
/// `frontend-1.1-en-small-no-fallback` profile: English preprocessing is on,
/// the pinned lexicon is selected by [englishDialect], and unresolved English
/// tokens render [unknownMarker] without a fallback. The returned outer token
/// list is always `null`, as in upstream `ZHG2P(version: '1.1')`.
///
/// The accepted profile supplies `PureDartSpacyEnglishTokenizerBackend` from
/// `package:misakid_spacy_en`; the interface remains injected so this package
/// does not load or discover model resources.
///
/// ```dart
/// final engine = ChineseFrontend11EnglishG2pEngine(
///   chineseBackend: chineseBackend,
///   englishTokenizer: englishTokenizer,
/// );
/// final result = engine.convert('你好 Hello world');
/// ```
final class ChineseFrontend11EnglishG2pEngine implements G2pEngine {
  /// Creates the fixed no-fallback composition from explicit backends.
  factory ChineseFrontend11EnglishG2pEngine({
    required ChineseFrontend11Backend chineseBackend,
    required EnglishTokenizerBackend englishTokenizer,
    EnglishDialect englishDialect = EnglishDialect.american,
    EnglishPhonemeVersion englishPhonemeVersion = EnglishPhonemeVersion.legacy,
    String unknownMarker = defaultUnknownMarker,
  }) {
    final english = EnglishG2pEngine(
      tokenizer: englishTokenizer,
      pronunciation: PinnedEnglishLexicon(dialect: englishDialect),
      phonemeVersion: englishPhonemeVersion,
      unknownMarker: unknownMarker,
      preprocessInput: true,
    );
    return ChineseFrontend11EnglishG2pEngine._(
      chineseBackend: chineseBackend,
      englishTokenizer: englishTokenizer,
      englishDialect: englishDialect,
      englishPhonemeVersion: englishPhonemeVersion,
      unknownMarker: unknownMarker,
      delegate: ChineseFrontend11G2pEngine(
        backend: chineseBackend,
        unknownMarker: unknownMarker,
        englishG2p: (text) => english.convert(text).phonemes,
      ),
    );
  }

  ChineseFrontend11EnglishG2pEngine._({
    required this.chineseBackend,
    required this.englishTokenizer,
    required this.englishDialect,
    required this.englishPhonemeVersion,
    required this.unknownMarker,
    required ChineseFrontend11G2pEngine delegate,
  }) : _delegate = delegate;

  /// Explicit Chinese frontend backend used by this engine.
  final ChineseFrontend11Backend chineseBackend;

  /// Explicit English tokenizer/tagger backend used by this engine.
  final EnglishTokenizerBackend englishTokenizer;

  /// American or British pinned lexicon behavior.
  final EnglishDialect englishDialect;

  /// Legacy or version-2 English phoneme rendering behavior.
  final EnglishPhonemeVersion englishPhonemeVersion;

  /// Marker shared by the Chinese and English stages.
  final String unknownMarker;

  final ChineseFrontend11G2pEngine _delegate;

  @override
  G2pResult convert(String text) => _delegate.convert(text);
}
