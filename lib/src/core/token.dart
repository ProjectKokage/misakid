import 'constants.dart';
import 'metadata.dart';

/// Immutable token shared by all language engines.
final class MisakiToken {
  /// Creates a token.
  const MisakiToken({
    required this.text,
    required this.tag,
    required this.whitespace,
    this.phonemes,
    this.startTimeSeconds,
    this.endTimeSeconds,
    this.metadata,
  });

  /// Source text represented by this token.
  final String text;

  /// Backend tag such as a part-of-speech label.
  final String tag;

  /// Exact whitespace rendered after this token.
  final String whitespace;

  /// Token phonemes, or `null` when pronunciation is unavailable.
  final String? phonemes;

  /// Optional source-aligned start timestamp, in seconds.
  final double? startTimeSeconds;

  /// Optional source-aligned end timestamp, in seconds.
  final double? endTimeSeconds;

  /// Typed language-specific details, when the selected mode supplies them.
  final TokenMetadata? metadata;

  /// Renders this token with the selected unknown marker.
  String render({String unknownMarker = defaultUnknownMarker}) =>
      (phonemes ?? unknownMarker) + whitespace;
}
