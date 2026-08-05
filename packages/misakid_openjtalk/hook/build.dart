// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

const _assetName = 'misakid_openjtalk';
const _frontendArchiveName = 'misakid_openjtalk_frontend';
const _vendorRoot = 'native/vendor/open_jtalk';
const _elfExportMap = 'native/exports_android.map';
const _expectedVendorFileCount = 139;
const _expectedVendorBytes = 5382103;
const _expectedVendorTreeSha256 =
    '8ce47a975dee79c078914df15c40df5906430e4a63be4fc2bc0987e7b5b2fccb';

const _mecabRuntimeSources = <String>[
  'char_property.cpp',
  'connector.cpp',
  'context_id.cpp',
  'dictionary.cpp',
  'dictionary_rewriter.cpp',
  'feature_index.cpp',
  'iconv_utils.cpp',
  'libmecab.cpp',
  'mecab.cpp',
  'nbest_generator.cpp',
  'param.cpp',
  'string_buffer.cpp',
  'tagger.cpp',
  'tokenizer.cpp',
  'utils.cpp',
  'viterbi.cpp',
  'writer.cpp',
];

const _frontendSources = <String>[
  'mecab2njd/mecab2njd.c',
  'njd/njd.c',
  'njd/njd_node.c',
  'njd_set_accent_phrase/njd_set_accent_phrase.c',
  'njd_set_accent_type/njd_set_accent_type.c',
  'njd_set_digit/njd_set_digit.c',
  'njd_set_long_vowel/njd_set_long_vowel.c',
  'njd_set_pronunciation/njd_set_pronunciation.c',
  'njd_set_unvoiced_vowel/njd_set_unvoiced_vowel.c',
  'text2mecab/text2mecab.c',
];

Future<void> main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }
    final vendorDependencies = await _verifyVendoredOpenJtalk(
      input.packageRoot,
    );
    output.dependencies.addAll(vendorDependencies);
    final targetOS = input.config.code.targetOS;
    if (!openJtalkNativeAssetOperatingSystems.contains(targetOS)) {
      return;
    }
    final targetArchitecture = input.config.code.targetArchitecture;
    validateOpenJtalkNativeAssetTarget(targetOS, targetArchitecture);
    validateOpenJtalkDesktopBuildHost(
      targetOS,
      targetArchitecture,
      OS.current,
      Architecture.current,
    );
    validateOpenJtalkWindowsCompiler(
      targetOS,
      input.config.code.cCompiler?.compiler,
    );

    final packageRoot = input.packageRoot.toFilePath();
    final elfExportMap = input.packageRoot.resolve(_elfExportMap).toFilePath();
    if (targetOS == OS.android || targetOS == OS.linux) {
      output.dependencies.add(Uri.file(elfExportMap));
    }
    await CBuilder.library(
      name: _frontendArchiveName,
      sources: <String>[
        'native/src/silent_stdio.c',
        for (final source in _frontendSources) '$_vendorRoot/$source',
      ],
      includes: const <String>[
        'native/src',
        '$_vendorRoot/mecab/src',
        '$_vendorRoot/mecab2njd',
        '$_vendorRoot/njd',
        '$_vendorRoot/njd_set_accent_phrase',
        '$_vendorRoot/njd_set_accent_type',
        '$_vendorRoot/njd_set_digit',
        '$_vendorRoot/njd_set_long_vowel',
        '$_vendorRoot/njd_set_pronunciation',
        '$_vendorRoot/njd_set_unvoiced_vowel',
        '$_vendorRoot/text2mecab',
      ],
      forcedIncludes: const <String>['native/src/silent_stdio.h'],
      language: Language.c,
      std: 'c11',
      defines: <String, String?>{
        'CHARSET_UTF_8': null,
        if (targetOS == OS.linux) '_POSIX_C_SOURCE': '200809L',
      },
      flags: openJtalkFrontendCompilerFlags(targetOS, packageRoot),
    ).run(
      input: input,
      output: output,
      routing: const <AssetRouting>[],
      linkModePreference: LinkModePreference.static,
    );

    await CBuilder.library(
      name: _assetName,
      assetName: _assetName,
      sources: <String>[
        'native/src/misakid_openjtalk.cpp',
        for (final source in _mecabRuntimeSources)
          '$_vendorRoot/mecab/src/$source',
      ],
      includes: const <String>[
        'native/include',
        'native/portable',
        '$_vendorRoot/mecab/src',
        '$_vendorRoot/mecab2njd',
        '$_vendorRoot/njd',
        '$_vendorRoot/njd_set_accent_phrase',
        '$_vendorRoot/njd_set_accent_type',
        '$_vendorRoot/njd_set_digit',
        '$_vendorRoot/njd_set_long_vowel',
        '$_vendorRoot/njd_set_pronunciation',
        '$_vendorRoot/njd_set_unvoiced_vowel',
        '$_vendorRoot/text2mecab',
      ],
      forcedIncludes: const <String>['native/src/silent_stdio.h'],
      language: Language.cpp,
      std: 'c++17',
      cppLinkStdLib: targetOS == OS.android ? 'c++_static' : null,
      libraries: <String>[
        _frontendArchiveName,
        if (targetOS == OS.android || targetOS == OS.linux) 'm',
        if (targetOS == OS.linux) 'pthread',
      ],
      libraryDirectories: const <String>['.'],
      defines: <String, String?>{
        'MISAKID_OPENJTALK_BUILD': null,
        'HAVE_CONFIG_H': null,
        'DIC_VERSION': '102',
        'MECAB_DEFAULT_RC': openJtalkMecabDefaultRc(targetOS),
        'MECAB_WITHOUT_SHARE_DIC': null,
        'MECAB_USE_UTF8_ONLY': null,
        'CHARSET_UTF_8': null,
        if (targetOS == OS.linux) '_POSIX_C_SOURCE': '200809L',
      },
      flags: openJtalkAdapterCompilerFlags(targetOS, packageRoot, elfExportMap),
    ).run(input: input, output: output);
  });
}

