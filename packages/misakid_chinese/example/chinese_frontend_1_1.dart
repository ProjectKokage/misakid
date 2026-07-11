import 'package:misakid_chinese/misakid_chinese.dart';

Future<void> main() async {
  final backend = await PureDartChineseFrontend11Backend.open(
    jiebaDictionaryPath: '/absolute/path/jieba/dict.txt',
    jiebaProbabilityStartPath: '/absolute/path/jieba/finalseg/prob_start.p',
    jiebaProbabilityTransitionPath:
        '/absolute/path/jieba/finalseg/prob_trans.p',
    jiebaProbabilityEmissionPath: '/absolute/path/jieba/finalseg/prob_emit.p',
    jiebaPartOfSpeechCharacterStatePath:
        '/absolute/path/jieba/posseg/char_state_tab.p',
    jiebaPartOfSpeechProbabilityStartPath:
        '/absolute/path/jieba/posseg/prob_start.p',
    jiebaPartOfSpeechProbabilityTransitionPath:
        '/absolute/path/jieba/posseg/prob_trans.p',
    jiebaPartOfSpeechProbabilityEmissionPath:
        '/absolute/path/jieba/posseg/prob_emit.p',
    pypinyinDictionaryPath: '/absolute/path/pypinyin/pinyin_dict.json',
    pypinyinPhrasesPath: '/absolute/path/pypinyin/phrases_dict.json',
    pypinyinLargePhrasesPath:
        '/absolute/path/phrase-pinyin-data/large_pinyin.txt',
  );
  final result = ChineseFrontend11G2pEngine(backend: backend).convert('你好，世界！');
  print(result.phonemes);
}
