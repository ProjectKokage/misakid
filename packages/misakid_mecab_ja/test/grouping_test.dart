import 'package:misakid_mecab_ja/misakid_mecab_ja.dart';
import 'package:misakid_mecab_ja/src/grouping.dart';
import 'package:test/test.dart';

void main() {
  test('reproduces the three-node longest match', () {
    final membership = _Membership(<String>{'あう', 'あうぎ'});
    final actual =
        applyJapaneseCutletLongestGrouping(<JapaneseCutletMorphologyWord>[
          _word('あ', known: true, charType: 6),
          _word('う', known: true, charType: 6),
          _word('ぎ', known: true, charType: 6),
        ], membership);
    expect(actual.map((word) => word.joinWithNext), <bool>[true, true, false]);
    expect(membership.calls, <String>['あうぎ']);
  });

  test('known and raw type 7 words share effective type 6', () {
    final membership = _Membership(<String>{'漢カな'});
    final actual =
        applyJapaneseCutletLongestGrouping(<JapaneseCutletMorphologyWord>[
          _word('漢', known: true, charType: 2),
          _word('カ', known: false, charType: 7),
          _word('な', known: false, charType: 6),
        ], membership);
    expect(actual.map((word) => word.joinWithNext), <bool>[true, true, false]);
  });

  test('unknown non-6 types bound membership runs', () {
    final membership = _Membership(<String>{'ab', 'abc'});
    final actual =
        applyJapaneseCutletLongestGrouping(<JapaneseCutletMorphologyWord>[
          _word('a', known: true, charType: 2),
          _word('b', known: false, charType: 2),
          _word('c', known: true, charType: 2),
        ], membership);
    expect(actual.map((word) => word.joinWithNext), everyElement(isFalse));
    expect(membership.calls, <String>['a', 'b', 'c']);
  });

  test('exhaustive short sequences match the Python algorithm', () {
    for (var length = 0; length <= 4; length++) {
      final surfaces = <String>[
        for (var index = 0; index < length; index++)
          String.fromCharCode(0x61 + index),
      ];
      final candidates = <String>{
        for (var start = 0; start < length; start++)
          for (var end = start + 1; end <= length; end++)
            surfaces.sublist(start, end).join(),
      }.toList(growable: false);
      for (var typeMask = 0; typeMask < 1 << length; typeMask++) {
        final input = <JapaneseCutletMorphologyWord>[
          for (var index = 0; index < length; index++)
            _word(
              surfaces[index],
              known: typeMask & (1 << index) == 0,
              charType: 2,
            ),
        ];
        for (
          var membershipMask = 0;
          membershipMask < 1 << candidates.length;
          membershipMask++
        ) {
          final members = <String>{
            for (var index = 0; index < candidates.length; index++)
              if (membershipMask & (1 << index) != 0) candidates[index],
          };
          final membership = _Membership(members);
          final expected = _pythonGroupingOracle(input, members);
          final actual = applyJapaneseCutletLongestGrouping(input, membership);
          expect(
            actual.map((word) => word.joinWithNext).toList(),
            expected,
            reason: 'length=$length types=$typeMask members=$membershipMask',
          );
          expect(
            input.map((word) => word.joinWithNext),
            everyElement(isFalse),
            reason: 'input must remain immutable',
          );
        }
      }
    }
  });

  test('returns an unmodifiable list', () {
    final result = applyJapaneseCutletLongestGrouping(
      <JapaneseCutletMorphologyWord>[_word('a', known: true, charType: 6)],
      _Membership(const <String>{}),
    );
    expect(
      () => result.add(_word('b', known: true, charType: 6)),
      throwsA(anything),
    );
  });
}

JapaneseCutletMorphologyWord _word(
  String surface, {
  required bool known,
  required int charType,
}) => JapaneseCutletMorphologyWord(
  surface: surface,
  hiragana: surface,
  charType: charType,
  isUnknown: !known,
);

List<bool> _pythonGroupingOracle(
  List<JapaneseCutletMorphologyWord> words,
  Set<String> membership,
) {
  final joins = List<bool>.filled(words.length, false);
  int effectiveType(JapaneseCutletMorphologyWord word) =>
      word.charType == 7 || !word.isUnknown ? 6 : word.charType;
  var index = 0;
  while (index < words.length) {
    var runEnd = index + 1;
    while (runEnd < words.length &&
        effectiveType(words[runEnd]) == effectiveType(words[index])) {
      runEnd++;
    }
    int? match;
    for (var candidate = runEnd; candidate > index; candidate--) {
      if (membership.contains(
        words.sublist(index, candidate).map((word) => word.surface).join(),
      )) {
        match = candidate;
        break;
      }
    }
    if (match == null) {
      index++;
    } else {
      for (var grouped = index; grouped < match - 1; grouped++) {
        joins[grouped] = true;
      }
      index = match;
    }
  }
  return joins;
}

final class _Membership implements JapaneseCutletWordMembership {
  _Membership(this.words);

  final Set<String> words;
  final List<String> calls = <String>[];

  @override
  final BackendInfo info = BackendInfo(name: 'test-membership', version: '1');

  @override
  bool contains(String surface) {
    calls.add(surface);
    return words.contains(surface);
  }
}
