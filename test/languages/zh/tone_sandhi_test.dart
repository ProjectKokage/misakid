import 'package:misakid/misaki_zh.dart';
import 'package:test/test.dart';

void main() {
  group('ChineseToneSandhi modifyFinals', () {
    test('applies 不 then 一 rules with pinned numeric quirks', () {
      final stage = ChineseToneSandhi(backend: _FakeSandhiBackend());
      final cases = <(String, String, List<String>, List<String>)>[
        (
          '看不懂',
          'v',
          <String>['an4', 'u4', 'ong3'],
          <String>['an4', 'u5', 'ong3'],
        ),
        ('不怕', 'v', <String>['u4', 'a4'], <String>['u2', 'a4']),
        (
          '看一看',
          'v',
          <String>['an4', 'i1', 'an4'],
          <String>['an4', 'i5', 'an4'],
        ),
        (
          '第一段',
          'm',
          <String>['i4', 'i4', 'uan4'],
          <String>['i4', 'i1', 'uan4'],
        ),
        ('一段', 'm', <String>['i1', 'uan4'], <String>['i2', 'uan4']),
        ('一天', 'm', <String>['i1', 'ian1'], <String>['i4', 'ian1']),
        ('一，', 'm', <String>['i1', '，'], <String>['i1', '，']),
        (
          '二一零',
          'm',
          <String>['er4', 'i1', 'ing2'],
          <String>['er4', 'i1', 'ing2'],
        ),
        // 一 returns early as a number sequence, then neutral reduplication
        // still applies to the repeated 零 because neutral rules run later.
        (
          '一零零',
          'n',
          <String>['i1', 'ing2', 'ing2'],
          <String>['i1', 'ing2', 'ing5'],
        ),
        ('一兩', 'm', <String>['i1', 'iang3'], <String>['i1', 'iang3']),
        ('一两', 'm', <String>['i1', 'iang3'], <String>['i4', 'iang3']),
      ];

      for (final (word, pos, finals, expected) in cases) {
        expect(
          stage.modifyFinals(
            ChineseSandhiWord(word: word, partOfSpeech: pos),
            finals,
          ),
          expected,
          reason: word,
        );
      }
    });

    test('applies every neutral-tone rule family and exception ordering', () {
      final backend = _FakeSandhiBackend(
        searchSegmentsByWord: <String, List<String>>{
          '麻烦事': <String>['麻烦', '麻烦事'],
        },
      );
      final stage = ChineseToneSandhi(backend: backend);
      final cases = <(String, String, List<String>, List<String>)>[
        ('麻烦', 'n', <String>['a2', 'an2'], <String>['a2', 'an5']),
        ('男子', 'n', <String>['an2', 'i3'], <String>['an2', 'i3']),
        ('奶奶', 'n', <String>['ai3', 'ai3'], <String>['ai3', 'ai5']),
        ('好吧', 'a', <String>['ao3', 'a1'], <String>['ao3', 'a5']),
        ('好的', 'u', <String>['ao3', 'e2'], <String>['ao3', 'e5']),
        ('了', 'ul', <String>['e3'], <String>['e5']),
        ('了', 'v', <String>['e3'], <String>['e3']),
        ('我们', 'r', <String>['o3', 'en2'], <String>['o3', 'en5']),
        ('桌子', 'n', <String>['uo1', 'i3'], <String>['uo1', 'i5']),
        ('桌上', 's', <String>['uo1', 'ang4'], <String>['uo1', 'ang5']),
        ('上来', 'v', <String>['ang4', 'ai2'], <String>['ang4', 'ai5']),
        ('三个', 'm', <String>['an1', 'e4'], <String>['an1', 'e5']),
        ('两个', 'm', <String>['iang3', 'e4'], <String>['iang3', 'e5']),
        ('个', 'q', <String>['e4'], <String>['e5']),
        ('麻烦事', 'n', <String>['a2', 'an2', 'i4'], <String>['a2', 'an5', 'i4']),
      ];

      for (final (word, pos, finals, expected) in cases) {
        expect(
          stage.modifyFinals(
            ChineseSandhiWord(word: word, partOfSpeech: pos),
            finals,
          ),
          expected,
          reason: word,
        );
      }
    });

    test('applies exact two-, three-, and four-syllable third-tone rules', () {
      final backend = _FakeSandhiBackend(
        searchSegmentsByWord: <String, List<String>>{
          '蒙古包': <String>['蒙古', '蒙古包'],
          '纸老虎': <String>['老虎', '纸老虎'],
          '所有人': <String>['所有', '有人', '所有人'],
          '好喜欢': <String>['好', '喜欢', '好喜欢'],
        },
      );
      final stage = ChineseToneSandhi(backend: backend);
      final cases = <(String, String, List<String>, List<String>)>[
        ('很好', 'a', <String>['en3', 'ao3'], <String>['en2', 'ao3']),
        (
          '蒙古包',
          'n',
          <String>['eng3', 'u3', 'ao3'],
          <String>['eng2', 'u2', 'ao3'],
        ),
        ('纸老虎', 'n', <String>['i3', 'ao3', 'u3'], <String>['i3', 'ao2', 'u3']),
        (
          '所有人',
          'n',
          <String>['uo3', 'iou3', 'en2'],
          <String>['uo2', 'iou3', 'en2'],
        ),
        (
          '好喜欢',
          'a',
          <String>['ao3', 'i3', 'uan1'],
          <String>['ao2', 'i3', 'uan5'],
        ),
        (
          '甲乙丙丁',
          'd',
          <String>['a3', 'a3', 'a3', 'a3'],
          <String>['a2', 'a3', 'a2', 'a3'],
        ),
        // Neutral reduplication runs before third tone, preventing 3+3 sandhi.
        ('奶奶', 'n', <String>['ai3', 'ai3'], <String>['ai3', 'ai5']),
      ];

      for (final (word, pos, finals, expected) in cases) {
        expect(
          stage.modifyFinals(
            ChineseSandhiWord(word: word, partOfSpeech: pos),
            finals,
          ),
          expected,
          reason: word,
        );
      }
    });

    test('does not mutate inputs and freezes the result', () {
      final stage = ChineseToneSandhi(backend: _FakeSandhiBackend());
      final source = <String>['u4', 'a4'];

      final result = stage.modifyFinals(
        const ChineseSandhiWord(word: '不怕', partOfSpeech: 'v'),
        source,
      );

      expect(source, <String>['u4', 'a4']);
      expect(result, <String>['u2', 'a4']);
      expect(() => result.add('x1'), throwsUnsupportedError);
    });
  });

  group('ChineseToneSandhi preMerge', () {
    test('merges 不 while respecting x/eng boundaries and pinned overlaps', () {
      final stage = ChineseToneSandhi(backend: _FakeSandhiBackend());
      final cases = <(List<ChineseSandhiWord>, List<ChineseSandhiWord>)>[
        (
          _words(<(String, String)>[('不', 'd'), ('怕', 'v')]),
          _words(<(String, String)>[('不怕', 'v')]),
        ),
        (
          _words(<(String, String)>[('不', 'd'), ('A', 'eng')]),
          _words(<(String, String)>[('不', 'd'), ('A', 'eng')]),
        ),
        (
          _words(<(String, String)>[('不', 'd'), ('，', 'x')]),
          _words(<(String, String)>[('不', 'd'), ('，', 'x')]),
        ),
        (
          _words(<(String, String)>[('不', 'eng'), ('怕', 'v')]),
          _words(<(String, String)>[('不怕', 'v')]),
        ),
        (
          _words(<(String, String)>[('不', 'd')]),
          _words(<(String, String)>[('不', 'd')]),
        ),
        (
          _words(<(String, String)>[('不', 'd'), ('不', 'd'), ('怕', 'v')]),
          _words(<(String, String)>[('不不', 'd'), ('不怕', 'v')]),
        ),
      ];

      for (final (input, expected) in cases) {
        expect(stage.preMerge(input), expected, reason: input.toString());
      }
    });

    test('merges 一 and reduplication with asymmetric English checks', () {
      final stage = ChineseToneSandhi(backend: _FakeSandhiBackend());
      final cases = <(List<ChineseSandhiWord>, List<ChineseSandhiWord>)>[
        (
          _words(<(String, String)>[('听', 'v'), ('一', 'm'), ('听', 'v')]),
          _words(<(String, String)>[('听一听', 'v')]),
        ),
        (
          _words(<(String, String)>[('听', 'v'), ('一', 'm'), ('听', 'eng')]),
          _words(<(String, String)>[('听', 'v'), ('一', 'm'), ('听', 'eng')]),
        ),
        (
          _words(<(String, String)>[('一', 'm'), ('段', 'q')]),
          _words(<(String, String)>[('一段', 'm')]),
        ),
        (
          _words(<(String, String)>[('一', 'eng'), ('段', 'q')]),
          _words(<(String, String)>[('一段', 'eng')]),
        ),
        (
          _words(<(String, String)>[('一', 'm'), ('A', 'eng')]),
          _words(<(String, String)>[('一', 'm'), ('A', 'eng')]),
        ),
        (
          _words(<(String, String)>[('奶', 'n'), ('奶', 'n')]),
          _words(<(String, String)>[('奶奶', 'n')]),
        ),
        // Only the current POS is checked, so Han-tagged A merges backward
        // into an English-tagged A and keeps the previous POS.
        (
          _words(<(String, String)>[('A', 'eng'), ('A', 'n')]),
          _words(<(String, String)>[('AA', 'eng')]),
        ),
      ];

      for (final (input, expected) in cases) {
        expect(stage.preMerge(input), expected, reason: input.toString());
      }
    });

    test(
      'runs both continuous-third-tone passes without crossing punctuation',
      () {
        final backend = _FakeSandhiBackend(
          toneByCharacter: <String, String>{
            '老': 'ao3',
            '虎': 'u3',
            '纸': 'i3',
            '所': 'uo2',
            '有': 'iou3',
            '好': 'ao3',
            '甲': 'a3',
            '乙': 'a3',
            '嗯': 'en3',
          },
        );
        final stage = ChineseToneSandhi(backend: backend);

        expect(
          stage.preMerge(_words(<(String, String)>[('纸', 'n'), ('老虎', 'n')])),
          _words(<(String, String)>[('纸老虎', 'n')]),
        );
        expect(
          stage.preMerge(_words(<(String, String)>[('所有', 'n'), ('好', 'a')])),
          _words(<(String, String)>[('所有好', 'n')]),
        );
        expect(
          stage.preMerge(
            _words(<(String, String)>[('甲', 'n'), ('，', 'x'), ('乙', 'n')]),
          ),
          _words(<(String, String)>[('甲', 'n'), ('，', 'x'), ('乙', 'n')]),
        );
        expect(
          stage.preMerge(_words(<(String, String)>[('嗯', 'n'), ('好', 'a')])),
          _words(<(String, String)>[('嗯', 'n'), ('好', 'a')]),
        );
        // Upper-case X is deliberately not a protected boundary.
        expect(
          stage.preMerge(_words(<(String, String)>[('甲', 'X'), ('乙', 'n')])),
          _words(<(String, String)>[('甲乙', 'X')]),
        );
        expect(backend.finalInputs, isNot(contains('，')));
      },
    );

    test('merges 儿 based only on the previous merged POS', () {
      final stage = ChineseToneSandhi(backend: _FakeSandhiBackend());

      expect(
        stage.preMerge(_words(<(String, String)>[('花', 'n'), ('儿', 'n')])),
        _words(<(String, String)>[('花儿', 'n')]),
      );
      expect(
        stage.preMerge(
          _words(<(String, String)>[('flower', 'eng'), ('儿', 'n')]),
        ),
        _words(<(String, String)>[('flower', 'eng'), ('儿', 'n')]),
      );
      expect(
        stage.preMerge(_words(<(String, String)>[('花', 'n'), ('儿', 'eng')])),
        _words(<(String, String)>[('花儿', 'n')]),
      );
    });

    test('freezes merged output', () {
      final stage = ChineseToneSandhi(backend: _FakeSandhiBackend());
      final result = stage.preMerge(
        _words(<(String, String)>[('不', 'd'), ('怕', 'v')]),
      );

      expect(() => result.add(result.single), throwsUnsupportedError);
    });
  });

  group('ChineseToneSandhi backend contracts', () {
    test('wraps backend exceptions with identity and cause', () {
      const error = FormatException('failed');
      final backend = _FakeSandhiBackend(searchError: error);
      final stage = ChineseToneSandhi(backend: backend);

      expect(
        () => stage.modifyFinals(
          const ChineseSandhiWord(word: '麻烦', partOfSpeech: 'n'),
          <String>['a2', 'an2'],
        ),
        throwsA(
          isA<BackendFailureException>()
              .having(
                (exception) => exception.message,
                'message',
                contains('fake-sandhi 0.9.4'),
              )
              .having((exception) => exception.cause, 'cause', same(error)),
        ),
      );

      final finalsBackend = _FakeSandhiBackend(finalsError: error);
      expect(
        () => ChineseToneSandhi(
          backend: finalsBackend,
        ).preMerge(_words(<(String, String)>[('甲', 'n'), ('乙', 'n')])),
        throwsA(
          isA<BackendFailureException>()
              .having(
                (exception) => exception.message,
                'message',
                contains('fake-sandhi 0.9.4'),
              )
              .having((exception) => exception.cause, 'cause', same(error)),
        ),
      );
    });

    test(
      'rejects malformed word/final/provider records with typed failures',
      () {
        final stage = ChineseToneSandhi(backend: _FakeSandhiBackend());
        expect(
          () => stage.modifyFinals(
            const ChineseSandhiWord(word: '不怕', partOfSpeech: 'v'),
            <String>['u4'],
          ),
          throwsA(isA<BackendFailureException>()),
        );
        expect(
          () => stage.preMerge(const <ChineseSandhiWord>[
            ChineseSandhiWord(word: '甲', partOfSpeech: ''),
          ]),
          throwsA(isA<BackendFailureException>()),
        );

        final malformed = ChineseToneSandhi(
          backend: _FakeSandhiBackend(
            finalsByWord: <String, List<String>>{'甲': <String>[]},
          ),
        );
        expect(
          () => malformed.preMerge(
            _words(<(String, String)>[('甲', 'n'), ('乙', 'n')]),
          ),
          throwsA(isA<BackendFailureException>()),
        );

        for (final searchSegments in <List<String>>[
          <String>[''],
          <String>['乙'],
        ]) {
          final malformedSearch = ChineseToneSandhi(
            backend: _FakeSandhiBackend(
              searchSegmentsByWord: <String, List<String>>{'甲': searchSegments},
            ),
          );
          expect(
            () => malformedSearch.modifyFinals(
              const ChineseSandhiWord(word: '甲', partOfSpeech: 'n'),
              <String>['ia3'],
            ),
            throwsA(isA<BackendFailureException>()),
            reason: searchSegments.toString(),
          );
        }
      },
    );
  });
}

