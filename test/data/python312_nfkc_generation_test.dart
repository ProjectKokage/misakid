import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'generated Python 3.12 NFKC data is byte-for-byte reproducible',
    () async {
      final result = await Process.run(Platform.resolvedExecutable, const [
        'run',
        'tool/generators/generate_python312_nfkc.dart',
        '--check',
      ]);

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    },
  );
}
