# Native source manifest

The package's native-assets hook builds from the reviewed source tree committed
under `native/vendor/open_jtalk`. The legacy macOS arm64 build tool instead
accepts an explicitly supplied `pyopenjtalk-0.4.1` source directory, proves its
original identity, and applies the same safety-v1 changes in a private staging
tree. Neither path downloads source or binaries.

## Upstream source distribution

- Project: `pyopenjtalk`
- Version: `0.4.1`
- Open JTalk version: `1.11`
- Archive: `pyopenjtalk-0.4.1.tar.gz`
- Archive size: 1,397,999 bytes
- Archive SHA-256:
  `d5ada46f7fc2b52c1c79c273eb9668ff6ad7ab276a8db9d8be119ef93440f0dc`
- URL:
  `https://files.pythonhosted.org/packages/58/74/ccd31c696f047ba381f9b11a504bf1199756c3f30f3de64e3eeb83e10b4a/pyopenjtalk-0.4.1.tar.gz`
- pyopenjtalk MIT license SHA-256:
  `c38083a4d51c1ea86e08b3303a984d0c23718c5ac214058af705814d30f4bb5b`
- Open JTalk `COPYING` SHA-256:
  `14f380a0db8dce139fdcfb731d21e993a31a00b68907515d1c54a5f356241343`
- embedded MeCab `COPYING` SHA-256:
  `05e94c185a3e31f0c658f7011132be952b6d1a4d588b682f92da380e0a290650`

The original-source verifier reads `pyopenjtalk.egg-info/SOURCES.txt`, selects
sorted paths below `lib/open_jtalk/src/`, strips that prefix, and hashes records
of:

```text
UTF-8 relative path, NUL, lowercase file SHA-256, newline
```

The accepted unmodified identity is exactly 139 files, 5,381,473 bytes, and
aggregate SHA-256
`dea0f240fad8dc8b9ea1984920a4d64a48227a40c2924a3c545eaeca50357857`.
Generated configuration, build products, Python extensions, HTS code, voice
data, and audio code are outside this selected tree.

## Vendored safety-v1 tree

`native/vendor/open_jtalk` is the deterministic post-patch tree derived from
the source distribution above. It contains exactly:

- 139 regular files;
- 5,382,103 bytes; and
- canonical tree SHA-256
  `8ce47a975dee79c078914df15c40df5906430e4a63be4fc2bc0987e7b5b2fccb`.

For this identity, relative POSIX paths are sorted as complete strings. Each
record is the path, one tab, the lowercase per-file SHA-256, and one newline;
the reported value is the SHA-256 of the concatenated UTF-8 records. Links and
other non-regular entries are forbidden.

`dart run tool/verify_vendored_openjtalk.dart` checks that identity plus the
byte-exact Open JTalk and MeCab notices. The native-assets build hook performs
the same whole-tree check before selecting a target profile, so modified or
incomplete vendored input cannot emit an asset. The duplicate verifier in the
hook is intentional: normal application builds do not depend on test tooling.

Native ABI identity field 3 remains the accepted unmodified source-tree hash,
field 4 remains the source-archive hash, and field 5 is
`misakid-openjtalk-safety-v1`. Together they identify the upstream input and
reviewed changes. The post-patch vendored hash is a build-time integrity gate;
it does not replace those stable ABI fields.

## Misakid safety patch set v1

Safety-v1 makes two exact, context-reviewed source changes:

1. `NJDNode_insert` no longer calls `exit(1)` for an invalid graph. A terminal
   insertion is discarded without changing the live list, the active loop can
   finish safely, and a bounded `digit` diagnostic causes the complete result
   to fail. The accepted valid path is unchanged.
2. The deprecated, compile-disabled long-vowel estimator's invalid-byte path
   no longer calls `exit(1)`. It records a bounded `long-vowel` diagnostic and
   returns safely if that branch is ever re-enabled.

