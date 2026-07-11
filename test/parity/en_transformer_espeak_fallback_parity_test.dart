import 'dart:io';

import 'package:misakid/misaki_en.dart';
import 'package:test/test.dart';

import '../support/english_fixture_replay.dart';
import '../support/upstream_fixture.dart';

void main() {
  const backendVersions = <String, Object?>{
    'en-core-web-trf': '3.8.0',
    'espeakng-data':
        'sha256:730e20a0d06976b23b8344bac21dab6e1da447d0e16906bab6a0b54db89dd6e2+files:364+bytes:18373365',
    'espeakng-library':
        'sha256:bb635eee1ee9c456f4a5cf06fb6cb352ecdd4d61e1951743b423ef22bb57f470+bytes:504168',
    'espeakng-loader': '0.2.4',
    'joblib': '1.4.2',
    'num2words': '0.5.14',
    'phonemizer-fork': '3.3.2',
    'python': '3.12.11',
    'spacy': '3.8.4',
  };

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
          fixtureFile: 'en_american_trf_espeak_fallback.jsonl',
          mode: 'american-espeak-fallback',
        ),
        (
          dialectName: 'British',
          dialect: EnglishDialect.british,
          fixtureFile: 'en_british_trf_espeak_fallback.jsonl',
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

    group('pinned English ${matrix.dialectName}/transformer/eSpeak parity', () {
      test('covers the complete 20-case combined matrix', () {
        expect(fixtures, hasLength(20));
        expect(
          fixtures.map((fixture) => fixture.caseId).toSet(),
          hasLength(20),
        );
        expect(
          fixtures.fold<int>(
            0,
            (total, fixture) =>
                total +
                (fixture.backendInput! as EnglishFixtureBackendInput)
                    .tokens
                    .length,
          ),
          43,
        );
        expect(
          fixtures.fold<int>(
            0,
            (total, fixture) =>
                total +
                (fixture.backendInput! as EnglishFixtureBackendInput)
                    .espeakCalls!
                    .length,
          ),
          25,
        );
      });

      for (final fixture in fixtures) {
        test(fixture.label, () {
          expect(fixture.language, 'en');
          expect(fixture.mode, matrix.mode);
          expect(
            fixture.options.keys.toSet(),
            anyOf(
              <String>{'trf', 'version'},
              <String>{'preprocess', 'trf', 'version'},
              <String>{'trf', 'unk', 'version'},
            ),
          );
          expect(fixture.options['trf'], isTrue);
          expect(fixture.options['version'], anyOf(isNull, '2.0'));
          expect(
            fixture.backendVersions,
            backendVersions,
            reason: fixture.label,
          );

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
