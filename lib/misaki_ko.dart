/// Korean APIs for the pure, backend-injected Misaki g2pkc pipeline.
///
/// No MeCab implementation, Korean morphology dictionary, NLTK runtime, or
/// CMUdict resource is bundled. Applications must inject both narrow provider
/// contracts explicitly.
///
/// ```dart
/// final engine = KoreanG2pkcEngine(
///   morphology: morphologyBackend,
///   cmuPronunciations: cmuPronunciationProvider,
/// );
/// final result = engine.convert('안녕하세요.');
/// print(result.phonemes);
/// ```
library;

export 'misaki.dart';
export 'src/languages/ko/backends.dart'
    show
        KoreanCmuPronunciation,
        KoreanCmuPronunciationProvider,
        KoreanMorphologyBackend,
        KoreanMorphologyToken;
export 'src/languages/ko/engine.dart' show KoreanG2pkcEngine;
export 'src/languages/ko/inventory.dart' show koreanPhonemeInventory;
export 'src/languages/ko/jamo.dart'
    show composeKoreanJamo, decomposeKoreanHangul;
export 'src/languages/ko/numerals.dart'
    show convertKoreanNumerals, spellKoreanNumber;