Pinned Open JTalk also writes some diagnostics directly with `printf` or
`fprintf`. A force-included adapter header redirects those C stdio calls to
inert functions. Status-bearing stages are checked by the ABI and exposed as
bounded structured errors without input text or configured paths. Provisioned
macOS arm64 tests prove that valid analysis and invalid native dictionary
loading produce byte-empty stdout and stderr.

The same app-owned force-include supplies the Windows portability boundary
without changing the identity-pinned vendor tree. It selects the Windows CRT
`_strdup` spelling, prevents Windows SDK `min`, `max`, and `ERROR` macros from
colliding with MeCab identifiers, and redirects the vendored `CreateFileA`
mapping call through a bounded `MB_ERR_INVALID_CHARS` conversion followed by
`CreateFileW`. The public ABI therefore continues to accept UTF-8 paths
independently of the active Windows ANSI code page. Canonical absolute drive
and UNC paths are mapped to `\\?\` and `\\?\UNC\` respectively, while an
already extended path is preserved. This keeps long dictionary mappings
independent of the consuming executable's `longPathAware` manifest.

The legacy build tool first proves the unmodified 139-file identity, copies
only those files into a dedicated staging directory, then applies these two
context-checked changes. CMake independently enumerates and verifies the
resulting 139-file, 5,382,103-byte safety-v1 tree before it can configure a
target. The committed native-assets input is that same accepted post-patch
tree.

## Compiled frontend subset

Both build paths compile the embedded MeCab runtime plus:

- `text2mecab`;
- `mecab2njd` and NJD records;
- pronunciation and digit transforms;
- accent-phrase and accent-type transforms;
- unvoiced-vowel transform; and
- the pinned long-vowel stage.

They do not compile or link HTS synthesis, voices, audio, `jpcommon`, or
`njd2jpcommon`. Native-assets builds use the reviewed portable UTF-8-only
configuration at `native/portable/config.h`; the legacy macOS CMake path
generates `config.h` in its build tree. Neither path writes generated
configuration into the upstream or vendored source tree.

## Native-assets C/C++ build split

The build hook intentionally uses two compiler profiles:

1. `silent_stdio.c` and the Open JTalk C frontend sources are compiled as C11
   into an internal static archive named `misakid_openjtalk_frontend`. That
   archive has no native-asset routing of its own.
2. `misakid_openjtalk.cpp` and the embedded MeCab `.cpp` runtime are compiled
   as C++17. The final routed native asset links the private C archive.

This preserves each upstream file's source-language semantics rather than
compiling the `.c` frontend as C++. Clang/GCC profiles use hidden visibility
and function/data sections; every profile uses its compiler's stable path
mapping and the force-included silent-stdio/Windows-compatibility header.

Open JTalk's UTF-8 C rule tables require signed 8-bit plain-`char` behavior.
Clang/GCC C11 profiles therefore pass `-fsigned-char`; MSVC's default is left
unchanged. The C-compiled `silent_stdio.c` contains a compile-time assertion
requiring
`CHAR_MIN == -128` and `CHAR_MAX == 127`; a target that cannot provide those
semantics fails its build. This invariant is required even when the build host
would happen to default to signed `char`.

### Target profiles and ABI boundaries

| Target profile | Accepted runtime ABIs | Link/export policy |
| --- | --- | --- |
| Android | `androidArm`, `androidArm64`, `androidX64` | Link `c++_static` and `libm`; garbage-collect sections; exclude static-archive symbols; apply the established `exports_android.map` for the exact 23-symbol adapter ABI. |
| iOS | `iosArm64`, `iosX64` | Link the platform C++ runtime and dead-strip unused sections; route one native framework asset through Dart native assets. |
| Linux | `linuxArm64`, `linuxX64` | Require a same-architecture native Linux host; link the platform C++ runtime, `libm`, and pthread; garbage-collect sections, hide the frontend archive, reuse the byte-identical established `exports_android.map`, and set SONAME `libmisakid_openjtalk.so`. |
| macOS | `macosArm64`, `macosX64` | Link the platform C++ runtime and dead-strip unused sections; route the package native asset. |
| Windows | `windowsX64` | Require an x64 Windows host and the native-assets MSVC `cl.exe`/`lib.exe` configuration, compile as UTF-8, and export the 23 ABI functions with `__declspec(dllexport)`. Windows arm64/x86 and clang/GCC hook drivers are rejected. |

The hook ignores unsupported operating systems and rejects unsupported
architectures for configured operating systems before compiler execution.
Dart rejects unsupported runtime ABI tuples before opening the dictionary.
Stable Flutter 3.41.7 release packaging has completed for Android
armv7/arm64/x86-64 and an unsigned iOS arm64 device application. The Android
libraries have exact 23-export surfaces, only
`libc`/`libdl`/`libm` dynamic dependencies, NativeAssets mappings, and 16 KiB
ELF/ZIP alignment. Both iOS frameworks have platform `IOS` and minimum-iOS-13
metadata, reviewed `@rpath` install names, platform libc++/libSystem linkage,
the application framework rpath, NativeAssets mappings, and exact 23-export
surfaces.

Stable Flutter 3.41.7 additionally ran
`integration_test/japanese_openjtalk_mobile_parity_test.dart` successfully on
an Android 15/API 35 arm64 emulator and an iPhone 17 iOS 26.5 Simulator. Each
run provisioned and verified the exact nine-file, 107,304,813-byte dictionary
and committed fixture, then matched all 24 cases, all 155 raw records and 14
fields, all 23 final phoneme and typed-token results, and the exact pinned
whitespace-only failure. Physical-device evidence, Android armv7/x86-64 and
iOS x64 runtime, and the clean hosted Android/iOS matrix remain release gates,
so broad mobile support remains experimental.

The bundled macOS arm64 asset has completed build, full frontend parity,
lifecycle, four-isolate, exact 23-export, and no-stdio verification. Bundled
macOS x64 is not yet provisioned.

On 2026-07-30, foreign-host, model-free Zig probes cross-linked the exact
configured source set as Linux x64 ELF, Linux arm64 ELF, and Windows x64 PE.
Both ELF artifacts carried SONAME `libmisakid_openjtalk.so`; all three
artifacts exposed the reviewed 23 adapter names. The Windows probe exercised a
GNU compatibility target, not the supported MSVC hook path. No Linux/Windows
Flutter package, native-assets mapping, host loader, dictionary, or G2P parity
result is implied by these probes. Target-host runtime initialization with a
long Japanese and space-containing dictionary path also remains untested.

The Android final asset statically embeds the NDK LLVM libc++ runtime requested
as `c++_static`. Its Apache-2.0 with LLVM exception terms are retained in the
package `LICENSE`, `THIRD_PARTY_NOTICES.md`, and
`native/licenses/llvm-exception.txt`. Apple targets use the platform C++
runtime. The legacy explicit CMake path remains a separate macOS 11+ arm64
profile and produces `libmisakid_openjtalk.dylib` with an `@rpath` install
name.

## Native ABI ownership and limits

ABI version 1 uses opaque contexts and per-call results. Results own contiguous
copies of every one of the 11 string and three integer NJD fields and remain
valid independently of the Open JTalk state until explicitly destroyed. A
process-global native mutex serializes initialization, analysis, and context
destruction across Dart isolates. Every C++ exception is contained at the C
boundary; fixed-capacity diagnostics and result/input limits bound failure
data and adapter-owned allocations. A direct ABI test retains one result,
performs another analysis on the same context, and rereads every retained field
before destruction.

The inherited Open JTalk/MeCab C routines still contain unchecked allocation
sites; an extreme system out-of-memory condition inside those routines is not
promised to be recoverable as status 8. The frontend rejects more than 65,536
MeCab words before NJD construction and retains the same cap after NJD
transforms. Individual copied fields are limited to 1 MiB and aggregate copied
string data to 64 MiB.
