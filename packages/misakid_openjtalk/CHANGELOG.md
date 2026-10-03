## Unreleased

- Use `code_assets` 2, `hooks` 2.2, and `native_toolchain_c` 0.19.4.
  Preserve the immutable native target inventory with the new OS equality
  contract and retain the existing non-code-asset hook guard.
- Reject a native result whose word count is negative or above the shim's
  65,536-word limit before reading any word.

## 0.1.0-dev.2

- Add `openBundledFromVerifiedInstall` for app-private dictionaries whose exact
  file identities were checked in staging before atomic promotion. The
  existing `open` and `openBundled` entry points retain full runtime
  verification by default.
- Return immediately from non-code-asset hook invocations before verifying
  native sources or reading `input.config.code`. This restores Flutter web
  builds and macOS development-run follow-up passes that do not request code
  assets.
- Add source-configured `openBundled` profiles for native Linux x64/arm64 and
  Windows x64 builds. Desktop hooks require a same-OS, same-architecture host;
  Windows additionally requires the reviewed MSVC `cl.exe` path.
- Keep the adapter ABI at 23 functions. Linux uses
  `libmisakid_openjtalk.so` with the matching SONAME and ELF version script;
  Windows uses `misakid_openjtalk.dll` with explicit exports.
- Add a portable Windows feature configuration and a bounded UTF-8 path shim
  that maps canonical drive and UNC paths through the extended `CreateFileW`
  namespace. Add strict POSIX declarations for Linux C11 compilation.
- Cross-link the exact source set as model-free Linux x64/arm64 ELF artifacts
  and a Windows x64 PE GNU-compatibility probe. Target-host Flutter packaging,
  loading, long Japanese/space-path initialization, and fixture parity remain
  unverified for both desktop platforms.

## 0.1.0-dev.1

- Add the explicit macOS arm64 Open JTalk 1.11 frontend for Misakid Japanese.
- Add an `openBundled` native-assets path with build profiles for Android,
  iOS, and macOS. Stable Flutter 3.41.7 release packaging passes for Android
  armv7/arm64/x86-64 and an unsigned iOS arm64 device app. Complete local
  committed-fixture parity also passes on an Android 15/API 35 arm64 emulator
  and an iPhone 17 iOS 26.5 Simulator; broad mobile support remains
  experimental pending physical devices, other runtime ABIs, and the clean
  hosted matrix.
- Verify both mobile-harness libraries have their exact 23 exports and
  NativeAssets mappings. Android additionally has only `libc`/`libdl`/`libm`
  dependencies and 16 KiB ELF/ZIP alignment; iOS has `IOS`/minimum-iOS-13
  metadata, reviewed `@rpath` install names, platform libc++/libSystem linkage,
  and the application framework rpath.
- Vendor and verify the exact 139-file, 5,382,103-byte
  `misakid-openjtalk-safety-v1` source tree (SHA-256
  `8ce47a975dee79c078914df15c40df5906430e4a63be4fc2bc0987e7b5b2fccb`)
  so native builds require no source download.
- Keep the nine-file, 107,304,813-byte Open JTalk dictionary external and
  require applications to materialize it at an absolute filesystem path.
- Compile the Open JTalk frontend as C11 and the adapter/MeCab runtime as
  C++17. Enforce signed 8-bit `char` semantics for the UTF-8 C rule tables
  with `-fsigned-char` and a compile-time assertion.
- Link Android's LLVM libc++ statically and include its Apache-2.0 with LLVM
  exception notice; keep only the reviewed 23-symbol adapter ABI visible.
- Verify the exact pyopenjtalk 0.4.1 source and Open JTalk dictionary identities
  without downloading either resource.
- Add an owned, bounded, no-Python C ABI with global locking, structured
  failures, deterministic close, and finalizer fallback.
- Add the package build executable, exact post-patch CMake provenance gate,
  fixed install tree with redistribution notices, and release artifact checks.
- Pass all 24 committed frontend cases, 155 raw records, 14 raw fields, 23
  successful final outputs, and every typed token/metadata field, plus direct
  ABI ownership, excessive-word, concurrent-isolate, and no-stdio tests on
  macOS arm64 for the explicit and bundled native-library paths.
- On both locally verified mobile runtimes, provision the exact nine-file,
  107,304,813-byte dictionary and committed fixture, then match the same 24
  cases, 155 raw records/14 fields, 23 final phoneme and typed-token results,
  and exact pinned whitespace-only failure.