/// Operating systems with an implemented native-assets build profile.
const Set<OS> openJtalkNativeAssetOperatingSystems = <OS>{
  OS.android,
  OS.iOS,
  OS.linux,
  OS.macOS,
  OS.windows,
};

/// Whether [targetOS] and [targetArchitecture] have a build profile.
///
/// This is source configuration, not provisioned target-runtime evidence.
bool supportsOpenJtalkNativeAssetTarget(
  OS targetOS,
  Architecture targetArchitecture,
) {
  if (targetOS == OS.android) {
    return targetArchitecture == Architecture.arm ||
        targetArchitecture == Architecture.arm64 ||
        targetArchitecture == Architecture.x64;
  }
  if (targetOS == OS.iOS || targetOS == OS.macOS || targetOS == OS.linux) {
    return targetArchitecture == Architecture.arm64 ||
        targetArchitecture == Architecture.x64;
  }
  return targetOS == OS.windows && targetArchitecture == Architecture.x64;
}

/// Fails an unsupported native-assets tuple before invoking a compiler.
void validateOpenJtalkNativeAssetTarget(
  OS targetOS,
  Architecture targetArchitecture,
) {
  if (!supportsOpenJtalkNativeAssetTarget(targetOS, targetArchitecture)) {
    throw BuildError(
      message:
          'misakid_openjtalk has no native-assets build profile for '
          '${targetOS.name}-${targetArchitecture.name}. Windows is limited '
          'to x64; Linux is limited to x64 and arm64.',
    );
  }
}

/// Requires desktop builds to use their native host and native architecture.
///
/// The pinned `native_toolchain_c` default compiler resolver can otherwise
/// select a host compiler for a foreign desktop target. The desktop profiles
/// intentionally reject that ambiguous path before invoking a compiler.
void validateOpenJtalkDesktopBuildHost(
  OS targetOS,
  Architecture targetArchitecture,
  OS hostOS,
  Architecture hostArchitecture,
) {
  if (targetOS != OS.linux && targetOS != OS.windows) {
    return;
  }
  if (targetOS != hostOS || targetArchitecture != hostArchitecture) {
    throw BuildError(
      message:
          'misakid_openjtalk ${targetOS.name}-${targetArchitecture.name} '
          'builds require a native ${targetOS.name}-'
          '${targetArchitecture.name} host; current host is '
          '${hostOS.name}-${hostArchitecture.name}. Foreign-host desktop '
          'cross-compilation is not a supported native-assets path.',
    );
  }
}

/// Rejects unsupported Windows compiler drivers with an actionable error.
///
/// `native_toolchain_c` 0.19.2 translates standards, defines, includes, forced
/// includes, archiving, and the developer environment for `cl.exe`. Its
/// clang-like Windows C++ path does not provide a Windows standard-library
/// link policy, so accepting that path would advertise a configuration the
/// package cannot actually link.
void validateOpenJtalkWindowsCompiler(OS targetOS, Uri? compiler) {
  if (targetOS != OS.windows || compiler == null) {
    return;
  }
  final pathSegments = compiler.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  final executable = pathSegments.isEmpty
      ? null
      : pathSegments.last.toLowerCase();
  if (executable != 'cl.exe' && executable != 'cl') {
    throw BuildError(
      message:
          'misakid_openjtalk Windows builds require the MSVC cl.exe '
          'toolchain supplied by a Visual Studio Developer Command Prompt; '
          'configured compiler was `${compiler.toString()}`.',
    );
  }
}

