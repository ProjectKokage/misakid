import 'dart:io';

import 'package:misakid_bart_en/misakid_bart_en.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

void main() {
  late BartEnglishBackend backend;

  setUpAll(() async {
    backend = await BartEnglishBackend.open(
      configPath: syntheticFixturePath('config.json'),
      weightsPath: syntheticFixturePath('model.safetensors'),
      identity: syntheticIdentity(),
      maximumGenerationLength: 5,
    );
  });

  test(
    'opens once and synchronously pronounces through the public boundary',
    () {
      final result = backend.pronounce(
        const MisakiToken(text: 'ab', tag: 'NN', whitespace: ''),
      );
      final firstCase =
          (syntheticExpected()['generationCases']! as List<Object?>).first!
              as Map<String, Object?>;
      expect(result.phonemes, firstCase['phonemes']);
      expect(result.rating, 1);
      expect(backend.info.name, 'external-bart-english');
      expect(
        backend.info.details['verification'],
        'experimental-caller-reviewed-resources',
      );
      expect(
        backend.info.details['weightsSha256'],
        syntheticIdentity().weightsSha256,
      );
    },
  );

  test('maps missing graphemes to ID 3 without deleting the call', () {
    final unknownCase =
        (syntheticExpected()['generationCases']! as List<Object?>)[1]!
            as Map<String, Object?>;
    expect(unknownCase['input'], '😀');
    expect(unknownCase['inputIds'], <int>[1, 3, 2]);
    final result = backend.pronounce(
      const MisakiToken(text: '😀', tag: 'NN', whitespace: ''),
    );
    expect(result.rating, 1);
    expect(result.phonemes, unknownCase['phonemes']);
  });

  test('stops immediately when the independent model emits EOS', () async {
    const weightsFile = 'model-early-eos.safetensors';
    final earlyBackend = await BartEnglishBackend.open(
      configPath: syntheticFixturePath('config.json'),
      weightsPath: syntheticFixturePath(weightsFile),
      identity: syntheticIdentity(weightsFile: weightsFile),
      maximumGenerationLength: 5,
    );
    final expected =
        syntheticExpected()['earlyEosCase']! as Map<String, Object?>;
    expect(expected['generatedIds'], <int>[1, 2]);
    expect(
      earlyBackend
          .pronounce(const MisakiToken(text: 'ab', tag: 'NN', whitespace: ''))
          .phonemes,
      expected['phonemes'],
    );
  });

  test('rejects invalid Unicode and overlong input with typed failures', () {
    expect(
      () => backend.pronounce(
        MisakiToken(
          text: String.fromCharCode(0xD800),
          tag: 'NN',
          whitespace: '',
        ),
      ),
      throwsA(isA<BackendFailureException>()),
    );
    expect(
      () => backend.pronounce(
        const MisakiToken(text: 'aaaaaaa', tag: 'NN', whitespace: ''),
      ),
      throwsA(isA<BackendFailureException>()),
    );
    expect(
      () => backend.pronounce(
        MisakiToken(text: 'a' * 100000, tag: 'NN', whitespace: ''),
      ),
      throwsA(isA<BackendFailureException>()),
    );
  });

  test(
    'requires absolute paths and a model-bounded generation length',
    () async {
      expect(
        () => BartEnglishBackend.open(
          configPath: 'config.json',
          weightsPath: syntheticFixturePath('model.safetensors'),
          identity: syntheticIdentity(),
          maximumGenerationLength: 5,
        ),
        throwsA(isA<InvalidConfigurationException>()),
      );
      expect(
        () => BartEnglishBackend.open(
          configPath: '/${'a' * 100000}',
          weightsPath: syntheticFixturePath('model.safetensors'),
          identity: syntheticIdentity(),
          maximumGenerationLength: 5,
        ),
        throwsA(isA<InvalidConfigurationException>()),
      );
      expect(
        () => BartEnglishBackend.open(
          configPath: syntheticFixturePath('config.json'),
          weightsPath: syntheticFixturePath('model.safetensors'),
          identity: syntheticIdentity(),
          maximumGenerationLength: 9,
        ),
        throwsA(isA<InvalidConfigurationException>()),
      );
    },
  );

  test('rejects wrong digest, wrong size, missing files, and links', () async {
    final identity = syntheticIdentity();
    final wrongDigest = BartEnglishResourceIdentity(
      name: identity.name,
      version: identity.version,
      configSizeBytes: identity.configSizeBytes,
      configSha256: '0' * 64,
      weightsSizeBytes: identity.weightsSizeBytes,
      weightsSha256: identity.weightsSha256,
    );
    expect(
      () => BartEnglishBackend.open(
        configPath: syntheticFixturePath('config.json'),
        weightsPath: syntheticFixturePath('model.safetensors'),
        identity: wrongDigest,
        maximumGenerationLength: 5,
      ),
      throwsA(isA<MalformedDataException>()),
    );
    final wrongSize = BartEnglishResourceIdentity(
      name: identity.name,
      version: identity.version,
      configSizeBytes: identity.configSizeBytes + 1,
      configSha256: identity.configSha256,
      weightsSizeBytes: identity.weightsSizeBytes,
      weightsSha256: identity.weightsSha256,
    );
    expect(
      () => BartEnglishBackend.open(
        configPath: syntheticFixturePath('config.json'),
        weightsPath: syntheticFixturePath('model.safetensors'),
        identity: wrongSize,
        maximumGenerationLength: 5,
      ),
      throwsA(isA<MalformedDataException>()),
    );

    final missing = '${Directory.systemTemp.path}/misakid-bart-does-not-exist';
    expect(
      () => BartEnglishBackend.open(
        configPath: missing,
        weightsPath: syntheticFixturePath('model.safetensors'),
        identity: identity,
        maximumGenerationLength: 5,
      ),
      throwsA(isA<BackendUnavailableException>()),
    );

    final temporary = await Directory.systemTemp.createTemp(
      'misakid-bart-link-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final link = Link('${temporary.path}/config.json');
    await link.create(syntheticFixturePath('config.json'));
    expect(
      () => BartEnglishBackend.open(
        configPath: link.path,
        weightsPath: syntheticFixturePath('model.safetensors'),
        identity: identity,
        maximumGenerationLength: 5,
      ),
      throwsA(isA<MalformedDataException>()),
    );
  });
}
