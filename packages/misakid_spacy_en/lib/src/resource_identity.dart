// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:misakid/misaki.dart';

/// Exact tokenizer resource size from `en_core_web_sm==3.8.0`.
const int spacyEnglishTokenizerSizeBytes = 77066;

/// Exact tokenizer resource SHA-256 from `en_core_web_sm==3.8.0`.
const String spacyEnglishTokenizerSha256 =
    'b014e8bba4958b120af2d0c1c63eabb7c00379f2bacaf10df7c5325efd2ea467';

/// Exact `vocab/lookups.bin` size from `en_core_web_sm==3.8.0`.
const int spacyEnglishVocabLookupsSizeBytes = 70040;

/// Exact `vocab/lookups.bin` SHA-256 from `en_core_web_sm==3.8.0`.
const String spacyEnglishVocabLookupsSha256 =
    'fce9c883c56165f29573cc938c2a1c9d417ac61bd8f56b671dd5f7996de70682';

/// Exact `tok2vec/model` size from `en_core_web_sm==3.8.0`.
const int spacyEnglishTok2vecModelSizeBytes = 6269370;

/// Exact `tok2vec/model` SHA-256 from `en_core_web_sm==3.8.0`.
const String spacyEnglishTok2vecModelSha256 =
    'e84fc06eb319c94d28e460fc334e292120b01f18baa5dc8b50c977459820a090';

/// Exact `tagger/model` size from `en_core_web_sm==3.8.0`.
const int spacyEnglishTaggerModelSizeBytes = 19829;

/// Exact `tagger/model` SHA-256 from `en_core_web_sm==3.8.0`.
const String spacyEnglishTaggerModelSha256 =
    '1ec3d93f38cebe172f2b5c89d84be72856ce42c8f1a64f1699f1d98a771f36b7';

/// Immutable owned tokenizer resources shared by the small and transformer models.
///
/// Construction defensively copies both inputs. The resulting byte views reject
/// mutation, so callers may safely reuse or modify their original buffers.
final class SpacyEnglishTokenizerResources {
  /// Copies [tokenizerBytes] and [vocabLookupsBytes] into owned immutable views.
  SpacyEnglishTokenizerResources({
    required Uint8List tokenizerBytes,
    required Uint8List vocabLookupsBytes,
  }) : tokenizerBytes = Uint8List.fromList(tokenizerBytes).asUnmodifiableView(),
       vocabLookupsBytes = Uint8List.fromList(
         vocabLookupsBytes,
       ).asUnmodifiableView();

  /// Exact serialized spaCy tokenizer bytes.
  final Uint8List tokenizerBytes;

  /// Exact serialized spaCy lexical-normalization lookup bytes.
  final Uint8List vocabLookupsBytes;
}

/// Immutable owned resources for the exact English small-model backend.
///
/// Construction defensively copies all four inputs. Identity and schema checks
/// are performed when these resources are supplied to the public backend.
final class SpacyEnglishModelResources {
  /// Copies the four serialized resources into owned immutable byte views.
  SpacyEnglishModelResources({
    required Uint8List tokenizerBytes,
    required Uint8List vocabLookupsBytes,
    required Uint8List tok2vecModelBytes,
    required Uint8List taggerModelBytes,
  }) : tokenizer = SpacyEnglishTokenizerResources(
         tokenizerBytes: tokenizerBytes,
         vocabLookupsBytes: vocabLookupsBytes,
       ),
       tok2vecModelBytes = Uint8List.fromList(
         tok2vecModelBytes,
       ).asUnmodifiableView(),
       taggerModelBytes = Uint8List.fromList(
         taggerModelBytes,
       ).asUnmodifiableView();

  /// Owned tokenizer and lexical-normalization resources.
  final SpacyEnglishTokenizerResources tokenizer;

  /// Exact serialized spaCy tok2vec model bytes.
  final Uint8List tok2vecModelBytes;

  /// Exact serialized spaCy tagger model bytes.
  final Uint8List taggerModelBytes;
}

/// Validates the exact tokenizer resource sizes and SHA-256 identities.
void validateSpacyEnglishTokenizerResources(
  SpacyEnglishTokenizerResources resources,
) {
  _validatePinnedResource(
    bytes: resources.tokenizerBytes,
    relativePath: 'tokenizer',
    sizeBytes: spacyEnglishTokenizerSizeBytes,
    sha256Value: spacyEnglishTokenizerSha256,
  );
  _validatePinnedResource(
    bytes: resources.vocabLookupsBytes,
    relativePath: 'vocab/lookups.bin',
    sizeBytes: spacyEnglishVocabLookupsSizeBytes,
    sha256Value: spacyEnglishVocabLookupsSha256,
  );
}

/// Validates all four exact English small-model sizes and SHA-256 identities.
void validateSpacyEnglishModelResources(SpacyEnglishModelResources resources) {
  validateSpacyEnglishTokenizerResources(resources.tokenizer);
  _validatePinnedResource(
    bytes: resources.tok2vecModelBytes,
    relativePath: 'tok2vec/model',
    sizeBytes: spacyEnglishTok2vecModelSizeBytes,
    sha256Value: spacyEnglishTok2vecModelSha256,
  );
  _validatePinnedResource(
    bytes: resources.taggerModelBytes,
    relativePath: 'tagger/model',
    sizeBytes: spacyEnglishTaggerModelSizeBytes,
    sha256Value: spacyEnglishTaggerModelSha256,
  );
}

void _validatePinnedResource({
  required Uint8List bytes,
  required String relativePath,
  required int sizeBytes,
  required String sha256Value,
}) {
  if (bytes.length != sizeBytes) {
    throw MalformedDataException(
      'The en_core_web_sm resource `$relativePath` has ${bytes.length} bytes; '
      'expected $sizeBytes.',
    );
  }
  final actualSha256 = sha256.convert(bytes).toString();
  if (actualSha256 != sha256Value) {
    throw MalformedDataException(
      'The en_core_web_sm resource `$relativePath` has SHA-256 '
      '$actualSha256; expected $sha256Value.',
    );
  }
}
