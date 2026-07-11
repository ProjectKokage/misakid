# misakid_openjtalk

`misakid_openjtalk` is the explicitly configured Open JTalk frontend for
Misakid's Japanese G2P engine. It runs without Python and keeps all FFI,
filesystem, and native lifecycle code outside the pure-Dart `misakid` core.

The first supported target is deliberately narrow:

- macOS 11 or newer on arm64;
- the frontend sources from `pyopenjtalk==0.4.1` / Open JTalk 1.11;
- the exact `open_jtalk_dic_utf_8-1.11` dictionary release; and
- Misaki 0.9.4 behavior at commit
  `fba1236595f2d2bf21d414ba6e57d25256afada3`.

No library, dictionary, Python runtime, model, or downloader is bundled. Other
Dart native operating systems and architectures fail during `open` with a
typed `BackendUnavailableException`. This FFI adapter cannot be imported on
Dart web; web applications should depend only on the platform-neutral
`misakid` core.

## Prerequisites

Building the optional native library requires:

- macOS 11 or newer on Apple silicon;
- Dart 3.11.5 or a compatible newer release below Dart 4;
- CMake 3.20 or newer;
- Xcode Command Line Tools or Xcode with an Apple Clang C++17 toolchain; and
- the two explicit pinned source and dictionary archives described below.

Check the build tools with `cmake --version` and `clang++ --version`. Python,
`package:ffi`, a voice model, and HTS are not required at build time or
runtime. The Dart adapter's only runtime package dependencies are `misakid`
and the pure-Dart `crypto` package.

## Build the native library

Obtain the exact pyopenjtalk 0.4.1 source distribution explicitly and verify:

- URL:
  `https://files.pythonhosted.org/packages/58/74/ccd31c696f047ba381f9b11a504bf1199756c3f30f3de64e3eeb83e10b4a/pyopenjtalk-0.4.1.tar.gz`
- size: 1,397,999 bytes
- SHA-256:
  `d5ada46f7fc2b52c1c79c273eb9668ff6ad7ab276a8db9d8be119ef93440f0dc`

After extracting it, build from an application that depends on this package,
using an absolute, dedicated output directory:

```sh
dart run misakid_openjtalk:build_misakid_openjtalk \
  --source /absolute/path/to/pyopenjtalk-0.4.1 \
  --build-dir /absolute/path/to/misakid-openjtalk-build
```

From a package checkout, `dart run tool/build_native.dart` is equivalent.

The build tool does not use the network. It verifies the 139 packaged Open
JTalk source files and three source-license files before staging them, applies
the reviewed non-terminating safety overlay, and builds only the frontend.
CMake independently verifies the complete post-patch staged tree, so a direct
build against untouched or modified upstream source is rejected. The output is
`install/lib/libmisakid_openjtalk.dylib`; the install tree also contains the C
header, source manifest, and exact redistribution notices. The library has an
`@rpath` install name, exports only the versioned Misakid C ABI, and links only
system libraries. See [native/SOURCE_MANIFEST.md](native/SOURCE_MANIFEST.md)
for the complete identity and modification record.

## Obtain the dictionary

Obtain `open_jtalk_dic_utf_8-1.11.tar.gz` explicitly from the Open JTalk 1.11.1
release:

- URL:
  `https://github.com/r9y9/open_jtalk/releases/download/v1.11.1/open_jtalk_dic_utf_8-1.11.tar.gz`
- size: 23,646,843 bytes
- SHA-256:
  `fe6ba0e43542cef98339abdffd903e062008ea170b04e7e2a35da805902f382a`

At `open`, Dart streams and verifies the exact nine installed files, their
individual sizes and SHA-256 values, the 107,304,813-byte total, and canonical
tree SHA-256
`8b26c37228c9e9b92333e612e1144c958f2788d219e46c8652f698a089be1ccc`.
Links, extra entries, and changed files are rejected. Keep the validated files
unchanged for the backend's lifetime because MeCab may memory-map them.

## Use it

```dart
import 'package:misakid/misaki_ja.dart';
import 'package:misakid_openjtalk/misakid_openjtalk.dart';

Future<void> main() async {
  final backend = await OpenJtalkFrontendBackend.open(
    libraryPath: '/absolute/path/libmisakid_openjtalk.dylib',
    dictionaryPath: '/absolute/path/open_jtalk_dic_utf_8-1.11',
  );
  try {
    final engine = JapanesePyopenjtalkEngine(backend: backend);
    final result = engine.convert('こんにちは。');
    print(result.phonemes);
  } finally {
    backend.close();
  }
}
```

Initialization is asynchronous because it hashes the 107 MB dictionary.
Conversion is synchronous and reusable. `close` is idempotent; a native
finalizer is only a leak-safety fallback.

`libraryPath` must identify a trusted artifact produced by the verified build
tool. ABI and source identity strings are compatibility checks performed after
the operating-system loader opens the dylib; they do not authenticate or
sandbox an untrusted library.

The default per-call input limit is 1 MiB of UTF-8 and can be configured up to
64 MiB. Dart and native code enforce the same value. Open JTalk exposes no
safe cancellation hook, so synchronous conversion has no timeout or
cancellation guarantee. Applications needing cancellation should isolate the
work in a separately managed process.

Native results are additionally limited to 65,536 words, 1 MiB for any one
field, and 64 MiB of aggregate string data. Exceeding a result bound returns a
typed code-6 backend failure. The adapter allocates Open JTalk's normalization
buffer as `3 * inputBytes + 1`; pinned pyopenjtalk 0.4.1 instead uses a fixed
8,192-byte stack buffer. The committed parity corpus stays within that
upstream-safe domain. Longer accepted inputs avoid upstream's buffer hazard,
but exact pyopenjtalk behavior is not claimed for them.

Adapter-owned allocation failures and C++ exceptions are converted to bounded
errors. The inherited Open JTalk/MeCab C code still contains some unchecked
allocation sites, so an extreme process-wide out-of-memory condition is not a
recoverable typed-error guarantee. Use a separately supervised process when
hard fault isolation is required.

The adapter intentionally rejects embedded NUL and unpaired UTF-16 surrogates.
Pinned pyopenjtalk rejects unpaired surrogates but silently truncates at NUL;
rejecting NUL is a documented security divergence that avoids silently
discarding the rest of the input.

## Verified behavior

The provisioned adapter test builds the production ABI and checks:

- all 24 committed Japanese inputs and all 155 raw frontend words;
- all 11 string and three integer Open JTalk fields;
- all 23 successful final phoneme strings and every token/metadata field;
- the pinned whitespace-only failure;
- copied-result ownership, byte limits, malformed input, and close behavior;
- concurrent use from four isolates through the native global lock; and
- byte-empty stdout/stderr on native success and failure paths.

Cutlet is a distinct Japanese backend and is not provided by this package.

## Licensing

The Dart adapter and new C ABI are Apache-2.0. The explicitly supplied build
source and dictionary retain MIT and BSD-style notices. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and `native/licenses/`.