List<ChineseSandhiWord> _words(List<(String, String)> values) =>
    <ChineseSandhiWord>[
      for (final (word, pos) in values)
        ChineseSandhiWord(word: word, partOfSpeech: pos),
    ];

final class _FakeSandhiBackend implements ChineseToneSandhiBackend {
  _FakeSandhiBackend({
    this.searchSegmentsByWord = const <String, List<String>>{},
    this.finalsByWord = const <String, List<String>>{},
    this.toneByCharacter = const <String, String>{},
    this.searchError,
    this.finalsError,
  });

  final Map<String, List<String>> searchSegmentsByWord;
  final Map<String, List<String>> finalsByWord;
  final Map<String, String> toneByCharacter;
  final Exception? searchError;
  final Exception? finalsError;

  final List<String> searchInputs = <String>[];
  final List<String> finalInputs = <String>[];

  @override
  BackendInfo get info => BackendInfo(name: 'fake-sandhi', version: '0.9.4');

  @override
  List<String> searchSegments(String word) {
    searchInputs.add(word);
    final error = searchError;
    if (error != null) {
      throw error;
    }
    return searchSegmentsByWord[word] ?? <String>[word];
  }

  @override
  List<String> tone3Finals(String word) {
    finalInputs.add(word);
    final error = finalsError;
    if (error != null) {
      throw error;
    }
    final exact = finalsByWord[word];
    if (exact != null) {
      return exact;
    }
    return <String>[
      for (final scalar in word.runes)
        toneByCharacter[String.fromCharCode(scalar)] ?? 'a1',
    ];
  }
}
