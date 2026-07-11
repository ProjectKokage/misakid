/// Explicit native MeCab/UniDic adapter for Misaki Japanese Cutlet mode.
///
/// This package builds its reviewed MeCab source as a native asset and never
/// discovers or downloads a dictionary or grouping lexicon. Applications
/// provide data resources explicitly. The
/// grouping data remains behind [JapaneseCutletWordMembership], so its source,
/// license, version, and identity are owned by the application or a separately
/// reviewed data package.
///
/// ```dart
/// final backend = await MecabJapaneseCutletBackend.openBundled(
///   dictionaryPath: '/absolute/path/unidic-3.1.0',
///   wordListBytes: wordListBytes,
/// );
/// final engine = JapaneseCutletEngine(backend: backend);
/// final result = engine.convert('日本語です');
/// backend.close();
/// ```
library;

export 'package:misakid/misaki_ja.dart';
export 'src/backend.dart'
    show
        MecabJapaneseCutletBackend,
        MecabJapaneseRawWord,
        defaultMecabJapaneseMaxInputBytes,
        mecabJapaneseBundledBuildPlatforms,
        mecabJapaneseSupportedPlatform;
export 'src/kata_to_hiragana.dart' show cutletKataToHiragana;
export 'src/word_membership.dart'
    show
        JapaneseCutletWordMembership,
        PinnedMisakiCutletWordMembership,
        pinnedMisakiCutletWordsRecordCount,
        pinnedMisakiCutletWordsSha256,
        pinnedMisakiCutletWordsSizeBytes;
