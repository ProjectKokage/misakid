import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('build tool rejects a package descendant before creating it', () async {
    final probe = Directory(
      '${Directory.current.path}${Platform.pathSeparator}'
      '.build-path-rejection-$pid',
    );
    expect(probe.existsSync(), isFalse);
    final result = await _runBuilder(probe.path);
    expect(result.exitCode, isNot(0));
    expect(
      '${result.stdout}${result.stderr}',
      contains('dedicated directory outside the source and package roots'),
    );
    expect(probe.existsSync(), isFalse);
  });

  test(
    'build tool resolves symlink aliases before its deletion boundary',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'misakid-mecab-ja-build-path-',
      );
      try {
        final alias = Link('${temporary.path}/package-alias');
        await alias.create(Directory.current.absolute.path);
        final probe = Directory('${alias.path}/never-create-$pid');
        final result = await _runBuilder(probe.path);
        expect(result.exitCode, isNot(0));
        expect(
          '${result.stdout}${result.stderr}',
          contains('dedicated directory outside the source and package roots'),
        );
        expect(probe.existsSync(), isFalse);
      } finally {
        await temporary.delete(recursive: true);
      }
    },
    skip: Platform.isWindows
        ? 'Creating symlinks may require elevation.'
        : false,
  );
}

Future<ProcessResult> _runBuilder(String buildPath) =>
    Process.run(Platform.resolvedExecutable, <String>[
      'run',
      'tool/build_native.dart',
      '--source',
      Directory.current.absolute.path,
      '--build-dir',
      buildPath,
    ], workingDirectory: Directory.current.absolute.path);
