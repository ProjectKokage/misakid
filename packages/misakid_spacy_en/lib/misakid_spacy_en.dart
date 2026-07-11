/// Exact-resource English tokenizer/tagger adapter for Misakid.
library;

export 'package:misakid/misaki_en.dart';
export 'src/backend.dart'
    show
        PureDartSpacyEnglishTokenizerBackend,
        PureDartSpacyEnglishTokenizer,
        SpacyEnglishRawToken,
        SpacyEnglishTokenization,
        maximumSpacyEnglishInputScalars,
        maximumSpacyEnglishTokens;
export 'src/resource_identity.dart'
    show
        spacyEnglishTaggerModelSha256,
        spacyEnglishTaggerModelSizeBytes,
        spacyEnglishTok2vecModelSha256,
        spacyEnglishTok2vecModelSizeBytes,
        spacyEnglishTokenizerSha256,
        spacyEnglishTokenizerSizeBytes,
        spacyEnglishVocabLookupsSha256,
        spacyEnglishVocabLookupsSizeBytes;
