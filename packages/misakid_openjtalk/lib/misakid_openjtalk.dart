/// Explicit macOS arm64 Open JTalk adapter for misakid Japanese G2P.
library;

export 'src/backend.dart'
    show
        OpenJtalkFrontendBackend,
        defaultOpenJtalkMaxInputBytes,
        openJtalkSupportedPlatform;
export 'src/dictionary_identity.dart'
    show
        openJtalkDictionaryName,
        openJtalkDictionarySizeBytes,
        openJtalkDictionaryTreeSha256;
export 'src/native_bindings.dart' show OpenJtalkNativeException;
