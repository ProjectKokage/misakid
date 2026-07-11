// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:misakid/misaki.dart';

/// Reads exactly [expectedBytes] and rejects either EOF or one extra byte.
///
/// This package-internal operation allocates no buffer larger than the caller's
/// already validated expected size.
Future<Uint8List> readExactlyBoundedFile(File file, int expectedBytes) async {
  const maximumChunkBytes = 64 * 1024;
  final result = Uint8List(expectedBytes);
  final reader = await file.open(mode: FileMode.read);
  try {
    var offset = 0;
    while (offset < expectedBytes) {
      final chunk = await reader.read(
        math.min(maximumChunkBytes, expectedBytes - offset),
      );
      if (chunk.isEmpty) {
        throw const MalformedDataException(
          'A configured BART resource became shorter while being read.',
        );
      }
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    if ((await reader.read(1)).isNotEmpty) {
      throw const MalformedDataException(
        'A configured BART resource grew beyond its declared byte size.',
      );
    }
    return result;
  } finally {
    await reader.close();
  }
}
