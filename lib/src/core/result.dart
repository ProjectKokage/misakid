import 'token.dart';

/// Exact output from one grapheme-to-phoneme conversion.
final class G2pResult {
  /// Creates a result and defensively freezes [tokens].
  G2pResult({required this.phonemes, required List<MisakiToken>? tokens})
    : tokens = tokens == null ? null : List<MisakiToken>.unmodifiable(tokens);

  /// Exact rendered phoneme string.
  final String phonemes;

  /// Token details.
  ///
  /// `null` means the selected backend cannot provide token details. An empty
  /// list means tokenization was available and produced no tokens.
  final List<MisakiToken>? tokens;
}
