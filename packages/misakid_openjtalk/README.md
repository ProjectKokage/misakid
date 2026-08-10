# misakid_openjtalk

`misakid_openjtalk` provides the Open JTalk 1.11 frontend used by Misakid's
Japanese G2P engine. It runs without Python and keeps FFI, filesystem, and
native lifecycle code outside the pure-Dart `misakid` core.

The package has two native-library paths and one explicit verified-install
variant:

- `OpenJtalkFrontendBackend.openBundled` uses the native asset built from the
  package's vendored, safety-patched sources. Build profiles are implemented
  for Android, iOS, Linux, macOS, and Windows.
- `OpenJtalkFrontendBackend.openBundledFromVerifiedInstall` uses the same
  native asset but skips a second dictionary content scan when an application
  already verified the exact files in private staging and installed them
  atomically.
- `OpenJtalkFrontendBackend.open` retains the original explicit-library
  contract. Its reviewed CMake build remains limited to macOS 11 or newer on
  arm64.

Both paths implement the frontend from `pyopenjtalk==0.4.1` / Open JTalk 1.11,
require the exact `open_jtalk_dic_utf_8-1.11` dictionary, and target Misaki
0.9.4 behavior at commit
`fba1236595f2d2bf21d414ba6e57d25256afada3`.

The build hook and runtime never download anything. The package distributes a
reviewed 139-file source tree, not a precompiled native binary, dictionary,
Python runtime, HTS engine, or voice model. The 107 MB dictionary remains an
explicit application-owned resource.

## Platform status

The native-assets build hook recognizes the following runtime ABI tuples:

| Target | `dart:ffi` ABIs accepted by `openBundled` | Current evidence |
| --- | --- | --- |
| Android | `androidArm`, `androidArm64`, `androidX64` | A stable Flutter 3.41.7 release APK passes artifact checks for armv7, arm64, and x86-64; complete committed-fixture parity passes locally on an Android 15/API 35 arm64 emulator. Other runtime ABIs and physical devices remain experimental. |
| iOS | `iosArm64`, `iosX64` | A stable Flutter 3.41.7 unsigned arm64 device application passes framework/artifact checks; complete committed-fixture parity passes locally on an iPhone 17 iOS 26.5 Simulator. Physical-device runtime and other tuples remain experimental. |
| Linux | `linuxArm64`, `linuxX64` | The exact sources cross-link as arm64 and x64 ELF libraries with the reviewed 23 exports and `libmisakid_openjtalk.so` SONAME. No Linux-host Flutter build, dictionary load, or parity run has completed. |
| macOS | `macosArm64`, `macosX64` | arm64 build and provisioned parity verified; x64 is implemented but not provisioned. |
| Windows | `windowsX64` | The exact sources cross-link as an x64 PE DLL with the reviewed 23 exports under a GNU compatibility probe. The supported hook profile requires MSVC; no Windows-host MSVC/Flutter build, dictionary load, or parity run has completed. |

Android x86 (32-bit), Android RISC-V, 32-bit iOS, Windows arm64/x86, Linux
x86/RISC-V, and other ABI tuples are not accepted by `openBundled`.
Unsupported tuples fail before dictionary hashing with a typed
`BackendUnavailableException`. This FFI adapter cannot be imported on Dart
web; web applications should depend only on the platform-neutral `misakid`
core.

`openJtalkBundledBuildPlatforms` reports the five configured operating-system
profiles. It is not a claim that every architecture or runtime tuple has
completed provisioned testing. `openJtalkSupportedPlatform` remains
`macos-arm64` for compatibility with the legacy explicit-library path.

Mobile build profiles are implemented for the accepted ABI tuples above.
Release packaging is verified for all three Android ABIs and iOS arm64. One
Android arm64 emulator and one iOS simulator have also completed the full
provisioned corpus. Broad mobile release support remains experimental pending
physical-device evidence, the other advertised runtime ABIs, and the clean
hosted Android/iOS matrix.

## Use the bundled native asset

The package build hook runs automatically when a consuming Dart or Flutter
build requests native code assets. It verifies the complete vendored source
identity before compiling. Configure the normal platform native toolchain for
the consuming application; there is no package-specific source bootstrap
command and no network access in the hook.

