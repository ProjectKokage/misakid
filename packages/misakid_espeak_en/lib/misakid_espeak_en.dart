/// Explicit macOS-arm64 eSpeak NG fallback backend for Misakid English.
///
/// Callers provide the package-owned adapter dylib, exact eSpeak NG dylib, and
/// complete data directory as absolute paths. This package never discovers,
/// downloads, or bundles the GPL runtime.
library;

export 'package:misakid/misaki_en.dart';
export 'src/backend.dart'
    show
        EspeakEnglishBackend,
        defaultEspeakEnglishMaxInputBytes,
        defaultEspeakEnglishMaxOutputBytes,
        espeakEnglishSupportedPlatform;
export 'src/resource_identity.dart'
    show
        pinnedEspeakNgDataFileCount,
        pinnedEspeakNgDataDirectoryCount,
        pinnedEspeakNgDataSizeBytes,
        pinnedEspeakNgDataTreeSha256,
        pinnedEspeakNgLibrarySha256,
        pinnedEspeakNgLibrarySizeBytes;
export 'src/phonemizer_contract.dart' show maximumEspeakEnglishChunksPerCall;
