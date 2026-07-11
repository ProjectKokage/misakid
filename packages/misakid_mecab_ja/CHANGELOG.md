## 0.1.0-dev.1

- Add first-class Android/iOS/macOS native-assets builds from the exact
  vendored MeCab source, with portable UTF-8 configuration and a reviewed
  23-function C ABI.
- Add `openBundled`, injected-membership, and byte-backed grouping-list APIs
  for Flutter and other mobile consumers.
- Verify Android armv7/arm64/x86-64 packaging, 16 KiB alignment, static-libc++
  symbol hiding, and iOS arm64 cross-compilation.
- Re-run every raw and final Japanese Cutlet parity case through the bundled
  native asset and add lifecycle/concurrent-isolate coverage.
- Add the explicit macOS arm64 MeCab 0.996 and UniDic 3.1.0 adapter for the
  Japanese Cutlet-compatible pipeline.
- Validate the complete native source, dictionary tree, and caller-supplied
  pinned Misaki grouping-list identities offline.
- Expose exact raw surface, nullable pronunciation/kana, character type, and
  unknown-node records.
- Add exact jaconv 0.4.0 conversion, longest-match grouping, native lifecycle,
  security, and provisioned parity coverage.
