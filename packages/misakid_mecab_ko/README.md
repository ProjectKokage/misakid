# misakid_mecab_ko

`misakid_mecab_ko` supplies the explicitly configured resources for Misakid's
Korean G2P engine: a native MeCab-ko morphology backend and a pure-Dart
CMUdict parser. Conversion runs without Python and keeps FFI and filesystem
code outside the platform-neutral `misakid` core.

The first supported target is deliberately narrow:

- macOS 11 or newer on arm64;
- MeCab-ko `0.996/ko-0.9.2` from the official `release-0.9.2` source;
- `python-mecab-ko-dic==2.1.1.post2`'s exact prebuilt dictionary;
- the exact CMUdict 0.7a resource distributed by NLTK; and
- Misaki 0.9.4 behavior at commit
  `fba1236595f2d2bf21d414ba6e57d25256afada3`.

No native library, dictionary, pronunciation data, Python runtime, or
downloader is bundled. Other operating systems and architectures fail during
`open` with a typed `BackendUnavailableException`. This package imports
`dart:ffi` and `dart:io`, so web applications should depend only on the pure
`misakid` package.

## Prerequisites

Building the native library requires Apple silicon, CMake 3.20 or newer, and
Xcode Command Line Tools or Xcode with Apple Clang C++14 support. Python,
`package:ffi`, NLTK, and a model runtime are not needed to build or run it.

Obtain the official MeCab-ko archive explicitly:

- URL:
  `https://bitbucket.org/eunjeon/mecab-ko/downloads/mecab-0.996-ko-0.9.2.tar.gz`
- size: 1,414,979 bytes
- SHA-256:
  `d0e0f696fc33c2183307d4eb87ec3b17845f90b81bf843bd0981e574ee3c38cb`

After extraction, build into a dedicated absolute directory:

```sh
dart run misakid_mecab_ko:build_misakid_mecab_ko \
  --source /absolute/path/to/mecab-0.996-ko-0.9.2 \
  --build-dir /absolute/path/to/misakid-mecab-ko-build
```

From this package's checkout, `dart run tool/build_native.dart` is equivalent.
The tool performs no network access. It verifies all 236 source files and
license identities before staging them, applies an exact non-terminating
safety overlay, then invokes CMake. CMake independently verifies the complete
post-patch tree. The output library is
`install/lib/libmisakid_mecab_ko.dylib`.

See [native/SOURCE_MANIFEST.md](native/SOURCE_MANIFEST.md) for exact source,
patch, binary, and ABI identities.

## Obtain the two data resources

Download `python-mecab-ko-dic` 2.1.1.post2 from its
[official PyPI release](https://pypi.org/project/python-mecab-ko-dic/2.1.1.post2/).
The accepted artifacts are:

- `python_mecab_ko_dic-2.1.1.post2-py3-none-any.whl`: 34,457,665 bytes,
  SHA-256
  `ef8f4e80c8976f1340a7264abb0c96f384fe059fd897584aeba0151753c6ae9b`;
- `python-mecab-ko-dic-2.1.1.post2.tar.gz`: 34,179,115 bytes, SHA-256
  `2c423713bdc475345ec98cd084b30759458f8f06c38a9ef94ab8687942c2cd34`.

Extract the `mecab_ko_dic/dictionary` directory. At `open`, Dart streams and
checks its exact 11 files, their individual hashes, 112,191,702-byte total,
and tree SHA-256
`d851fab8708745442ac3a2d970851dbd0ef598e786a363f406847461d77a6f51`.
Links, missing or extra entries, and files changed during initialization are
rejected. Keep the validated files unchanged for the backend's lifetime;
MeCab may memory-map them.

Download CMUdict from NLTK's explicit data URL:

- URL:
  `https://raw.githubusercontent.com/nltk/nltk_data/gh-pages/packages/corpora/cmudict.zip`
- size: 896,069 bytes
- SHA-256:
  `d07cca47fd72ad32ea9d8ad1219f85301eeaf4568f8b6b73747506a71fb5afd6`

Pass the extracted `cmudict/cmudict` file. The pure-Dart loader requires its
3,820,830-byte size, SHA-256
`cad209c39eb87677d64e93d97f8eed10b7e6f9bdd42de8e7ca8efc8e17d62e8a`,
133,737 records, and 123,455 lookup keys. It preserves the first pronunciation
for each lowercase key, matching NLTK's dictionary contract used by Misaki.

## Use it

```dart
import 'package:misakid_mecab_ko/misakid_mecab_ko.dart';

Future<void> main() async {
  final morphology = await MecabKoMorphologyBackend.open(
    libraryPath: '/absolute/path/libmisakid_mecab_ko.dylib',
    dictionaryPath: '/absolute/path/mecab_ko_dic/dictionary',
  );
  final cmu = await CmuDictionaryPronunciationProvider.open(
    '/absolute/path/cmudict/cmudict',
  );
  try {
    final engine = KoreanG2pkcEngine(
      morphology: morphology,
      cmuPronunciations: cmu,
    );
    print(engine.convert('안녕하세요.').phonemes);
  } finally {
    morphology.close();
  }
}
```

Initialization is asynchronous because it verifies roughly 116 MB of data.
Conversion and CMU lookup are synchronous after initialization. The CMU table
is retained in Dart memory; reuse one provider. `close` is idempotent, and a
native finalizer exists only as leak protection.

`libraryPath` must be a trusted output from the verified build tool. ABI and
source identity values detect accidental incompatibility after the operating
system loads the library; they do not authenticate or sandbox hostile native
code.

The default input limit is 1 MiB of UTF-8 and can be configured up to 64 MiB.
Native results are limited to 65,536 tokens, 1 MiB per returned field, and
64 MiB of aggregate returned strings. Embedded NUL and unpaired UTF-16
surrogates are rejected instead of risking native truncation. MeCab exposes no
safe cancellation hook, so applications requiring hard cancellation or fault
isolation should run conversion in a separately supervised process.

Adapter-owned C++ exceptions and allocation failures become bounded errors.
The inherited MeCab implementation contains some unchecked extreme
out-of-memory paths, so process-wide OOM is not guaranteed to be recoverable.

## Verified behavior

Provisioned tests compare directly with committed output captured from the
pinned original Misaki environment. They cover all 34 inputs and 293 MeCab
surface/tag pairs, all 23 captured CMUdict lookups, all 33 successful final
phoneme strings, and the one pinned upstream numeral failure. Tests also cover
copied-result ownership, byte limits, deterministic close, concurrent Dart
isolates, dictionary/CMU tampering, and byte-empty stdout/stderr on native
success and failure paths.

## Licensing

The Dart adapter and new C ABI are Apache-2.0. The MeCab-ko build is
redistributed under its BSD option; the explicitly supplied Korean dictionary
is Apache-2.0; CMUdict has its own permissive notice. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and `native/licenses/`.
