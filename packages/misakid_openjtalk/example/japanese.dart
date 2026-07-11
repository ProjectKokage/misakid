import 'dart:io';

import 'package:misakid/misaki_ja.dart';
import 'package:misakid_openjtalk/misakid_openjtalk.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length < 3) {
    stderr.writeln(
      'Usage: dart run example/japanese.dart '
      '<library.dylib> <dictionary-directory> <text>',
    );
    exitCode = 64;
    return;
  }
  final backend = await OpenJtalkFrontendBackend.open(
    libraryPath: arguments[0],
    dictionaryPath: arguments[1],
  );
  try {
    final engine = JapanesePyopenjtalkEngine(backend: backend);
    stdout.writeln(engine.convert(arguments.sublist(2).join(' ')).phonemes);
  } finally {
    backend.close();
  }
}
