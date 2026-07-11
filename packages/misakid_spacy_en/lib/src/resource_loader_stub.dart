// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'package:misakid/misaki.dart';

import 'resource_identity.dart';

/// Reports that path-backed loading is unavailable without `dart:io`.
Future<
  ({
    SpacyEnglishTokenizerResources resources,
    Future<void> Function() ensureUnchanged,
  })
>
loadSpacyEnglishTokenizerResources(String modelDirectoryPath) async {
  throw const BackendUnavailableException(
    'Path-backed spaCy English loading requires dart:io; use '
    'PureDartSpacyEnglishTokenizer.fromResources instead.',
  );
}

/// Reports that path-backed loading is unavailable without `dart:io`.
Future<
  ({
    SpacyEnglishModelResources resources,
    Future<void> Function() ensureUnchanged,
  })
>
loadSpacyEnglishModelResources(String modelDirectoryPath) async {
  throw const BackendUnavailableException(
    'Path-backed spaCy English loading requires dart:io; use '
    'PureDartSpacyEnglishTokenizerBackend.fromResources instead.',
  );
}
