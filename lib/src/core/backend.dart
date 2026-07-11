import 'errors.dart';

/// Stable identity information reported by an injected backend.
final class BackendInfo {
  /// Creates backend identity information.
  BackendInfo({
    required this.name,
    required this.version,
    Map<String, String> details = const <String, String>{},
  }) : details = Map<String, String>.unmodifiable(details) {
    if (name.trim().isEmpty || version.trim().isEmpty) {
      throw const InvalidConfigurationException(
        'Backend name and version must both be non-empty.',
      );
    }
    if (details.entries.any(
      (entry) => entry.key.trim().isEmpty || entry.value.trim().isEmpty,
    )) {
      throw const InvalidConfigurationException(
        'Backend detail keys and values must be non-empty.',
      );
    }
  }

  /// Backend or adapter name.
  final String name;

  /// Backend version, model revision, or another stable version identifier.
  final String version;

  /// Additional stable diagnostic values, such as a dictionary version.
  final Map<String, String> details;

  @override
  String toString() => '$name $version';
}

/// Common contract for explicitly supplied language backends.
abstract interface class MisakiBackend {
  /// Stable backend identity included in diagnostics and fixture metadata.
  BackendInfo get info;
}
