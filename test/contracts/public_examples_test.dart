import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final examples =
      Directory('example')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList(growable: false)
        ..sort((left, right) => left.path.compareTo(right.path));

  test('every public example executes offline', () async {
    expect(examples, isNotEmpty);
    for (final example in examples) {
      final result = await Process.run(Platform.resolvedExecutable, <String>[
        'run',
        example.path,
      ]);
      expect(
        result.exitCode,
        0,
        reason:
            '${example.path}\nstdout:\n${result.stdout}\n'
            'stderr:\n${result.stderr}',
      );
    }
  });

  test('versioned benchmark emits its machine-readable schema', () async {
    final result = await Process.run(Platform.resolvedExecutable, const [
      'run',
      'benchmark/misakid_benchmark.dart',
      '--iterations=1',
    ]);

    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    final report = jsonDecode(result.stdout as String) as Map<String, Object?>;
    expect(report['schemaVersion'], 1);
    expect(
      report['upstreamCommit'],
      'fba1236595f2d2bf21d414ba6e57d25256afada3',
    );
    expect(report['iterations'], 1);
    expect(report, containsPair('coldEnglish', isA<Map<String, Object?>>()));
    expect(report, containsPair('warmEnglish', isA<Map<String, Object?>>()));
    expect(
      report,
      containsPair('warmJapaneseNumbers', isA<Map<String, Object?>>()),
    );
  });
}
