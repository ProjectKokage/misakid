// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'package:misakid/misaki_en.dart';

import 'config.dart';
import 'input_encoding.dart';
import 'limits.dart';
import 'model.dart';
import 'resource_bundle.dart';
import 'resource_identity.dart';
import 'safetensors.dart';

export 'limits.dart'
    show
        defaultBartEnglishMaximumGenerationLength,
        maximumBartEnglishConfigBytes,
        maximumBartEnglishInputCodePoints,
        maximumBartEnglishWeightsBytes;

/// Experimental caller-provisioned BART fallback for Misakid English.
///
/// [open] reads and validates resources once. [pronounce] is synchronous and
/// reusable. The package has no built-in model identities and makes no parity
/// claim for third-party weights merely because a caller supplies them.
final class BartEnglishBackend implements EnglishFallbackBackend {
  BartEnglishBackend._({
    required BartModel model,
    required this.info,
    required int maximumGenerationLength,
  }) : _model = model,
       _maximumGenerationLength = maximumGenerationLength,
       _graphemeToToken = buildBartGraphemeMap(model.config);

  /// Opens an exactly identified configuration/safetensors pair.
  static Future<BartEnglishBackend> open({
    required String configPath,
    required String weightsPath,
    required BartEnglishResourceIdentity identity,
    int maximumGenerationLength = defaultBartEnglishMaximumGenerationLength,
  }) async {
    if (maximumGenerationLength < 2 ||
        maximumGenerationLength > maximumBartEnglishInputCodePoints + 2) {
      throw InvalidConfigurationException(
        'maximumGenerationLength must be between 2 and '
        '${maximumBartEnglishInputCodePoints + 2}.',
      );
    }
    final resources = await BartResourceBundle.load(
      configPath: configPath,
      weightsPath: weightsPath,
      identity: identity,
    );
    final config = BartConfig.parse(resources.configBytes);
    if (maximumGenerationLength > config.maxPositionEmbeddings) {
      throw InvalidConfigurationException(
        'maximumGenerationLength exceeds the model positional bound '
        'of ${config.maxPositionEmbeddings}.',
      );
    }
    final safetensors = BartSafetensors.parse(resources.weightsBytes);
    final model = BartModel.load(config, safetensors);
    await resources.ensureUnchanged();
    return BartEnglishBackend._(
      model: model,
      maximumGenerationLength: maximumGenerationLength,
      info: BackendInfo(
        name: 'external-bart-english',
        version: identity.version,
        details: <String, String>{
          'resourceName': identity.name,
          'configSha256': identity.configSha256,
          'configBytes': identity.configSizeBytes.toString(),
          'weightsSha256': identity.weightsSha256,
          'weightsBytes': identity.weightsSizeBytes.toString(),
          'architecture': 'bart-conditional-generation-1x1-f32',
          'maximumGenerationLength': maximumGenerationLength.toString(),
          'verification': 'experimental-caller-reviewed-resources',
        },
      ),
    );
  }

  final BartModel _model;
  final int _maximumGenerationLength;
  final Map<int, int> _graphemeToToken;

  @override
  final BackendInfo info;

  @override
  EnglishPronunciation pronounce(MisakiToken token) {
    final inputIds = encodeBartEnglishInput(
      text: token.text,
      graphemeToToken: _graphemeToToken,
      maximumCodePoints: _model.config.maxPositionEmbeddings - 2,
    );
    final generatedIds = _model.generate(
      inputIds,
      maximumLength: _maximumGenerationLength,
    );
    final output = StringBuffer();
    for (final tokenId in generatedIds) {
      if (tokenId > 3 && tokenId < _model.config.phonemeCharacters.length) {
        output.writeCharCode(_model.config.phonemeCharacters[tokenId]);
      }
    }
    return EnglishPronunciation(phonemes: output.toString(), rating: 1);
  }
}
