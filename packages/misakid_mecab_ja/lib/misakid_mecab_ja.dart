/// Explicit native MeCab/UniDic adapter for Misaki Japanese Cutlet mode.
///
/// This package builds its reviewed MeCab source as a native asset and never
/// discovers or downloads a dictionary or grouping lexicon. Applications
/// provide data resources explicitly. By default, the backend accepts a
/// caller-selected compatible UTF-8 UniDic with a 26- or 29-field feature
/// layout. That layout does not distinguish CWJ from CSJ. Dictionary-dependent
/// segmentation and readings can change output, so this default carries no
/// exact Misaki parity claim.
///
/// Select [MecabJapaneseDictionaryProfile.pinnedUnidicPyCwjParity] to require
/// the complete modified unidic-py CWJ tree used by the committed fixtures.
/// Its tree hash establishes identity; its 3.1.0 release marker alone does not.
/// The grouping data remains behind [JapaneseCutletWordMembership], so its
/// source, license, version, and identity are owned by the application or a
/// separately reviewed data package.
///
/// ```dart
/// final backend = await MecabJapaneseCutletBackend.openBundled(
///   dictionaryPath: '/absolute/path/pinned-unidic-py-cwj',
///   wordListBytes: wordListBytes,
///   dictionaryProfile:
///       MecabJapaneseDictionaryProfile.pinnedUnidicPyCwjParity,
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
        MecabJapaneseDictionaryProfile,
        MecabJapaneseRawWord,
        MecabJapaneseUnidicFeatureLayout,
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
