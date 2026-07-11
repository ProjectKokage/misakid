import 'package:misakid_chinese/misakid_chinese.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 7) {
    throw ArgumentError(
      'Usage: chinese_legacy.dart <jieba-dict> <prob-start> <prob-trans> '
      '<prob-emit> <pinyin-dict> <phrases-dict> <text>',
    );
  }
  final backend = await PureDartChineseLegacyBackend.open(
    jiebaDictionaryPath: arguments[0],
    jiebaProbabilityStartPath: arguments[1],
    jiebaProbabilityTransitionPath: arguments[2],
    jiebaProbabilityEmissionPath: arguments[3],
    pypinyinDictionaryPath: arguments[4],
    pypinyinPhrasesPath: arguments[5],
  );
  final result = ChineseLegacyG2pEngine(backend: backend).convert(arguments[6]);
  print(result.phonemes);
}
