import 'package:misakid/src/languages/zh/transcription.dart';
import 'package:test/test.dart';

void main() {
  group('pinyinToIpa', () {
    test('preserves all five exact tone renderings', () {
      final cases = <String, List<String>>{
        'mā': <String>['m', 'a˥'],
        'má': <String>['m', 'a˧˥'],
        'mǎ': <String>['m', 'a˧˩˧'],
        'mà': <String>['m', 'a˥˩'],
        'ma': <String>['m', 'a'],
        'ma5': <String>['m', 'a'],
      };

      for (final entry in cases.entries) {
        expect(_onlyVariant(entry.key), entry.value, reason: entry.key);
      }
    });

    test('preserves the six Misaki-specific initial symbols', () {
      expect(_onlyVariant('ca1'), <String>['ʦʰ', 'a˥']);
      expect(_onlyVariant('cha2'), <String>['ꭧʰ', 'a˧˥']);
      expect(_onlyVariant('ji3'), <String>['ʨ', 'i˧˩˧']);
      expect(_onlyVariant('qi4'), <String>['ʨʰ', 'i˥˩']);
      expect(_variants('zi1'), <List<String>>[
        <String>['ʦ', 'ɹ̩˥'],
        <String>['ʦ', 'z̩˥'],
      ]);
      expect(_variants('zhi2'), <List<String>>[
        <String>['ꭧ', 'ɻ̩˧˥'],
        <String>['ꭧ', 'ʐ̩˧˥'],
      ]);
    });

    test('preserves ordered initial and final variant products', () {
      expect(_variants('he4'), <List<String>>[
        <String>['x', 'ɤ˥˩'],
        <String>['h', 'ɤ˥˩'],
      ]);
      expect(_variants('ri3'), <List<String>>[
        <String>['ɻ', 'ɻ̩˧˩˧'],
        <String>['ɻ', 'ʐ̩˧˩˧'],
        <String>['ʐ', 'ɻ̩˧˩˧'],
        <String>['ʐ', 'ʐ̩˧˩˧'],
      ]);
      expect(_variants('er2'), <List<String>>[
        <String>['ɚ˧˥'],
        <String>['aɚ̯˧˥'],
      ]);
    });

    test('covers the canonical final inventory', () {
      final cases = <String, List<String>>{
        'a1': <String>['a˥'],
        'ai2': <String>['ai̯˧˥'],
        'an3': <String>['a˧˩˧', 'n'],
        'ang4': <String>['a˥˩', 'ŋ'],
        'ao1': <String>['au̯˥'],
        'e2': <String>['ɤ˧˥'],
        'ei3': <String>['ei̯˧˩˧'],
        'en4': <String>['ə˥˩', 'n'],
        'eng1': <String>['ə˥', 'ŋ'],
        'i2': <String>['i˧˥'],
        'ia3': <String>['j', 'a˧˩˧'],
        'ian4': <String>['j', 'ɛ˥˩', 'n'],
        'iang1': <String>['j', 'a˥', 'ŋ'],
        'iao2': <String>['j', 'au̯˧˥'],
        'ie3': <String>['j', 'e˧˩˧'],
        'in4': <String>['i˥˩', 'n'],
        'iou1': <String>['j', 'ou̯˥'],
        'ing2': <String>['i˧˥', 'ŋ'],
        'iong3': <String>['j', 'ʊ˧˩˧', 'ŋ'],
        'ong4': <String>['ʊ˥˩', 'ŋ'],
        'ou1': <String>['ou̯˥'],
        'u2': <String>['u˧˥'],
        'uei3': <String>['w', 'ei̯˧˩˧'],
        'ua4': <String>['w', 'a˥˩'],
        'uai1': <String>['w', 'ai̯˥'],
        'uan2': <String>['w', 'a˧˥', 'n'],
        'uen3': <String>['w', 'ə˧˩˧', 'n'],
        'uang4': <String>['w', 'a˥˩', 'ŋ'],
        'ueng1': <String>['w', 'ə˥', 'ŋ'],
        'uo2': <String>['w', 'o˧˥'],
        'lo1': <String>['l', 'w', 'o˥'],
        'ü3': <String>['y˧˩˧'],
        'üe4': <String>['ɥ', 'e˥˩'],
        'üan1': <String>['ɥ', 'ɛ˥', 'n'],
        'ün2': <String>['y˧˥', 'n'],
      };

      for (final entry in cases.entries) {
        expect(_onlyVariant(entry.key), entry.value, reason: entry.key);
      }
    });

    test('restores strict zero-initial and contracted-final spellings', () {
      final cases = <String, List<String>>{
        'yi1': <String>['i˥'],
        'ya2': <String>['j', 'a˧˥'],
        'ye3': <String>['j', 'e˧˩˧'],
        'you5': <String>['j', 'ou̯'],
        'yan1': <String>['j', 'ɛ˥', 'n'],
        'yin2': <String>['i˧˥', 'n'],
        'yang3': <String>['j', 'a˧˩˧', 'ŋ'],
        'ying4': <String>['i˥˩', 'ŋ'],
        'yong1': <String>['j', 'ʊ˥', 'ŋ'],
        'wu1': <String>['u˥'],
        'wa2': <String>['w', 'a˧˥'],
        'wo3': <String>['w', 'o˧˩˧'],
        'wei1': <String>['w', 'ei̯˥'],
        'wen3': <String>['w', 'ə˧˩˧', 'n'],
        'weng1': <String>['w', 'ə˥', 'ŋ'],
        'ju4': <String>['ʨ', 'y˥˩'],
        'jue2': <String>['ʨ', 'ɥ', 'e˧˥'],
        'juan3': <String>['ʨ', 'ɥ', 'ɛ˧˩˧', 'n'],
        'jun1': <String>['ʨ', 'y˥', 'n'],
        'niu2': <String>['n', 'j', 'ou̯˧˥'],
        'gui1': <String>['k', 'w', 'ei̯˥'],
        'lun4': <String>['l', 'w', 'ə˥˩', 'n'],
      };

      for (final entry in cases.entries) {
        expect(_onlyVariant(entry.key), entry.value, reason: entry.key);
      }
    });

    test('preserves syllabic consonants and interjections', () {
      final cases = <String, List<String>>{
        'm̄': <String>['m˥'],
        'ḿ': <String>['m˧˥'],
        'm̀': <String>['m˥˩'],
        'ń': <String>['n˧˥'],
        'ň': <String>['n˧˩˧'],
        'ǹ': <String>['n˥˩'],
        'ng3': <String>['ŋ˧˩˧'],
        'hm4': <String>['h', 'm˥˩'],
        'hng2': <String>['h', 'ŋ˧˥'],
        'io4': <String>['j', 'ɔ˥˩'],
        'ê̄': <String>['ɛ˥'],
        'ê̌': <String>['ɛ˧˩˧'],
        'o1': <String>['ɔ˥'],
      };

      for (final entry in cases.entries) {
        expect(_onlyVariant(entry.key), entry.value, reason: entry.key);
      }
    });

    test('matches pypinyin tone normalization quirks', () {
      final cases = <String, List<String>>{
        'zho1ng': <String>['ꭧ', 'ʊ˥', 'ŋ'],
        'lv4': <String>['l', 'y˥˩'],
        'lü4': <String>['l', 'y˥˩'],
        'lǜ': <String>['l', 'y˥˩'],
        'mā2': <String>['m', 'a˥'],
        'ma12': <String>['m', 'a˥'],
        'ma55': <String>['m', 'a'],
        'ma１': <String>['m', 'a˥'],
        'ma٢': <String>['m', 'a˧˥'],
        'ma𝟛': <String>['m', 'a˧˩˧'],
      };

      for (final entry in cases.entries) {
        expect(_onlyVariant(entry.key), entry.value, reason: entry.key);
      }
    });

    test('preserves pinned invalid-input categories and messages', () {
      final cases = <String, String>{
        '': "Parameter 'pinyin': Tone couldn't be detected!",
        'ma0': "Parameter 'pinyin': Tone '0' couldn't be detected!",
        'ma6': "Parameter 'pinyin': Tone '6' couldn't be detected!",
        'u:1': "Parameter 'pinyin': Tone ':' couldn't be detected!",
        'Ma1': "Parameter 'normal_pinyin': Final couldn't be detected!",
        'foo1': "Parameter 'normal_pinyin': Final couldn't be detected!",
        '1': "Parameter 'normal_pinyin': Final couldn't be detected!",
        'zh': "Parameter 'normal_pinyin': Final couldn't be detected!",
        '𠀋1': "Parameter 'normal_pinyin': Final couldn't be detected!",
        'y𠀋1': "Parameter 'normal_pinyin': Final couldn't be detected!",
      };

      for (final entry in cases.entries) {
        expect(
          () => pinyinToIpa(entry.key),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              entry.value,
            ),
          ),
          reason: entry.key,
        );
      }
    });

    test('freezes the ordered result and each phoneme tuple', () {
      final variants = pinyinToIpa('ri3');

      expect(() => variants.add(variants.first), throwsUnsupportedError);
      expect(() => variants.first.phonemes.add('x'), throwsUnsupportedError);
    });
  });
}

List<List<String>> _variants(String pinyin) => <List<String>>[
  for (final variant in pinyinToIpa(pinyin)) variant.phonemes,
];

List<String> _onlyVariant(String pinyin) {
  final variants = _variants(pinyin);
  expect(variants, hasLength(1), reason: pinyin);
  return variants.single;
}
