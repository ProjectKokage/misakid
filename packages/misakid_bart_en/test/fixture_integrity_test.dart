import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

void main() {
  test('committed synthetic artifacts match their generated manifest', () {
    final manifest = syntheticManifest();
    expect(manifest['schemaVersion'], 3);
    expect(
      manifest['oracle'],
      'transformers.BartForConditionalGeneration on CPU',
    );
    final versions = manifest['backendVersions']! as Map<String, Object?>;
    expect(versions['torch'], '2.6.0');
    expect(versions['transformers'], '4.51.3');
    expect(versions['safetensors'], '0.5.3');
    expect(versions['attentionImplementation'], 'sdpa');
    expect(versions['python'], '3.12.11');
    expect(versions['pythonImplementation'], 'CPython');
    expect(versions['machine'], 'arm64');
    expect(versions['system'], 'Darwin');
    expect(
      manifest['requirements'],
      'tool/reference/requirements-en-espeak-py312.txt',
    );
    final files = manifest['files']! as Map<String, Object?>;
    expect(files.keys.toSet(), <String>{
      'config.json',
      'expected.json',
      'model-early-eos.safetensors',
      'model.safetensors',
    });
    for (final entry in files.entries) {
      final expected = entry.value! as Map<String, Object?>;
      final bytes = File(syntheticFixturePath(entry.key)).readAsBytesSync();
      expect(bytes, hasLength(expected['bytes']! as int), reason: entry.key);
      expect(
        sha256.convert(bytes).toString(),
        expected['sha256'],
        reason: entry.key,
      );
    }
  });
}
