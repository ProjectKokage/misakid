import 'dart:io';

/// The size and timestamps of a file, captured to detect a change while the
/// file is read or after it was validated.
final class FileSnapshot {
  /// Creates a snapshot from already-read values.
  const FileSnapshot({
    required this.size,
    required this.modifiedMicroseconds,
    required this.changedMicroseconds,
  });

  /// Captures the values of [stat].
  factory FileSnapshot.fromStat(FileStat stat) => FileSnapshot(
    size: stat.size,
    modifiedMicroseconds: stat.modified.microsecondsSinceEpoch,
    changedMicroseconds: stat.changed.microsecondsSinceEpoch,
  );

  /// File size in bytes.
  final int size;

  /// Last modification time, in microseconds since the epoch.
  final int modifiedMicroseconds;

  /// Last status-change time, in microseconds since the epoch.
  final int changedMicroseconds;

  /// Whether [stat] still describes a regular file with the same size and
  /// timestamps.
  bool matches(FileStat stat) =>
      stat.type == FileSystemEntityType.file &&
      stat.size == size &&
      stat.modified.microsecondsSinceEpoch == modifiedMicroseconds &&
      stat.changed.microsecondsSinceEpoch == changedMicroseconds;
}
