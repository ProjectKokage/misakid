// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'resource_file.dart';
import 'resource_file_loader_stub.dart'
    if (dart.library.io) 'resource_file_loader_io.dart'
    as platform;

export 'resource_file.dart' show LoadedChineseResourceFile;

/// Loads one explicitly configured resource through the current platform.
Future<LoadedChineseResourceFile> loadChineseResourceFile({
  required String path,
  required String family,
  required String label,
  required int maximumBytes,
  int? expectedBytes,
}) => platform.loadChineseResourceFile(
  path: path,
  family: family,
  label: label,
  maximumBytes: maximumBytes,
  expectedBytes: expectedBytes,
);
