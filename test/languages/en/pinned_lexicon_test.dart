import 'package:misakid/misaki_en.dart';
import 'package:test/test.dart';

void main() {
  const american = PinnedEnglishLexicon();

  group('PinnedEnglishLexicon lexical lookup', () {
    final cases = <({String text, String tag, String phonemes, int rating})>[
      (text: 'hello', tag: 'NN', phonemes: 'həlˈO', rating: 4),
      (text: 'Hello', tag: 'NN', phonemes: 'həlˈO', rating: 4),
      (text: 'NASA', tag: 'NNP', phonemes: 'nˈæsə', rating: 4),
      (text: 'FBI', tag: 'NNP', phonemes: 'ˌɛfbˌiˈI', rating: 3),
      (text: 'USA', tag: 'NNP', phonemes: 'jˌuˌɛsˈA', rating: 3),
      (text: 'Nato', tag: 'NNP', phonemes: 'nˈAɾO', rating: 4),
      (text: 'p.m.', tag: 'NN', phonemes: 'pˌiˈɛm', rating: 3),
      (text: 'a', tag: 'DT', phonemes: 'ɐ', rating: 4),
      (text: 'a', tag: 'NN', phonemes: 'ˈA', rating: 4),
      (text: 'am', tag: 'NN', phonemes: 'ˌAˈɛm', rating: 3),
      (text: 'AN', tag: 'NNP', phonemes: 'ˌAˈɛn', rating: 3),
      (text: 'I', tag: 'PRP', phonemes: 'ˌI', rating: 4),
      (text: 'by', tag: 'RB', phonemes: 'bˈI', rating: 4),
      (text: 'vs.', tag: 'IN', phonemes: 'vˈɜɹsəs', rating: 4),
    ];

    for (final entry in cases) {
      test('${entry.text}/${entry.tag}', () {
        final result = _lookup(american, entry.text, tag: entry.tag);
        expect(result?.phonemes, entry.phonemes);
        expect(result?.rating, entry.rating);
      });
    }

    test('returns null for unknown and non-ASCII lexical input', () {
      expect(_lookup(american, 'outofdictionary'), isNull);
      expect(_lookup(american, 'café', tag: 'NNP'), isNull);
      expect(_lookup(american, '😀', tag: 'NNP'), isNull);
    });

    test('uses aliases and applies explicit token stress last', () {
      expect(_lookup(american, 'ignored', alias: 'hello')?.phonemes, 'həlˈO');
      expect(_lookup(american, 'hello', stress: -2)?.phonemes, 'həlO');
    });
  });

  group('PinnedEnglishLexicon contextual special cases', () {
    test('selects to, in, the, and am from future vowel context', () {
      expect(_lookup(american, 'to', tag: 'TO')?.phonemes, 'tu');
      expect(
        _lookup(american, 'to', tag: 'TO', futureVowel: false)?.phonemes,
        'tə',
      );
      expect(
        _lookup(american, 'to', tag: 'TO', futureVowel: true)?.phonemes,
        'tʊ',
      );
      expect(_lookup(american, 'in', tag: 'IN')?.phonemes, 'ˈɪn');
      expect(
        _lookup(american, 'in', tag: 'IN', futureVowel: false)?.phonemes,
        'ɪn',
      );
      expect(
        _lookup(american, 'the', tag: 'DT', futureVowel: true)?.phonemes,
        'ði',
      );
      expect(
        _lookup(american, 'am', tag: 'VBP', futureVowel: false)?.phonemes,
        'ɐm',
      );
    });

    test('uses future-to context for used', () {
      expect(
        _lookup(
          american,
          'used',
          tag: 'VBD',
          futureVowel: false,
          futureTo: true,
        )?.phonemes,
        'jˈust',
      );
      expect(
        _lookup(american, 'used', tag: 'VBD', futureVowel: false)?.phonemes,
        'jˈuzd',
      );
    });
  });

  group('PinnedEnglishLexicon morphology', () {
    final cases = <({String text, String tag, String phonemes, int rating})>[
      (text: 'cats', tag: 'NNS', phonemes: 'kˈæts', rating: 3),
      (text: 'dogs', tag: 'NNS', phonemes: 'dˈɔɡz', rating: 4),
      (text: 'buses', tag: 'NNS', phonemes: 'bˈʌsᵻz', rating: 4),
      (text: 'walked', tag: 'VBD', phonemes: 'wˈɔkt', rating: 3),
      (text: 'played', tag: 'VBD', phonemes: 'plˈAd', rating: 3),
      (text: 'wanted', tag: 'VBD', phonemes: 'wˈɑntᵻd', rating: 4),
      (text: 'running', tag: 'VBG', phonemes: 'ɹˈʌnɪŋ', rating: 4),
      (text: 'making', tag: 'VBG', phonemes: 'mˈAkɪŋ', rating: 4),
    ];

    for (final entry in cases) {
      test(entry.text, () {
        final result = _lookup(american, entry.text, tag: entry.tag);
        expect(result?.phonemes, entry.phonemes);
        expect(result?.rating, entry.rating);
      });
    }
  });

  group('PinnedEnglishLexicon numbers', () {
    final cases = <String, String>{
      '0': 'zˈɪɹO',
      '21': 'twˈɛnti wˈʌn',
      '105': 'wˈʌn hˈʌndɹəd fˈIv',
      '1000': 'wˈʌn θˈWzᵊnd',
      '1000000': 'wˈʌn mˈɪljᵊn',
      '1,234': 'wˈʌn θˈWzᵊnd tˈu hˈʌndɹəd θˈɜɹɾi fˈɔɹ',
      '3.14': 'θɹˈi pYnt wˈʌn fˈɔɹ',
      '0.29': 'zˈɪɹO pYnt tˈu nˈIn',
      '10.01': 'tˈɛn pYnt zˈɪɹO wˈʌn',
      '0.05': 'zˈɪɹO pYnt zˈɪɹO fˈIv',
      '1st': 'fˈɜɹst',
      '21st': 'twˈɛnti fˈɜɹst',
      '102nd': 'wˈʌn hˈʌndɹəd sˈɛkənd',
      '1905': 'nˌIntˈin ˈO fˈIv',
      '2005': 'tˈu θˈWzᵊnd fˈIv',
      '2024': 'twˈɛnti twˈɛnti fˈɔɹ',
      '1990s': 'nˌIntˈin nˈIndiz',
      '12ed': 'twˈɛlvd',
      '12ing': 'twˈɛlvɪŋ',
      '-5': 'mˈInəs fˈIv',
    };

    for (final entry in cases.entries) {
      test(entry.key, () {
        final result = _lookup(american, entry.key, tag: 'CD');
        expect(result?.phonemes, entry.value);
        expect(result?.rating, 4);
      });
    }

    test('preserves non-head number grouping', () {
      expect(
        _lookup(american, '123', tag: 'CD', isHead: false)?.phonemes,
        'wˈʌn twˈɛnti θɹˈi',
      );
      expect(
        _lookup(american, '101', tag: 'CD', isHead: false)?.phonemes,
        'wˈʌn O wˈʌn',
      );
      expect(
        _lookup(american, '007', tag: 'CD', isHead: false)?.phonemes,
        'zˈɪɹO zˈɪɹO sˈɛvən',
      );
    });

    test('preserves number-control flags', () {
      expect(
        _lookup(american, '105', tag: 'CD', numberFlags: 'a')?.phonemes,
        'ə hˈʌndɹəd fˈIv',
      );
      expect(
        _lookup(american, '105', tag: 'CD', numberFlags: '&')?.phonemes,
        'wˈʌn hˈʌndɹəd ænd fˈIv',
      );
      expect(
        _lookup(american, '105', tag: 'CD', numberFlags: 'n')?.phonemes,
        'wˈʌn hˈʌndɹədən fˈIv',
      );
    });
  });

  group('PinnedEnglishLexicon currency and Unicode normalization', () {
    test('spells major and minor currency units exactly', () {
      expect(
        _lookup(american, '1', tag: 'CD', currency: r'$')?.phonemes,
        'wˈʌn dˈɑləɹ',
      );
      expect(
        _lookup(american, '2.50', tag: 'CD', currency: r'$')?.phonemes,
        'tˈu dˈɑləɹz ænd fˈɪfti sˈɛnts',
      );
      expect(
        _lookup(american, '0.50', tag: 'CD', currency: r'$')?.phonemes,
        'fˈɪfti sˈɛnts',
      );
      expect(
        _lookup(american, '4.01', tag: 'CD', currency: '€')?.phonemes,
        'fˈɔɹ jˈʊɹOz ænd wˈʌn sˈɛnt',
      );
    });

    test('applies NFKC and Python integral digit mapping', () {
      expect(_lookup(american, 'Ｈｅｌｌｏ')?.phonemes, 'həlˈO');
      for (final number in <String>['１２３', '١٢٣', '१२३']) {
        expect(
          _lookup(american, number, tag: 'CD')?.phonemes,
          'wˈʌn hˈʌndɹəd twˈɛnti θɹˈi',
        );
      }
      for (final one in <String>['①', '፩', '𐩀']) {
        expect(_lookup(american, one, tag: 'CD')?.phonemes, 'wˈʌn');
      }
      expect(_lookup(american, '²', tag: 'CD')?.phonemes, 'tˈu');
    });
  });

  group('PinnedEnglishLexicon British dialect', () {
    const british = PinnedEnglishLexicon(dialect: EnglishDialect.british);

    test('uses pinned British data and suffix vowels', () {
      expect(_lookup(british, 'hello')?.phonemes, 'həlˈQ');
      expect(_lookup(british, 'water')?.phonemes, 'wˈɔːtə');
      expect(_lookup(british, 'buses', tag: 'NNS')?.phonemes, 'bˈʌsɪz');
      expect(_lookup(british, 'wanted', tag: 'VBD')?.phonemes, 'wˈɒntɪd');
    });
  });

  test('reports stable identity and validates token metadata', () {
    expect(american.info.name, 'misaki-pinned-english-lexicon');
    expect(american.info.version, '0.9.4');
    expect(american.info.details['dialect'], 'american');
    expect(
      () => american.lookup(
        const MisakiToken(text: 'hello', tag: 'NN', whitespace: ''),
        const EnglishTokenContext(),
      ),
      throwsA(isA<MalformedDataException>()),
    );
  });
}

EnglishPronunciation? _lookup(
  PinnedEnglishLexicon lexicon,
  String text, {
  String tag = 'NN',
  bool isHead = true,
  String? alias,
  num? stress,
  String? currency,
  String numberFlags = '',
  bool? futureVowel,
  bool futureTo = false,
}) => lexicon.lookup(
  MisakiToken(
    text: text,
    tag: tag,
    whitespace: '',
    metadata: EnglishTokenMetadata(
      isHead: isHead,
      alias: alias,
      stress: stress,
      currency: currency,
      numberFlags: numberFlags,
    ),
  ),
  EnglishTokenContext(futureVowel: futureVowel, futureTo: futureTo),
);
