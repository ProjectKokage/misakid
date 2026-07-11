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
    final vendorDependencies = await _verifyVendoredOpenJtalk(
      input.packageRoot,
    );
    output.dependencies.addAll(vendorDependencies);
    final targetOS = input.config.code.targetOS;
    if (targetOS != OS.android && targetOS != OS.iOS && targetOS != OS.macOS) {
      return;
    }

    final packageRoot = input.packageRoot.toFilePath();
    final androidExportMap = input.packageRoot
        .resolve('native/exports_android.map')
        .toFilePath();
    output.dependencies.add(Uri.file(androidExportMap));
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
      defines: const <String, String?>{'CHARSET_UTF_8': null},
      flags: <String>[
        '-fsigned-char',
        '-finput-charset=UTF-8',
        '-fexec-charset=UTF-8',
        '-ffunction-sections',
        '-fdata-sections',
        '-fvisibility=hidden',
        '-ffile-prefix-map=$packageRoot=misakid_openjtalk',
        '-Wno-deprecated-declarations',
        '-Wno-unused-command-line-argument',
      ],
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
        if (targetOS == OS.android) 'm',
      ],
      libraryDirectories: const <String>['.'],
      defines: const <String, String?>{
        'MISAKID_OPENJTALK_BUILD': null,
        'HAVE_CONFIG_H': null,
        'DIC_VERSION': '102',
        'MECAB_DEFAULT_RC': '"/dev/null"',
        'MECAB_WITHOUT_SHARE_DIC': null,
        'MECAB_USE_UTF8_ONLY': null,
        'CHARSET_UTF_8': null,
      },
      flags: <String>[
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
        if (targetOS == OS.android) ...const <String>[
          '-Wl,--gc-sections',
          '-Wl,--exclude-libs,ALL',
        ],
        if (targetOS == OS.android) '-Wl,--version-script=$androidExportMap',
        if (targetOS == OS.iOS || targetOS == OS.macOS) '-Wl,-dead_strip',
      ],
    ).run(input: input, output: output);
  });
}

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
