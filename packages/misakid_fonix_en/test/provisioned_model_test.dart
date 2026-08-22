@Tags(<String>['provisioned'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:misakid_fonix_en/misakid_fonix_en.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  final manifestPath = Platform.environment['MISAKID_FONIX_EN_MANIFEST'];
  final modelPath = Platform.environment['MISAKID_FONIX_EN_MODEL'];
  final parityPath = Platform.environment['MISAKID_FONIX_EN_PARITY'];
  final runtimePath = Platform.environment['MISAKID_FONIX_EN_RUNTIME'];
  final missing = <String>[
    if (manifestPath == null) 'MISAKID_FONIX_EN_MANIFEST',
    if (modelPath == null) 'MISAKID_FONIX_EN_MODEL',
    if (parityPath == null) 'MISAKID_FONIX_EN_PARITY',
    if (runtimePath == null) 'MISAKID_FONIX_EN_RUNTIME',
  ];

  test(
    'runs the exported parity corpus through a real Fonix isolate session',
    () async {
      final manifestFile = _regularFile(manifestPath!);
      final modelFile = _regularFile(modelPath!);
      final parityFile = _regularFile(parityPath!);
      final runtimeFile = _regularFile(runtimePath!);
      final parityBytes = parityFile.readAsBytesSync();
      if (parityBytes.isEmpty || parityBytes.length > 256 * 1024) {
        fail('The provisioned parity file has an invalid byte length.');
      }
      final parity = _object(
        decodeStrictJson(utf8.decode(parityBytes, allowMalformed: false)),
        'parity root',
      );
      final rawCases = parity['cases'];
      if (rawCases is! List<Object?> ||
          rawCases.isEmpty ||
          rawCases.length > 32) {
        fail('The provisioned parity case list is invalid.');
      }

      final backend = await FonixEnglishG2pBackend.open(
        manifestBytes: manifestFile.readAsBytesSync(),
        modelBytes: modelFile.readAsBytesSync(),
        runtimeSource: OrtRuntimeSource.file(
          absolutePath: runtimeFile.absolute.path,
          allowedRoot: runtimeFile.parent.absolute.path,
        ),
      );
      try {
        expect(backend.profile.modelId, 'misakid-en-us-g2p');
        expect(backend.info.details['provider'], 'cpu');
        expect(parity['modelSha256'], backend.profile.modelSha256);
        for (final rawCase in rawCases) {
          final record = _object(rawCase, 'parity case');
          final word = record['word'];
          final prediction = record['prediction'];
          if (word is! String ||
              word.isEmpty ||
              word.runes.length > backend.profile.maximumGraphemeCodePoints ||
              prediction is! String ||
              prediction.isEmpty) {
            fail('The provisioned parity case is malformed.');
          }
          final result = await backend.pronounce(
            MisakiToken(
              text: word,
              tag: 'NN',
              whitespace: '',
              metadata: const EnglishTokenMetadata(isHead: true),
            ),
          );
          expect(result.phonemes, prediction, reason: word);
          expect(result.rating, 1);
        }
        final firstClose = backend.close();
        expect(identical(firstClose, backend.close()), isTrue);
        await firstClose;
      } finally {
        await backend.close();
      }
    },
    skip: missing.isEmpty
        ? false
        : 'Requires provisioned paths: ${missing.join(', ')}.',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

File _regularFile(String filePath) {
  if (!path.isAbsolute(filePath)) {
    fail('Provisioned paths must be absolute.');
  }
  final file = File(filePath);
  if (file.statSync().type != FileSystemEntityType.file) {
    fail('A provisioned path does not name a regular file.');
  }
  return file;
}

Map<String, Object?> _object(Object? value, String location) {
  if (value is! Map<String, Object?>) {
    fail('The provisioned $location must be a JSON object.');
  }
  return value;
}