Provide the dictionary as a real directory, then pass its absolute filesystem
path:

```dart
import 'package:misakid/misaki_ja.dart';
import 'package:misakid_openjtalk/misakid_openjtalk.dart';

Future<void> convertJapanese(String dictionaryPath) async {
  final backend = await OpenJtalkFrontendBackend.openBundled(
    dictionaryPath: dictionaryPath,
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

`openBundled` resolves the package-built code asset; it does not search for a
native library or dictionary. Initialization is asynchronous because it
streams and hashes the dictionary. Conversion is synchronous and the backend
is reusable. `close` is idempotent; a native finalizer is only a leak-safety
fallback.

Applications with an app-private installer may instead call
`openBundledFromVerifiedInstall` after checking every pinned file size and
SHA-256 in staging and atomically promoting the complete directory. That entry
point still requires the exact nine regular filenames and sizes, snapshots
their metadata across native open, and lets Open JTalk parse the dictionary,
but it does not authenticate the installed bytes again. Use `openBundled` for
every other resource path.

### Provide the external dictionary

Obtain `open_jtalk_dic_utf_8-1.11.tar.gz` explicitly from the Open JTalk
1.11.1 release and verify it before adding it to an application-controlled
resource workflow:

- URL:
  `https://github.com/r9y9/open_jtalk/releases/download/v1.11.1/open_jtalk_dic_utf_8-1.11.tar.gz`
- archive size: 23,646,843 bytes
- archive SHA-256:
  `fe6ba0e43542cef98339abdffd903e062008ea170b04e7e2a35da805902f382a`

The directory passed to `openBundled` must be a real, absolute filesystem
directory containing exactly these nine regular files and no other entries:

```text
COPYING
char.bin
left-id.def
matrix.bin
pos-id.def
rewrite.def
right-id.def
sys.dic
unk.dic
```

Their installed total is 107,304,813 bytes (about 107 MB), with canonical tree
SHA-256
`8b26c37228c9e9b92333e612e1144c958f2788d219e46c8652f698a089be1ccc`.
The default `open` and `openBundled` entry points verify every individual size
and SHA-256 as well as the file set, total, and tree identity. Links,
subdirectories, extra entries, missing files, and modified bytes are rejected.

Android Flutter/APK assets are not directly usable as the required filesystem
directory. An Android application must copy or extract the nine files into its
own app storage, preferably through a private staging directory followed by an
atomic rename, and then call `openBundled` with that absolute path.

An exact dictionary directory inside a signed iOS application bundle is an
ordinary read-only filesystem directory and may be passed directly to
`openBundled`; no writable copy is required. The selected directory must still
contain exactly the nine files above with no extra entries. An iOS application
that instead provisions the dictionary after installation should materialize
it in application-support storage using the same staging discipline as
Android.

On every platform, keep the validated files unchanged for the backend's
lifetime because MeCab may memory-map them. This package supplies neither a
downloader nor a dictionary extraction/materialization helper.

### Desktop toolchains

Linux builds require a same-architecture native Linux host with an x64 or
arm64 clang/GCC-compatible C/C++17 toolchain, an archiver, the platform C++
runtime, `libm`, and pthread. The emitted asset is
`libmisakid_openjtalk.so` with the same SONAME and the reviewed 23-symbol
version-script surface.

Windows builds are deliberately x64-only and require an x64 Windows host plus
the MSVC `cl.exe`/`lib.exe` toolchain supplied by the application's Visual
Studio Developer Command Prompt configuration. A configured clang or GCC
driver is rejected before compilation because the pinned `native_toolchain_c`
Windows C++ link path is reviewed only for MSVC. The emitted asset is
`misakid_openjtalk.dll`; the adapter header uses `__declspec(dllexport)` on
exactly the 23 ABI functions. Dictionary paths remain UTF-8 at the Dart
boundary, are converted strictly to UTF-16, and canonical drive/UNC paths are
mapped to the extended `CreateFileW` namespace. This avoids dependence on the
active ANSI code page or the consuming executable's `longPathAware` manifest.
Target-host initialization with long Japanese and space-containing paths is
still a required runtime evidence gate.

