import 'dart:io';

import 'package:misakid_openjtalk/src/native_bindings.dart';

void main(List<String> arguments) {
  if (arguments.length != 2) exit(64);
  final library = OpenJtalkNativeLibrary.load(arguments[0]);
  final frontend = OpenJtalkNativeFrontend.create(
    library: library,
    dictionaryPath: arguments[1],
    maxInputBytes: 1024,
  );
  try {
    final words = frontend.analyzeRaw('猫😀犬。');
    if (words.length != 4) exit(1);
    try {
      frontend.analyzeRaw('猫\u0000犬');
      exit(2);
    } on OpenJtalkNativeException {
      // Expected explicit divergence from upstream C-string truncation.
    }
  } finally {
    frontend.close();
  }

  try {
    OpenJtalkNativeFrontend.create(
      library: library,
      dictionaryPath: '/definitely/not/a/dictionary',
      maxInputBytes: 1024,
    );
    exit(3);
  } on OpenJtalkNativeException {
    // The native Mecab_load error must use the structured channel only.
  }
}
