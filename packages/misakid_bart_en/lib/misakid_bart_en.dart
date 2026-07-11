// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

/// Experimental pure-Dart one-layer BART English fallback adapter.
///
/// The adapter requires caller-provisioned, exactly identified resources. It
/// does not bundle or endorse any third-party model weights.
library;

export 'package:misakid/misaki_en.dart';
export 'src/backend.dart'
    show
        BartEnglishBackend,
        defaultBartEnglishMaximumGenerationLength,
        maximumBartEnglishConfigBytes,
        maximumBartEnglishInputCodePoints,
        maximumBartEnglishWeightsBytes;
export 'src/resource_identity.dart' show BartEnglishResourceIdentity;
