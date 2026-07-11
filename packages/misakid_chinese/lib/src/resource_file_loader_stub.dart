// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'package:misakid/misaki.dart';

import 'resource_file.dart';

/// Fails explicitly when path-backed resources are unavailable.
Future<LoadedChineseResourceFile> loadChineseResourceFile({
  required String path,
  required String family,
  required String label,
  required int maximumBytes,
  int? expectedBytes,
}) {
  throw BackendUnavailableException(
    '$family path-backed resources require a dart:io platform; use the byte-backed resource API instead.',
  );
}
