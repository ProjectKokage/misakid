import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'generated Python 3.11 case data is byte-for-byte reproducible',
    () async {
      final result = await Process.run(Platform.resolvedExecutable, const [
        'run',
        'tool/generators/generate_python311_case.dart',
        '--check',
      ]);

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    },
  );
}
