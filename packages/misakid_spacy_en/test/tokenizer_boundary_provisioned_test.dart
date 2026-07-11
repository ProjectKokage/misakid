import 'dart:io';

import 'package:misakid_spacy_en/misakid_spacy_en.dart';
import 'package:test/test.dart';

void main() {
  final modelDirectory =
      Platform.environment['MISAKID_SPACY_EN_MODEL_DIR'] ??
      Platform.environment['MISAKID_SPACY_EN_MODEL'];
  final skipReason = modelDirectory == null
      ? 'Set MISAKID_SPACY_EN_MODEL_DIR to en_core_web_sm-3.8.0.'
      : false;

  group(
    'provisioned tokenizer-only capability boundary',
    () {
      late PureDartSpacyEnglishTokenizer tokenizer;
      late PureDartSpacyEnglishTokenizerBackend smallBackend;

      setUpAll(() async {
        tokenizer = await PureDartSpacyEnglishTokenizer.open(
          modelDirectoryPath: modelDirectory!,
        );
        smallBackend = await PureDartSpacyEnglishTokenizerBackend.open(
          modelDirectoryPath: modelDirectory,
        );
      });

      test('preserves empty input and exact public whitespace records', () {
        final emptyInput = const EnglishInlinePreprocessor().preprocess(
          ' \t\n  ',
        );
        final empty = tokenizer.tokenize(emptyInput);
        expect(empty.tokens, isEmpty);
        expect(
          () => empty.tokens.addAll(const <SpacyEnglishRawToken>[]),
          throwsA(isA<UnsupportedError>()),
        );
        final emptyAssembled = tokenizer.assembleTagged(
          input: emptyInput,
          tokenization: empty,
          tags: const <String>[],
        );
        expect(emptyAssembled, isEmpty);
        expect(
          () => emptyAssembled.add(
            const MisakiToken(text: 'forbidden', tag: 'NN', whitespace: ''),
          ),
          throwsA(isA<UnsupportedError>()),
        );

        final input = const EnglishInlinePreprocessor().preprocess(
          '  Hello\tworld\nagain  ',
        );
        final tokenization = tokenizer.tokenize(input);
        expect(
          tokenization.tokens.map(
            (token) => (
              token.text,
              token.whitespace,
              token.isSpace,
              token.startOffsetUtf16,
              token.endOffsetUtf16,
            ),
          ),
          <(String, String, bool, int, int)>[
            ('Hello', '', false, 0, 5),
            ('\t', '', true, 5, 6),
            ('world', '', false, 6, 11),
            ('\n', '', true, 11, 12),
            ('again', ' ', false, 12, 17),
            (' ', '', true, 18, 19),
          ],
        );
        final reconstructed = StringBuffer();
        for (final token in tokenization.tokens) {
          reconstructed
            ..write(token.text)
            ..write(token.whitespace);
        }
        expect(reconstructed.toString(), input.text);
      });

      test(
        'binds assembly to the exact tokenizer and preprocess result',
        () async {
          final input = const EnglishInlinePreprocessor().preprocess('hello');
          final tokenization = tokenizer.tokenize(input);
          final clone = EnglishPreprocessResult(
            text: input.text,
            sourceWords: input.sourceWords,
            controls: input.controls,
          );
          expect(
            () => tokenizer.assembleTagged(
              input: clone,
              tokenization: tokenization,
              tags: const <String>['NN'],
            ),
            throwsA(isA<InvalidConfigurationException>()),
          );

          final otherTokenizer = await PureDartSpacyEnglishTokenizer.open(
            modelDirectoryPath: modelDirectory!,
          );
          expect(
            () => otherTokenizer.assembleTagged(
              input: input,
              tokenization: tokenization,
              tags: const <String>['NN'],
            ),
            throwsA(isA<InvalidConfigurationException>()),
          );
          expect(
            () => tokenizer.assembleTagged(
              input: input,
              tokenization: tokenization,
              tags: const <String>['not-a-pinned-tag'],
            ),
            throwsA(isA<InvalidConfigurationException>()),
          );
          expect(
            tokenizer
                .assembleTagged(
                  input: input,
                  tokenization: tokenization,
                  tags: const <String>['NN'],
                )
                .single
                .tag,
            'NN',
          );
        },
      );

      test('reapplies every inline-control kind after external tagging', () {
        final input = const EnglishInlinePreprocessor().preprocess(
          '[New York](/njuː jɔɹk/) [12](#n#) [word](2)',
        );
        final tokenization = tokenizer.tokenize(input);
        expect(tokenization.tokens.map((token) => token.text), <String>[
          'New',
          'York',
          '12',
          'word',
        ]);
        final assembled = tokenizer.assembleTagged(
          input: input,
          tokenization: tokenization,
          tags: const <String>['NNP', 'NNP', 'CD', 'NN'],
        );

        expect(assembled[0].phonemes, 'njuː jɔɹk');
        expect(assembled[1].phonemes, '');
        final first = assembled[0].metadata! as EnglishTokenMetadata;
        final second = assembled[1].metadata! as EnglishTokenMetadata;
        final number = assembled[2].metadata! as EnglishTokenMetadata;
        final stressed = assembled[3].metadata! as EnglishTokenMetadata;
        expect((first.isHead, first.rating), (true, 5));
        expect((second.isHead, second.rating), (false, 5));
        expect(number.numberFlags, 'n');
        expect(stressed.stress, 2);
      });

      test('loads only shared resources from a tokenizer-only root', () async {
        final temporary = await Directory.systemTemp.createTemp(
          'misakid-spacy-tokenizer-only-',
        );
        addTearDown(() => temporary.delete(recursive: true));
        await Directory('${temporary.path}/vocab').create();
        await File(
          '$modelDirectory/tokenizer',
        ).copy('${temporary.path}/tokenizer');
        await File(
          '$modelDirectory/vocab/lookups.bin',
        ).copy('${temporary.path}/vocab/lookups.bin');

        final narrow = await PureDartSpacyEnglishTokenizer.open(
          modelDirectoryPath: temporary.path,
        );
        final input = const EnglishInlinePreprocessor().preprocess('hello');
        expect(narrow.tokenize(input).tokens.single.text, 'hello');
        await expectLater(
          PureDartSpacyEnglishTokenizerBackend.open(
            modelDirectoryPath: temporary.path,
          ),
          throwsA(isA<BackendUnavailableException>()),
        );
      });

      test('keeps the small tagger limit out of the shared tokenizer', () {
        final text = List<String>.filled(
          maximumSpacyEnglishTokens + 1,
          'a',
        ).join(' ');
        final input = EnglishPreprocessResult(
          text: text,
          sourceWords: const <String>[],
          controls: const <int, EnglishInlineControl>{},
        );

        expect(
          tokenizer.tokenize(input).tokens,
          hasLength(maximumSpacyEnglishTokens + 1),
        );
        expect(
          () => smallBackend.tokenize(input),
          throwsA(
            isA<BackendFailureException>().having(
              (error) => error.message,
              'message',
              contains('pure-Dart tagger limit'),
            ),
          ),
        );
      });
    },
    skip: skipReason,
    tags: 'provisioned',
  );
}
