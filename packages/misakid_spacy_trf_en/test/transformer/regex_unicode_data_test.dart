import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:misakid_spacy_trf_en/src/transformer/regex_unicode_data.g.dart';
import 'package:test/test.dart';

void main() {
  test('generated regex 2024.11.6 property identity is pinned', () {
    expect(
      regex20241106RangeDataSha256,
      'e7d2d9a6dd95d4553ab6693cf82157ea3b994c755119ef14bf81a1f2d9777a14',
    );
    expect(regex20241106LetterRanges, hasLength(677 * 2));
    expect(regex20241106NumberRanges, hasLength(144 * 2));
    expect(regex20241106WhitespaceRanges, hasLength(10 * 2));
    expect(_scalarCount(regex20241106LetterRanges), 141028);
    expect(_scalarCount(regex20241106NumberRanges), 1911);
    expect(_scalarCount(regex20241106WhitespaceRanges), 25);
    for (final ranges in <List<int>>[
      regex20241106LetterRanges,
      regex20241106NumberRanges,
      regex20241106WhitespaceRanges,
    ]) {
      _expectCanonicalRanges(ranges);
    }
    expect(
      sha256.convert(utf8.encode(_canonicalRangeJson())).toString(),
      regex20241106RangeDataSha256,
    );
  });

  test('Unicode 16 additions and White_Space differences are exact', () {
    expect(isRegex20241106LetterScalar(0x1C89), isTrue);
    expect(isRegex20241106NumberScalar(0x10D40), isTrue);
    expect(isRegex20241106WhitespaceScalar(0x1C), isFalse);
    expect(isRegex20241106WhitespaceScalar(0x20), isTrue);
    expect(isRegex20241106WhitespaceScalar(0x3000), isTrue);
  });
}

int _scalarCount(List<int> ranges) {
  var count = 0;
  for (var index = 0; index < ranges.length; index += 2) {
    count += ranges[index + 1] - ranges[index] + 1;
  }
  return count;
}

void _expectCanonicalRanges(List<int> ranges) {
  var previousEnd = -2;
  for (var index = 0; index < ranges.length; index += 2) {
    final start = ranges[index];
    final end = ranges[index + 1];
    expect(start, inInclusiveRange(0, 0x10FFFF));
    expect(end, inInclusiveRange(start, 0x10FFFF));
    expect(start, greaterThan(previousEnd + 1));
    previousEnd = end;
  }
}

String _canonicalRangeJson() => jsonEncode(<String, Object>{
  'letter': _pairs(regex20241106LetterRanges),
  'number': _pairs(regex20241106NumberRanges),
  'whiteSpace': _pairs(regex20241106WhitespaceRanges),
});

List<List<int>> _pairs(List<int> ranges) => <List<int>>[
  for (var index = 0; index < ranges.length; index += 2)
    <int>[ranges[index], ranges[index + 1]],
];
