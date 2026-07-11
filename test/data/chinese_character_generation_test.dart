import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'generated Chinese character map is byte-for-byte reproducible',
    () async {
      final result = await Process.run(Platform.resolvedExecutable, const [
        'run',
        'tool/generators/generate_chinese_character_map.dart',
        '--check',
      ]);

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    },
  );
}
