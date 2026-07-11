/// Exact-resource English transformer adapter for Misakid.
library;

export 'package:misakid/misaki_en.dart';
export 'src/backend.dart'
    show
        NativeSpacyTransformerEnglishTokenizerBackend,
        defaultSpacyTransformerMaxPieces,
        maximumConfigurableSpacyTransformerPieces,
        spacyTransformerSupportedPlatform,
        spacyTransformerTagLabels;
export 'src/transformer/byte_bpe.dart'
    show
        SpacyTransformerByteBpe,
        SpacyTransformerByteBpeMerge,
        SpacyTransformerInputToken,
        SpacyTransformerPieceSequence,
        spacyTransformerByteBpePayloadByteLength,
        spacyTransformerByteBpePayloadSha256;
