import 'dart:io';

import 'package:misakid/misaki_en.dart';
import 'package:test/test.dart';

import '../support/english_fixture_replay.dart';
import '../support/upstream_fixture.dart';

void main() {
  for (final matrix
      in <
        ({
          String dialectName,
          EnglishDialect dialect,
          String fixtureFile,
          String mode,
        })
      >[
        (
          dialectName: 'American',
          dialect: EnglishDialect.american,
          fixtureFile: 'en_american_espeak_fallback.jsonl',
          mode: 'american-espeak-fallback',
        ),
        (
          dialectName: 'British',
          dialect: EnglishDialect.british,
          fixtureFile: 'en_british_espeak_fallback.jsonl',
          mode: 'british-espeak-fallback',
        ),
      ]) {
    final fixtures = readUpstreamFixtures(
      File(
        'test/fixtures/upstream/'
        'fba1236595f2d2bf21d414ba6e57d25256afada3/'
        '${matrix.fixtureFile}',
      ),
    );

    group('pinned English ${matrix.dialectName}/eSpeak-fallback parity', () {
      test('covers the complete 20-case dialect matrix', () {
        expect(fixtures, hasLength(20));
        expect(
          fixtures.map((fixture) => fixture.caseId).toSet(),
          hasLength(20),
        );
        expect(
          fixtures
              .map(
                (fixture) =>
                    (fixture.backendInput! as EnglishFixtureBackendInput)
                        .espeakCalls!
                        .length,
              )
              .fold<int>(0, (total, count) => total + count),
          29,
        );
      });

      for (final fixture in fixtures) {
        test(fixture.label, () {
          expect(fixture.language, 'en');
          expect(fixture.mode, matrix.mode);
          expect(
            fixture.options.keys.toSet(),
            anyOf(
              <String>{'version'},
              <String>{'preprocess', 'version'},
              <String>{'unk', 'version'},
            ),
          );
          expect(fixture.options['version'], anyOf(isNull, '2.0'));
          final backendInput = fixture.backendInput;
          expect(backendInput, isA<EnglishFixtureBackendInput>());
          final englishInput = backendInput! as EnglishFixtureBackendInput;
          expect(englishInput.espeakCalls, isNotNull);
          final tokenizer = EnglishFixtureTokenizerReplay(englishInput);
          final espeak = EnglishFixtureEspeakReplay(
            calls: englishInput.espeakCalls!,
            expectedDialect: matrix.dialect,
          );
          final version = fixture.options['version'] == '2.0'
              ? EnglishPhonemeVersion.v2
              : EnglishPhonemeVersion.legacy;
          final result = EnglishG2pEngine(
            tokenizer: tokenizer,
            pronunciation: PinnedEnglishLexicon(dialect: matrix.dialect),
            fallback: EnglishEspeakFallback(
              backend: espeak,
              dialect: matrix.dialect,
              phonemeVersion: version,
            ),
            phonemeVersion: version,
            unknownMarker: fixture.options['unk'] as String? ?? '❓',
            preprocessInput: fixture.options['preprocess'] as bool? ?? true,
          ).convert(fixture.input);

          expect(result.phonemes, fixture.phonemes, reason: fixture.label);
          expect(tokenizer.calls, 1);
          espeak.expectComplete(fixture.label);
          expectEnglishFixtureTokens(
            result.tokens,
            fixture.tokens,
            fixture.label,
          );
        });
      }
    });
  }
}
