// Dart adaptation of the final rendering block in
// hexgrad/misaki/misaki/en.py at
// fba1236595f2d2bf21d414ba6e57d25256afada3 (Misaki 0.9.4,
// Apache-2.0).

import '../../core/constants.dart';
import '../../core/result.dart';
import '../../core/token.dart';

/// English phoneme inventory behavior selected for final rendering.
enum EnglishPhonemeVersion {
  /// Upstream's default compatibility rendering (`ɾ` → `T`, `ʔ` → `t`).
  legacy,

  /// Upstream version `2.0`, which preserves `ɾ` and `ʔ`.
  v2,
}

/// Renders resolved English [tokens] into an exact immutable result.
G2pResult renderEnglishTokens(
  List<MisakiToken> tokens, {
  EnglishPhonemeVersion version = EnglishPhonemeVersion.legacy,
  String unknownMarker = defaultUnknownMarker,
}) {
  final renderedTokens = <MisakiToken>[
    for (final token in tokens)
      _renderToken(
        token,
        preserveVersion2: version == EnglishPhonemeVersion.v2,
      ),
  ];
  final output = StringBuffer();
  for (final token in renderedTokens) {
    output
      ..write(token.phonemes ?? unknownMarker)
      ..write(token.whitespace);
  }
  return G2pResult(phonemes: output.toString(), tokens: renderedTokens);
}

MisakiToken _renderToken(MisakiToken token, {required bool preserveVersion2}) {
  final phonemes = token.phonemes;
  if (preserveVersion2 || phonemes == null || phonemes.isEmpty) {
    return token;
  }
  return MisakiToken(
    text: token.text,
    tag: token.tag,
    whitespace: token.whitespace,
    phonemes: phonemes.replaceAll('ɾ', 'T').replaceAll('ʔ', 't'),
    startTimeSeconds: token.startTimeSeconds,
    endTimeSeconds: token.endTimeSeconds,
    metadata: token.metadata,
  );
}
