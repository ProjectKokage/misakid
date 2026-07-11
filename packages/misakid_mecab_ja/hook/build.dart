// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

const _assetName = 'misakid_mecab_ja';
const _vendorRoot = 'native/vendor/mecab';
const _expectedVendorFileCount = 54;
const _expectedVendorBytes = 4499769;
const _expectedVendorTreeSha256 =
    '473f27f510fbcb70ab6a73c556a56cf00b0fac23091dd3656efbee05cf032258';

const _runtimeSources = <String>[
  'char_property.cpp',
  'connector.cpp',
  'context_id.cpp',
  'dictionary.cpp',
  'dictionary_rewriter.cpp',
  'feature_index.cpp',
  'iconv_utils.cpp',
  'libmecab.cpp',
  'nbest_generator.cpp',
  'param.cpp',
  'string_buffer.cpp',
  'tagger.cpp',
  'tokenizer.cpp',
  'utils.cpp',
  'viterbi.cpp',
  'writer.cpp',
];

Future<void> main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    await _verifyVendoredMecab(input.packageRoot);
    final targetOS = input.config.code.targetOS;
    if (targetOS != OS.android && targetOS != OS.iOS && targetOS != OS.macOS) {
      return;
    }

    final packageRoot = input.packageRoot.toFilePath();
    await CBuilder.library(
      name: _assetName,
      assetName: _assetName,
      sources: <String>[
        'native/src/misakid_mecab_ja.cpp',
        for (final source in _runtimeSources) '$_vendorRoot/src/$source',
      ],
      includes: const <String>[
        'native/include',
        'native/portable',
        '$_vendorRoot/src',
      ],
      language: Language.cpp,
      std: 'c++17',
      cppLinkStdLib: targetOS == OS.android ? 'c++_static' : null,
      libraries: targetOS == OS.android
          ? const <String>['m']
          : const <String>[],
      defines: const <String, String?>{
        'MISAKID_MECAB_JA_BUILD': null,
        'HAVE_CONFIG_H': null,
        'DIC_VERSION': '102',
        'MECAB_DEFAULT_RC': '"/dev/null"',
        'MECAB_USE_UTF8_ONLY': null,
      },
      flags: <String>[
        '-finput-charset=UTF-8',
        '-fexec-charset=UTF-8',
        '-ffunction-sections',
        '-fdata-sections',
        '-fvisibility=hidden',
        '-fvisibility-inlines-hidden',
        '-ffile-prefix-map=$packageRoot=misakid_mecab_ja',
        '-Wno-deprecated-declarations',
        '-Wno-deprecated-register',
        '-Wno-string-plus-int',
        if (targetOS == OS.android) ...const <String>[
          '-Wl,--gc-sections',
          '-Wl,--exclude-libs,ALL',
        ],
      ],
    ).run(input: input, output: output);
  });
}

Future<void> _verifyVendoredMecab(Uri packageRoot) async {
  final root = Directory.fromUri(packageRoot.resolve('$_vendorRoot/'));
  final absoluteRoot = root.absolute.path;
  final prefix = absoluteRoot.endsWith(Platform.pathSeparator)
      ? absoluteRoot
      : '$absoluteRoot${Platform.pathSeparator}';
  final entities = await root
      .list(recursive: true, followLinks: false)
      .toList();
  if (entities.any((entity) => entity is Link)) {
    throw StateError(
      'The vendored MeCab tree must contain regular files only.',
    );
  }
  final files = <({File file, String relative})>[
    for (final file in entities.whereType<File>())
      (
        file: file,
        relative: file.absolute.path
            .substring(prefix.length)
            .split(Platform.pathSeparator)
            .join('/'),
      ),
  ]..sort((left, right) => left.relative.compareTo(right.relative));
  var totalBytes = 0;
  final records = BytesBuilder(copy: false);
  for (final entry in files) {
    final bytes = await entry.file.readAsBytes();
    totalBytes += bytes.length;
    records
      ..add(utf8.encode(entry.relative))
      ..addByte(0x00)
      ..add(ascii.encode(sha256.convert(bytes).toString()))
      ..addByte(0x0A);
  }
  final treeHash = sha256.convert(records.takeBytes()).toString();
  if (files.length != _expectedVendorFileCount ||
      totalBytes != _expectedVendorBytes ||
      treeHash != _expectedVendorTreeSha256) {
    throw StateError(
      'Vendored MeCab source identity mismatch: ${files.length} files, '
      '$totalBytes bytes, $treeHash.',
    );
  }
}
