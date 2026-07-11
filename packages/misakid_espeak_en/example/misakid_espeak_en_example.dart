import 'package:misakid_espeak_en/misakid_espeak_en.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 3) {
    throw ArgumentError(
      'Expected: <adapter-dylib> <espeak-dylib> <espeak-ng-data>',
    );
  }
  final backend = await EspeakEnglishBackend.open(
    adapterLibraryPath: arguments[0],
    espeakLibraryPath: arguments[1],
    dataPath: arguments[2],
  );
  try {
    print(backend.phonemize('blorptastic', dialect: EnglishDialect.american));
  } finally {
    backend.close();
  }
}
