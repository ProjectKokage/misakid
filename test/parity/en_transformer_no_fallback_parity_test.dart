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
          fixtureFile: 'en_american_trf_no_fallback.jsonl',
          mode: 'american-no-fallback',
        ),
        (
          dialectName: 'British',
          dialect: EnglishDialect.british,
          fixtureFile: 'en_british_trf_no_fallback.jsonl',
          mode: 'british-no-fallback',
        ),
      ]) {
    final fixtures = readUpstreamFixtures(
      File(
        'test/fixtures/upstream/'
        'fba1236595f2d2bf21d414ba6e57d25256afada3/'
        '${matrix.fixtureFile}',
      ),
    );

    group('pinned English ${matrix.dialectName}/transformer parity', () {
      test('captures the complete 38-case transformer stream', () {
        expect(fixtures, hasLength(38));
        expect(
          fixtures.map((fixture) => fixture.caseId).toSet(),
          hasLength(38),
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
          1096,
        );
        expect(fixtures.skip(32).map((fixture) => fixture.caseId), <String?>[
          'trf-full-pieces-104',
          'trf-full-pieces-105',
          'trf-full-pieces-144',
          'trf-overlap-emoji-145',
          'trf-full-pieces-208',
          'trf-full-pieces-249',
        ]);
      });

      for (final fixture in fixtures) {
        test(fixture.label, () {
          expect(fixture.language, 'en');
          expect(fixture.mode, matrix.mode);
          expect(fixture.options.keys, <String>{'trf', 'version'});
          expect(fixture.options['trf'], isTrue);
          expect(fixture.options['version'], anyOf(isNull, '2.0'));
          expect(fixture.backendVersions, <String, Object?>{
            'en-core-web-trf': '3.8.0',
            'num2words': '0.5.14',
            'spacy': '3.8.4',
          });

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
