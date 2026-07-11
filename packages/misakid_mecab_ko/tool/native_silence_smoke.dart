// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:misakid_mecab_ko/src/native_bindings.dart';

void main(List<String> arguments) {
  if (arguments.length != 2) exit(64);
  final library = MecabKoNativeLibrary.load(arguments[0]);
  final analyzer = MecabKoNativeAnalyzer.create(
    library: library,
    dictionaryPath: arguments[1],
    maxInputBytes: 1024 * 1024,
  );
  try {
    if (analyzer.analyzeRaw('안녕하세요.').isEmpty) exit(1);
  } finally {
    analyzer.close();
  }

  try {
    final invalid = MecabKoNativeAnalyzer.create(
      library: library,
      dictionaryPath: '/definitely-missing/secret-dictionary',
      maxInputBytes: 1024,
    );
    invalid.close();
    exit(1);
  } on MecabKoNativeException {
    // Expected. The smoke test itself deliberately emits no process output.
  }
}
