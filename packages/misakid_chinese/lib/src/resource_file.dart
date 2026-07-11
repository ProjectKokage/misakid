// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

/// Internal platform-file snapshot returned by the conditional loader.
final class LoadedChineseResourceFile {
  /// Creates a loaded file with an opaque revalidation callback.
  const LoadedChineseResourceFile({
    required this.resolvedPath,
    required this.bytes,
    required Future<void> Function() ensureUnchanged,
  }) : _ensureUnchanged = ensureUnchanged;

  /// Canonical path used to detect duplicate configured resources.
  final String resolvedPath;

  /// Complete bounded file contents.
  final Uint8List bytes;

  final Future<void> Function() _ensureUnchanged;

  /// Rejects a file changed since its initial snapshot.
  Future<void> ensureUnchanged() => _ensureUnchanged();
}
