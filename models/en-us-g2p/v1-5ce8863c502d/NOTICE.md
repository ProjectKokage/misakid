# Misakid en-US G2P V1 notices

This is the Misakid project's original trained en-US neural fallback under
Apache License 2.0; see the adjacent `LICENSE`. Its only training inputs are
the American English lexicons from hexgrad's Misaki 0.9.4 at commit
`fba1236595f2d2bf21d414ba6e57d25256afada3`:

| Source path | Bytes | SHA-256 |
| --- | ---: | --- |
| `misaki/data/us_gold.json` | 3,000,469 | `dc414872a49a28ae6c141463d502fd945f3b2fde040484fdc47d00cc4612686f` |
| `misaki/data/us_silver.json` | 3,099,517 | `de8f67be911bb6c659187b4a65fd966b6a30e56350e0f790d763210b053ac475` |

Source repository: [hexgrad/misaki](https://github.com/hexgrad/misaki/tree/fba1236595f2d2bf21d414ba6e57d25256afada3).
The same exact files appear in the author's
[Apache-2.0 dataset snapshot](https://huggingface.co/datasets/hexgrad/misaki/tree/b65a6b4398e053983b9c360f0682b720e362859d).
The pinned Misaki repository has no root NOTICE file. The full provenance
review remains in Misakid's [THIRD_PARTY_NOTICES.md](../../../THIRD_PARTY_NOTICES.md#english-and-shared-language-data).

Misakid's training tool merges these sources with gold `DEFAULT`
pronunciations overriding matching silver spellings and groups case-folded
spellings into one deterministic train/development/test partition. The graph
is a newly trained medium convolutional/BiGRU CTC model; it is not a copy of
PeterReid/BART weights and uses no eSpeak corpus or unrecorded training source.
The source lexicon files are not included in this artifact directory.

The runtime pair is distinct from the optional `misakid_fonix_en` adapter,
Fonix, ONNX Runtime, spaCy models, and Kokoro models/voices. Their own licenses,
notices, and application packaging obligations remain separate. Publishing
this G2P pair grants no additional rights in those resources and makes no
physical-device or signed-package qualification claim.
