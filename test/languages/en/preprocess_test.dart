import 'package:misakid/src/languages/en/preprocess.dart';
import 'package:test/test.dart';

void main() {
  const preprocessor = EnglishInlinePreprocessor();

  group('Python 3.12 whitespace behavior', () {
    test('lstrips input and splits ordinary text without changing spacing', () {
      final result = preprocessor.preprocess(' \t\nHello   world');

      expect(result.text, 'Hello   world');
      expect(result.sourceWords, <String>['Hello', 'world']);
      expect(result.controls, isEmpty);
    });

    test('recognizes CPython information separators and Unicode spaces', () {
      final result = preprocessor.preprocess(
        '\u001c\u00a0alpha\u2007beta\u3000gamma',
      );

      expect(result.text, 'alpha\u2007beta\u3000gamma');
      expect(result.sourceWords, <String>['alpha', 'beta', 'gamma']);
    });

    test('returns empty immutable outputs for whitespace-only input', () {
      final result = preprocessor.preprocess(' \t\u3000');

      expect(result.text, '');
      expect(result.sourceWords, isEmpty);
      expect(result.controls, isEmpty);
      expect(() => result.sourceWords.add('x'), throwsUnsupportedError);
      expect(
        () => result.controls[0] = const EnglishStressControl(1),
        throwsUnsupportedError,
      );
    });
  });

  group('source-word alignment', () {
    test('retains a link source as one word and indexes surrounding words', () {
      final result = preprocessor.preprocess(
        '\u001c\u00a0[hello world](/həˈloʊ///)  + [42](#an###)!',
      );

      expect(result.text, 'hello world  + 42!');
      expect(result.sourceWords, <String>['hello world', '+', '42', '!']);
      expect(result.controls.keys, <int>[0, 2]);
      final pronunciation = result.controls[0] as EnglishPronunciationControl;
      final flags = result.controls[2] as EnglishNumberFlagsControl;
      expect(pronunciation.encoded, '/həˈloʊ');
      expect(pronunciation.phonemes, 'həˈloʊ');
      expect(flags.encoded, '#an');
      expect(flags.flags, 'an');
    });

    test('aligns multiple valid controls to their source indices', () {
      final result = preprocessor.preprocess(
        '[hello world](/həˈloʊ///)  + [42](#an###!#)',
      );

      expect(result.text, 'hello world  + 42');
      expect(result.sourceWords, <String>['hello world', '+', '42']);
      expect(result.controls.keys, <int>[0, 2]);
      final pronunciation = result.controls[0] as EnglishPronunciationControl;
      final flags = result.controls[2] as EnglishNumberFlagsControl;
      expect(pronunciation.encoded, '/həˈloʊ');
      expect(flags.encoded, '#an###!');
      expect(flags.flags, 'an###!');
    });

    test('preserves newlines inside a visible link source', () {
      final result = preprocessor.preprocess('[line\nbreak](/a/)');

      expect(result.text, 'line\nbreak');
      expect(result.sourceWords, <String>['line\nbreak']);
      expect(result.controls.keys, <int>[0]);
    });
  });

  group('stress controls', () {
    test('parses signed integers and only the supported half steps', () {
      final result = preprocessor.preprocess(
        '[a](-2) [b](+3) [c](0.5) [d](+0.5) [e](-0.5) '
        '[f](-0) [g](01)',
      );

      expect(result.text, 'a b c d e f g');
      final stresses = <num>[
        for (var index = 0; index < 7; index++)
          (result.controls[index] as EnglishStressControl).stress,
      ];
      expect(stresses, <num>[-2, 3, 0.5, 0.5, -0.5, 0, 1]);
      expect(stresses[0], isA<int>());
      expect(stresses[2], isA<double>());
    });
  });

  group('slash and hash controls', () {
    test('strips repeated trailing delimiters with upstream encoding', () {
      final result = preprocessor.preprocess(
        '[x](//a///) [empty](//) [n](##an###) [z](##)',
      );

      final x = result.controls[0] as EnglishPronunciationControl;
      final emptyPronunciation =
          result.controls[1] as EnglishPronunciationControl;
      final n = result.controls[2] as EnglishNumberFlagsControl;
      final emptyFlags = result.controls[3] as EnglishNumberFlagsControl;
      expect(x.encoded, '//a');
      expect(x.phonemes, 'a');
      expect(emptyPronunciation.encoded, '/');
      expect(emptyPronunciation.phonemes, '');
      expect(n.encoded, '##an');
      expect(n.flags, 'an');
      expect(emptyFlags.encoded, '#');
      expect(emptyFlags.flags, '');
    });
  });

  group('invalid and malformed controls', () {
    test(
      'ignores invalid destinations but still removes valid link syntax',
      () {
        final result = preprocessor.preprocess(
          '[a]() [b](/) [c](#) [d](0.0) [e]( 1) [f](１２) '
          '[g](+0.50) [h](abc)',
        );

        expect(result.text, 'a b c d e f g h');
        expect(result.sourceWords, <String>[
          'a',
          'b',
          'c',
          'd',
          'e',
          'f',
          'g',
          'h',
        ]);
        expect(result.controls, isEmpty);
      },
    );

    test('leaves malformed trailing link text untouched', () {
      final result = preprocessor.preprocess('[a](/x/) tail [broken](/x/');

      expect(result.text, 'a tail [broken](/x/');
      expect(result.sourceWords, <String>['a', 'tail', '[broken](/x/']);
      expect((result.controls[0] as EnglishPronunciationControl).encoded, '/x');
    });

    test('uses the first closing bracket just like the pinned regex', () {
      final result = preprocessor.preprocess('[a[b](/x/)');

      expect(result.text, 'a[b');
      expect(result.sourceWords, <String>['a[b']);
      expect((result.controls[0] as EnglishPronunciationControl).phonemes, 'x');
    });
  });

  test(
    'preserves supplementary and decomposed source text without normalization',
    () {
      final result = preprocessor.preprocess(
        '\u3000[𠀋 e\u0301](/ɐˈb/) café\u00a0😀',
      );

      expect(result.text, '𠀋 e\u0301 café\u00a0😀');
      expect(result.sourceWords, <String>['𠀋 e\u0301', 'café', '😀']);
      final pronunciation = result.controls[0] as EnglishPronunciationControl;
      expect(pronunciation.encoded, '/ɐˈb');
      expect(pronunciation.phonemes, 'ɐˈb');
    },
  );
}
