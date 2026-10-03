## Unreleased

- Use `misakid_adapter_support` for the path and file checks this package
  shared with the other adapters, instead of private copies. No behavior
  change.

## 0.1.0-dev.1

- Add an explicit macOS arm64 MeCab-ko 0.996/ko-0.9.2 morphology adapter.
- Add a pure-Dart, checksum-pinned CMUdict 0.7a pronunciation provider.
- Verify the exact MeCab-ko source, Korean dictionary, and CMUdict identities
  without downloading any resource at build time or runtime.
- Add an owned and bounded no-Python C ABI with global locking, structured
  failures, deterministic close, and a native-finalizer fallback.
- Match all 34 committed Korean morphology streams, 293 morphology records,
  23 CMUdict lookups, 33 successful final outputs, and the pinned upstream
  failure from original Misaki 0.9.4.
