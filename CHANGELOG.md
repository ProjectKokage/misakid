## 0.1.0

- Add `AsyncEnglishG2pEngine` and `KokoroAsyncEnglishG2pFrontend`, preserving
  the deterministic English pipeline and Kokoro chunking while allowing a
  cancellable asynchronous unknown-word backend.
- Add the optional `misakid_fonix_en` adapter with a closed en-US medium
  convolutional/BiGRU CTC
  manifest, exact model identity, one isolate-owned CPU Fonix session, bounded
  inputs/messages/logits, cancellation and drain, recovery, and idempotent
  close behavior.
- Add a locked UV training/export project for the app-owned en-US fallback.
  It deterministically merges and splits the two pinned Apache-2.0 American
  lexicons, trains on CPU, exports opset-17 ONNX, checks Torch/ORT parity, and
  emits external manifest/report/parity artifacts. The 1,173,871-parameter
  `v1-5ce8863c502d` graph passes the fixed 67% word-accuracy, 7% PER, 6 MiB,
  warm-latency, Torch/ORT, and 32-case real-Fonix gates; its exact model bytes
  remain outside Git. The earlier 692,643-byte graph remains an unfrozen
  prototype and is not V1.
- Promote the duplicate-key-rejecting bounded JSON parser into the shared root
  library and reuse it in both optional neural-model adapters.
- Add immutable Kokoro handoff chunks that reproduce the pinned Kokoro 0.9.4
  English and non-English text-splitting limits, fixed English `unk=''`
  policy, source-segment indices, and Python code-point behavior. An accepted
  eleven-case fixture executes the unmodified pinned pipeline while leaving
  vocabulary, voice/style, tensor construction, and ONNX inference to the
  consuming runtime.
- Add Android, iOS, and macOS bundled-native-asset build profiles to the
  Japanese Cutlet backend, with vendored checksum-pinned MeCab source, exact
  ABI/export validation, byte-backed `ja_words.txt`, and a repository-owned
  mobile release-build verification app. Android and unsigned iOS device
  artifacts are verified, including exact Android libc/libdl/libm linkage, and
  the complete accepted fixture passes through bundled assets on Android
  15/API 35 arm64 and iOS 26.4 emulated runtimes. Physical-device and clean
  hosted-matrix validation remain before broad mobile release support is
  claimed.
- Release `misakid_mecab_ja` 0.1.0 with an exact pinned modified-CWJ parity
  profile and a separate corpus-agnostic compatible profile. Provision the
  latter against unidic-lite 2.1.2's 26-field layout and the distinct official
  NINJAL CWJ/CSJ 2023.02 29-field archives; do not infer corpus identity from
  release or layout, and remove the unprovisioned 17-field claim.
- Add Android, iOS, and macOS bundled-native-asset build profiles to the
  Japanese Open JTalk backend. The package vendors the exact reviewed
  safety-patched source tree, preserves C11/C++17 language boundaries, and
  enforces signed-char UTF-8 table semantics on Android. The shared Flutter
  release APK and unsigned iOS app pass exact dual-library export, linkage,
  manifest, and alignment checks; the complete 24-case/155-record fixture and
  23 typed-token outputs pass on Android 15/API 35 arm64 and iOS 26.5 emulated
  runtimes. Physical-device and clean hosted-matrix validation remain.
- Add byte-backed English small-model and Chinese legacy/frontend-1.1 resource
  constructors so mobile applications can load packaged assets without
  filesystem-only APIs.
- Add the optional pure-Dart `misakid_spacy_en` adapter for the exact
  `en_core_web_sm==3.8.0` tokenizer/tagger resources. It matches all 146
  accepted English streams and 744 raw tokens without Python or native code.
- Add the optional `misakid_espeak_en` macOS-arm64 adapter for the exact eSpeak
  NG 1.52.0 tuple. Real spaCy-plus-eSpeak composition matches all 40 accepted
  fallback outputs, tokens, and 58 ordered raw calls.
- Add the experimental `misakid_bart_en` pure-Dart one-layer BART fallback
  adapter with explicit checksum-identified F32 resources, bounded parsing and
  inference, and a real Transformers 4.51.3 synthetic-model oracle. The named
  PeterReid weights remain unaccepted and unsupported.
- Accept the deterministic 33-member inventory for the exact 457 MB
  `en_core_web_trf==3.8.0` artifact after checksum, archive-safety, metadata,
  and license review; the model remains an explicit external caller resource
  and is never bundled.
- Accept 116 American/British transformer cases across no-fallback and eSpeak
  fallback, with 2,278 captured raw token records, 50 ordered eSpeak calls, and
  exact final replay. Route the two resource closures through distinct locked
  oracle interpreters and add a deterministic graph/tensor inspection tool.
- Add the supported `misakid_spacy_trf_en` macOS 11+ arm64 adapter: exact
  tokenizer and byte-BPE stages in Dart, a package-owned Apple-Accelerate
  12-layer transformer, strict external-resource identities, reproducible
  builds, and no Python or Torch runtime. The real backend matches all 116
  accepted cases, and real transformer-plus-eSpeak composition matches all 40
  fallback cases.
