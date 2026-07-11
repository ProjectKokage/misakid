import 'dart:io';

import 'package:misakid/misaki_ja.dart';
import 'package:test/test.dart';

import '../support/upstream_fixture.dart';

void main() {
  const converter = JapaneseNumberConverter();
  final fixtureFile = File(
    '${Directory.current.path}/test/fixtures/upstream/'
    'fba1236595f2d2bf21d414ba6e57d25256afada3/ja_num2kana.jsonl',
  );
  final fixtures = readUpstreamFixtures(fixtureFile);

  test('fixture covers both dependency-free Japanese number modes', () {
    expect(fixtures, hasLength(20));
    expect(fixtures.map((fixture) => fixture.mode).toSet(), <String>{
      'ja-num2kana',
      'ja-kanji-number',
    });
  });

  for (final fixture in fixtures) {
    test(fixture.label, () {
      expect(fixture.language, 'ja');
      expect(fixture.errorCategory, isNull);
      expect(fixture.tokens, isNull);

      final actual = switch (fixture.mode) {
        'ja-num2kana' => converter.convert(
          fixture.input,
          format: _numberFormat(fixture),
        ),
        'ja-kanji-number' => converter.kanjiToArabic(fixture.input),
        final mode => throw StateError('Unexpected fixture mode: $mode'),
      };

      expect(actual, fixture.phonemes, reason: fixture.label);
    });
  }
}

JapaneseNumberFormat _numberFormat(UpstreamFixture fixture) {
  final value = fixture.options['dictionary'];
  if (value is! String) {
    throw StateError('${fixture.label}: dictionary must be a string');
  }
  return JapaneseNumberFormat.values.byName(value);
}
