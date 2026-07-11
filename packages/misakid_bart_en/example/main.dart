import 'package:misakid_bart_en/misakid_bart_en.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 6) {
    throw ArgumentError(
      'Expected: CONFIG WEIGHTS CONFIG_BYTES CONFIG_SHA256 '
      'WEIGHTS_BYTES WEIGHTS_SHA256',
    );
  }
  final backend = await BartEnglishBackend.open(
    configPath: arguments[0],
    weightsPath: arguments[1],
    identity: BartEnglishResourceIdentity(
      name: 'caller-reviewed-model',
      version: '1',
      configSizeBytes: int.parse(arguments[2]),
      configSha256: arguments[3],
      weightsSizeBytes: int.parse(arguments[4]),
      weightsSha256: arguments[5],
    ),
  );
  final result = backend.pronounce(
    const MisakiToken(text: 'example', tag: 'NN', whitespace: ''),
  );
  // ignore: avoid_print
  print(result.phonemes);
}
