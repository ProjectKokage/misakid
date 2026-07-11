// Dart adaptation of the backend boundary in hexgrad/misaki/misaki/he.py at
// fba1236595f2d2bf21d414ba6e57d25256afada3 (Misaki 0.9.4, Apache-2.0).
//
// Modifications: replaced the imported Python Mishkal implementation with an
// explicit, side-effect-free Dart backend contract and typed failure handling.

import '../../core/backend.dart';
import '../../core/engine.dart';
import '../../core/errors.dart';
import '../../core/result.dart';

/// Options forwarded unchanged to a Hebrew phonemizer backend.
///
/// These are the two keyword options exposed by pinned `misaki/he.py`:
///
/// ```dart
/// const options = HebrewOptions(
///   preservePunctuation: false,
///   preserveStress: true,
/// );
/// ```
final class HebrewOptions {
  /// Creates Hebrew conversion options.
  const HebrewOptions({
    this.preservePunctuation = true,
    this.preserveStress = true,
  });

  /// Whether punctuation is retained in the phoneme output.
  final bool preservePunctuation;

  /// Whether stress marks are retained in the phoneme output.
  final bool preserveStress;
}

/// Explicit adapter boundary for Mishkal-equivalent Hebrew phonemization.
///
/// Implementations must validate their platform and resources before they are
/// supplied to [HebrewG2pEngine]. Misakid does not discover, download, or
/// bundle Mishkal or a Hebrew model.
abstract interface class HebrewPhonemizerBackend implements MisakiBackend {
  /// Phonemizes [text] using the requested preservation flags.
  String phonemize(
    String text, {
    required bool preservePunctuation,
    required bool preserveStress,
  });

  /// Exact phoneme inventory reported by this backend version.
  Set<String> phonemeInventory();
}

/// Hebrew G2P facade backed by an explicitly supplied phonemizer.
///
/// The pinned Python mode does not return token details, so successful results
/// always have `tokens == null`. For example, with an application-provided
/// backend named `backend`:
///
/// ```dart
/// final engine = HebrewG2pEngine(backend: backend);
/// final result = engine.convert('שָׁלוֹם');
/// ```
final class HebrewG2pEngine implements G2pEngine {
  /// Creates a Hebrew engine with an explicitly configured [backend].
  const HebrewG2pEngine({
    required this.backend,
    this.options = const HebrewOptions(),
  });

  /// Configured Mishkal-equivalent backend.
  final HebrewPhonemizerBackend backend;

  /// Flags applied to every conversion.
  final HebrewOptions options;

  @override
  G2pResult convert(String text) {
    try {
      final phonemes = backend.phonemize(
        text,
        preservePunctuation: options.preservePunctuation,
        preserveStress: options.preserveStress,
      );
      return G2pResult(phonemes: phonemes, tokens: null);
    } on MisakiException {
      rethrow;
    } on Exception catch (error) {
      throw BackendFailureException(
        'Hebrew backend ${backend.info} failed to phonemize the input.',
        cause: error,
      );
    }
  }

  /// Returns a frozen copy of the backend's exact phoneme inventory.
  Set<String> phonemeInventory() {
    try {
      final inventory = backend.phonemeInventory();
      if (inventory.isEmpty) {
        throw MalformedDataException(
          'Hebrew backend ${backend.info} reported an empty phoneme inventory.',
        );
      }
      if (inventory.any((symbol) => symbol.isEmpty)) {
        throw MalformedDataException(
          'Hebrew backend ${backend.info} reported an empty phoneme symbol.',
        );
      }
      return Set<String>.unmodifiable(inventory);
    } on MisakiException {
      rethrow;
    } on Exception catch (error) {
      throw BackendFailureException(
        'Hebrew backend ${backend.info} failed to report its inventory.',
        cause: error,
      );
    }
  }
}
