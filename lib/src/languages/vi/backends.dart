import '../../core/backend.dart';

/// Explicit tokenizer boundary matching underthesea's `tokenize` function.
abstract interface class VietnameseTokenizerBackend implements MisakiBackend {
  /// Returns exact ordered token strings for cleaned [text].
  List<String> tokenize(String text);
}

/// Optional English fallback used only after Vietnamese transcription fails.
abstract interface class VietnameseEnglishFallbackBackend
    implements MisakiBackend {
  /// Returns exact phonemes for lowercase ASCII [token], or `null` on a miss.
  String? phonemize(String token);
}
