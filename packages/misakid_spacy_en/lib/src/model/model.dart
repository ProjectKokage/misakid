/// Internal exact small-English model inference API.
library;

export 'inference.dart'
    show
        SpacyEnglishInferenceResult,
        SpacyEnglishTaggerModel,
        SpacyFloat32Matrix,
        SpacyTokenFeatures,
        maximumSpacyEnglishModelTokens;
export 'murmur_hash.dart' show murmurHash3X86_128Uint64;
export 'parameters.dart'
    show
        SpacyEmbeddingTableParameters,
        SpacyEnglishModelParameters,
        SpacyMaxoutLayerParameters,
        SpacyTaggerLinearParameters;
export 'serialized_model_loader.dart' show SpacyEnglishSerializedModelLoader;
