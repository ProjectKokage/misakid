// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const _expectedSourceFileCount = 236;
const _expectedSourceBytes = 7840684;
const _expectedSourceTreeSha256 =
    '9b870a921e8d80fa11eec1066d21c0960916fa617e77a8c83758223dfe28827f';

const _expectedLicenseHashes = <String, String>{
  'COPYING': '9ed8a017f2226b6f0d6dd6a1d25404800374a12c70e14a56ca9613176f78778e',
  'LGPL': '512d2d21b6b3384ba64781abb0208a1b87740bc31e2df48e2b206ddb7e4d5779',
  'BSD': '62f4b23450a9ad40e4db8063d45c1d13c78d07ca27c9ada62c4ca9c11c1f3e7b',
};

/// Verifies, patches, builds, and installs the pinned MeCab-ko adapter.
Future<void> main(List<String> arguments) async {
  final options = _parseArguments(arguments);
  final packageLibrary = await Isolate.resolvePackageUri(
    Uri.parse('package:misakid_mecab_ko/misakid_mecab_ko.dart'),
  );
  if (packageLibrary == null || packageLibrary.scheme != 'file') {
    throw StateError('Could not resolve the misakid_mecab_ko package root.');
  }

  final packageRoot = Directory(
    _canonicalDirectoryPath(File.fromUri(packageLibrary).parent.parent),
  );
  final sourceRoot = Directory(
    _canonicalExistingDirectoryPath(Directory(options.sourcePath)),
  );
  var buildRoot = Directory(
    _canonicalDirectoryPath(Directory(options.buildPath)),
  );
  _ensureSafeBuildLocation(sourceRoot, buildRoot, packageRoot);

  if (!Platform.isMacOS || Abi.current() != Abi.macosArm64) {
    stderr.writeln('misakid_mecab_ko v1 builds only on macOS arm64.');
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

  for (final directory in <Directory>[stagedSource, cmakeBuild, installRoot]) {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
  stagedSource.createSync(recursive: true);

  for (final source in sourceFiles) {
    final destination = File('${stagedSource.path}/${source.relativePath}');
    destination.parent.createSync(recursive: true);
    await destination.writeAsBytes(source.bytes, flush: true);
  }
  await _applySafetyPatch(stagedSource);

  await _run(<String>[
    options.cmakeExecutable,
    '-S',
    '${packageRoot.path}/native',
    '-B',
    cmakeBuild.path,
    '-DMISAKID_MECAB_KO_SOURCE_DIR=${stagedSource.path}',
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

  final library = File('${installRoot.path}/lib/libmisakid_mecab_ko.dylib');
  if (!library.existsSync()) {
    throw StateError(
      'CMake completed without installing libmisakid_mecab_ko.dylib.',
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
    'Usage: dart run bin/build_misakid_mecab_ko.dart '
    '--source <mecab-0.996-ko-0.9.2> --build-dir <output>',
  );
  exit(64);
}

final class _SourceSnapshot {
  const _SourceSnapshot({required this.relativePath, required this.bytes});

  final String relativePath;
  final Uint8List bytes;
}

Future<List<_SourceSnapshot>> _verifySource(Directory sourceRoot) async {
  final entities = await sourceRoot
      .list(recursive: true, followLinks: false)
      .toList();
  final files = <File>[];
  for (final entity in entities) {
    final type = await FileSystemEntity.type(entity.path, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw StateError('The MeCab-ko source tree must not contain links.');
    }
    if (type == FileSystemEntityType.file) {
      files.add(File(entity.path));
    } else if (type != FileSystemEntityType.directory) {
      throw StateError('The MeCab-ko source tree has an unsupported entry.');
    }
  }
  files.sort((left, right) => left.path.compareTo(right.path));
  if (files.length != _expectedSourceFileCount) {
    throw StateError(
      'Expected $_expectedSourceFileCount MeCab-ko source files, '
      'found ${files.length}.',
    );
  }

  var totalBytes = 0;
  final treeRecords = BytesBuilder(copy: false);
  final snapshots = <_SourceSnapshot>[];
  for (final file in files) {
    final before = await file.stat();
    final bytes = await file.readAsBytes();
    final after = await file.stat();
    if (!_sameFileState(before, after) || bytes.length != after.size) {
      throw StateError('The MeCab-ko source changed while it was read.');
    }
    final relativePath = file.path
        .substring(sourceRoot.path.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    totalBytes += bytes.length;
    final fileHash = sha256.convert(bytes).toString();
    treeRecords
      ..add(utf8.encode(relativePath))
      ..addByte(0)
      ..add(ascii.encode(fileHash))
      ..addByte(10);
    snapshots.add(_SourceSnapshot(relativePath: relativePath, bytes: bytes));
  }
  final treeHash = sha256.convert(treeRecords.takeBytes()).toString();
  if (totalBytes != _expectedSourceBytes ||
      treeHash != _expectedSourceTreeSha256) {
    throw StateError(
      'MeCab-ko source identity mismatch: $totalBytes bytes, $treeHash.',
    );
  }

  final byPath = <String, _SourceSnapshot>{
    for (final snapshot in snapshots) snapshot.relativePath: snapshot,
  };
  for (final entry in _expectedLicenseHashes.entries) {
    final source = byPath[entry.key];
    if (source == null ||
        sha256.convert(source.bytes).toString() != entry.value) {
      throw StateError('License identity mismatch: ${entry.key}.');
    }
  }
  return List<_SourceSnapshot>.unmodifiable(snapshots);
}

bool _sameFileState(FileStat left, FileStat right) =>
    left.type == FileSystemEntityType.file &&
    right.type == FileSystemEntityType.file &&
    left.size == right.size &&
    left.modified == right.modified &&
    left.changed == right.changed;

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

String _canonicalExistingDirectoryPath(Directory directory) {
  if (!directory.existsSync()) {
    throw ArgumentError.value(directory.path, '--source', 'Does not exist.');
  }
  return _normalizedAbsolutePath(directory.resolveSymbolicLinksSync());
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

Future<void> _applySafetyPatch(Directory stagedSource) async {
  await _replaceExactlyOnce(
    File('${stagedSource.path}/src/common.h'),
    '''class die {
 public:
  die() {}
  ~die() {
    std::cerr << std::endl;
    exit(-1);
  }
  int operator&(std::ostream&) { return 0; }
};''',
    '''/* Modified by misakid: convert CHECK_DIE into a catchable exception
 * without writing paths or diagnostics to process-global stdio. Valid
 * upstream execution is unchanged. */
class die {
 public:
  die() {}
  ~die() noexcept(false) { throw std::runtime_error(stream_.str()); }

  template <typename T>
  die &operator<<(const T &value) {
    stream_ << value;
    return *this;
  }

 private:
  std::ostringstream stream_;
};''',
  );
  await _replaceExactlyOnce(
    File('${stagedSource.path}/src/common.h'),
    '''#include <sstream>''',
    '''#include <sstream>
#include <stdexcept>''',
  );
  await _replaceExactlyOnce(
    File('${stagedSource.path}/src/common.h'),
    '''#define CHECK_DIE(condition) \\
(condition) ? 0 : die() & std::cerr << __FILE__ << \\
"(" << __LINE__ << ") [" << #condition << "] "''',
    '''#define CHECK_DIE(condition) \\
if (condition) {} else die() << __FILE__ << \\
"(" << __LINE__ << ") [" << #condition << "] "''',
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
      command.skip(1).toList(growable: false),
      'Native build command exited unsuccessfully.',
      result,
    );
  }
}
