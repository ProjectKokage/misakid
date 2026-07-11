// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

/// Maximum accepted JSON configuration size.
const int maximumBartEnglishConfigBytes = 1024 * 1024;

/// Maximum accepted F32 safetensors resource size.
const int maximumBartEnglishWeightsBytes = 16 * 1024 * 1024;

/// Maximum input scalars permitted by the architecture whitelist.
const int maximumBartEnglishInputCodePoints = 62;

/// Pinned Transformers-compatible default total decoder sequence length.
const int defaultBartEnglishMaximumGenerationLength = 20;

const int maximumBartEnglishPathUtf8Bytes = 32768;
