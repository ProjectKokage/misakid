/// Chinese-specific APIs for the Misaki Dart port.
///
/// The legacy and 1.1 renderers are platform-neutral pure Dart, but this
/// core package does not bundle cn2an, Jieba, or pypinyin data. Supply an
/// explicit [ChineseLegacyBackend] or [ChineseFrontend11Backend]
/// implementation for the selected contract. The sibling
/// `misakid_chinese` package provides supported explicit-resource pure-Dart
/// backends for both contracts.
/// [ChineseTextNormalizer] accepts either the bundled pinned character map or
/// another explicit [ChineseCharacterConverter].
library;

export 'misaki.dart';
export 'src/languages/zh/frontend_1_1_engine.dart'
    show
        ChineseEnglishG2p,
        ChineseFrontend11,
        ChineseFrontend11Backend,
        ChineseFrontend11G2pEngine;
export 'src/languages/zh/inventory.dart'
    show ChinesePhonemeMode, chinesePhonemeInventory;
export 'src/languages/zh/legacy_engine.dart'
    show ChineseLegacyBackend, ChineseLegacyG2pEngine;
export 'src/languages/zh/normalization/character_converter.dart'
    show ChineseCharacterConverter, PinnedChineseCharacterConverter;
export 'src/languages/zh/normalization/text_normalizer.dart'
    show ChineseTextNormalizer;
export 'src/languages/zh/tone_sandhi.dart'
    show ChineseSandhiWord, ChineseToneSandhi, ChineseToneSandhiBackend;
