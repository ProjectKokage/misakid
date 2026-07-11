import 'result.dart';

/// A synchronous, reusable grapheme-to-phoneme engine.
abstract interface class G2pEngine {
  /// Converts [text] into exact phoneme output and optional token details.
  G2pResult convert(String text);
}

/// A synchronous G2P engine whose unresolved-token marker is inspectable.
///
/// Frontends with a fixed unknown-token contract use this capability to
/// validate the engine's real configuration instead of trusting a separate
/// caller-supplied flag.
abstract interface class UnknownMarkerG2pEngine implements G2pEngine {
  /// Exact text rendered for a token that remains unresolved.
  String get unknownMarker;
}

/// A reusable engine whose backend requires asynchronous work.
///
/// Process- and model-backed adapters implement this interface instead of
/// making the pure in-process [G2pEngine] API return `FutureOr`.
abstract interface class AsyncG2pEngine {
  /// Converts [text] into exact phoneme output and optional token details.
  Future<G2pResult> convert(String text);
}
