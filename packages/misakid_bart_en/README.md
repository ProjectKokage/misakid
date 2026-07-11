# misakid_bart_en

Experimental pure-Dart one-layer BART inference at Misakid's English fallback
boundary.

This adapter uses `dart:io` for explicit resource files and therefore supports
the Dart VM only, not web builds. Model execution itself uses Dart code and no
native inference library.

The caller must provide absolute paths to a BART JSON configuration and F32
safetensors file, together with their exact byte sizes and SHA-256 digests.
The package never discovers, downloads, or bundles model resources. It accepts
only the narrow one-encoder-layer/one-decoder-layer architecture documented by
the API.

The current whitelist requires F32 GELU BART, one encoder layer, one decoder
layer, fixed special IDs `0/1/2/3`, unscaled embeddings, at most 128 hidden
dimensions, 8 heads, 1024 feed-forward dimensions, 64 positions, 256 vocabulary
entries, and 16 MiB of weights. All tensor names and shapes must match exactly.
Configuration JSON is limited to 1 MiB and rejects duplicate keys. Resource
paths must name absolute, real files rather than symbolic links.

Input is limited to `model.max_position_embeddings - 2` Unicode scalars and
never more than 62. The total generated decoder length defaults to 20 and may
be configured from 2 through the model's positional limit, never above 64.

```dart
final backend = await BartEnglishBackend.open(
  configPath: '/absolute/model/config.json',
  weightsPath: '/absolute/model/model.safetensors',
  identity: BartEnglishResourceIdentity(
    name: 'my-reviewed-model',
    version: '1',
    configSizeBytes: 1234,
    configSha256: '...64 lowercase hexadecimal characters...',
    weightsSizeBytes: 123456,
    weightsSha256: '...64 lowercase hexadecimal characters...',
  ),
);
```

This package has not been verified against the `PeterReid` model weights used
by pinned Python Misaki. Those weights are not accepted as parity evidence or
redistributed here because their model cards do not document sufficient weight
and training-data provenance. Supplying resources is an explicit decision by
the caller and does not make them supported by Misakid.

The committed tiny fixture contains only formula-generated synthetic weights.
Its expected encoder states, logits, and greedy IDs come from CPU
`BartForConditionalGeneration` under CPython 3.12.11 on Darwin arm64, Torch 2.6.0,
Transformers 4.51.3, safetensors 0.5.3, and SDPA attention. The complete Python
closure is the repository's pinned English eSpeak oracle closure. The Dart
runtime uses an explicitly ordered float32 scalar implementation and stays
within `1e-6` of that fixture's recorded values. This numerical test is not a
claim about any external model.

Checking is read-only and is also the command's default mode. Regeneration is
explicit and prints sizes, hashes, a per-file added/changed/unchanged summary,
and unified diffs for changed JSON:

```sh
/path/to/pinned/python tool/generate_synthetic_fixture.py --check
/path/to/pinned/python tool/generate_synthetic_fixture.py --accept
```
