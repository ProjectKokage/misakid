/// Explicit MeCab-ko morphology and pure-Dart CMUdict adapters for Misaki.
///
/// This package never discovers or downloads native libraries, dictionaries,
/// or pronunciation data. Applications supply every checksum-pinned resource
/// path explicitly.
///
/// ```dart
/// final morphology = await MecabKoMorphologyBackend.open(
///   libraryPath: '/absolute/path/libmisakid_mecab_ko.dylib',
///   dictionaryPath: '/absolute/path/mecab_ko_dic/dictionary',
/// );
/// final cmu = await CmuDictionaryPronunciationProvider.open(
///   '/absolute/path/cmudict/cmudict',
/// );
/// final engine = KoreanG2pkcEngine(
///   morphology: morphology,
///   cmuPronunciations: cmu,
/// );
/// ```
library;

export 'package:misakid/misaki_ko.dart';
export 'src/backend.dart'
    show
        MecabKoMorphologyBackend,
        defaultMecabKoMaxInputBytes,
        mecabKoSupportedPlatform;
export 'src/cmu_dictionary.dart' show CmuDictionaryPronunciationProvider;
