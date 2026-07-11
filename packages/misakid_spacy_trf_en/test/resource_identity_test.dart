import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:misakid/misaki.dart';
import 'package:misakid_spacy_trf_en/src/resource_identity.dart';
import 'package:test/test.dart';

void main() {
  final provisionedRoot =
      Platform.environment['MISAKID_SPACY_TRF_EN_MODEL_DIR'] ??
      Platform.environment['MISAKI_SPACY_TRF_EN_MODEL_DIR'];
  final provisionedSkip = provisionedRoot == null
      ? 'Set MISAKID_SPACY_TRF_EN_MODEL_DIR to en_core_web_trf-3.8.0.'
      : false;

  test('pins every retained resource and the streamed transformer model', () {
    expect(spacyTransformerModelVersion, '3.8.0');
    expect(spacyTransformerTokenizerSizeBytes, 77066);
    expect(
      spacyTransformerTokenizerSha256,
      'b014e8bba4958b120af2d0c1c63eabb7c00379f2bacaf10df7c5325efd2ea467',
    );
    expect(spacyTransformerVocabLookupsSizeBytes, 70040);
    expect(
      spacyTransformerVocabLookupsSha256,
      'fce9c883c56165f29573cc938c2a1c9d417ac61bd8f56b671dd5f7996de70682',
    );
    expect(spacyTransformerModelSizeBytes, 497343046);
    expect(
      spacyTransformerModelSha256,
      '2b7061c623f424486e5dddcff79276927127cee339cc6a9d26d87837c3e6074a',
    );
    expect(spacyTransformerTaggerModelSizeBytes, 151450);
    expect(
      spacyTransformerTaggerModelSha256,
      'a489a41d998a6c042eaa279b6b823cd24b40854faf602e696d280788ed62f84c',
    );
    expect(spacyTransformerByteBpeOffsetBytes, 416);
    expect(spacyTransformerByteBpeSizeBytes, 1063863);
    expect(
      spacyTransformerByteBpeSha256,
      '3a937453afcd04229fc5e32d7304c117781d4c48f1e7c87a603194e2077576f0',
    );
  });

  test('rejects relative, NUL, and malformed-Unicode roots', () async {
    for (final path in <String>[
      'en_core_web_trf-3.8.0',
      '${Directory.systemTemp.path}\u0000model',
      '${Directory.systemTemp.path}\uD800model',
    ]) {
      await expectLater(
        SpacyTransformerResourceSnapshot.validate(path),
        throwsA(isA<InvalidConfigurationException>()),
        reason: path.codeUnits.toString(),
      );
    }
  });

  test(
    'distinguishes missing, non-directory, and linked model roots',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'misakid-spacy-trf-root-',
      );
      addTearDown(() => temporary.delete(recursive: true));

      await expectLater(
        SpacyTransformerResourceSnapshot.validate('${temporary.path}/missing'),
        throwsA(isA<BackendUnavailableException>()),
      );

      final file = File('${temporary.path}/file')..writeAsBytesSync(<int>[0]);
      await expectLater(
        SpacyTransformerResourceSnapshot.validate(file.path),
        throwsA(isA<InvalidConfigurationException>()),
      );

      if (!Platform.isWindows) {
        final real = await Directory('${temporary.path}/real').create();
        final link = Link('${temporary.path}/link');
        await link.create(real.path);
        await expectLater(
          SpacyTransformerResourceSnapshot.validate(link.path),
          throwsA(isA<InvalidConfigurationException>()),
        );
      }
    },
  );

  test(
    'rejects linked, wrong-size, and same-size tampered resources',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'misakid-spacy-trf-resource-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final temporaryPath = await temporary.resolveSymbolicLinks();

      final source = File('$temporaryPath/source')..writeAsBytesSync(<int>[0]);
      final linkedRoot = await Directory('$temporaryPath/linked').create();
      if (!Platform.isWindows) {
        await Link('${linkedRoot.path}/tokenizer').create(source.path);
        await expectLater(
          SpacyTransformerResourceSnapshot.validate(linkedRoot.path),
          throwsA(isA<MalformedDataException>()),
        );
      }

      final tamperedRoot = await Directory('$temporaryPath/tampered').create();
      final tokenizer = File('${tamperedRoot.path}/tokenizer');
      tokenizer.writeAsBytesSync(<int>[0]);
      await expectLater(
        SpacyTransformerResourceSnapshot.validate(tamperedRoot.path),
        throwsA(isA<MalformedDataException>()),
      );

      tokenizer.writeAsBytesSync(
        Uint8List(spacyTransformerTokenizerSizeBytes),
        flush: true,
      );
      await expectLater(
        SpacyTransformerResourceSnapshot.validate(tamperedRoot.path),
        throwsA(isA<MalformedDataException>()),
      );
    },
  );

  test(
    'streams exact provisioned identities and retains only bounded bytes',
    () async {
      final snapshot = await SpacyTransformerResourceSnapshot.validate(
        provisionedRoot!,
      );
      expect(snapshot.modelDirectoryPath, provisionedRoot);
      expect(
        snapshot.transformerModelPath,
        '$provisionedRoot${Platform.pathSeparator}transformer'
        '${Platform.pathSeparator}model',
      );
      expect(snapshot.tokenizerBytes, hasLength(77066));
      expect(snapshot.vocabLookupsBytes, hasLength(70040));
      expect(snapshot.byteBpeBytes, hasLength(1063863));
      expect(snapshot.taggerModelBytes, hasLength(151450));
      expect(
        sha256.convert(snapshot.tokenizerBytes).toString(),
        spacyTransformerTokenizerSha256,
      );
      expect(
        sha256.convert(snapshot.vocabLookupsBytes).toString(),
        spacyTransformerVocabLookupsSha256,
      );
      expect(
        sha256.convert(snapshot.byteBpeBytes).toString(),
        spacyTransformerByteBpeSha256,
      );
      expect(
        sha256.convert(snapshot.taggerModelBytes).toString(),
        spacyTransformerTaggerModelSha256,
      );

      final mutableCopy = snapshot.tokenizerBytes;
      mutableCopy[0] ^= 0xff;
      expect(snapshot.tokenizerBytes[0], isNot(mutableCopy[0]));
      await snapshot.ensureUnchanged();
    },
    tags: 'provisioned',
    skip: provisionedSkip,
  );
}
