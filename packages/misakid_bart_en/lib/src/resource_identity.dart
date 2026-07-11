// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'package:misakid/misaki.dart';

final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

/// Caller-reviewed identity of one configuration/weights pair.
///
/// This value is deliberately not a catalog entry. The adapter has no built-in
/// model identities: callers must obtain, review, and identify every resource
/// themselves.
final class BartEnglishResourceIdentity {
  /// Creates an exact external-resource identity.
  BartEnglishResourceIdentity({
    required this.name,
    required this.version,
    required this.configSizeBytes,
    required this.configSha256,
    required this.weightsSizeBytes,
    required this.weightsSha256,
  }) {
    if (!_isSafeLabel(name) || !_isSafeLabel(version)) {
      throw const InvalidConfigurationException(
        'BART resource name and version must be non-empty printable labels.',
      );
    }
    if (configSizeBytes <= 0 || weightsSizeBytes <= 0) {
      throw const InvalidConfigurationException(
        'BART resource byte sizes must be positive.',
      );
    }
    if (!_sha256Pattern.hasMatch(configSha256) ||
        !_sha256Pattern.hasMatch(weightsSha256)) {
      throw const InvalidConfigurationException(
        'BART resource SHA-256 values must be 64 lowercase hexadecimal characters.',
      );
    }
  }

  /// Human-readable, caller-controlled model name.
  final String name;

  /// Caller-controlled resource version or revision.
  final String version;

  /// Exact configuration byte size.
  final int configSizeBytes;

  /// Exact lowercase SHA-256 of the configuration bytes.
  final String configSha256;

  /// Exact safetensors byte size.
  final int weightsSizeBytes;

  /// Exact lowercase SHA-256 of the safetensors bytes.
  final String weightsSha256;
}

bool _isSafeLabel(String value) {
  if (value.trim().isEmpty || value.length > 128) return false;
  final units = value.codeUnits;
  for (var index = 0; index < units.length; index++) {
    final unit = units[index];
    if (unit < 0x20 || unit == 0x7F) {
      return false;
    }
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (index + 1 >= units.length ||
          units[index + 1] < 0xDC00 ||
          units[index + 1] > 0xDFFF) {
        return false;
      }
      index++;
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      return false;
    }
  }
  return true;
}
