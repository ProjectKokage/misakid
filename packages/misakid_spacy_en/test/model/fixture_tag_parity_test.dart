import 'dart:convert';
import 'dart:io';

import 'package:misakid_spacy_en/src/model/model.dart';
import 'package:misakid_spacy_en/src/tokenizer/config.dart';
import 'package:misakid_spacy_en/src/tokenizer/tokenizer.dart';
import 'package:test/test.dart';

void main() {
  final modelRoot =
      Platform.environment['MISAKID_SPACY_EN_MODEL_DIR'] ??
      Platform.environment['MISAKI_SPACY_EN_MODEL_DIR'];
  final fixtureRoot =
      Platform.environment['MISAKID_SPACY_EN_FIXTURES'] ??
      '../../test/fixtures/upstream/'
          'fba1236595f2d2bf21d414ba6e57d25256afada3';
  final skipReason = modelRoot == null
      ? 'Set MISAKID_SPACY_EN_MODEL_DIR to en_core_web_sm-3.8.0.'
      : false;

  test('all 146 accepted streams and 744 tags match en_core_web_sm 3.8.0', () {
    final tokenizer = SpacyTokenizer(
      SpacyTokenizerConfig.decode(
        tokenizerBytes: File('$modelRoot/tokenizer').readAsBytesSync(),
        vocabLookupsBytes: File(
          '$modelRoot/vocab/lookups.bin',
        ).readAsBytesSync(),
      ),
    );
    final model = SpacyEnglishTaggerModel(
      SpacyEnglishSerializedModelLoader.decode(
        tok2vecModel: File('$modelRoot/tok2vec/model').readAsBytesSync(),
        taggerModel: File('$modelRoot/tagger/model').readAsBytesSync(),
      ),
    );

    var caseCount = 0;
    var tokenCount = 0;
    for (final name in _fixtureNames) {
      for (final line in File('$fixtureRoot/$name').readAsLinesSync()) {
        final fixture = jsonDecode(line) as Map<String, Object?>;
        final backend = fixture['backendInput']! as Map<String, Object?>;
        if (backend['kind'] != 'misaki.en.G2P.preprocess-tokenize') {
          continue;
        }
        final preprocess = backend['preprocess']! as Map<String, Object?>;
        final text = preprocess['text']! as String;
        final expectedTokens = backend['tokens']! as List<Object?>;
        final tokens = tokenizer.tokenize(text);
        final features = <SpacyTokenFeatures>[
          for (final token in tokens)
            SpacyTokenFeatures(
              norm: token.normId,
              prefix: token.prefixId,
              suffix: token.suffixId,
              shape: token.shapeId,
              spacy: token.spacy,
              isSpace: token.isSpace,
            ),
        ];
        final expectedTags = <String>[
          for (final encoded in expectedTokens)
            (encoded! as Map<String, Object?>)['tag']! as String,
        ];
        final reason = '${fixture['caseId']} in $name';
        expect(tokens, hasLength(expectedTags.length), reason: reason);
        expect(model.infer(features).tags, expectedTags, reason: reason);
        caseCount++;
        tokenCount += tokens.length;
      }
    }
    expect(caseCount, 146);
    expect(tokenCount, 744);
  }, skip: skipReason);
}

const List<String> _fixtureNames = <String>[
  'en_american_espeak_fallback.jsonl',
  'en_american_no_fallback.jsonl',
  'en_american_no_fallback_adversarial.jsonl',
  'en_british_espeak_fallback.jsonl',
  'en_british_no_fallback.jsonl',
  'en_british_no_fallback_adversarial.jsonl',
];
