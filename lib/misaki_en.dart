/// English APIs for the pure, backend-injected Misaki Dart pipeline.
///
/// This entrypoint exposes the offline pinned lexicon provider. It does not
/// bundle a tokenizer/tagger, spaCy, eSpeak, or a model fallback; applications
/// must still supply those optional backend boundaries explicitly.
library;

export 'misaki.dart';
export 'src/languages/en/backends.dart'
    show
        AsyncEnglishFallbackBackend,
        EnglishFallbackBackend,
        EnglishPronunciation,
        EnglishPronunciationBackend,
        EnglishTokenizerBackend;
export 'src/languages/en/context.dart' show EnglishTokenContext;
export 'src/languages/en/engine.dart'
    show AsyncEnglishG2pEngine, EnglishG2pEngine;
export 'src/languages/en/espeak_fallback.dart'
    show EnglishEspeakBackend, EnglishEspeakFallback;
export 'src/languages/en/inventory.dart' show englishPhonemeInventory;
export 'src/languages/en/morphology.dart' show EnglishDialect;
export 'src/languages/en/pinned_lexicon.dart' show PinnedEnglishLexicon;
export 'src/languages/en/preprocess.dart'
    show
        EnglishInlineControl,
        EnglishInlinePreprocessor,
        EnglishNumberFlagsControl,
        EnglishPreprocessResult,
        EnglishPronunciationControl,
        EnglishStressControl;
export 'src/languages/en/render.dart' show EnglishPhonemeVersion;
