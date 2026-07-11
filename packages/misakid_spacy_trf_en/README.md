# misakid_spacy_trf_en

Exact, offline English transformer tokenizer/tagger for pinned Misaki 0.9.4
and `en_core_web_trf==3.8.0`.

The supported configuration is deliberately narrow:

- macOS 11 or newer on arm64;
- the exact caller-supplied `en_core_web_trf==3.8.0` model directory;
- a package-owned native library built from this package's reviewed source;
- American or British English with legacy or 2.0 phoneme rendering; and
- no fallback, or the separately supported `misakid_espeak_en` fallback.

Tokenization, byte-BPE, alignment, and resource validation run in Dart. The
native library evaluates the 12-layer RoBERTa graph and 49-label tagger with
Apple Accelerate. Conversion invokes neither Python, spaCy, Torch, a
subprocess, nor the network. No model or prebuilt native binary is bundled,
discovered, or downloaded.

Misaki's PeterReid BART fallback is a different backend and remains
unsupported because its model provenance is unresolved.

## Prerequisites

Building the native library requires:

- macOS 11 or newer on Apple silicon;
- Dart 3.11.5 or a compatible newer release below Dart 4;
- CMake 3.20 or newer; and
- Xcode Command Line Tools or Xcode with Apple Clang C++17 and Accelerate.

Check the build tools with `cmake --version` and `clang++ --version`. Python,
spaCy, Torch, and `package:ffi` are not build or runtime requirements.

## Obtain the model

Obtain Explosion's official wheel explicitly:

```text
https://github.com/explosion/spacy-models/releases/download/
en_core_web_trf-3.8.0/en_core_web_trf-3.8.0-py3-none-any.whl

Bytes:   457421864
SHA-256: 272a31e9d8530d1e075351d30a462d7e80e31da23574f1b274e200f3fff35bf5
```

Extract the wheel as a ZIP archive without installing it. Pass the absolute,
canonical path to the extracted `en_core_web_trf/en_core_web_trf-3.8.0`
directory. At `open`, the adapter validates the exact tokenizer, lookup,
transformer, and tagger resources by size and SHA-256. Links, wrong types,
changed files, and other model revisions fail with typed errors. See
[RESOURCE_MANIFEST.md](RESOURCE_MANIFEST.md) for every identity and the
external model's license caveats.

## Build the native library

Use an absolute, dedicated output directory outside the package:

```sh
dart run misakid_spacy_trf_en:build_misakid_spacy_trf_en \
  --build-dir /absolute/path/to/misakid-spacy-trf-en-build
```

From a package checkout, `dart run tool/build_native.dart` is equivalent. The
tool validates the deterministic 149-tensor manifest, builds only the
package-owned C++ source, and installs:

```text
install/lib/libmisakid_spacy_trf_en.dylib
```

The installed library exports only the versioned package ABI and links to
Accelerate, libc++, and libSystem. The install tree also contains the C
header, source manifest, license, and third-party notices.

## Use it

```dart
import 'package:misakid_spacy_trf_en/misakid_spacy_trf_en.dart';

Future<void> main() async {
  final tokenizer =
      await NativeSpacyTransformerEnglishTokenizerBackend.open(
        modelDirectoryPath:
            '/absolute/path/en_core_web_trf/en_core_web_trf-3.8.0',
        nativeLibraryPath:
            '/absolute/path/libmisakid_spacy_trf_en.dylib',
      );
  try {
    final engine = EnglishG2pEngine(
      tokenizer: tokenizer,
      pronunciation: const PinnedEnglishLexicon(),
    );
    print(engine.convert('Hello from Misakid.').phonemes);
  } finally {
    tokenizer.close();
  }
}
```

The compiling
[`example/misakid_spacy_trf_en_example.dart`](example/misakid_spacy_trf_en_example.dart)
accepts the model directory and native-library paths as command-line
arguments. Compose the same tokenizer with `EnglishEspeakFallback` and the
`misakid_espeak_en` backend for the supported eSpeak-fallback profile.

## Resource and execution limits

Initialization is asynchronous because Dart streams and hashes the 497 MB
transformer file before native initialization validates and copies its exact
149 F32 tensors. One live model uses approximately 496 MB for immutable native
weights, plus tokenizer tables and per-conversion scratch buffers. Native
contexts for the same canonical model path share that weight allocation while
at least one remains open.

Call `close` explicitly. The native finalizer is leak-safety only; garbage
collection timing is not a resource-management contract. Opening a model and
conversion should run off a latency-sensitive UI isolate.

The default public limit is 4,096 marked byte-BPE pieces per conversion. A
caller may select a value from 2 through 16,384 at `open`. The pure byte-BPE
stage also has fixed scalar and output bounds, and the native ABI validates
piece IDs, token lengths, array alignment, and aggregate counts before
inference. Exceeding a bound fails with a typed error rather than partial
output.

Inference is synchronous. Accelerate exposes no safe cancellation point for
this graph, so there is no timeout or cancellation guarantee. Applications
that require hard cancellation or crash isolation should run conversion in a
separately supervised process.

Linux, Windows, Intel macOS, web, automatic resource discovery, alternate
model versions, embedded links, and bundled weights remain unsupported.

## Public byte-BPE API

The pure-Dart byte-BPE stage remains independently public for reviewed tooling
and tests:

```dart
final encoder = SpacyTransformerByteBpe.decodePinnedPayload(payload);
final ids = encoder.encodeAsIds('Misaki');
```

`payload` must be the exact 1,063,863-byte range beginning at byte offset 416
of the pinned `transformer/model`; both its length and SHA-256 are checked
before bounded MessagePack decoding. The implementation contains generated
`regex==2024.11.6` / Unicode 16 property tables and needs no Python `regex`
module.

## Verified behavior

The provisioned production suite checks:

- all 116 accepted American/British transformer cases;
- all 2,278 raw tokenizer/tagger records and every final token field;
- legacy and 2.0 rendering, no fallback, and eSpeak-fallback replay;
- exact striding boundaries through 249 marked pieces, including an
  overlap-sensitive emoji tag;
- all 40 fallback cases, 86 raw transformer tokens, and 50 raw eSpeak calls
  again with both real native adapters composed;
- native ownership, malformed input, bounds, lifecycle, identities, exports,
  linked libraries, and resource tampering; and
- byte-for-byte reproducible native builds on the provisioned toolchain.

Normal offline tests skip the external-resource group. Provisioned tests use
`MISAKID_SPACY_TRF_EN_MODEL_DIR` and `MISAKID_SPACY_TRF_EN_LIBRARY`.

## Licensing

The Dart adapter and package-owned C++ implementation are Apache-2.0. The
caller-supplied model declares MIT at the wheel level but includes a more
detailed source ledger that callers must review and retain. No model bytes are
redistributed by this package. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and
[RESOURCE_MANIFEST.md](RESOURCE_MANIFEST.md).
