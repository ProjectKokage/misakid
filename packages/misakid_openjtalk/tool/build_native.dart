// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const _expectedSourceFileCount = 139;
const _expectedSourceBytes = 5381473;
const _expectedSourceTreeSha256 =
    'dea0f240fad8dc8b9ea1984920a4d64a48227a40c2924a3c545eaeca50357857';
const _sourcePrefix = 'lib/open_jtalk/src/';

const _expectedLicenseHashes = <String, String>{
  'LICENSE.md':
      'c38083a4d51c1ea86e08b3303a984d0c23718c5ac214058af705814d30f4bb5b',
  '${_sourcePrefix}COPYING':
      '14f380a0db8dce139fdcfb731d21e993a31a00b68907515d1c54a5f356241343',
  '${_sourcePrefix}mecab/COPYING':
      '05e94c185a3e31f0c658f7011132be952b6d1a4d588b682f92da380e0a290650',
};

Future<void> main(List<String> arguments) async {
  final options = _parseArguments(arguments);
  final packageLibrary = await Isolate.resolvePackageUri(
    Uri.parse('package:misakid_openjtalk/misakid_openjtalk.dart'),
  );
  if (packageLibrary == null || packageLibrary.scheme != 'file') {
    throw StateError('Could not resolve the misakid_openjtalk package root.');
  }

  final packageRoot = Directory(
    _canonicalDirectoryPath(File.fromUri(packageLibrary).parent.parent),
  );
  final sourceRoot = Directory(
    _canonicalDirectoryPath(Directory(options.sourcePath)),
  );
  var buildRoot = Directory(
    _canonicalDirectoryPath(Directory(options.buildPath)),
  );
  _ensureSafeBuildLocation(sourceRoot, buildRoot, packageRoot);

  if (Abi.current() != Abi.macosArm64) {
    stderr.writeln('misakid_openjtalk v1 builds only on macOS arm64.');
    exitCode = 64;
    return;
  }

  buildRoot.createSync(recursive: true);
  buildRoot = Directory(buildRoot.resolveSymbolicLinksSync());
  _ensureSafeBuildLocation(sourceRoot, buildRoot, packageRoot);

  final sourceFiles = await _verifySource(sourceRoot);
  final stagedSource = Directory('${buildRoot.path}/staged_source');
  final cmakeBuild = Directory('${buildRoot.path}/cmake');
  final installRoot = Directory('${buildRoot.path}/install');

  if (stagedSource.existsSync()) stagedSource.deleteSync(recursive: true);
  if (cmakeBuild.existsSync()) cmakeBuild.deleteSync(recursive: true);
  if (installRoot.existsSync()) installRoot.deleteSync(recursive: true);
  stagedSource.createSync(recursive: true);

  for (final sourcePath in sourceFiles) {
    final relative = sourcePath.substring(_sourcePrefix.length);
    final destination = File('${stagedSource.path}/$relative');
    destination.parent.createSync(recursive: true);
    await File('${sourceRoot.path}/$sourcePath').copy(destination.path);
  }
  await _applySafetyPatches(stagedSource);

  await _run(<String>[
    options.cmakeExecutable,
    '-S',
    '${packageRoot.path}/native',
    '-B',
    cmakeBuild.path,
    '-DMISAKID_OPENJTALK_SOURCE_DIR=${stagedSource.path}',
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

  final library = File('${installRoot.path}/lib/libmisakid_openjtalk.dylib');
  if (!library.existsSync()) {
    throw StateError(
      'CMake completed without installing libmisakid_openjtalk.dylib.',
    );
  }
  stdout.writeln(library.path);
}

final class _Options {
  const _Options({
    required this.sourcePath,
    required this.buildPath,
    required this.cmakeExecutable,
  });

  final String sourcePath;
  final String buildPath;
  final String cmakeExecutable;
}

_Options _parseArguments(List<String> arguments) {
  String? sourcePath;
  String? buildPath;
  var cmakeExecutable = 'cmake';
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (index + 1 >= arguments.length) {
      _usage('Missing value for $argument.');
    }
    switch (argument) {
      case '--source':
        sourcePath = arguments[++index];
      case '--build-dir':
        buildPath = arguments[++index];
      case '--cmake':
        cmakeExecutable = arguments[++index];
      default:
        _usage('Unknown argument: $argument');
    }
  }
  if (sourcePath == null || buildPath == null) {
    _usage('Both --source and --build-dir are required.');
  }
  return _Options(
    sourcePath: sourcePath,
    buildPath: buildPath,
    cmakeExecutable: cmakeExecutable,
  );
}

Never _usage(String message) {
  stderr.writeln(message);
  stderr.writeln(
    'Usage: dart run tool/build_native.dart '
    '--source <pyopenjtalk-0.4.1-source> --build-dir <output>',
  );
  exit(64);
}

Future<List<String>> _verifySource(Directory sourceRoot) async {
  final manifest = File('${sourceRoot.path}/pyopenjtalk.egg-info/SOURCES.txt');
  if (!manifest.existsSync()) {
    throw StateError(
      'The source directory has no pyopenjtalk.egg-info/SOURCES.txt.',
    );
  }
  final paths =
      (await manifest.readAsLines())
          .where((path) => path.startsWith(_sourcePrefix))
          .toList(growable: false)
        ..sort();
  if (paths.length != _expectedSourceFileCount) {
    throw StateError(
      'Expected $_expectedSourceFileCount Open JTalk source files, '
      'found ${paths.length}.',
    );
  }

  var totalBytes = 0;
  final treeRecords = BytesBuilder(copy: false);
  for (final path in paths) {
    final file = File('${sourceRoot.path}/$path');
    if (!file.existsSync()) throw StateError('Missing source file: $path');
    final bytes = await file.readAsBytes();
    totalBytes += bytes.length;
    final fileHash = sha256.convert(bytes).toString();
    treeRecords
      ..add(utf8.encode(path.substring(_sourcePrefix.length)))
      ..addByte(0)
      ..add(ascii.encode(fileHash))
      ..addByte(10);
  }
  final treeHash = sha256.convert(treeRecords.takeBytes()).toString();
  if (totalBytes != _expectedSourceBytes ||
      treeHash != _expectedSourceTreeSha256) {
    throw StateError(
      'Open JTalk source identity mismatch: $totalBytes bytes, $treeHash.',
    );
  }

  for (final entry in _expectedLicenseHashes.entries) {
    final bytes = await File('${sourceRoot.path}/${entry.key}').readAsBytes();
    final actual = sha256.convert(bytes).toString();
    if (actual != entry.value) {
      throw StateError('License identity mismatch: ${entry.key}.');
    }
  }
  return paths;
}

void _ensureSafeBuildLocation(
  Directory sourceRoot,
  Directory buildRoot,
  Directory packageRoot,
) {
  final source = _comparisonPath(sourceRoot.path);
  final build = _comparisonPath(buildRoot.path);
  final package = _comparisonPath(packageRoot.path);
  if (_containsPath(build, source) ||
      _containsPath(source, build) ||
      _containsPath(build, package) ||
      _containsPath(package, build) ||
      buildRoot.parent.path == buildRoot.path) {
    throw ArgumentError.value(
      buildRoot.path,
      '--build-dir',
      'Must be a dedicated directory outside the source and package roots.',
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

String _normalizedAbsolutePath(String path) {
  final absolute = Directory(path).absolute.path;
  return Uri.file(
    absolute,
    windows: Platform.isWindows,
  ).normalizePath().toFilePath(windows: Platform.isWindows);
}

String _comparisonPath(String path) =>
    Platform.isWindows ? path.toLowerCase() : path;

bool _containsPath(String child, String parent) =>
    child == parent || child.startsWith('$parent${Platform.pathSeparator}');

String _basename(String path) {
  final index = path.lastIndexOf(Platform.pathSeparator);
  return index < 0 ? path : path.substring(index + 1);
}

Future<void> _applySafetyPatches(Directory stagedSource) async {
  await _replaceExactlyOnce(
    File('${stagedSource.path}/njd/njd_node.c'),
    '''NJDNode *NJDNode_insert(NJDNode * prev, NJDNode * next, NJDNode * node)
{
   NJDNode *tail;

   if (prev == NULL || next == NULL) {
      fprintf(stderr, "ERROR: NJDNode_insert() in njd_node.c: NJDNodes are not specified.\\n");
      exit(1);
   }
   for (tail = node; tail->next != NULL; tail = tail->next);
   prev->next = node;
   node->prev = prev;
   next->prev = tail;
   tail->next = next;

   return tail;
}''',
    '''/* Modified by misakid: report fatal graph errors through the bounded
 * adapter diagnostic instead of terminating the Dart process. The valid
 * upstream path is unchanged. */
NJDNode *NJDNode_insert(NJDNode * prev, NJDNode * next, NJDNode * node)
{
   NJDNode *tail;
   NJDNode *discard;

   if (prev == NULL || node == NULL) {
      misakid_openjtalk_report_native_error("digit", "Invalid NJD insertion graph.");
      return prev;
   }
   if (next == NULL) {
      misakid_openjtalk_report_native_error("digit", "Invalid terminal NJD insertion.");
      while (node != NULL) {
         discard = node->next;
         NJDNode_clear(node);
         free(node);
         node = discard;
      }
      return prev;
   }
   for (tail = node; tail->next != NULL; tail = tail->next);
   prev->next = node;
   node->prev = prev;
   next->prev = tail;
   tail->next = next;

   return tail;
}''',
  );
  await _replaceExactlyOnce(
    File('${stagedSource.path}/njd_set_long_vowel/njd_set_long_vowel.c'),
    '''   if (byte < 0) {
      fprintf(stderr, "ERROR: detect_byte() in njd_set_long_vowel.c: Wrong character.\\n");
      exit(1);
   }
   return byte;''',
    '''   if (byte < 0) {
      /* Modified by misakid: the legacy estimator is disabled upstream, but
       * retain a non-terminating structured failure if it is re-enabled. */
      misakid_openjtalk_report_native_error("long-vowel", "Invalid long-vowel input byte.");
      return 1;
   }
   return byte;''',
  );
}

Future<void> _replaceExactlyOnce(
  File file,
  String original,
  String replacement,
) async {
  final source = await file.readAsString();
  final first = source.indexOf(original);
  if (first < 0 || source.indexOf(original, first + original.length) >= 0) {
    throw StateError('Safety patch context mismatch: ${file.path}.');
  }
  await file.writeAsString(source.replaceFirst(original, replacement));
}

Future<void> _run(List<String> command) async {
  final process = await Process.start(
    command.first,
    command.skip(1).toList(growable: false),
    mode: ProcessStartMode.inheritStdio,
  );
  final result = await process.exitCode;
  if (result != 0) {
    throw ProcessException(
      command.first,
      command.skip(1).toList(),
      'Native build command exited unsuccessfully.',
      result,
    );
  }
}
