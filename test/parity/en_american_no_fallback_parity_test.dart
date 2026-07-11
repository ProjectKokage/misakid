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
          int caseCount,
        })
      >[
        (
          dialectName: 'American',
          dialect: EnglishDialect.american,
          fixtureFile: 'en_american_no_fallback.jsonl',
          mode: 'american-no-fallback',
          caseCount: 32,
        ),
        (
          dialectName: 'British',
          dialect: EnglishDialect.british,
          fixtureFile: 'en_british_no_fallback.jsonl',
          mode: 'british-no-fallback',
          caseCount: 32,
        ),
        (
          dialectName: 'American adversarial',
          dialect: EnglishDialect.american,
          fixtureFile: 'en_american_no_fallback_adversarial.jsonl',
          mode: 'american-no-fallback',
          caseCount: 21,
        ),
        (
          dialectName: 'British adversarial',
          dialect: EnglishDialect.british,
          fixtureFile: 'en_british_no_fallback_adversarial.jsonl',
          mode: 'british-no-fallback',
          caseCount: 21,
        ),
      ]) {
    final fixtures = readUpstreamFixtures(
      File(
        'test/fixtures/upstream/'
        'fba1236595f2d2bf21d414ba6e57d25256afada3/'
        '${matrix.fixtureFile}',
      ),
    );

    group('pinned English ${matrix.dialectName}/no-fallback parity', () {
      test('covers the complete ${matrix.caseCount}-case dialect matrix', () {
        expect(fixtures, hasLength(matrix.caseCount));
        expect(
          fixtures.map((fixture) => fixture.caseId).toSet(),
          hasLength(matrix.caseCount),
        );
      });

      for (final fixture in fixtures) {
        test(fixture.label, () {
          expect(fixture.language, 'en');
          expect(fixture.mode, matrix.mode);
          expect(fixture.options.keys, <String>{'version'});
          expect(fixture.options['version'], anyOf(isNull, '2.0'));
          final backendInput = fixture.backendInput;
          expect(backendInput, isA<EnglishFixtureBackendInput>());
          final replay = EnglishFixtureTokenizerReplay(
            backendInput! as EnglishFixtureBackendInput,
          );
          final version = fixture.options['version'] == '2.0'
              ? EnglishPhonemeVersion.v2
              : EnglishPhonemeVersion.legacy;
          final result = EnglishG2pEngine(
            tokenizer: replay,
            pronunciation: PinnedEnglishLexicon(dialect: matrix.dialect),
            phonemeVersion: version,
          ).convert(fixture.input);

          expect(result.phonemes, fixture.phonemes, reason: fixture.label);
          expect(replay.calls, 1);
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
