import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  test(
    'generated Python 3.12 spaCy Unicode data is byte-for-byte reproducible',
    () async {
      final result = await Process.run(Platform.resolvedExecutable, const [
        'run',
        'tool/generators/generate_python312_spacy_unicode.dart',
        '--check',
      ]);

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    },
  );

  test('spaCy Unicode manifest identities match every recorded artifact', () {
    const manifestDirectory =
        'tool/upstream_data/python-3.12.11-unicode-15.0.0';
    final manifest =
        jsonDecode(File('$manifestDirectory/manifest.json').readAsStringSync())
            as Map<String, Object?>;
    final section = manifest['spacyUnicode']! as Map<String, Object?>;
    for (final field in <String>[
      'extractor',
      'canonicalData',
      'runtimeGenerator',
      'generatedRuntime',
      'generatedSharedRuntime',
      'reproducibilityTest',
    ]) {
      final artifact = section[field]! as Map<String, Object?>;
      final recordedPath = artifact['path']! as String;
      final path = field == 'canonicalData'
          ? '$manifestDirectory/$recordedPath'
          : recordedPath;
      expect(
        sha256.convert(File(path).readAsBytesSync()).toString(),
        artifact['sha256'],
        reason: '$field identity for $path',
      );
    }
  });
}
