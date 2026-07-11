import 'package:misakid/misaki_zh.dart';

void main() {
  final legacy = ChineseLegacyG2pEngine(backend: _RecordedLegacyBackend());
  final frontend11 = ChineseFrontend11G2pEngine(
    backend: _RecordedFrontend11Backend(),
  );

  print(legacy.convert('你好').phonemes);
  print(frontend11.convert('你好').phonemes);
}

// These fixed records demonstrate the public provider shapes only. Production
// applications must inject versioned cn2an/jieba/pypinyin-equivalent adapters
// that validate their packages and dictionaries before processing text.
final class _RecordedLegacyBackend implements ChineseLegacyBackend {
  @override
  final BackendInfo info = BackendInfo(
    name: 'recorded-chinese-legacy-example',
    version: '1',
  );

  @override
  String normalizeNumbers(String text) => text;

  @override
  List<String> segmentChinese(String text) {
    if (text != '你好') {
      throw ArgumentError.value(text, 'text', 'example supports only 你好');
    }
    return <String>['你好'];
  }

  @override
  List<String> tone3Pinyin(String word) {
    if (word != '你好') {
      throw ArgumentError.value(word, 'word', 'example supports only 你好');
    }
    return <String>['ni3', 'hao3'];
  }
}

final class _RecordedFrontend11Backend implements ChineseFrontend11Backend {
  @override
  final BackendInfo info = BackendInfo(
    name: 'recorded-chinese-frontend-1.1-example',
    version: '1',
  );

  @override
  String normalizeNumbers(String text) => text;

  @override
  List<ChineseSandhiWord> segmentWithPartOfSpeech(String text) {
    if (text != '你好') {
      throw ArgumentError.value(text, 'text', 'example supports only 你好');
    }
    return const <ChineseSandhiWord>[
      ChineseSandhiWord(word: '你好', partOfSpeech: 'l'),
    ];
  }

  @override
  List<String> initials(String word) {
    _requireGreeting(word);
    return <String>['n', 'h'];
  }

  @override
  List<String> tone3Finals(String word) {
    _requireGreeting(word);
    return <String>['i3', 'ao3'];
  }

  @override
  List<String> searchSegments(String word) {
    _requireGreeting(word);
    return <String>['你好'];
  }

  static void _requireGreeting(String word) {
    if (word != '你好') {
      throw ArgumentError.value(word, 'word', 'example supports only 你好');
    }
  }
}
