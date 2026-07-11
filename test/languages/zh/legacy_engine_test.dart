import 'package:misakid/misaki_zh.dart';
import 'package:test/test.dart';

void main() {
  group('ChineseLegacyG2pEngine', () {
    test('short-circuits exact CPython whitespace with null tokens', () {
      final backend = _FakeChineseLegacyBackend();
      final engine = ChineseLegacyG2pEngine(backend: backend);

      for (final text in <String>[
        '',
        '\t\r\n',
        '\u001c　\u001f',
        '\u0085\u202f',
      ]) {
        final result = engine.convert(text);
        expect(
          result.phonemes,
          isEmpty,
          reason: text.runes.toList().toString(),
        );
        expect(result.tokens, isNull);
      }
      expect(backend.calls, isEmpty);
    });

    test('normalizes before punctuation mapping and run splitting', () {
      final backend = _FakeChineseLegacyBackend(
        normalized: '中，ABC国',
        segments: <String, List<String>>{
          '中': <String>['中'],
          '国': <String>['国'],
        },
        pinyins: <String, List<String>>{
          '中': <String>['zhong1'],
          '国': <String>['guo2'],
        },
      );

      final result = ChineseLegacyG2pEngine(
        backend: backend,
      ).convert('100，ignored');

      expect(result.phonemes, 'ꭧʊ→ŋ, ABCkwo↗');
      expect(result.tokens, isNull);
      expect(backend.normalizationInputs, <String>['100，ignored']);
      expect(backend.segmentationInputs, <String>['中', '国']);
      expect(backend.pinyinInputs, <String>['中', '国']);
    });

    test('joins segmented words but concatenates each word syllables', () {
      final backend = _FakeChineseLegacyBackend(
        segments: <String, List<String>>{
          '中国人': <String>['中国', '人'],
        },
        pinyins: <String, List<String>>{
          '中国': <String>['zhong1', 'guo2'],
          '人': <String>['ren2'],
        },
      );

      final result = ChineseLegacyG2pEngine(backend: backend).convert('中国人');

      expect(result.phonemes, 'ꭧʊ→ŋkwo↗ ɻə↗n');
    });

    test('uses the first ordered IPA variant and applies legacy retone', () {
      final backend = _FakeChineseLegacyBackend(
        segments: <String, List<String>>{
          '何日': <String>['何', '日'],
        },
        pinyins: <String, List<String>>{
          '何': <String>['he2'],
          '日': <String>['ri3'],
        },
      );

      final result = ChineseLegacyG2pEngine(backend: backend).convert('何日');

      expect(result.phonemes, 'xɤ↗ ɻɨ↓');
    });

    test('removes U+032F only from the assembled output', () {
      final backend = _FakeChineseLegacyBackend(
        normalized: '爱ai̯',
        segments: <String, List<String>>{
          '爱': <String>['爱'],
        },
        pinyins: <String, List<String>>{
          '爱': <String>['ai4'],
        },
      );

      final result = ChineseLegacyG2pEngine(backend: backend).convert('爱ai̯');

      expect(result.phonemes, 'ai↘ai');
      expect(result.phonemes, isNot(contains('\u032f')));
    });

    test('splits only the inclusive U+4E00-U+9FFF scalar range', () {
      final backend = _FakeChineseLegacyBackend(
        segments: <String, List<String>>{
          '一': <String>['一'],
          '鿿': <String>['鿿'],
        },
        pinyins: <String, List<String>>{
          '一': <String>['yi1'],
          '鿿': <String>['er4'],
        },
      );

      final result = ChineseLegacyG2pEngine(backend: backend).convert('㐀一𠀋鿿ꀀ');

      expect(result.phonemes, '㐀i→𠀋ɚ↘ꀀ');
      expect(backend.segmentationInputs, <String>['一', '鿿']);
    });

    test('preserves non-Chinese runs and alternates around every CJK run', () {
      final backend = _FakeChineseLegacyBackend(
        segments: <String, List<String>>{
          '甲': <String>['甲'],
          '乙': <String>['乙'],
        },
        pinyins: <String, List<String>>{
          '甲': <String>['jia3'],
          '乙': <String>['yi3'],
        },
      );

      final result = ChineseLegacyG2pEngine(
        backend: backend,
      ).convert('A🙂甲-B乙 C');

      expect(result.phonemes, 'A🙂ʨja↓-Bi↓ C');
      expect(backend.segmentationInputs, <String>['甲', '乙']);
    });

    test('wraps failures at each backend stage with identity and cause', () {
      for (final stage in _FailureStage.values) {
        final error = FormatException(stage.name);
        final backend = _FakeChineseLegacyBackend(
          segments: <String, List<String>>{
            '甲': <String>['甲'],
          },
          pinyins: <String, List<String>>{
            '甲': <String>['jia3'],
          },
          failureStage: stage,
          error: error,
        );

        expect(
          () => ChineseLegacyG2pEngine(backend: backend).convert('甲'),
          throwsA(
            isA<BackendFailureException>()
                .having(
                  (exception) => exception.message,
                  'message',
                  contains('fake-chinese 0.9.4'),
                )
                .having((exception) => exception.cause, 'cause', same(error)),
          ),
          reason: stage.name,
        );
      }
    });

    test('reports invalid backend Pinyin as a typed backend failure', () {
      final backend = _FakeChineseLegacyBackend(
        segments: <String, List<String>>{
          '甲': <String>['甲'],
        },
        pinyins: <String, List<String>>{
          '甲': <String>['not-pinyin'],
        },
      );

      expect(
        () => ChineseLegacyG2pEngine(backend: backend).convert('甲'),
        throwsA(
          isA<BackendFailureException>()
              .having(
                (exception) => exception.message,
                'message',
                contains('invalid tone-3 Pinyin'),
              )
              .having(
                (exception) => exception.cause,
                'cause',
                isA<FormatException>(),
              ),
        ),
      );
    });

    test('preserves typed backend exceptions', () {
      const error = BackendUnavailableException('dictionary unavailable');
      final backend = _FakeChineseLegacyBackend(
        failureStage: _FailureStage.normalize,
        error: error,
      );

      expect(
        () => ChineseLegacyG2pEngine(backend: backend).convert('甲'),
        throwsA(same(error)),
      );
    });

    test('rejects empty normalization of non-whitespace input', () {
      final backend = _FakeChineseLegacyBackend(normalized: '　');

      expect(
        () => ChineseLegacyG2pEngine(backend: backend).convert('甲'),
        throwsA(
          isA<BackendFailureException>().having(
            (exception) => exception.message,
            'message',
            contains('normalized non-whitespace input to empty text'),
          ),
        ),
      );
    });

    test('rejects segmentation that drops, inserts, or reorders text', () {
      final malformedSegments = <List<String>>[
        <String>[],
        <String>['甲', ''],
        <String>['乙甲'],
      ];
      for (final segments in malformedSegments) {
        final backend = _FakeChineseLegacyBackend(
          segments: <String, List<String>>{'甲乙': segments},
        );
        expect(
          () => ChineseLegacyG2pEngine(backend: backend).convert('甲乙'),
          throwsA(
            isA<BackendFailureException>().having(
              (error) => error.message,
              'message',
              contains('does not preserve'),
            ),
          ),
          reason: segments.toString(),
        );
      }
    });

    test('rejects missing or empty pinyin syllables before rendering', () {
      for (final pinyins in <List<String>>[
        <String>['jia3'],
        <String>['jia3', ''],
      ]) {
        final backend = _FakeChineseLegacyBackend(
          segments: <String, List<String>>{
            '甲乙': <String>['甲乙'],
          },
          pinyins: <String, List<String>>{'甲乙': pinyins},
        );
        expect(
          () => ChineseLegacyG2pEngine(backend: backend).convert('甲乙'),
          throwsA(
            isA<BackendFailureException>().having(
              (error) => error.message,
              'message',
              contains('one non-empty syllable'),
            ),
          ),
          reason: pinyins.toString(),
        );
      }
    });
  });
}

