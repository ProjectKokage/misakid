import 'package:misakid/misaki_ko.dart';

void main() {
  final engine = KoreanG2pkcEngine(
    morphology: _RecordedMorphology(),
    cmuPronunciations: _NoEnglishPronunciations(),
  );
  print(engine.convert('안녕하세요.').phonemes);
}

// This fixed record demonstrates the provider shape only. Applications must
// inject a compatible real analyzer for arbitrary input.
final class _RecordedMorphology implements KoreanMorphologyBackend {
  @override
  final BackendInfo info = BackendInfo(name: 'recorded-example', version: '1');

  @override
  List<KoreanMorphologyToken> pos(String text) {
    if (text != '안녕하세요.') {
      throw ArgumentError.value(text, 'text', 'example supports one input');
    }
    return const <KoreanMorphologyToken>[
      KoreanMorphologyToken(surface: '안녕', tag: 'NNG'),
      KoreanMorphologyToken(surface: '하', tag: 'XSV'),
      KoreanMorphologyToken(surface: '세요', tag: 'EP+EF'),
      KoreanMorphologyToken(surface: '.', tag: 'SF'),
    ];
  }
}

final class _NoEnglishPronunciations implements KoreanCmuPronunciationProvider {
  @override
  final BackendInfo info = BackendInfo(name: 'none', version: '1');

  @override
  KoreanCmuPronunciation? lookup(String word) => null;
}
