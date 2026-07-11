# misakid_espeak_en

`misakid_espeak_en` is the explicitly configured eSpeak NG fallback provider
for Misakid's English G2P engine. It runs without Python and keeps all FFI,
filesystem, and process-global eSpeak lifecycle code outside the platform-
neutral `misakid` core.

The first supported compatibility tuple is deliberately narrow:

- macOS 11 or newer on arm64;
- eSpeak NG 1.52.0 with the exact library and data identities below;
- the observable `phonemizer-fork==3.3.2` English US/GB option contract; and
- Misaki 0.9.4 at commit
  `fba1236595f2d2bf21d414ba6e57d25256afada3`.

No eSpeak library, data, voice, Python runtime, package installer, or
downloader is bundled. Callers pass three absolute paths explicitly: the
package-owned adapter dylib they built, their eSpeak dylib, and their complete
data directory. Other native platforms fail during `open` with a typed
`BackendUnavailableException`. This FFI package cannot be imported on Dart
web; web applications should depend only on the `misakid` core.

## Prerequisites and native build

Building the small Apache-2.0 shim requires macOS on Apple silicon, CMake 3.20
or newer, and Apple Clang with C++17 support. It does not compile or link any
eSpeak or phonemizer source.

From an application that depends on this package, use an absolute dedicated
output directory outside the package checkout:

```sh
dart run misakid_espeak_en:build_misakid_espeak_en \
  --build-dir /absolute/path/to/misakid-espeak-en-build
```

From this repository, `dart run tool/build_native.dart` is equivalent. The
installed adapter is
`install/lib/libmisakid_espeak_en.dylib`. The install tree also contains the C
header, source manifest, Apache license, and third-party notices. Independent
clean builds with the same Apple toolchain are byte-identical. The dylib has
an `@rpath` install name, a macOS 11 deployment target, the reviewed 21-symbol
C ABI, and only system `libc++`/`libSystem` dependencies.

## Required eSpeak resources

The supported runtime library is exactly:

- eSpeak NG version: 1.52.0;
- byte size: 504,168;
- SHA-256:
  `bb635eee1ee9c456f4a5cf06fb6cb352ecdd4d61e1951743b423ef22bb57f470`.

The supported `espeak-ng-data` tree is exactly:

- directories, including the root: 37;
- files: 364;
- aggregate file bytes: 18,373,365;
- canonical path/size/content SHA-256:
  `730e20a0d06976b23b8344bac21dab6e1da447d0e16906bab6a0b54db89dd6e2`.

The accepted oracle was provisioned from the macOS-arm64 resources installed
by `espeakng-loader==0.2.4`. Its installed package metadata declares no loader
license, so this package neither redistributes that wheel nor treats it as a
licensed runtime dependency. Obtain the byte-identical eSpeak resources by an
explicit, independently reviewed route and comply with eSpeak NG's
GPL-3.0-or-later terms. `open` streams and validates the complete resources;
links, special entries, extra empty directories, changed files, and alternate
eSpeak builds are rejected.

## Use the fallback provider

```dart
import 'package:misakid_espeak_en/misakid_espeak_en.dart';

Future<void> main() async {
  final backend = await EspeakEnglishBackend.open(
    adapterLibraryPath:
        '/absolute/path/libmisakid_espeak_en.dylib',
    espeakLibraryPath: '/absolute/path/libespeak-ng.dylib',
    dataPath: '/absolute/path/espeak-ng-data',
  );
  try {
    final phones = backend.phonemize(
      'blorptastic',
      dialect: EnglishDialect.american,
    );
    print(phones); // blɔː^ɹptˈe^ɪstɪk 
  } finally {
    backend.close();
  }
}
```

The class implements the core `EnglishEspeakBackend` contract and can be
passed to `EnglishEspeakFallback`. A complete English engine additionally
needs an exact `EnglishTokenizerBackend`; this package intentionally supplies
only raw eSpeak fallback behavior.

Initialization is asynchronous because it hashes roughly 19 MB of external
resources. Phonemization is synchronous and reusable. `close` is idempotent;
a native finalizer is only a leak-safety fallback. The package-owned dylib path
must identify a trusted artifact produced by the reviewed build. ABI identity
strings are compatibility checks performed after the operating-system loader
executes the dylib; they do not authenticate or sandbox an untrusted library.

The default whole-call input limit is 1 MiB of UTF-8 and the default aggregate
formatted-result limit is 4 MiB. Each is configurable from 1 byte through 64
MiB, with matching per-native-chunk bounds. Punctuation preservation is
limited to 65,536 direct calls, and the native eSpeak loop independently
limits one direct call to 65,536 eSpeak clauses. Embedded NUL, unpaired
UTF-16 surrogates, malformed UTF-8 at the ABI, alternate dialect values, and
oversized results fail with typed, bounded diagnostics that contain no input
text or configured path.

Exceeding either 65,536-chunk boundary is an intentional denial-of-service
safety limit and surfaces as a typed `BackendFailureException`.

eSpeak uses process-global mutable state. The shim therefore serializes
initialization, voice selection, conversion, termination, and context release
behind one process-wide C++ mutex, including calls from separate Dart
isolates. Conversion has no safe timeout or cancellation hook and blocks its
calling isolate. Applications needing hard cancellation or crash isolation
should run the adapter in a separately supervised process.

## Verified behavior

The provisioned adapter suite checks:

- all 58 accepted raw fallback calls for American and British English;
- all 40 final `EnglishG2pEngine` outputs and every token/metadata field using
  the real pure-Dart small-model tokenizer/tagger and real eSpeak adapter
  together;
- all 40 transformer+eSpeak outputs, 86 raw transformer tokens, every final
  token/metadata field, and all 50 raw eSpeak calls using the real native
  transformer and eSpeak adapters together;
- both legacy and 2.0 phoneme versions, preprocessing and unknown options;
- exact external resource and native identity, including tampering failures;
- owned/copied results, malformed input, byte limits, and repeated close;
- concurrent use from four Dart isolates through the global native lock;
- reproducible builds, exact exports, dependencies, and deployment target;
- and byte-empty process stdout/stderr on native success and failure paths.

Normal offline tests do not require the GPL runtime and skip the provisioned
native groups when their explicit environment variables are absent. The
eSpeak tests require `MISAKID_ESPEAK_EN_ADAPTER_LIBRARY`,
`MISAKID_ESPEAK_EN_LIBRARY`, and `MISAKID_ESPEAK_EN_DATA`. The separate
transformer composition test additionally requires
`MISAKID_SPACY_TRF_EN_LIBRARY` and `MISAKID_SPACY_TRF_EN_MODEL_DIR`; run it as
`dart test test/transformer_combined_parity_test.dart`. The dependency is
development-only here and no external resource is published by either
package. The supported transformer contract and its limits are documented by
`misakid_spacy_trf_en`; see the repository's native workflows for explicitly
provisioned invocations.

## Licensing

The Dart adapter, native C ABI, and clean-room fixture-derived formatting
stage are Apache-2.0. Caller-supplied eSpeak NG 1.52.0 is GPL-3.0-or-later.
`phonemizer-fork==3.3.2`, used only as the executable reference, declares
GPL-3.0; no phonemizer code or tables are included. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and
[native/SOURCE_MANIFEST.md](native/SOURCE_MANIFEST.md).
