import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('generated English lexicons are byte-for-byte reproducible', () async {
    final result = await Process.run(Platform.resolvedExecutable, const [
      'run',
      'tool/generators/generate_english_lexicons.dart',
      '--check',
    ]);

    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  });
}