The normal application build invokes the hook; there is no separate desktop
bootstrap step. A successful foreign-host cross-link is only source
portability evidence. Linux- and Windows-host Flutter packaging, native asset
mapping, dependency inspection, dictionary initialization, and committed
fixture parity remain required before either desktop target is called
verified.

## Native-assets build profiles

The hook compiles the upstream-language boundaries explicitly:

1. Open JTalk's C frontend stages and the silent-stdio shim are compiled as
   C11 into an internal static archive with no asset routing.
2. The Misakid ABI and embedded MeCab runtime are compiled as C++17 and linked
   with that archive into the routed native code asset.

The C/C++ split is intentional: `.c` frontend files are not reinterpreted as
C++. Open JTalk's UTF-8 C rule tables also depend on signed 8-bit `char`
semantics. Clang/GCC profiles pass `-fsigned-char`; MSVC's signed default is
checked rather than changed. `silent_stdio.c` rejects every target at compile
time unless `CHAR_MIN == -128` and `CHAR_MAX == 127`. This is a portability
invariant, not an assumption inherited from the build host.

Clang/GCC profiles use hidden visibility and section-level dead-code
elimination; all profiles apply their toolchain's stable path mapping. Android
links the NDK C++ runtime statically (`c++_static`) and `libm`. Linux links its
platform C++ runtime, `libm`, and pthread. Both ELF profiles hide archive
symbols and apply the reviewed 23-symbol Android version script. Windows uses
`__declspec(dllexport)`. iOS and macOS use the platform C++ runtime and dead
stripping. See
[native/SOURCE_MANIFEST.md](native/SOURCE_MANIFEST.md) for the exact source
identity and build record.

## Legacy explicit macOS arm64 build

The explicit `open` API and build executable remain available for applications
that want to construct and authenticate their own dylib path. This workflow is
still deliberately limited to macOS 11 or newer on Apple silicon.

Prerequisites are:

- Dart 3.11.5 or a compatible newer release below Dart 4;
- CMake 3.20 or newer;
- Xcode Command Line Tools or Xcode with Apple Clang and C++17; and
- an explicitly obtained `pyopenjtalk-0.4.1` source distribution.

Verify the source distribution before extracting it:

- URL:
  `https://files.pythonhosted.org/packages/58/74/ccd31c696f047ba381f9b11a504bf1199756c3f30f3de64e3eeb83e10b4a/pyopenjtalk-0.4.1.tar.gz`
- size: 1,397,999 bytes
- SHA-256:
  `d5ada46f7fc2b52c1c79c273eb9668ff6ad7ab276a8db9d8be119ef93440f0dc`

Build from an application that depends on this package, using an absolute,
dedicated output directory:

```sh
dart run misakid_openjtalk:build_misakid_openjtalk \
  --source /absolute/path/to/pyopenjtalk-0.4.1 \
  --build-dir /absolute/path/to/misakid-openjtalk-build
```

From a package checkout, `dart run tool/build_native.dart` is equivalent. The
tool does not use the network. It verifies the original 139 source files and
three source-license files, applies the reviewed non-terminating safety-v1
overlay, and builds only the frontend. CMake independently verifies the
complete post-patch staged tree. The output is
`install/lib/libmisakid_openjtalk.dylib`; the install tree also contains the C
header, source manifest, and redistribution notices. The dylib has an `@rpath`
install name, exports only the versioned Misakid C ABI, and links only system
libraries.

Open the explicit artifact with both trusted absolute paths:

```dart
final backend = await OpenJtalkFrontendBackend.open(
  libraryPath: '/absolute/path/libmisakid_openjtalk.dylib',
  dictionaryPath: '/absolute/path/open_jtalk_dic_utf_8-1.11',
);
```

The package's [example/japanese.dart](example/japanese.dart) remains a complete
command-line example of this legacy explicit-library workflow.

`libraryPath` must identify a trusted artifact produced by the verified build
tool. ABI and source identity strings are checks performed after the operating
system loader opens the dylib; they do not authenticate or sandbox an
untrusted library.

## Runtime limits and divergences

The default per-call input limit is 1 MiB of UTF-8 and can be configured up to
64 MiB. Dart and native code enforce the same value. Open JTalk exposes no safe
cancellation hook, so synchronous conversion has no timeout or cancellation
guarantee. Applications needing cancellation should isolate the work in a
separately supervised process.