enum _FailureStage { normalize, segment, pinyin }

final class _FakeChineseLegacyBackend implements ChineseLegacyBackend {
  _FakeChineseLegacyBackend({
    this.normalized,
    this.segments = const <String, List<String>>{},
    this.pinyins = const <String, List<String>>{},
    this.failureStage,
    this.error,
  });

  final String? normalized;
  final Map<String, List<String>> segments;
  final Map<String, List<String>> pinyins;
  final _FailureStage? failureStage;
  final Exception? error;

  final List<String> calls = <String>[];
  final List<String> normalizationInputs = <String>[];
  final List<String> segmentationInputs = <String>[];
  final List<String> pinyinInputs = <String>[];

  @override
  BackendInfo get info => BackendInfo(name: 'fake-chinese', version: '0.9.4');

  @override
  String normalizeNumbers(String text) {
    calls.add('normalize');
    normalizationInputs.add(text);
    _throwAt(_FailureStage.normalize);
    return normalized ?? text;
  }

  @override
  List<String> segmentChinese(String text) {
    calls.add('segment');
    segmentationInputs.add(text);
    _throwAt(_FailureStage.segment);
    return segments[text] ?? <String>[text];
  }

  @override
  List<String> tone3Pinyin(String word) {
    calls.add('pinyin');
    pinyinInputs.add(word);
    _throwAt(_FailureStage.pinyin);
    return pinyins[word] ?? const <String>[];
  }

  void _throwAt(_FailureStage stage) {
    if (failureStage == stage) {
      throw error!;
    }
  }
}