- Add exact transformer boundary cases at 104, 105, 144, 145, 208, and 249
  marked pieces per dialect, including an emoji whose tag detects omitted
  overlap averaging.
- Bound transformer byte-BPE work by threading the configured aggregate piece
  limit through assembly and replacing quadratic full-list rescans with an
  exact ranked linked merge algorithm verified against the former reference
  scan on seeded adversarial tables.
- Correct both accepted eSpeak oracle locks to include upstream's exact
  `joblib==1.4.2` transitive runtime dependency.
- Use generated CPython 3.12 lowercase semantics in shared English stages and
  add an authoritative Cherokee tag-weight regression whose final tag differs
  under the host Dart lowercase mapping.
- Complete both Japanese contracts on macOS arm64 with the explicit Open JTalk
  and MeCab/UniDic Cutlet adapters, including exact final/raw parity, resource
  identity, ownership, isolate, lifecycle, and no-stdio tests.
- Complete the pure-Dart Chinese frontend-1.1 backend without an English
  callback using eleven checksum-pinned resources and exact parity for all 26
  accepted outputs plus every captured POS, pinyin, and search call.
- Support the exact Chinese frontend-1.1 plus pure-Dart English small-model
  no-fallback composition across American/British and legacy/2.0 rendering.
  Its 14 accepted cases exhaust 14 callbacks, 40 raw tokenizer records, and
  33 final English tokens; the read-only aggregate now covers 431 cases in 17
  fixtures through distinct combined and transformer/eSpeak interpreter keys.
- Exclude root `/test` and `/tool` content from the root library boundary so no
  Python oracle tooling, fixture tests, or fixture-generator inputs are
  distributed as runtime code.
- Keep workspace members directly publishable by allowing their publishable
  source trees through the root archive while each nested `.pubignore` removes
  tests, Python/oracle tooling, caches, models, and binaries. Required offline
  native-builder source and manifests remain in the relevant adapter archive.
- Add the optional `misakid_chinese` sibling package with a complete
  no-Python legacy/default backend: exact pure-Dart cn2an 0.5.23, Jieba 0.42.1
  accurate+HMM, and pypinyin 0.53.0 stages over six explicitly supplied,
  checksum-pinned resources.
- Accept and replay 24 authoritative Chinese legacy fixtures, matching all 22
  outputs, two pinned failures, 41 segmentation runs, 82 words/pinyin calls,
  152 syllables, and null-token semantics; add a direct original-Jieba replay,
  adversarial resource/parser tests, complete MIT notices, and provisioned CI.
- Restore pinned g2pkc's non-overlapping silent-onset insertion for
  consecutive standalone Jamo vowels, fixing adjacent-ARPABET-vowel rendering
  and adding focused composition regressions.
- Make Vietnamese lower/upper and whitespace handling host-independent with
  exhaustive CPython-3.11.15/Unicode-14 candidate mappings, including
  multi-scalar expansion, supplementary scripts, and context-sensitive
  Final_Sigma; retain exact-3.11.13 comparison as an explicit parity gate.
- Restore pinned English decimal near-integer rounding, reverse-Japanese
  fractional unit/repeated-point quirks, and Cutlet's decimal-versus-digit
  Unicode distinction; harden injected English rating validation.
- Add 42 checksum-pinned adversarial English fixtures, bringing exact
  American/British no-fallback replay coverage to 106 cases across number
  flags and edge values, morphology, controls, Unicode, mixed scripts, and
  symbols.
- Add a strict accepted-fixture manifest and one read-only command that
  validates complete corpus/fixture/provenance coverage and verifies all 431
  committed oracle cases by default.
- Harden the publish archive exclusions for lock, generated documentation,
  the empty `bin` directory, and Dart/Python cache artifacts; remove the
  misleading upstream Python homepage from package metadata pending a
  canonical Dart package repository URL.
- Pinned the exact `en_core_web_trf==3.8.0` transformer oracle artifact and
  curated Python 3.12 dependency closure without downloading or bundling the
  457 MB model, and prepared mode-only American/British transformer corpora.
- Recorded the checksum-pinned Mishkal 0.3.2 source/data license blocker; no
  historical Mishkal material is copied or translated.
- Recorded the GPLv3 underthesea 6.8.4 and independently unresolved packaged
  tokenizer-model boundary; no underthesea code, native library, or model is
  included.
- Add the optional `misakid_openjtalk` sibling package: an explicit no-Python
  macOS arm64 Open JTalk 1.11 adapter with verified source/dictionary identity,
  owned results, structured no-stdio failures, process-global locking, bounded
  inputs/results, deterministic close, and no committed native artifact.
- Pass its real production ABI against all 24 Japanese cases, 155 raw frontend
  records and 14 fields, all final phoneme/token fields, four concurrent
  isolates, direct native result ownership, lifecycle/bounds cases, and
  byte-empty native stdout/stderr; add reproducible release artifact gates.
