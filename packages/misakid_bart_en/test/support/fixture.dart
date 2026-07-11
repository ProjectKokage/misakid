import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:misakid_bart_en/misakid_bart_en.dart';

String syntheticFixturePath(String name) {
  final local = File('test/fixtures/synthetic/$name');
  if (local.existsSync()) return local.absolute.path;
  return File(
    'packages/misakid_bart_en/test/fixtures/synthetic/$name',
  ).absolute.path;
}

Map<String, Object?> syntheticManifest() =>
    jsonDecode(File(syntheticFixturePath('manifest.json')).readAsStringSync())
        as Map<String, Object?>;

BartEnglishResourceIdentity syntheticIdentity({
  String weightsFile = 'model.safetensors',
}) {
  final files = syntheticManifest()['files']! as Map<String, Object?>;
  final config = files['config.json']! as Map<String, Object?>;
  final weights = files[weightsFile]! as Map<String, Object?>;
  return BartEnglishResourceIdentity(
    name: 'misakid-bart-synthetic-v1:$weightsFile',
    version: 'fixture-1',
    configSizeBytes: config['bytes']! as int,
    configSha256: config['sha256']! as String,
    weightsSizeBytes: weights['bytes']! as int,
    weightsSha256: weights['sha256']! as String,
  );
}

Uint8List syntheticConfigBytes() =>
    File(syntheticFixturePath('config.json')).readAsBytesSync();

Uint8List syntheticWeightsBytes({String weightsFile = 'model.safetensors'}) =>
    File(syntheticFixturePath(weightsFile)).readAsBytesSync();

Map<String, Object?> syntheticExpected() =>
    jsonDecode(File(syntheticFixturePath('expected.json')).readAsStringSync())
        as Map<String, Object?>;
