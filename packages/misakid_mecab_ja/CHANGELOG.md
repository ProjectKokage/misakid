## Unreleased

- Align the workspace adapter with `code_assets` 2, `hooks` 2.2, and
  `native_toolchain_c` 0.19.4.

## 0.1.0

- Publish with explicit repository and Android/iOS/macOS platform metadata,
  depending on the stable `misakid` 0.1.0 core.
- Make caller-selected compatible UTF-8 UniDic dictionaries the default,
  accepting the provisioned 26- and 29-field layouts without inferring their
  corpus, distribution, release, or exact identity and without claiming exact
  output parity; retain the content-hashed modified unidic-py CWJ tree as the
  explicit `pinnedUnidicPyCwjParity` fixture profile.
- Exercise the 29-field contract against distinct official NINJAL
  `unidic-cwj-202302.zip` and `unidic-csj-202302.zip` resources and keep both
  corpus and exact identity unknown in the generic backend metadata. Retain
  unidic-lite 2.1.2 as the independent 26-field provisioned test.
- Remove the unprovisioned 17-field layout from the public and native
  compatibility contract before the first stable adapter release.
- Advance the native contract to ABI 3 and
  `misakid-mecab-ja-build-v4-portable`, reporting the detected feature layout
  independently from dictionary corpus and release metadata.
- Add first-class Android/iOS/macOS native-assets builds from the exact
  vendored MeCab source, with portable UTF-8 configuration and a reviewed
  24-function C ABI.
- Add `openBundled`, injected-membership, and byte-backed grouping-list APIs
  for Flutter and other mobile consumers.
- Verify Android armv7/arm64/x86-64 packaging, 16 KiB alignment, static-libc++
  symbol hiding, and iOS arm64 cross-compilation.
- Re-run every raw and final Japanese Cutlet parity case through the bundled
  native asset with the strict pinned modified unidic-py CWJ profile and add
  lifecycle/concurrent-isolate coverage.
- Add the explicit macOS arm64 MeCab 0.996 adapter for the Japanese
  Cutlet-compatible pipeline, with separate compatible and exact-parity
  dictionary profiles.
- Validate the complete native source, the optional strict dictionary tree,
  and caller-supplied pinned Misaki grouping-list identities offline.
- Expose exact raw surface, nullable pronunciation/kana, character type, and
  unknown-node records.
- Add exact jaconv 0.4.0 conversion, longest-match grouping, native lifecycle,
  security, and provisioned parity coverage.
