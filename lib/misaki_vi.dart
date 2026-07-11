/// Vietnamese APIs for the pure, backend-injected Misaki Dart pipeline.
///
/// The phonology and cleaner are bundled and run offline. Applications must
/// supply an underthesea-compatible tokenizer; an English fallback is
/// optional and is never discovered or downloaded automatically.
///
/// ```dart
/// final engine = VietnameseG2pEngine(tokenizer: tokenizerBackend);
/// final result = engine.convert('xin chào');
/// print(result.phonemes);
/// ```
library;

export 'misaki.dart';
export 'src/languages/vi/backends.dart'
    show VietnameseEnglishFallbackBackend, VietnameseTokenizerBackend;
export 'src/languages/vi/engine.dart' show VietnameseG2pEngine;
export 'src/languages/vi/inventory.dart' show vietnamesePhonemeInventory;
export 'src/languages/vi/options.dart'
    show VietnameseDialect, VietnameseOptions, VietnameseToneType;
