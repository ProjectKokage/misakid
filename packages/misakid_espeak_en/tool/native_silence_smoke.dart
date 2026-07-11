// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:misakid_espeak_en/misakid_espeak_en.dart';
import 'package:misakid_espeak_en/src/native_bindings.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 3) {
    exitCode = 64;
    return;
  }
  final adapterPath = arguments[0];
  final runtimePath = arguments[1];
  final dataPath = arguments[2];
  EspeakEnglishBackend? backend;
  try {
    backend = await EspeakEnglishBackend.open(
      adapterLibraryPath: adapterPath,
      espeakLibraryPath: runtimePath,
      dataPath: dataPath,
    );
    if (backend.phonemize('blorptastic', dialect: EnglishDialect.american) !=
        'blɔː^ɹptˈe^ɪstɪk ') {
      exitCode = 11;
      return;
    }
    try {
      backend.phonemize('a\u0000b', dialect: EnglishDialect.american);
      exitCode = 12;
      return;
    } on BackendFailureException {
      // Expected bounded Dart-side input rejection.
    }

    final nativeLibrary = EspeakEnglishNativeLibrary.load(adapterPath);
    try {
      EspeakEnglishNativeContext.create(
        library: nativeLibrary,
        runtimeLibraryPath: runtimePath,
        dataPath: '/definitely/missing/espeak-ng-data',
        maxInputBytes: 1024,
        maxOutputBytes: 1024,
      );
      exitCode = 13;
      return;
    } on EspeakEnglishNativeException {
      // Expected silent native initialization failure.
    }
  } on Object {
    exitCode = 20;
  } finally {
    backend?.close();
  }
}