Native results are limited to 65,536 words, 1 MiB for any one field, and 64 MiB
of aggregate string data. Exceeding a result bound returns a typed code-6
backend failure. The adapter allocates Open JTalk's normalization buffer as
`3 * inputBytes + 1`; pinned pyopenjtalk 0.4.1 instead uses a fixed 8,192-byte
stack buffer. The committed parity corpus stays within that upstream-safe
domain. Longer accepted inputs avoid upstream's buffer hazard, but exact
pyopenjtalk behavior is not claimed for them.

Adapter-owned allocation failures and C++ exceptions are converted to bounded
errors. The inherited Open JTalk/MeCab routines still contain unchecked
allocation sites, so an extreme process-wide out-of-memory condition is not a
recoverable typed-error guarantee.

The adapter rejects embedded NUL and unpaired UTF-16 surrogates. Pinned
pyopenjtalk rejects unpaired surrogates but silently truncates at NUL; rejecting
NUL is a documented security divergence that avoids silently discarding the
rest of the input.

## Verified behavior

On macOS arm64, the bundled native asset and provisioned adapter suite verify:

- all 24 committed Japanese inputs and all 155 raw frontend words;
- all 11 string and three integer Open JTalk fields;
- all 23 successful final phoneme strings and every token/metadata field;
- the pinned whitespace-only failure;
- copied-result ownership, byte limits, malformed input, and close behavior;
- concurrent use from four isolates through the native global lock;
- the exact 23-symbol C ABI identity; and
- byte-empty stdout/stderr on native success and failure paths.

The legacy explicit macOS arm64 dylib remains covered by the same frontend
parity contract.

On 2026-07-30, model-free foreign-host probes cross-linked the exact configured
source set for Linux x64, Linux arm64, and Windows x64. Both ELF artifacts had
the `libmisakid_openjtalk.so` SONAME and exactly 23 public adapter symbols; the
PE artifact had exactly the same 23 exported names. The Windows probe used a
GNU-compatible cross toolchain, not the supported MSVC hook path. These probes
did not load the dictionary or execute G2P and do not replace target-host
Flutter packaging or provisioned parity evidence.

Stable Flutter 3.41.7 release packaging has also completed these mobile gates:

- an Android release APK contains armv7, arm64, and x86-64 assets for both
  `misakid_openjtalk` and the companion `misakid_mecab_ja` package;
- each Android library exports exactly its reviewed 23-symbol adapter ABI, has
  only `libc`, `libdl`, and `libm` dynamic dependencies, has its NativeAssets
  manifest mapping, and passes 16 KiB ELF segment and uncompressed ZIP-entry
  alignment checks; and
- an unsigned arm64 iOS device application contains both native frameworks,
  each with an `IOS` build platform, minimum iOS 13 metadata, its reviewed
  `@rpath` install name, only platform libc++/libSystem linkage, the application
  framework rpath, its NativeAssets manifest mapping, and exactly its reviewed
  23 exports.

Stable Flutter 3.41.7 also ran
`integration_test/japanese_openjtalk_mobile_parity_test.dart` successfully on:

- an Android 15/API 35 arm64 emulator; and
- an iPhone 17 iOS 26.5 Simulator.

Each run provisioned and verified the exact nine-file, 107,304,813-byte Open
JTalk dictionary plus the committed fixture before calling `openBundled`. Each
then matched all 24 cases, all 155 raw records and their 11 string plus three
integer fields, all 23 successful final phoneme strings with typed token
metadata, and the exact pinned whitespace-only failure.

These are local emulated-runtime results. Android armv7/x86-64 runtime, iOS x64
simulator runtime, physical Android/iOS devices, and the clean hosted
Android/iOS matrix remain release gates, so broad mobile support remains
experimental. Cutlet is a distinct Japanese backend and is not provided here.

## Licensing

The Dart adapter, new C ABI, build hook, and safety overlay are Apache-2.0. The
vendored Open JTalk and embedded MeCab sources retain their BSD-style notices.
Android assets statically link the NDK's LLVM libc++ under Apache-2.0 with the
LLVM exception. The dictionary remains external and retains its own notices.
See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and `native/licenses/`.
