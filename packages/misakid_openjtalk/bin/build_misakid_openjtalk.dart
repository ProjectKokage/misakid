// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import '../tool/build_native.dart' as builder;

/// Builds the verified frontend-only native library from explicit source.
Future<void> main(List<String> arguments) => builder.main(arguments);
