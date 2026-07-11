import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('generated Vietnamese data is byte-for-byte reproducible', () async {
    final python = Platform.isWindows ? 'python' : 'python3';
    final commands = <(String, List<String>)>[
      (
        Platform.resolvedExecutable,
        const <String>[
          'run',
          'tool/generators/generate_vietnamese_data.dart',
          '--check',
        ],
      ),
      (
        python,
        const <String>[
          'tool/generators/generate_vietnamese_phonology_data.py',
          '--check',
        ],
      ),
      (
        python,
        const <String>[
          'tool/generators/generate_vietnamese_cleaner_tables.py',
          '--check',
        ],
      ),
    ];

    for (final (executable, arguments) in commands) {
      final result = await Process.run(executable, arguments);
      expect(
        result.exitCode,
        0,
        reason:
            '$executable ${arguments.join(' ')}\n'
            '${result.stdout}${result.stderr}',
      );
    }
  });
}
