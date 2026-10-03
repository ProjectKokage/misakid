## Unreleased

- Use `misakid_adapter_support` for the path and file checks this package
  shared with the other adapters, instead of private copies. No behavior
  change.

## 0.1.0-dev.1

- Add exact pure-Dart GPT-2/RoBERTa byte-BPE decoding, splitting, merging, and
  spaCy token-to-piece alignment for `en_core_web_trf==3.8.0`.
- Add deterministic `regex==2024.11.6` / Unicode 16 Letter, Number, and
  White_Space tables.
- Add internal bounded validation for the exact external model resources and
  strict decoding of the 49-label `[49, 768]` tagger projection.
- Add the supported macOS 11+ arm64 composite backend, package-owned
  Apple-Accelerate implementation, CMake build, and explicit offline builder;
  no prebuilt binary is bundled.
- Match all 116 accepted transformer cases and 2,278 raw records, then compose
  the real transformer and eSpeak adapters for all 40 accepted fallback cases
  and 50 raw eSpeak calls.
- Add strict resource, lifecycle, input, ABI/export/linkage, reproducibility,
  packaging, and provisioned-CI checks without a Python or Torch runtime.
- Enforce configured aggregate piece limits during byte-BPE assembly and
  replace repeated whole-sequence merge scans with an exact ranked linked
  algorithm, preserving simultaneous-merge behavior while bounding
  adversarial work.
