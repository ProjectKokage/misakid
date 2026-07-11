/// Base class for failures exposed by Misaki Dart APIs.
sealed class MisakiException implements Exception {
  /// Creates a package exception with an actionable [message].
  const MisakiException(this.message, {this.cause});

  /// Human-readable description of the failure and how to address it.
  final String message;

  /// Original failure when one is available.
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// The selected options do not form a supported configuration.
final class InvalidConfigurationException extends MisakiException {
  /// Creates an invalid-configuration failure.
  const InvalidConfigurationException(super.message, {super.cause});
}

/// A required explicitly configured backend is not available.
final class BackendUnavailableException extends MisakiException {
  /// Creates an unavailable-backend failure.
  const BackendUnavailableException(super.message, {super.cause});
}

/// Generated or copied runtime data failed validation.
final class MalformedDataException extends MisakiException {
  /// Creates a malformed-data failure.
  const MalformedDataException(super.message, {super.cause});
}

/// A configured backend failed while processing input.
final class BackendFailureException extends MisakiException {
  /// Creates a backend-processing failure.
  const BackendFailureException(super.message, {super.cause});
}
