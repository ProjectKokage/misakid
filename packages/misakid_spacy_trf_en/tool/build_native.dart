// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'generate_native_tensor_manifest.dart' as tensor_manifest;

Future<void> main(List<String> arguments) async {
  final options = _parseArguments(arguments);
  final packageLibrary = await Isolate.resolvePackageUri(
    Uri.parse('package:misakid_spacy_trf_en/misakid_spacy_trf_en.dart'),
  );
  if (packageLibrary == null || packageLibrary.scheme != 'file') {
    throw StateError(
      'Could not resolve the misakid_spacy_trf_en package root.',
    );
  }
  final packageRoot = Directory(
    _canonicalDirectoryPath(File.fromUri(packageLibrary).parent.parent),
  );
  var buildRoot = Directory(
    _canonicalDirectoryPath(Directory(options.buildPath)),
  );
  _ensureSafeBuildLocation(buildRoot, packageRoot);
  if (Abi.current() != Abi.macosArm64) {
    stderr.writeln('misakid_spacy_trf_en v1 builds only on macOS arm64.');
    exitCode = 64;
    return;
  }

  await tensor_manifest.main(<String>['--check']);
  buildRoot.createSync(recursive: true);
  buildRoot = Directory(buildRoot.resolveSymbolicLinksSync());
  _ensureSafeBuildLocation(buildRoot, packageRoot);
  final cmakeBuild = Directory('${buildRoot.path}/cmake');
  final installRoot = Directory('${buildRoot.path}/install');
  if (cmakeBuild.existsSync()) cmakeBuild.deleteSync(recursive: true);
  if (installRoot.existsSync()) installRoot.deleteSync(recursive: true);

  await _run(<String>[
    options.cmakeExecutable,
    '-S',
    '${packageRoot.path}/native',
    '-B',
    cmakeBuild.path,
    '-DCMAKE_BUILD_TYPE=Release',
  ]);
  await _run(<String>[
    options.cmakeExecutable,
    '--build',
    cmakeBuild.path,
    '--config',
    'Release',
    '--parallel',
  ]);
  await _run(<String>[
    options.cmakeExecutable,
    '--install',
    cmakeBuild.path,
    '--config',
    'Release',
    '--prefix',
    installRoot.path,
  ]);
  final library = File('${installRoot.path}/lib/libmisakid_spacy_trf_en.dylib');
  if (!library.existsSync()) {
    throw StateError(
      'CMake completed without installing libmisakid_spacy_trf_en.dylib.',
    );
  }
  stdout.writeln(library.path);
}

final class _Options {
  const _Options({required this.buildPath, required this.cmakeExecutable});

  final String buildPath;
  final String cmakeExecutable;
}

_Options _parseArguments(List<String> arguments) {
  String? buildPath;
  var cmakeExecutable = 'cmake';
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (index + 1 >= arguments.length) _usage('Missing value for $argument.');
    switch (argument) {
      case '--build-dir':
        buildPath = arguments[++index];
      case '--cmake':
        cmakeExecutable = arguments[++index];
      default:
        _usage('Unknown argument: $argument');
    }
  }
  if (buildPath == null) _usage('--build-dir is required.');
  return _Options(buildPath: buildPath, cmakeExecutable: cmakeExecutable);
}

Never _usage(String message) {
  stderr.writeln(message);
  stderr.writeln(
    'Usage: dart run tool/build_native.dart '
    '--build-dir <dedicated-output> [--cmake <executable>]',
  );
  exit(64);
}

void _ensureSafeBuildLocation(Directory buildRoot, Directory packageRoot) {
  final build = _comparisonPath(buildRoot.path);
  final package = _comparisonPath(packageRoot.path);
  if (_containsPath(build, package) ||
      _containsPath(package, build) ||
      buildRoot.parent.path == buildRoot.path) {
    throw ArgumentError.value(
      buildRoot.path,
      '--build-dir',
      'Must be a dedicated directory outside the package root.',
    );
  }
}

String _canonicalDirectoryPath(Directory directory) {
  var current = Directory(_normalizedAbsolutePath(directory.path));
  final missingSegments = <String>[];
  while (!current.existsSync()) {
    final parent = current.parent;
    if (parent.path == current.path) {
      throw ArgumentError.value(
        directory.path,
        'path',
        'Could not resolve an existing filesystem ancestor.',
      );
    }
    missingSegments.add(_basename(current.path));
    current = parent;
  }
  var resolved = current.resolveSymbolicLinksSync();
  for (final segment in missingSegments.reversed) {
    resolved = '$resolved${Platform.pathSeparator}$segment';
  }
  return _normalizedAbsolutePath(resolved);
}

String _normalizedAbsolutePath(String path) => Uri.file(
  Directory(path).absolute.path,
  windows: Platform.isWindows,
).normalizePath().toFilePath(windows: Platform.isWindows);

String _comparisonPath(String path) =>
    Platform.isWindows ? path.toLowerCase() : path;

bool _containsPath(String child, String parent) =>
    child == parent || child.startsWith('$parent${Platform.pathSeparator}');

String _basename(String path) {
  final index = path.lastIndexOf(Platform.pathSeparator);
  return index < 0 ? path : path.substring(index + 1);
}

Future<void> _run(List<String> command) async {
  final result = await Process.run(command.first, command.sublist(1));
  if (result.stdout case final String stdoutText when stdoutText.isNotEmpty) {
    stdout.write(stdoutText);
  }
  if (result.stderr case final String stderrText when stderrText.isNotEmpty) {
    stderr.write(stderrText);
  }
  if (result.exitCode != 0) {
    throw ProcessException(
      command.first,
      command.sublist(1),
      'Native build command failed.',
      result.exitCode,
    );
  }
}
