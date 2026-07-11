/// Pure-Dart, explicitly provisioned Chinese providers for Misaki.
///
/// This package never discovers or downloads dictionaries. Applications pass
/// every checksum-pinned resource path or immutable byte bundle explicitly
/// before constructing a synchronous Chinese engine.
library;

export 'package:misakid/misaki_zh.dart';
export 'src/cn2an.dart' show Cn2AnNormalizer;
export 'src/frontend_1_1_backend.dart' show PureDartChineseFrontend11Backend;
export 'src/frontend_1_1_english.dart' show ChineseFrontend11EnglishG2pEngine;
export 'src/jieba.dart' show JiebaSegmenter, maximumJiebaSegmentInputScalars;
export 'src/legacy_backend.dart' show PureDartChineseLegacyBackend;
export 'src/pypinyin.dart'
    show PypinyinTone3Provider, maximumPypinyinTone3InputScalars;
export 'src/resource_bundle.dart'
    show ChineseFrontend11ResourceBundle, ChineseLegacyResourceBundle;