/// Target-specific C compiler and linker flags for the private C11 archive.
List<String> openJtalkFrontendCompilerFlags(OS targetOS, String packageRoot) {
  if (targetOS == OS.windows) {
    return <String>[
      '/utf-8',
      '/Gy',
      '/Gw',
      '/pathmap:$packageRoot=misakid_openjtalk',
    ];
  }
  return <String>[
    '-fsigned-char',
    '-finput-charset=UTF-8',
    '-fexec-charset=UTF-8',
    '-ffunction-sections',
    '-fdata-sections',
    '-fvisibility=hidden',
    '-ffile-prefix-map=$packageRoot=misakid_openjtalk',
    '-Wno-deprecated-declarations',
    '-Wno-unused-command-line-argument',
  ];
}

/// Target-specific flags for the routed C++17 code asset.
List<String> openJtalkAdapterCompilerFlags(
  OS targetOS,
  String packageRoot,
  String elfExportMap,
) {
  if (targetOS == OS.windows) {
    return <String>[
      '/utf-8',
      '/EHsc',
      '/Gy',
      '/Gw',
      '/pathmap:$packageRoot=misakid_openjtalk',
    ];
  }
  return <String>[
    '-finput-charset=UTF-8',
    '-fexec-charset=UTF-8',
    '-ffunction-sections',
    '-fdata-sections',
    '-fvisibility=hidden',
    '-fvisibility-inlines-hidden',
    '-ffile-prefix-map=$packageRoot=misakid_openjtalk',
    '-Wno-deprecated-declarations',
    '-Wno-deprecated-register',
    '-Wno-string-plus-int',
    if (targetOS == OS.android || targetOS == OS.linux) ...<String>[
      '-Wl,--gc-sections',
      '-Wl,--exclude-libs,ALL',
      '-Wl,--version-script=$elfExportMap',
    ],
    if (targetOS == OS.linux) '-Wl,-soname,libmisakid_openjtalk.so',
    if (targetOS == OS.iOS || targetOS == OS.macOS) '-Wl,-dead_strip',
  ];
}

/// Platform null-device spelling retained in the generated MeCab definition.
String openJtalkMecabDefaultRc(OS targetOS) =>
    targetOS == OS.windows ? '"NUL"' : '"/dev/null"';

Future<Set<Uri>> _verifyVendoredOpenJtalk(Uri packageRoot) async {
  final root = Directory.fromUri(packageRoot.resolve('$_vendorRoot/'));
  final rootType = await FileSystemEntity.type(root.path, followLinks: false);
  if (rootType != FileSystemEntityType.directory) {
    throw StateError('The vendored Open JTalk root must be a real directory.');
  }
  final absoluteRoot = root.absolute.path;
  final prefix = absoluteRoot.endsWith(Platform.pathSeparator)
      ? absoluteRoot
      : '$absoluteRoot${Platform.pathSeparator}';
  final entities = await root
      .list(recursive: true, followLinks: false)
      .toList();
  entities.sort((left, right) => left.path.compareTo(right.path));
  final dependencies = <Uri>{root.uri};
  final files = <({File file, String relative})>[];
  for (final entity in entities) {
    final type = await FileSystemEntity.type(entity.path, followLinks: false);
    if (type != FileSystemEntityType.file &&
        type != FileSystemEntityType.directory) {
      throw StateError(
        'The vendored Open JTalk tree must contain regular files and '
        'directories only.',
      );
    }
    dependencies.add(entity.uri);
    if (type == FileSystemEntityType.file) {
      files.add((
        file: File(entity.path),
        relative: entity.absolute.path
            .substring(prefix.length)
            .split(Platform.pathSeparator)
            .join('/'),
      ));
    }
  }
  files.sort((left, right) => left.relative.compareTo(right.relative));
  var totalBytes = 0;
  final records = BytesBuilder(copy: false);
  for (final entry in files) {
    final bytes = await entry.file.readAsBytes();
    totalBytes += bytes.length;
    records
      ..add(utf8.encode(entry.relative))
      ..addByte(0x09)
      ..add(ascii.encode(sha256.convert(bytes).toString()))
      ..addByte(0x0A);
  }
  final treeHash = sha256.convert(records.takeBytes()).toString();
  if (files.length != _expectedVendorFileCount ||
      totalBytes != _expectedVendorBytes ||
      treeHash != _expectedVendorTreeSha256) {
    throw StateError(
      'Vendored Open JTalk source identity mismatch: ${files.length} files, '
      '$totalBytes bytes, $treeHash.',
    );
  }
  return dependencies;
}
