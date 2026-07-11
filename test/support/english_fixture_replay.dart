import 'package:misakid/misaki_en.dart';
import 'package:test/test.dart';

import 'upstream_fixture.dart';

final class EnglishFixtureTokenizerReplay implements EnglishTokenizerBackend {
  EnglishFixtureTokenizerReplay(this.fixture);

  final EnglishFixtureBackendInput fixture;
  var calls = 0;

  @override
  BackendInfo get info => BackendInfo(
    name: 'committed-spacy-token-replay',
    version: 'en-core-web-sm-3.8.0',
  );

  @override
  List<MisakiToken> tokenize(EnglishPreprocessResult input) {
    calls++;
    final expected = fixture.preprocess;
    expect(input.text, expected.text);
    expect(input.sourceWords, expected.sourceWords);
    expect(
      <int, Object?>{
        for (final entry in input.controls.entries)
          entry.key: _publicControlValue(entry.value),
      },
      <int, Object?>{
        for (final feature in expected.features)
          feature.sourceWordIndex: _fixtureFeatureValue(feature.value),
      },
    );
    return <MisakiToken>[
      for (final token in fixture.tokens)
        MisakiToken(
          text: token.text,
          tag: token.tag,
          whitespace: token.whitespace,
          phonemes: token.phonemes,
          startTimeSeconds: token.startTimeSeconds?.toDouble(),
          endTimeSeconds: token.endTimeSeconds?.toDouble(),
          metadata: EnglishTokenMetadata(
            isHead: token.metadata.isHead,
            stress: token.metadata.stress,
            numberFlags: token.metadata.numberFlags,
            precededBySpace: token.metadata.precededBySpace,
            rating: token.metadata.rating,
          ),
        ),
    ];
  }
}

final class EnglishFixtureEspeakReplay implements EnglishEspeakBackend {
  EnglishFixtureEspeakReplay({
    required List<EnglishFixtureEspeakCall> calls,
    required this.expectedDialect,
  }) : _calls = calls;

  final List<EnglishFixtureEspeakCall> _calls;
  final EnglishDialect expectedDialect;
  var _index = 0;

  @override
  BackendInfo get info => BackendInfo(
    name: 'committed-espeak-ng-replay',
    version: 'espeakng-loader-0.2.4',
  );

  @override
  String? phonemize(String text, {required EnglishDialect dialect}) {
    expect(_index, lessThan(_calls.length), reason: 'unexpected eSpeak call');
    final call = _calls[_index++];
    expect(text, call.text, reason: 'eSpeak call ${_index - 1}');
    expect(dialect, expectedDialect, reason: 'eSpeak call ${_index - 1}');
    return call.rawPhones;
  }

  void expectComplete(String reason) {
    expect(_index, _calls.length, reason: reason);
  }
}

void expectEnglishFixtureTokens(
  List<MisakiToken>? actual,
  List<Object?>? expected,
  String reason,
) {
  expect(actual, isNotNull, reason: reason);
  expect(expected, isNotNull, reason: reason);
  final actualTokens = actual!;
  final expectedTokens = expected!;
  expect(actualTokens, hasLength(expectedTokens.length), reason: reason);
  for (var index = 0; index < expectedTokens.length; index++) {
    final expectedToken = expectedTokens[index]! as Map<String, Object?>;
    final expectedMetadata = expectedToken['_']! as Map<String, Object?>;
    final actualToken = actualTokens[index];
    final actualMetadata = actualToken.metadata! as EnglishTokenMetadata;
    final tokenReason = '$reason token $index';

    expect(actualToken.text, expectedToken['text'], reason: tokenReason);
    expect(actualToken.tag, expectedToken['tag'], reason: tokenReason);
    expect(
      actualToken.whitespace,
      expectedToken['whitespace'],
      reason: tokenReason,
    );
    expect(
      actualToken.phonemes,
      expectedToken['phonemes'],
      reason: tokenReason,
    );
    expect(
      actualToken.startTimeSeconds,
      expectedToken['start_ts'],
      reason: tokenReason,
    );
    expect(
      actualToken.endTimeSeconds,
      expectedToken['end_ts'],
      reason: tokenReason,
    );
    expect(
      actualMetadata.isHead,
      expectedMetadata['is_head'],
      reason: tokenReason,
    );
    expect(
      actualMetadata.alias,
      expectedMetadata['alias'],
      reason: tokenReason,
    );
    expect(
      actualMetadata.stress,
      expectedMetadata['stress'],
      reason: tokenReason,
    );
    expect(
      actualMetadata.currency,
      expectedMetadata['currency'],
      reason: tokenReason,
    );
    expect(
      actualMetadata.numberFlags,
      expectedMetadata['num_flags'],
      reason: tokenReason,
    );
    expect(
      actualMetadata.precededBySpace,
      expectedMetadata['prespace'],
      reason: tokenReason,
    );
    expect(
      actualMetadata.rating,
      expectedToken['rating'] ?? expectedMetadata['rating'],
      reason: tokenReason,
    );
  }
}

Object _publicControlValue(EnglishInlineControl control) => switch (control) {
  EnglishPronunciationControl(:final encoded) => encoded,
  EnglishNumberFlagsControl(:final encoded) => encoded,
  EnglishStressControl(:final stress) => stress,
};

Object _fixtureFeatureValue(EnglishFixtureFeatureValue feature) =>
    switch (feature) {
      EnglishFixtureStringFeature(:final value) => value,
      EnglishFixtureIntegerFeature(:final value) => value,
      EnglishFixtureDoubleFeature(:final value) => value,
    };