- Add the optional `misakid_mecab_ko` sibling package: a reproducibly
  source-built macOS arm64 MeCab-ko adapter plus pure-Dart CMUdict provider,
  with exact source/data identities, owned no-stdio ABI, bounded lifecycle,
  and no committed native binary or data resource.
- Pass its production path against all 34 Korean morphology streams, 293
  morphology records, 23 CMU lookups, 33 successful final outputs, and the
  pinned failure, plus concurrent-isolate, tampering, and lifecycle tests.
- Begin the behavior-preserving Dart port pinned to Misaki 0.9.4.
- Add shared engine, result, token, metadata, backend, and error contracts.
- Add dependency-free Japanese Arabic/kanji/kana/romaji number conversion.
- Add the pure Japanese pyopenjtalk-style mora, accent, pitch, and rendering
  pipeline behind an explicit frontend contract.
- Add the explicit Hebrew phonemizer backend contract and typed facade.
- Port the pure English phoneme stress and weighting stage.
- Port the dialect-sensitive English inflection suffix rules.
- Port exact English token merging with typed metadata.
- Port the right-to-left English vowel/`to` context stage.
- Port English subtoken resolution and stress balancing.
- Port exact legacy versus 2.0 English final rendering.
- Add the public injected English engine and typed tokenizer, pronunciation,
  and fallback backend contracts.
- Reject malformed English tokenizer records and any token stream that does
  not reconstruct the exact preprocessed input.
- Add the offline pinned American/British lexicon provider with contextual,
  morphology, currency, and clean-room number behavior.
- Expose immutable dialect/version English inventories and validate every
  generated gold and silver pronunciation against the pinned raw inventory.
- Pass both 52-case American and British no-fallback English suites end to end
  using the same strict typed raw-token replay boundary.
- Add pure eSpeak fallback replacement/postprocessing behind an injected raw
  eSpeak-phone backend without bundling or discovering eSpeak-ng.
- Pin and review the named US/GB BART fallback revisions and document the
  unresolved training-data, lineage, license, copyright, and notice blocker;
  no model artifacts are accepted or distributed.
- Add exact host-independent CPython 3.12.11 / Unicode 15.0.0 NFC/NFKC and
  alphabetic, decimal, digit, and whitespace tables with exhaustive scalar
  plus cross-scalar digest verification.
- Add the pure Japanese Cutlet normalizer and renderer behind a typed,
  explicitly grouped morphology boundary without vendoring `ja_words.txt`,
  with exact mapping integrity, typed-failure preservation, strict oracle
  capture scaffolding, and a compiling fixed-record example.
- Expose immutable source-derived Japanese phoneme inventories for both Cutlet
  and pyopenjtalk-style rendering, with exact scalar and mora-table digests.
- Port the pure legacy-Chinese tone and punctuation mapping helpers.
- Add public injected legacy and 1.1 Chinese engines with typed
  cn2an/jieba/POS/search/pypinyin boundaries, ordered sandhi and erhua,
  mixed-English handling, exact internal tokens, and null outer-token
  semantics. The legacy contract is now completed by the separate resource
  package; frontend 1.1 without an English callback is completed by the same
  resource package, and the precise small-model/no-fallback callback profile
  is completed by composing it with `misakid_spacy_en`.
- Expose immutable source-derived Chinese render-scalar inventories for the
  legacy and frontend-1.1 contracts, with exact digest and exclusion tests.
- Add the public injected Korean g2pkc engine with typed morphology and
  CMUdict boundaries, deterministic generated idiom/rule data, and null-token
  semantics.
- Pass the adversarial 34-case Korean default-mode matrix end to end using
  strict ordered MeCab and CMUdict replay: 33 exact successful outputs and the
  pinned 17-digit numeral failure boundary.
- Preserve CPython 3.12 seed-zero tuple-set iteration for order-sensitive
  Korean numeral replacements, backed by fixed hash/table vectors and a
  4,096-case zero-mismatch offline differential.
- Expose the immutable 67-symbol modern conjoining-Jamo inventory used by the
  default Korean renderer and validate committed Jamo output against it.
- Add the public pure Vietnamese cleaner, phonology, substring behavior,
  clean-room number spelling, dialect/tone options, typed tokenizer and
  English-fallback boundaries, token metadata, and deterministic generated
  licensed data.
- Add strict raw eSpeak and Vietnamese external-stage oracle capture schemas
  for deterministic Dart replay.
- Add Linux, macOS, and Windows CI, warning-free API documentation checks,
  compiling public examples, and a versioned cold/warm latency, throughput,
  RSS, and generated-data-size benchmark.
- Enforce documentation for every public Dart member, including deterministic
  generated-data contracts, through fatal analyzer infos.
- Add a contract test that keeps the published library free of platform-only
  I/O, FFI, web, Flutter, and direct printing APIs.
