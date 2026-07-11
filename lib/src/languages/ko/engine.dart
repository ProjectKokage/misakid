// Dart adaptation of hexgrad/misaki/misaki/{ko.py,g2pkc/g2pk.py} at
// fba1236595f2d2bf21d414ba6e57d25256afada3 (Misaki 0.9.4).
// Copied/adapted g2pkc material originates from 5Hyeons/StyleTTS2 and
// Kyubyong/g2pK under Apache-2.0. Modifications: pure staged Dart pipeline,
// immutable results, and explicitly injected morphology/CMUdict boundaries.

import '../../core/engine.dart';
import '../../core/errors.dart';
import '../../core/result.dart';
import 'backends.dart';
import 'english.dart';
import 'idioms.dart';
import 'jamo.dart';
import 'morphology.dart';
import 'numerals.dart';
import 'rules.dart';

/// Pure deterministic Korean g2pkc pipeline with injected external data.
///
/// This implements pinned `KOG2P`, including its `use_dict=True` morphology
/// path and `tokens == null` result contract. The package does not bundle or
/// discover MeCab, a Korean morphology dictionary, NLTK, or CMUdict.
final class KoreanG2pkcEngine implements G2pEngine {
  /// Creates a Korean engine using explicit morphology and CMUdict providers.
  const KoreanG2pkcEngine({
    required this.morphology,
    required this.cmuPronunciations,
  });

  /// Korean morphology/POS provider.
  final KoreanMorphologyBackend morphology;

  /// First-pronunciation CMUdict lookup provider for embedded English.
  final KoreanCmuPronunciationProvider cmuPronunciations;

  @override
  G2pResult convert(String text) {
    final idiomatic = applyKoreanG2pkcIdioms(text);
    final convertedEnglish = convertKoreanEnglish(idiomatic, _lookupEnglish);
    final morphologyTokens = _analyze(convertedEnglish);
    final annotated = annotateKoreanMorphology(
      convertedEnglish,
      morphologyTokens,
    );
    final numbered = convertKoreanNumerals(annotated);
    final decomposed = decomposeKoreanHangul(numbered);
    final phonemes = applyKoreanG2pkcRules(decomposed);
    return G2pResult(phonemes: phonemes, tokens: null);
  }

  KoreanCmuPronunciation? _lookupEnglish(String word) {
    final backendInfo = cmuPronunciations.info;
    late final KoreanCmuPronunciation? pronunciation;
    try {
      pronunciation = cmuPronunciations.lookup(word);
    } on MisakiException {
      rethrow;
    } on Exception catch (error) {
      throw BackendFailureException(
        'Korean CMUdict ${backendInfo.name} ${backendInfo.version} failed '
        'while looking up `$word`.',
        cause: error,
      );
    }
    if (pronunciation != null &&
        (pronunciation.arpabet.isEmpty ||
            pronunciation.arpabet.any((symbol) => symbol.isEmpty))) {
      throw BackendFailureException(
        'Korean CMUdict ${backendInfo.name} ${backendInfo.version} returned '
        'an invalid empty pronunciation for `$word`.',
      );
    }
    return pronunciation;
  }

  List<KoreanMorphologyToken> _analyze(String text) {
    final backendInfo = morphology.info;
    late final List<KoreanMorphologyToken> tokens;
    try {
      tokens = morphology.pos(text);
    } on MisakiException {
      rethrow;
    } on Exception catch (error) {
      throw BackendFailureException(
        'Korean morphology ${backendInfo.name} ${backendInfo.version} failed.',
        cause: error,
      );
    }
    for (var index = 0; index < tokens.length; index++) {
      final token = tokens[index];
      if (token.surface.isEmpty || token.tag.isEmpty) {
        throw BackendFailureException(
          'Korean morphology ${backendInfo.name} ${backendInfo.version} '
          'returned invalid token $index with an empty surface or tag.',
        );
      }
    }
    return List<KoreanMorphologyToken>.unmodifiable(tokens);
  }
}
