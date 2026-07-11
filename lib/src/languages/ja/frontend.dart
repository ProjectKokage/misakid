import '../../core/backend.dart';

/// One immutable word produced by a Japanese morphological/accent frontend.
///
/// This is the narrow data boundary consumed by [JapaneseFrontendBackend]. A
/// real adapter may translate pyopenjtalk dictionaries into this type, but the
/// pure-Dart package does not discover or provide a native adapter.
final class JapaneseFrontendWord {
  /// Creates a frontend word.
  const JapaneseFrontendWord({
    required this.surface,
    required this.partOfSpeech,
    required this.pronunciation,
    required this.accent,
    required this.moraSize,
    required this.chainFlag,
  });

  /// Surface text reported by the frontend.
  final String surface;

  /// Part-of-speech label reported by the frontend.
  final String partOfSpeech;

  /// Katakana pronunciation reported by the frontend.
  final String pronunciation;

  /// Accent nucleus reported by the frontend.
  final int accent;

  /// Frontend-reported mora count.
  final int moraSize;

  /// Whether the frontend's raw chain flag selects the preceding phrase.
  ///
  /// A pyopenjtalk adapter should set this to `rawChainFlag == 1`.
  final bool chainFlag;
}

/// Explicit backend boundary for pyopenjtalk-style Japanese frontend data.
///
/// Implementations perform morphology and accent analysis outside the pure
/// pipeline. This contract does not imply that a real pyopenjtalk adapter is
/// bundled or supported by the package.
abstract interface class JapaneseFrontendBackend implements MisakiBackend {
  /// Analyzes [text] into words in exact source order.
  List<JapaneseFrontendWord> analyze(String text);
}
