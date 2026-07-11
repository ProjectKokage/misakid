## 0.1.0-dev.1

- Add immutable byte-backed legacy and frontend-1.1 resource bundles with the
  same exact identity/schema validation as the preserved path APIs, behind a
  platform-neutral conditional file-loading boundary.
- Add a complete no-Python legacy Chinese backend composed from pure-Dart
  cn2an 0.5.23, Jieba 0.42.1 accurate+HMM, and pypinyin 0.53.0 stages.
- Validate every caller-supplied dictionary and probability resource by file
  kind, byte size, SHA-256, schema/count invariants, and stable snapshots.
- Match all 24 accepted original-Misaki legacy cases, 41 segmentation runs,
  82 words/pinyin calls, 152 pinyin syllables, and two pinned failures.
- Add source/data provenance, exact third-party license texts, public usage
  documentation, adversarial parser tests, and provisioned resource tests.
- Add the complete frontend-1.1 backend with checksum-pinned Jieba POS/search
  and pypinyin-dict large-phrase resources. Match all 26 accepted outputs,
  131 POS records, 365 pypinyin calls, and 107 search calls exactly.
- Add the pure-Dart frontend-1.1 plus `en_core_web_sm` no-fallback composition,
  with exact American/British and legacy/2.0 parity for 14 callback cases.
