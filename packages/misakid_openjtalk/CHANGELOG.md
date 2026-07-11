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
