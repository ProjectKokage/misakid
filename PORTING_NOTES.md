# Porting Notes

This file records compatibility decisions, upstream observations, intentional
divergences, and fixture-impacting changes. It is not a roadmap or a claim of
support; see PORTING_STATUS.md for the current support matrix.

## 2026-08-23: Retired permanent generator inputs

- Removed repository copies of upstream generator inputs and the one-consumer
  generators that produced already committed runtime tables.
- Runtime behavior is unchanged: focused data tests, exhaustive behavior
  digests, and accepted parity fixtures continue to cover the committed tables.
- Upstream revisions and licensing provenance remain in this file and
  `THIRD_PARTY_NOTICES.md`; an explicit future upstream sync may use temporary
  extraction tooling without keeping a second source tree in Git.

## 2026-07-10: Phase 0 compliance baseline

- Established hexgrad/misaki commit
  fba1236595f2d2bf21d414ba6e57d25256afada3, Python package version 0.9.4,
  as the reference baseline.
- Added the upstream Apache License 2.0 text and an initial third-party
  provenance ledger.
- Recorded every language, version, dialect, fallback, and backend family as
  unsupported.
- Made no concrete language-engine behavior change. A concurrent initial
  shared-core slice replaced the generated calculate example with immutable
  result/token types, typed metadata, engine and backend interfaces, package
  exceptions, pinned-upstream constants, and focused shared API tests.
- No Python reference environment, JSONL exporter, corpus, fixture, runtime
  table, generator, backend adapter, or parity verifier has been added.
- No upstream language pipeline source or language data has been translated
  or copied into the Dart implementation in this compliance change.

## Pinned-reference observations

These observations constrain later implementation. They do not describe
features already present in Dart.

- misaki/token.py defines shared token text, tag, whitespace, phonemes, start
  and end timestamps, and optional dynamic metadata. The Dart API must retain
  observable null-versus-empty distinctions while replacing dynamic metadata
  with typed language-specific values.
- The default unknown marker used by the language implementations is ❓.
- English G2P accepts a version value, transformer selection, British dialect
  selection, fallback, and unknown marker. Version 2.0 preserves symbols that
  the older/default rendering maps to compatibility symbols.
- Japanese exposes distinct cutlet and pyopenjtalk contracts. The latter
  constructs mora, accent, chain, and pitch information.
- Chinese exposes a legacy/default path and a version 1.1 frontend. The legacy
  contract returns no token list; mixed-English behavior differs based on
  whether an English callable is supplied.
- Korean currently returns no token list. Vietnamese has three dialects and
  multiple tone, cleaning, substring, and English-fallback options. Hebrew is
  a Mishkal-backed adapter surface.
- Some upstream constructors perform network-affecting installation behavior:
  English can call spaCy model download, and g2pkc can call NLTK CMUdict
  download. Production Dart code will not reproduce those side effects.
  Resources and executables must instead be supplied explicitly by adapters,
  with typed initialization failures. This is an integration-policy decision,
  not permission to change phoneme output.

## Compatibility decisions

- The pinned Python execution result is authoritative when source comments,
  documentation, or linguistic expectations disagree.
- Normal tests will consume committed fixtures offline. Running Python or
  accepting regenerated fixtures will require a separate explicit command.
- No output normalization, trimming, symbol folding, token sorting, or other
  comparison relaxation is approved.
- A missing external backend will be reported explicitly; it will not be
  replaced with an undocumented heuristic.

## Intentional divergences

- Invalid configuration and malformed injected-backend records fail with typed
  Dart package exceptions instead of incidental Python `IndexError`,
  `KeyError`, or assertion failures. Valid-domain output remains exact, and
  upstream-defined diagnostics that are returned as values remain values.
- In particular, Japanese number input longer than nine comma-free characters
  returns the exact upstream string `Number length too long, choose less than
  10 digits`; it is not converted into an exception.
- The explicit-resource adapter policy changes resource acquisition and
  failure timing, not the selected mode's phoneme or token output contract.
- Pinned g2pkc collects numeral matches in a Python `set`, so overlapping
  replacement order otherwise varies with Python's hash seed. Dart reproduces
  the pinned CPython 3.12 SipHash13 tuple-set table order for the required
  `PYTHONHASHSEED=0` oracle (including bare-number replacement inside a counter
  span and `10` changing the prefix of `106`) while keeping production output
  deterministic.
- Pinned `process_num` leaves its local name uninitialized for a nonzero digit
  at position 16 and raises `UnboundLocalError`. Dart rejects the same
  17-digit domain explicitly with `InvalidConfigurationException`; no partial
  pronunciation is returned.

## Licensing blockers discovered at baseline

- The pinned Vietnamese number converter names a source and explicitly says
  “No license.” That code must not be copied or translated without compatible
  permission; a separately reviewed implementation strategy is required.
- The pinned Korean g2pkc directory records a copy/adaptation chain but does
  not include license evidence in its local headers or README. This baseline
  blocker was subsequently resolved by the review recorded below.
- Several copied dictionaries and rule/data files have no file-level source
  commit, license, or checksum in the pinned package.
- MIT-labeled adapted files in the pinned package initially named their origin
  without the original full license text or exact source revision. Japanese
  num2kana, Cutlet, and Chinese pinyin-to-IPA have since been reviewed as
  recorded below.

THIRD_PARTY_NOTICES.md contains the detailed provenance ledger. Generated code
will not erase the obligations or unresolved status of its inputs.

## 2026-07-10: Japanese num2kana provenance review

- Verified that Greatdane/Convert-Numbers-to-Japanese is MIT-licensed with
  “Copyright (c) 2018 David Wilson, https://github.com/Greatdane”. The full
  notice is now retained in THIRD_PARTY_NOTICES.md.
- Pinned Greatdane commit
  c01b072e8d52c89c307dcbcb69958d05e953d4c1 as the closest source revision.
  It was the repository's master and last source-file revision when reviewed
  on 2026-07-10.
- Compared every source-file revision reachable in the 14-commit repository
  history. No Greatdane revision is byte-identical to the pinned Misaki file.
- After removing Misaki's two provenance lines, the pinned file differs from
  c01b072e8d52c89c307dcbcb69958d05e953d4c1 in two lines: it changes an
  oversized-number return into an assertion and adds hiragana as Convert's
  default dictionary choice.
- Both modifications first appear with the file's introduction in Misaki
  commit fdc9c5e5ec74a9fbb81e02bd487d0fb8bd8e4ec8. Later Misaki commits change
  only the provenance header.

The num2kana origin-license blocker is resolved subject to retaining the MIT
copyright and permission notice with any derived material. Its precise source
description must remain “Greatdane c01b072 plus two Misaki modifications,” not
an assertion of a byte-identical Greatdane revision.

The current Dart adaptation is lib/src/languages/ja/number_converter.dart. It
records its source and Dart modifications in the file header, and the required
MIT copyright and permission notice is distributed in
THIRD_PARTY_NOTICES.md.

## 2026-07-10: Japanese Cutlet provenance review

- Identified polm/cutlet commit
  `d03f11c52a7cc7ed29a17d538e9271d693cb1cd0` as the precise pre-refactor
  source structure from which pinned Misaki's Cutlet algorithm was adapted.
- Recorded hashes for the original `cutlet.py`, `mapping.py`, the substantially
  modified Misaki file, and Cutlet's MIT license.
- Retained the complete MIT notice for “Copyright (c) 2020 Paul O'Leary
  McCann” in `THIRD_PARTY_NOTICES.md`.

This resolves the Cutlet code-license blocker. The unrelated
`misaki/data/ja_words.txt` surface-form list was initially left outside the
Dart runtime because upstream records no source, generator, data notice, or
license for it. Its exact Misaki identity is nevertheless authoritative: the
1,921,140-byte, 147,571-record file first entered Misaki in commit
`fdc9c5e5ec74a9fbb81e02bd487d0fb8bd8e4ec8`, has pinned Git blob
`fb3b5b1f87e8dcf113857f96ffe845869a616908`, and has SHA-256
`a93a8e8aee24db307a32becb8bf01c4c2908ecf37e6c91f7a705fafdfeba67ff`.
The subsequent review below replaces the categorical runtime prohibition with
an explicit external-resource boundary without asserting an unproven original
generator.

## 2026-07-11: Japanese ja_words external-resource provenance review

- Recorded the authoritative compatibility artifact as
  `misaki/data/ja_words.txt` at pinned Misaki commit
  `fba1236595f2d2bf21d414ba6e57d25256afada3`. It contains 147,571 sorted
  unique UTF-8 records without a terminal newline; its exact byte length, Git
  blob, and SHA-256 are recorded above and in `THIRD_PARTY_NOTICES.md`.
- Compared it with the current postprocessed Japanese JSONL published at
  https://kaikki.org/dictionary/Japanese/kaikki.org-dictionary-Japanese.jsonl.
  After collecting every top-level `word` and `forms[].form`, filtering to
  length-at-least-two strings fully matching
  `[々\u3040-\u30FF\u4E00-\u9FFF]+`, and deduplicating, 146,737 of the 147,571
  pinned records match: 99.4348%. Of those, 85,647 now occur only as forms.
  The 834 missing pinned records include many old-looking generated
  inflections. This strongly supports an older Kaikki/Wiktextract snapshot,
  but the exact January 2025 dump, extractor revisions, and generation command
  were not recovered. The relationship is an inference, not byte-identical
  provenance.
- Recorded Kaikki's statement that its Wiktionary-derived data is available
  under Wiktionary's CC-BY-SA and GFDL licenses at
  https://kaikki.org/dictionary/index.html. English Wiktionary specifies CC
  BY-SA 4.0 International and GFDL 1.1 or later at
  https://en.wiktionary.org/wiki/Wiktionary:Copyrights; the CC BY-SA 4.0 legal
  code is https://creativecommons.org/licenses/by-sa/4.0/legalcode.en.
- Resolved the implementation boundary by keeping the list outside Misakid.
  The package does not vendor, generate from, discover, download, or
  redistribute it. A Cutlet adapter may require the caller to provide the exact
  pinned Misaki artifact and must validate SHA-256, byte length, record count,
  and format before use. This compatibility check is not a license grant, and
  the adapter must not substitute a mutable or merely similar word list.

## 2026-07-10: Japanese Cutlet injected core and oracle boundary

- Ported the exact Cutlet normalization order, all 189 pinned mapping entries,
  romanization, punctuation spacing, sokuon and moraic-nasal behavior, and
  `tokens == null` contract behind a typed synchronous morphology backend.
- Kept `ja_words.txt` outside the distributed runtime and used explicit
  `joinWithNext` decisions. The reference capture schema records only those
  case-local boolean decisions plus raw fugashi fields; it never copies the
  source list into a fixture or generated Dart data.
- Added exact mapping-digest coverage, malformed-record checks, preservation of
  typed backend failures, a fixed public example, a 25-case adversarial corpus,
  and strict exporter tests. The exporter rejects staged or unstaged tracked
  changes in the pinned checkout and validates `ja_words.txt` by SHA-256, byte
  length, and record count before capture.
- Exposed immutable mode-specific phonetic-scalar inventories derived from the
  complete pinned tables and Cutlet's algorithmic sokuon, moraic-nasal, and
  long-vowel outputs. Exact canonical digests cover all 35 Cutlet and 40
  pyopenjtalk-style symbols; a separate digest covers all 193 mora mappings.
- Did not invent or accept a golden fixture without the exact modified
  unidic-py CWJ resource later pinned by complete tree hash. Its release marker
  alone could not identify it because CWJ and CSJ can share a release number.
  Fixture generation remained pending until that archive was
  explicitly provisioned, its installed tree and live fugashi dictionary are
  pinned, and both regeneration and read-only verification pass.

The pure injected core is experimental. No fugashi/MeCab adapter, UniDic data,
or complete supported Cutlet mode is included.

## 2026-07-10: Japanese number-converter implementation

- Added the public pure-Dart JapaneseNumberConverter and
  JapaneseNumberFormat API, based on pinned Misaki num2kana behavior.
- Preserved valid-input output quirks, including irregular readings, the
  nine-character check, decimal gemination, and romaji whitespace.
- Preserved the upstream over-limit diagnostic string exactly. Other malformed
  inputs that trigger incidental Python indexing/lookup failures use typed
  package validation errors, as documented above.
- Added 20 committed exact Python fixtures, including irregular readings,
  decimal and romaji whitespace quirks, the nine-digit limit, and reverse
  Kanji conversion. Dart consumes those fixtures offline.
- This number-conversion slice is partial and does not by itself establish
  support for either complete Japanese backend mode.

## 2026-07-10: Chinese pure-source provenance review

- Pinned pinyin-to-IPA commit
  ef81b82bfa42601300463c50a5db063d3b47e347 and retained its MIT notice for
  “Copyright (c) 2024 Stefan Taubert.” No source revision exactly matches
  pinned Misaki transcription.py; the closest source differs in six initial
  symbol mappings introduced with Misaki commit
  fdc9c5e5ec74a9fbb81e02bd487d0fb8bd8e4ec8.
- Pinned PaddleSpeech commit
  d7bf91561d5a8a025f3cfc4bd7b28368fd98d102 as the coherent develop snapshot
  immediately preceding Misaki's Mandarin frontend import. Its Apache License
  2.0 text is byte-identical to this package's root LICENSE, and it has no root
  NOTICE file.
- PaddleSpeech zh_frontend.py and tone_sandhi.py are substantial adaptations,
  not exact copies. Their closest contemporaneous source blobs and precise
  line-diff counts are recorded in THIRD_PARTY_NOTICES.md.
- Seven normalization implementation files are byte-identical to the pinned
  PaddleSpeech snapshot. The README is exact after a provenance prefix;
  __init__.py changes one import; and text_normlization.py was renamed to the
  corrected text_normalization.py without changing its bytes.
- Retained the applicable 2020 and 2021 PaddlePaddle Authors copyright lines.
  Future Dart adaptations must also carry prominent modification notices.

This review resolves the named pinyin-to-IPA and PaddleSpeech source-license
pins, but does not by itself establish Chinese mode support or clear unrelated
runtime dependencies and data.

## 2026-07-10: Korean g2pkc provenance review

- Pinned the immediate `vocos`-branch source to 5Hyeons/StyleTTS2 commit
  `a895e5bff1d7a22dff2f2d32dafb7c4c4e0ee4b7`.
- Compared all ten code/rule/data files in `g2pK/g2pkc`; every file is
  byte-for-byte identical to pinned Misaki. Misaki adds only a short source
  README.
- Verified that the immediate source's nested `g2pK/LICENSE`, the reviewed
  Kyubyong/g2pK license, and this package's root license are the same Apache
  License 2.0 bytes. Kyubyong/g2pK metadata names Kyubyong Park as author and
  declares Apache License 2.0.
- Recorded permanent source revisions, per-file SHA-256 values, and the
  adaptation obligations in `THIRD_PARTY_NOTICES.md`.

This resolves the Korean code-and-data licensing blocker for the exact pinned
payload. It does not establish behavioral parity or permission to add an
automatic MeCab/CMUdict download path; those remain explicit adapter inputs.

## 2026-07-10: Korean injected g2pkc implementation

- Added `misaki_ko.dart` with a synchronous pure-Dart engine and narrow typed
  morphology/POS and first-pronunciation CMUdict provider contracts. Neither
  provider is discovered, downloaded, or bundled.
- Ported the pinned ordered idiom, embedded-English ARPABET, morphology marker,
  numeral, modern Jamo, special, 401 table-rule, link, and final rendering
  stages. The public result retains upstream's unavailable token list (`null`).
- Copied canonical `idioms.txt` and `table.csv` bytes under the pinned upstream
  tree, recorded their SHA-256 values, and added an offline generator that
  validates 355 idioms and 401 emitted table rules before producing immutable
  Dart data.
- Added a 34-case default-mode fixture produced with Python 3.12.11,
  `python-mecab-ko` 1.3.7, dictionary 2.1.1.post2, and NLTK CMUdict 0.7a at
  SHA-256 `d07cca47fd72ad32ea9d8ad1219f85301eeaf4568f8b6b73747506a71fb5afd6`.
  Backend-input schema 2 records all 293 ordered morphology tokens plus 23
  ordered normalized CMU lookups (22 selected pronunciations and one miss).
  Strict replay passes all 33 successful phoneme strings exactly, requires null
  tokens, and preserves the 17-digit upstream failure boundary with an
  actionable typed `InvalidConfigurationException`; malformed direct number
  input now uses the same package exception rather than a raw SDK error.
- Expanded parity coverage with nine focused cases for source-ordered
  overlapping idioms, numeric exceptions and units; POS-sensitive complex
  batchim, palatalization, and `ui` rules; native-counter boundaries, Unicode
  decimal digits, and 16/17-digit place handling; plus ARPABET fricative,
  affricate, nasal, liquid, glide, case, overlapping-word paths, and the
  observable CPython 3.12 seed-zero tuple-set order used by numeral replacement.
- Replaced the prior semantic numeral-token comparator after it diverged on
  overlapping bare/counter spans such as `1개/B 1`. The Dart stage now reproduces
  CPython 3.12 SipHash13 string hashes, tuple hashes, set probing, and the
  five-entry resize boundary. Fixed ASCII, Korean/UCS-2, supplementary/UCS-4,
  tuple, and resize vectors are covered by unit tests. An offline differential
  generated 4,096 annotated inputs with `random.Random(0)` under
  `PYTHONHASHSEED=0`, spanning repeated prefixes, commas, Unicode decimals,
  spaces, bare numerals, and bound nouns; all 4,096 matched pinned `convert_num`.
- Preserved Unicode and upstream quirks explicitly, including compatibility
  Jamo pass-through, supplementary scalars, variation selectors, all Unicode
  decimal matching against ASCII-only number tables, caret rule blockers, and
  the repeated `p_next2` index in embedded-English conversion.
- Corrected the shared Jamo composer to reproduce the non-overlapping
  silent-onset regular expression in pinned `g2pkc/utils.py`. Consecutive
  standalone vowels receive onsets at alternating positions rather than every
  position; this also preserves the upstream deletion of a remaining
  uncomposed Jamo in embedded-English output. A deterministic differential of
  30,004 ARPABET sequences now has zero mismatches, including adjacent
  monophthong and onset-separated vowel regressions.
- Added `abbreviate abiola` to the authoritative matrix so adjacent CMUdict
  vowels are covered end to end through two exact lookups, five captured MeCab
  records, and final Korean rendering rather than only by a synthetic unit
  differential.
- Additional read-only synthetic differentials found zero mismatches across
  47,340 Korean special/table/link-rule combinations, 50,000 Chinese
  tone-sandhi modifications/pre-merges using equivalent injected records, and
  24,310 Chinese normalization inputs (with the documented typed
  `KeyError`-to-`FormatException` boundary treated as equivalent). These audits
  do not replace authoritative end-to-end fixture coverage.

This is an experimental injected core, not a complete supported Korean mode.

The public Korean inventory is the exact modern conjoining-Jamo domain used by
the pinned default `to_syl=false` path: 19 leading consonants, 21 vowels, and
27 trailing consonants. Input punctuation, whitespace, and other preserved
non-Hangul scalars are intentionally not advertised as phonemes.
A compatible real morphology/CMUdict adapter remains external work.

## 2026-07-10: Vietnamese provenance review

- Pinned Viphoneme at `616a505fdbe83b23bd30a358819e6dded0e1de4a`,
  CodeLinkIO/Vietnamese-text-normalization at
  `4f7b9ea525de73b95838700abab33b68a96bfe85`, and Vinorm at
  `577c9cd9bf499e074801b703a5fd1eaad8300d43`.
- Verified the Viphoneme/Vinorm and CodeLinkIO MIT notices and recorded their
  complete text, source revisions, and checksums in `THIRD_PARTY_NOTICES.md`.
- Confirmed six cleaner modules are exact CodeLinkIO copies and that the three
  pinned JSON dictionaries are deterministic Vinorm derivatives, including
  the precise uppercasing and two-symbol delta.
- Confirmed the independently named `vietnam-number` source still has no
  license. Its `num2vi.py` derivative remains prohibited source material.

Vietnamese phonemizer, cleaner, and dictionary provenance is now sufficiently
pinned for reviewed adaptation. Number spelling must be implemented clean-room
from observable behavior and oracle cases, without translating the unlicensed
file.

## 2026-07-10: English lexicon provenance review

- Verified that hexgrad separately publishes all four English lexicons as the
  `hexgrad/misaki` Hugging Face dataset with Apache-2.0 license metadata.
- Pinned dataset revision `b65a6b4398e053983b9c360f0682b720e362859d`;
  all four files are byte-for-byte identical to the pinned Misaki main-branch
  snapshot. The dataset's later main revision corresponds to an unmerged dev
  dictionary bump and is intentionally not used.
- Recorded the permanent dataset revision and exact SHA-256 for every lexicon
  in `THIRD_PARTY_NOTICES.md`.

This resolves the English runtime lexicon data-specific license blocker for
those exact four inputs.

## 2026-07-10: Deterministic runtime data

- Added byte-for-byte canonical copies of all four English lexicons under the
  pinned `tool/upstream_data/` tree and a manifest recording source revision,
  license, hashes, and entry counts.
- Added an offline deterministic generator that verifies every SHA-256 and
  typed JSON entry before producing a pure-Dart raw-JSON embed. Runtime loading
  is lazy per dialect, immutable, validates the pinned gold inventory, and
  emulates `grow_dictionary` aliases without duplicating approximately 400,000
  entries in memory.
- Exposed frozen inventories by dialect and phoneme version and now validate
  every gold and silver entry against the raw version-2 inventory. The pinned
  American data contains observable `ʔ` in addition to the 45 symbols claimed
  by `EN_PHONES.md`; legacy rendering removes it and replaces `ɾ` with `T`,
  while version 2 preserves the 46-symbol raw data contract.
- Added the exact PaddleSpeech/Misaki `char_convert.py` input and a second
  deterministic generator for the Chinese traditional/simplified scalar map.
  Duplicate mappings preserve upstream's last-write-wins behavior.
- Reproducibility tests run both generators in read-only `--check` mode during
  normal offline Dart tests.
- A package dry run measured a 3 MB compressed archive with the 12 MB English
  runtime source included and canonical generator inputs excluded by
  `.pubignore`. Publish exclusions now also name lock, generated documentation,
  the empty `bin` directory, and Dart/Python cache artifacts explicitly. The
  upstream Python repository is not used as this package's homepage. A live
  pub.dev dry run reached the service and reported only the missing
  owner-supplied repository/homepage URL; that canonical URL remains part of
  the final publish gate.

## 2026-07-10: Oracle and initial pure-pipeline implementation

- Added a standard-library Python exporter that rejects the wrong upstream
  commit/version, serializes all token and dynamic metadata deterministically,
  separates accepted regeneration from read-only verification, captures stable
  failures, and diagnoses the first differing Unicode code point and token.
- Added a locked Python 3.12 American/no-fallback environment and 32 English
  cases covering the README, whitespace, controls, morphology, numbers,
  currency, context, punctuation, Unicode, unknowns, and legacy/2.0 output.
  The truthy constructor sentinel avoids the pinned constructor's unintended
  Hugging Face fallback initialization, and the effective fallback is set to
  `None` before conversion.
- Added the public Japanese pyopenjtalk-style pure pipeline behind an injected
  frontend. It validates all 193 mora mappings and preserves accent, chain,
  punctuation, unknown, metadata, Unicode-scalar pitch lengths, and upstream's
  unusual `phoneme text + pitch trace` result contract. No native adapter is
  claimed.
- Added pure English stress/weight and dialect-sensitive suffix stages, plus
  the first legacy-Chinese tone/punctuation helpers.
- Added the public Hebrew phonemizer boundary and facade. It retains upstream's
  punctuation/stress flags and null token contract, but ships no Mishkal code
  or adapter.

## 2026-07-10: English injected pipeline and pinned provider

- Added the public `EnglishG2pEngine` with narrow typed tokenizer/tagger,
  pronunciation, and fallback contracts. The engine preserves inline-control
  folding, exact subtoken grouping, currency and punctuation state,
  right-to-left context, longest-suffix group search, fallback behavior,
  legacy/2.0 rendering, and available-empty token semantics.
- The tokenizer boundary rejects empty or untagged records, an initial
  continuation, non-half-step stress, out-of-range quality, and any record
  stream that does not reconstruct the exact preprocessed text. Typed backend
  failures therefore surface source deletion or reordering before resolution.
- Added `PinnedEnglishLexicon`, backed lazily by the deterministic American or
  British generated data. It ports contextual and special cases, acronym and
  capitalization behavior, gold/silver ratings, inflection lookup, currency,
  ordinal/year/decimal handling, number flags, NFKC, and Unicode integral
  digit mapping.
- English number spelling is a clean-room implementation derived only from
  observable `num2words==0.5.14` oracle outputs. It covers the pinned scale
  domain through centillion and does not copy or invoke num2words code.
- Replayed the committed spaCy raw-token snapshots through the public engine
  and built-in provider. Both 52-case American and British no-fallback suites
  match exact phoneme output and typed token fields. Each suite combines the
  original 32-case matrix with a separately reviewed 21-case adversarial
  matrix covering number flags, signed/year/large values, currency edges,
  contractions, possessives, suffix branches, homographs, capitalization,
  adjacent/multiword controls, compatibility forms, Python whitespace, mixed
  scripts, combining marks, and symbol clusters. Coverage includes
  legacy/2.0 symbol changes, null/empty distinctions, ratings, controls,
  Unicode, context, morphology, numbers, and currencies. The reviewed British
  corpora differ from their American twins only by mode; the original 154 and
  adversarial 175 captured raw tokens are identical across dialects, while
  dialect processing remains independently observable in final output.
- Added `tool/reference/accepted_fixtures.json` and a single read-only
  `verify_committed.py` gate. It strictly covers every committed JSONL fixture,
  validates repository-contained paths, both record counts, corpus-to-fixture
  identity, and adjacent provenance hashes, dispatches to the exact
  per-language interpreters without a shell, and verifies all 182 accepted
  cases by default without exposing a regeneration or acceptance path.
- Added `EnglishEspeakFallback`, which ports the pinned deterministic eSpeak
  replacement and postprocessing behavior behind a typed raw-phone backend.
  It does not discover, invoke, download, or bundle eSpeak-ng; a real adapter
  and authoritative eSpeak end-to-end fixtures remain separate work.
- Reviewed the two Hugging Face BART fallback repositories named by pinned
  `en.py` at immutable US revision `a5631b285d18d59483c32c0c3379cb9fac924f4b`
  and GB revision `d8357d5067fa26a5c34134d6bbcf4bbf000c0ac8`.
  Their weights are technically checksum-pinnable, but empty model cards and
  absent dataset, lineage, copyright, `LICENSE`, and `NOTICE` evidence fail the
  repository's provenance standard. Model-backed fixtures and adapters remain
  legally blocked; no model files were downloaded.
- Identified the exact transformer tokenizer/tagger artifact as Explosion's
  `en_core_web_trf==3.8.0`, not legacy `spacy-transformers` or the distinct
  `en_core_web_hftrf` package. The 457,421,864-byte official wheel has SHA-256
  `272a31e9d8530d1e075351d30a462d7e80e31da23574f1b274e200f3fff35bf5`.
  A separate Python 3.12 lock now includes the pinned curated-transformer
  closure, and the exporter preflights those three additional distributions
  whenever `trf: true` is selected. Explosion's model metadata and the
  FacebookAI-hosted RoBERTa source resolve the temporary-oracle provenance
  review; authoritative transformer fixtures still require explicit
  provisioning and CPU-platform capture. No transformer artifact was
  downloaded.
- Added American and British 32-case transformer corpora that differ from the
  accepted small-model corpora only by `trf: true`. Their content and dialect
  symmetry are unit-checked, but no golden is accepted without executing the
  explicitly provisioned transformer environment.
- Added a generated pure-Dart NFKC implementation pinned exactly to CPython
  3.12.11's Unicode 15.0.0 database. The accepted canonical table records
  5,857 non-Hangul compatibility decompositions, 922 nonzero combining
  classes, and 941 canonical composition pairs; Hangul is handled
  algorithmically. The same source pins alphabetic, decimal, digit, and
  whitespace properties used by language regular expressions and classifiers.
  Digest tests compare every Unicode scalar, every scalar-property record, and
  21,111 cross-scalar ordering/composition sequences with the Python oracle.
  This replaced and removed the earlier Unicode-8 `unorm_dart` dependency.
This is an experimental injected core, not a declaration that a complete
At this milestone no complete English mode was supported: a real
tokenizer/tagger, spaCy adapter, raw eSpeak-ng provider, model backend adapter,
and real-backend CI job had not yet landed. The later supported small-model
work is recorded below.

## 2026-07-10: Chinese injected frontends and oracle boundaries

- Added separate public engines for pinned legacy/default Chinese and frontend
  version 1.1. The 1.1 outer engine preserves mixed-English splitting,
  configurable unknown/English behavior, and the pinned `tokens == null`
  contract; its internal frontend separately exposes exact tokens.
- Ported the 1.1 POS correction, punctuation/whitespace token handling, Pinyin
  initial/final postprocessing, phone map, erhua exceptions, and rendering on
  top of the ordered pure tone-sandhi stage. All backend capabilities remain
  narrow, typed, explicit, and synchronous.
- Hardened both injected modes against provider records that delete or reorder
  source text, empty/misaligned pinyin arrays, and invalid search segments.
  Added a compiling public-only fixed-record example for both contracts.
- Added independent legacy and frontend-1.1 reference corpora and versioned
  external-stage capture schemas. They snapshot cn2an normalization, jieba
  segmentation/POS/search results, and pypinyin outputs during the actual
  upstream call, with a hard network guard and a locked Python 3.12 dependency
  closure.
- Authoritative Chinese fixtures were not invented while the exact environment
  was unavailable. Until accepted regeneration, read-only verification, and
  typed replay land, both Chinese engines remain experimental injected cores,
  not supported complete modes.
- Exposed immutable source-derived inventories for the distinct renderers. The
  legacy 38-scalar set follows only the first transcription variant selected
  by pinned `ZHG2P`, then applies legacy tones and final U+032F removal; it
  excludes punctuation, whitespace, mixed-script pass-through, and backend
  text. The frontend-1.1 80-scalar set contains every pinned phone-map value,
  including mapped tone digits and structural punctuation/spacing. Unknown
  markers and injected English output remain explicit exclusions. Exact count,
  digest, immutability, and alternate-variant exclusion tests do not constitute
  authoritative fixture parity or change either mode's support status.

## 2026-07-10: Vietnamese injected core and prepared oracle

- Added `misaki_vi.dart`, `VietnameseG2pEngine`, immutable dialect/tone/cleaner
  options, an explicit underthesea-compatible tokenizer contract, and an
  optional explicit English-fallback contract. No backend is discovered,
  downloaded, or bundled.
- Ported the Viphoneme-derived onset/nucleus/glide/coda/tone stages, all north,
  central, and south behaviors, substring/acronym handling, punctuation,
  custom controls, exact joined rendering, and typed parent/onset/nucleus/coda
  metadata. The frozen public inventory contains all 139 pinned `vi_syms`
  entries.
- Ported the reviewed cleaner stages and deterministic licensed dictionaries.
  Canonical inputs are checksum-pinned under `tool/upstream_data/`; three
  generators emit immutable phonology, cleaner-table, and JSON data and pass
  normal-CI reproducibility checks.
- Implemented Vietnamese number spelling independently from black-box output.
  Pinned `num2vi.py` was not copied, translated, imported into production, or
  used as a source template.
- Captured the CPython-version normalization candidate exhaustively under
  CPython 3.11.15. Its Unicode 14 data and Python 3.12's Unicode 15 data have
  identical scalar NFC,
  canonical decompositions, and compositions. Their entire 21,111-sequence
  difference is ten newly assigned combining classes, which
  `normalizePython311Nfc` treats as class-zero starters. The exact Unicode-14
  sequence digest is
  `ffefdbecb7c23fc2e588e042eb5f055ee4809c918c2c63eea52ada4af6369113`.
  The committed exact-3.11.13 comparator remains required before describing
  this as target-runtime proof.
- Replaced every host-Dart lower/upper/strip decision in the Vietnamese
  cleaner, control lookup, currency matching, acronym handling, and substring
  stage with an accepted CPython-3.11.15/Unicode-14 candidate payload. Its
  1,433 lowercase mappings, 1,525 uppercase mappings, Cased,
  Case_Ignorable, and whitespace ranges, multi-scalar expansions,
  supplementary mappings, and context-sensitive Final_Sigma rule are
  deterministic and exhaustively digest-tested across 1,112,064 scalars.
  This is stronger than host-Dart behavior but is not yet evidence of exact
  CPython 3.11.13 parity. A standard-library-only exact-3.11.13 comparator is
  committed and remains unrun until that locked runtime is provisioned.
- Added three reviewed, mode-only 33-case corpora for north, central, and south
  no-English-fallback behavior, including every public option family,
  cleaning, controls, numbers, Unicode, and all ten Unicode-15 CCC deltas. The
  exporter preflights an exact Python 3.11.13/underthesea 6.8.4 closure and
  captures exact cleaned tokenizer input plus ordered raw output. Dart has a
  strict typed parser and synthetic public-engine replay test for that schema.
- The exact Python 3.11.13 environment download was not authorized. No fixture
  output was invented or accepted, and no Vietnamese parity or supported mode
  is claimed. Authoritative regeneration, read-only verification, exact token
  replay, and a real adapter remain required.

## 2026-07-10: Public API and generated-contract documentation

- Enabled the `public_member_api_docs` lint under fatal analyzer infos so every
  Dart library-visible contract is documented continuously.
- Updated all deterministic generators to emit documentation for their
  internal generated constants. Reproducibility checks still compare the
  complete generated bytes and normal library analysis still covers the
  generated sources.
- Exposed the exact 67-symbol modern conjoining-Jamo inventory used by pinned
  Korean `to_syl=false`; preserved punctuation, whitespace, compatibility
  Jamo, and non-Hangul input remain outside that phoneme inventory.
- Added a source-level architecture contract that fails if published library
  code imports I/O, FFI, browser-only, or Flutter libraries, or directly
  prints. This keeps adapter concerns outside the pure package boundary.

## 2026-07-10: External adapter architecture audit

- The existing language backend methods are synchronous. A subprocess cannot
  implement one of those methods while also meeting the required timeout,
  cancellation, bounded-output, and no-shell guarantees: Dart's synchronous
  process API has no timeout. A subprocess-backed integration must therefore
  be a language-specific `AsyncG2pEngine` that starts and can terminate the
  helper, captures bounded typed records, and replays those records through
  the pure pipeline. A blocking synchronous process bridge and a generic
  process-backend abstraction are explicitly rejected.
- Native C-ABI/FFI and pure-Dart providers can implement the current
  synchronous contracts. They belong in optional sibling packages, must take
  explicit library and resource paths, and must validate the native version,
  ABI, model or dictionary identity, platform, and resource checksums before
  conversion. No adapter may discover, download, or silently substitute a
  resource. Platform support remains limited to provisioned real-backend CI
  targets; the pure package remains platform-neutral.
- The first evidence-backed adapter candidate is a Japanese OpenJTalk native
  shim built from the exact sources carried by `pyopenjtalk==0.4.1`, with the
  pinned Open JTalk 1.11 dictionary supplied explicitly. The Cython frontend
  sequence and consumed fields are locally identifiable, and 24 committed
  raw-frontend replay cases already provide an exact comparison target.
- The second candidate is one Korean adapter package containing a native
  MeCab provider plus a deterministic CMUdict 0.7a provider. The native MeCab
  C API can supply the exact surface/POS records, the Korean dictionary and
  CMUdict resources have locally reviewed permissive licenses, and the
  committed 34-case matrix contains 33 successful exact backend replays plus
  the pinned 17-digit failure.
- After authoritative Chinese fixtures are accepted, the preferred Chinese
  provider is a pure-Dart port of only the pinned `cn2an` `an2cn`, jieba
  default/POS/search, and pypinyin/large-pinyin behavior. A different native
  segmenter or pinyin library would define a different mode, not an exact
  adapter. The locked source and resource inputs still require per-data
  license review, deterministic generation, and checksum validation before
  inclusion.
- A raw eSpeak-ng FFI provider is technically feasible against the pinned
  `espeakng-loader==0.2.4` library/data identities, but it does not complete an
  English mode without an exact tokenizer/tagger. It is therefore lower
  priority than adapters that can close an already fixture-backed mode.
- At this review point no exact non-Python spaCy adapter was available. Pinned
  English tokenization and tagging depend on spaCy/Thinc's CPython-bound
  runtime, and the transformer configuration additionally depends on its
  model runtime.
  ONNX conversion, a different tagger, or a Python process would not satisfy
  the compatibility and production-runtime policies.
- At this audit point, a Cutlet adapter remained pending because the full
  modified unidic-py CWJ installed tree and live tagger had not yet passed the
  required content pinning and fixture
  workflow. Exact grouping may use `misaki/data/ja_words.txt` only as an
  explicitly caller-supplied external resource whose pinned SHA-256, byte
  length, record count, and format are validated at initialization. Misakid
  must not bundle, discover, download, or silently substitute the list; the
  inferred Kaikki lineage and applicable data-license obligations remain
  documented in `THIRD_PARTY_NOTICES.md`. The supported 2026-07-11 adapter
  section below records the completed resolution.
- Underthesea 6.8.4's exact 20,914,512-byte wheel and 21,434,162-byte source
  archive are pinned. The implementation is GPLv3 and its word-tokenization
  path depends on `underthesea-core==1.0.4` plus a packaged CRF model whose
  exact lineage/training-data/redistribution terms are not recorded precisely.
  It cannot be copied or linked into this Apache core, and a Python bridge is
  prohibited. The required CPython 3.11 oracle fixtures are also not accepted;
  no heuristic or alternate tokenizer may be advertised as equivalent.
- Mishkal 0.3.2's exact PyPI wheel/source identities are pinned, but the
  release metadata declares no license and the historical package contains
  substantially more material than later rule-only releases. The renamed
  Phonikud repository's current CC BY 4.0 declaration does not establish
  terms for that earlier snapshot. A Python Mishkal process is prohibited;
  a pure-Dart port is blocked until the maintainer identifies the exact
  revision and license, and no authoritative fixture exists yet.

This audit adds no adapter, native library, executable, model, dictionary, or
support claim. It narrows the implementation order and records why the other
boundaries remain explicit experimental contracts.

## 2026-07-10: Native OpenJTalk feasibility proof

- Built a temporary macOS arm64 C ABI shim from the exact
  `pyopenjtalk==0.4.1` source distribution (1,397,999 bytes, SHA-256
  `d5ada46f7fc2b52c1c79c273eb9668ff6ad7ab276a8db9d8be119ef93440f0dc`)
  and the already-provisioned Open JTalk 1.11 dictionary. The resulting
  library links only libc++ and libSystem, not Python.
- The proof executes the identical native frontend sequence used by pinned
  pyopenjtalk: text normalization, MeCab analysis, NJD conversion,
  pronunciation, digit, accent-phrase, accent-type, unvoiced-vowel, and
  long-vowel stages. It then reads all 11 string and three integer NJD fields
  through an opaque C handle.
- Compared every raw frontend word for all 24 committed cases. All 155 records
  and all 14 fields matched exactly, with zero mismatches. The six fields
  consumed by `JapaneseFrontendWord` are therefore available without Python.
- The installed dictionary identity remains exactly nine files,
  107,304,813 bytes, canonical tree SHA-256
  `8b26c37228c9e9b92333e612e1144c958f2788d219e46c8652f698a089be1ccc`.
- The proof is deliberately not copied into the repository or advertised as
  an adapter. Its ABI borrows NJD pointers and native failure paths can print
  to stderr. A production v1 ABI must instead return copied opaque result
  records, bounded structured errors, an immutable source identity, explicit
  lifecycle methods, a process-global lock matching pyopenjtalk, and no native
  printing. Dart must stream-validate the dictionary before construction and
  enforce a configurable input-byte limit on both sides.
- Open JTalk exposes no safe cancellation hook. A synchronous FFI backend can
  document and bound that limitation but cannot promise an enforceable
  timeout. Applications requiring cancellation need a separate
  language-specific asynchronous helper-process engine.
- A support claim broader than macOS arm64 remains gated on provisioned
  Linux, Intel-macOS, and Windows builds and CI. The first adapter may declare
  the proved macOS arm64 resource tuple precisely once its production ABI,
  source manifest, notices, and real Dart tests satisfy the remaining gates.

## 2026-07-10: Native Korean backend feasibility proof

- Inspected the exact native resources used by the accepted Korean oracle.
  The installed MeCab library reports `0.996/ko-0.9.2`; its macOS arm64
  binary is 523,296 bytes with SHA-256
  `883de49e4f674f2f69d52e0ba30b7a615ddcadd6082fbf193f764f364110ce3f`.
  The Korean system dictionary reports UTF-8, binary version 102, 816,283
  entries, left size 3,822, and right size 2,693.
- Called the MeCab C ABI directly for all 34 fixture morphology inputs using
  explicit `--rcfile` and `--dicdir` arguments. Iterating normal/unknown nodes,
  decoding each surface by pointer plus byte length, and selecting field zero
  from the required eight-column feature record reproduced every captured
  morphology stream with zero mismatches.
- Parsed the exact extracted CMUdict 0.7a data file (3,820,830 bytes, SHA-256
  `cad209c39eb87677d64e93d97f8eed10b7e6f9bdd42de8e7ca8efc8e17d62e8a`)
  in file order, retaining the first pronunciation per lowercase key. The
  133,737 records produced 123,455 keys and reproduced all 23 ordered
  fixture lookups, including the miss, with zero mismatches.
- This proves the native/provider data boundary, not a Dart adapter. A sibling
  package must generate bindings from the pinned MeCab header, stream-validate
  the library/dictionary/CMU data at construction, use explicit lifecycle and
  native finalization, preserve bounded `mecab_strerror` diagnostics, and run
  the existing 34-case matrix through the real Dart adapter.
- The only provisioned library is a macOS arm64 binary bundled inside the
  `python-mecab-ko` wheel. Although the distribution is BSD-3-Clause and the
  dictionary package is Apache-2.0, the dylib's exact native source revision
  and component notice are not independently pinned. It must not be bundled;
  an explicit-path adapter can be developed once real macOS/Linux/Windows
  builds and CI resources are provisioned.

## 2026-07-10: Offline English and Japanese edge-parity audit

- Restored the `num2words==0.5.14` float-remainder correction used by pinned
  English decimal pronunciation. Scaled binary remainders within `0.01` of an
  integer are rounded before the usual floor, so values such as `0.29`,
  `2.675`, and `10.01` no longer lose one in the last spoken digit. A seeded
  5,000-case differential against the exact oracle produced zero mismatches;
  separate 30,000-case cardinal, ordinal, and year and 10,000-case integrated
  numeric-lexicon differentials also produced zero mismatches.
- English pronunciation and fallback backend results now reject ratings
  outside the upstream `1..5` metadata domain with backend-identified typed
  failures, matching the existing tokenizer boundary validation.
- Restored pinned `ConvertKanji` fractional dictionary concatenation. Unit
  symbols after `点` expand literally (`一点十` becomes `1.10`) and repeated
  `点` characters remain additional decimal points. A 60,000-case seeded
  forward/reverse differential, including arbitrary unit and repeated-point
  tails, produced zero mismatches.
- Cutlet normalization and morphology validation now preserve the distinction
  between Python `re \d` (decimal scalars) and `str.isdigit`. Isolated
  non-decimal digits follow upstream into number conversion and fail with the
  package's typed validation error instead of being silently discarded.

These fixes change no accepted fixture. English and Cutlet retain their
documented real-backend and provenance gates.

## 2026-07-10: Supported Japanese Open JTalk adapter

- Added `packages/misakid_openjtalk` as a Pub workspace member while keeping
  the root library free of `dart:io` and `dart:ffi`. It depends only on the
  pure-Dart `crypto` package and the hosted `misakid` version constraint; the
  small FFI surface uses native ABI-owned input buffers instead of
  `package:ffi`. The reviewed `crypto` 3.0.7 release is used only for streaming
  SHA-256, carries a BSD-3-Clause-style license, and has one small
  `typed_data` dependency.
- The caller explicitly supplies absolute native-library and dictionary
  paths. `open` first restricts the configuration to macOS arm64, validates
  the numeric ABI and seven immutable source/resource identities, streams all
  nine dictionary files through exact size and SHA-256 checks, verifies the
  107,304,813-byte tree digest, rejects links/extra entries, and re-stats the
  files after native initialization. Nothing is searched, downloaded, or
  installed.
- The offline build tool accepts an explicitly extracted
  `pyopenjtalk-0.4.1` source directory. It verifies the exact 139-file,
  5,381,473-byte Open JTalk subtree with canonical relative-path SHA-256
  `dea0f240fad8dc8b9ea1984920a4d64a48227a40c2924a3c545eaeca50357857`
  plus the three source licenses, stages only manifest files, generates
  `config.h` outside the source, and compiles only MeCab plus the frontend
  normalization/NJD stages. HTS, voices, audio, `jpcommon`, and
  `njd2jpcommon` are excluded. CMake independently accepts only the complete
  139-file, 5,382,103-byte post-patch tree and installs the library, header,
  manifest, and redistribution notices to a generator-independent directory.
- ABI v1 owns one context and a separate immutable snapshot per analysis.
  Each snapshot copies all 11 string and three integer NJD fields into bounded
  storage before unlocking. Explicit result/context destruction, idempotent
  Dart `close`, a `NativeFinalizer` leak fallback, exception-safe frontend
  refresh, C++ exception containment, fixed structured diagnostics,
  input/result limits, strict UTF-8 checks, and a process-global native mutex
  replace the proof's borrowed pointers and unstructured status values.
  Inherited Open JTalk/MeCab C allocation sites are not all null-checked, so
  extreme process-wide out-of-memory recovery is not promised as typed status
  8; hard fault isolation requires a supervised process.
- The reviewed `misakid-openjtalk-safety-v1` overlay replaces the two
  reachable-or-latent upstream `exit(1)` paths with bounded native diagnostics
  and redirects direct C stdio diagnostics away from the host process. These
  are explicit safety divergences only for paths that previously terminated
  the process. Embedded NUL is also rejected instead of preserving upstream's
  silent C-string truncation; unpaired UTF-16 is rejected as in Python.
  Native results are capped at 65,536 words, 1 MiB per field, and 64 MiB of
  aggregate string data. The MeCab count is rejected before NJD construction
  and checked again after transforms. The dynamic `3 * inputBytes + 1`
  normalization buffer avoids pyopenjtalk 0.4.1's fixed 8,192-byte buffer
  hazard; exact parity is not claimed beyond that upstream-safe input domain.
- A clean local CMake build produced a 1,246,680-byte arm64 dylib with an
  `@rpath` install name, macOS 11.0 minimum, only libc++/libSystem dependencies,
  and exactly 23 exported ABI symbols. Compiler prefix mapping removed the
  caller's absolute source/build paths; clean builds in two distinct output
  directories were byte-identical with local SHA-256
  `1196e431274ba673611427b905c17e13a0d5b0e663937051cbd7e5a11b80f996`.
  The binary itself is not committed and its toolchain-specific hash is not a
  compatibility identity.
- The production adapter—not the temporary proof—matches all 24 committed
  frontend inputs, all 155 raw records and 14 fields, all 23 successful final
  phoneme strings and every typed token/metadata field, plus the pinned
  whitespace failure. It also passes direct C-ABI ownership across a later
  analysis, early excessive-word rejection, exact byte-limit boundaries,
  malformed scalar/NUL handling, repeated close/use-after-close, four
  concurrent isolates, and byte-empty stdout/stderr for valid analysis and an
  invalid native dictionary load.
- Complete exact notices are committed under the adapter's `native/licenses`
  directory. A release-tag/workflow-dispatch job targets an explicitly
  provisioned self-hosted macOS arm64 runner and verifies two byte-identical
  clean builds, exports, install name, deployment target, dependencies,
  absence of caller paths/termination symbols, installed notices, and exact
  native parity. Normal Linux/macOS/Windows core CI remains offline and
  resource-free.
- The supported tuple is precise: Misaki 0.9.4 pyopenjtalk behavior,
  pyopenjtalk 0.4.1/Open JTalk 1.11 sources, the exact Open JTalk 1.11
  dictionary, macOS 11+ arm64, and explicit resource paths. Linux, Windows,
  Intel macOS, embedded NUL, runtime cancellation, bundled resources, and
  automatic discovery/download remain unsupported. Cutlet is a distinct
  contract supplied by the sibling adapter recorded below.

## 2026-07-10: Supported Korean MeCab-ko and CMUdict adapter

- Added `packages/misakid_mecab_ko` as a second Pub workspace adapter while
  keeping the root library free of `dart:io` and `dart:ffi`. The native FFI
  boundary uses ABI-owned buffers directly, and the CMUdict provider is pure
  Dart after its asynchronous file validation. Runtime dependencies remain
  the root package and reviewed pure-Dart `crypto` 3.0.7.
- The offline builder accepts only the official
  `mecab-0.996-ko-0.9.2.tar.gz` release (1,414,979 bytes, SHA-256
  `d0e0f696fc33c2183307d4eb87ec3b17845f90b81bf843bd0981e574ee3c38cb`,
  tag commit `908db8de3cb5f4931b4e3a7a5a3894daefb98c37`). It validates the clean
  236-file, 7,840,684-byte tree and all license identities before staging.
  CMake independently accepts only the complete 236-file, 7,840,991-byte
  safety-overlay tree with digest
  `f12784924ac4a55296520308472d55e433a50e708f338fd52a9106ece5997691`.
- `misakid-mecab-ko-safety-v1` changes the upstream `CHECK_DIE` failure path
  from `std::cerr` plus `exit(-1)` to a catchable `runtime_error`. The new C
  boundary contains every C++ exception, returns fixed-capacity diagnostics
  without user text or configured paths, and produces no process stdout or
  stderr on either a valid analysis or invalid dictionary initialization.
  Valid morphology behavior is unchanged.
- ABI v1 passes fixed argv entries for `/dev/null` rcfile and the explicit
  dictionary directory, so no shell, `$HOME`, `MECABRC`, discovery, or
  interpolation participates. It validates the loaded dictionary as UTF-8,
  format 102, 816,283 entries, left size 3,822, and right size 2,693. A
  process-global mutex serializes create/analyze/destroy across isolates.
  Results own copied surface/tag pairs across later calls.
- Dart first rejects links and streams every file of the exact
  `python-mecab-ko-dic==2.1.1.post2` tree: 11 files, 112,191,702 bytes,
  SHA-256
  `d851fab8708745442ac3a2d970851dbd0ef598e786a363f406847461d77a6f51`.
  It re-stats the tree after native initialization. The separate CMU provider
  requires the exact 3,820,830-byte CMUdict file, validates its SHA-256 plus
  133,737 records and 123,455 keys, and preserves the first pronunciation per
  lowercase key.
- The production adapter matches all 34 committed morphology streams and all
  293 surface/tag records, all 23 ordered CMUdict lookups (22 hits and one
  miss), all 33 successful final phoneme outputs, null token semantics, and
  the pinned 17-digit typed failure. It also passes close/use-after-close,
  strict scalar/NUL and byte limits, copied ownership, four concurrent
  isolates, resource corruption/symlink checks, and no-stdio subprocess tests.
- Two independent clean builds produced byte-identical 217,384-byte arm64
  dylibs with local SHA-256
  `30794f21cc6c7be98cbe84f669c867bfe6947c87cf611152d306caa9ef32b8cd`.
  The library has an `@rpath` name, macOS 11 minimum, only system
  libiconv/libc++/libSystem dependencies, exactly the reviewed ABI exports,
  no build/source paths, and no `_exit` or `_abort` import. The binary is not
  committed and its toolchain-specific hash is not an ABI identity.
- The intentional input safety divergence rejects embedded NUL instead of
  risking native truncation. Inputs are capped at a configured 1..64 MiB;
  results at 65,536 tokens, 1 MiB per field, and 64 MiB aggregate. MeCab has
  no safe cancellation hook, and inherited unchecked extreme allocation
  sites mean hard fault isolation still requires a supervised process.
- Complete MeCab-ko BSD, dictionary Apache-2.0, and CMUdict notices are
  committed under the adapter's `native/licenses/`. No native binary,
  dictionary, CMUdict data, Python runtime, or downloader is distributed.
- The supported tuple is precise: pinned Misaki 0.9.4 g2pkc-default,
  MeCab-ko 0.996/ko-0.9.2, the exact 2.1.1.post2 dictionary, CMUdict 0.7a,
  macOS 11+ arm64, and explicit resource paths. Linux, Windows, Intel macOS,
  embedded NUL, cancellation, bundled resources, and discovery remain
  unsupported.

## 2026-07-11: Supported pure-Dart Chinese legacy backend

- Accepted the 24-case `zh/legacy` fixture byte-for-byte from pinned Misaki
  0.9.4. Its SHA-256 is
  `30a1f8988aa19cc68cbba5bd9e256159e23e2c9be87fd19a6a990a1141c49096`;
  it contains 22 exact successes and the two original transcription failures
  for unknown Basic-CJK U+9FFF. The read-only aggregate verifier now executes
  206 cases across eight fixture files.
- Added the `misakid_chinese` sibling package. `Cn2AnNormalizer` ports only
  cn2an 0.5.23's ordered `an2cn` sentence transform. A 44,000-case seeded
  differential had zero mismatches, and focused oracle cases preserve
  CPython 3.12.11's 4,300-decimal-digit `int()` boundary before leading-zero
  removal.
- Added `JiebaSegmenter`, a pure-Dart port of Jieba 0.42.1 accurate mode with
  HMM. Callers explicitly provide the exact default dictionary and three
  finalseg probability files. The loader validates file type, byte length,
  SHA-256, record/prefix/frequency/model counts, strict UTF-8, and stable file
  snapshots. Its protocol-0 parser accepts only the inert dictionary,
  string/Unicode, finite-float, memo, and set-item subset present in the
  pinned resources; executable pickle globals/reducers/objects and trailing
  data are rejected.
- Added `PypinyinTone3Provider`, which validates the exact pypinyin 0.53.0
  character and phrase JSONs and implements the legacy call's Han grouping,
  strict maximum-matching phrase segmentation, first-pronunciation behavior,
  complete tone-mark conversion, unknown fallback, and neutral-tone `5`.
  It matches all 60 unique captured calls; an independent audit covered all
  41,651 character records, all 47,098 phrases, and 20,000 randomized phrase
  concatenations without a discrepancy.
- `PureDartChineseLegacyBackend` composes those three stages behind the
  existing core contract. Fully provisioned tests match all 22 final phoneme
  strings, null tokens, two failures, 22 normalizations, 41 segmentation runs,
  82 segmented words/pinyin calls, and 152 pinyin syllables. A separate live
  subprocess test reproduces the 41 runs with the installed original Jieba
  0.42.1; Python is not used by production code.
- The package bundles no dictionaries and performs no discovery or download.
  Exact source commits, six resource identities, source-data lineage, and the
  complete MIT notices for cn2an, Jieba, pypinyin, pinyin-data, and
  phrase-pinyin-data are recorded beside the adapter. Initialization uses
  `dart:io`; conversion is synchronous and pure Dart after loading. Basic-CJK
  runs and pypinyin words are bounded at 65,536 scalars.
- The support claim is limited to pinned legacy/default behavior with these
  explicit resources on Dart VM platforms. Chinese frontend 1.1 remains a
  separate experimental contract because its Jieba POS/search and
  large-pinyin overlay are not yet implemented or fixture-accepted.

## 2026-07-11: Supported pure-Dart Chinese frontend 1.1

- Added `PureDartChineseFrontend11Backend` to `misakid_chinese`. It composes
  the existing cn2an implementation with exact Jieba 0.42.1 POS/search and
  pypinyin 0.53.0 initial/final behavior plus pypinyin-dict 0.9.0's large
  phrase overlay. Conversion is synchronous and entirely Dart after explicit
  asynchronous resource loading; no Python or native runtime is used.
- The profile validates eleven caller-supplied regular non-link files: the
  four legacy Jieba resources, four POS HMM protocol-0 tables, both pypinyin
  JSON dictionaries, and the exact 9,140,316-byte `large_pinyin.txt`. Exact
  commits, lengths, hashes, record counts, parsable opcode subsets, and MIT
  notices are recorded in the sibling package resource manifest.
- Provisioned parity matches all 26 accepted frontend-1.1 outputs and null
  outer-token results, 24 cn2an calls, 25 POS runs with 131 records, 365
  pinyin calls with 746 returned values, and 107 search calls with 164
  segments. Direct live Jieba comparison and malformed/tampered-resource
  contract tests pass as part of the 36-test provisioned package suite.
- The precise supported configuration is pinned Misaki frontend 1.1 on Dart
  VM platforms with those eleven explicit resources and no English callback.
  In that configuration each mixed ASCII segment renders the configured
  unknown marker. The callback boundary remains public but no combined
  Chinese+English support claim is made until an equivalent English engine
  and combined authoritative fixture exist. The root core remains
  platform-neutral; the sibling loader's `dart:io` dependency excludes web.

## 2026-07-11: Supported Japanese Cutlet adapter

- Accepted the 27-case `ja/cutlet` fixture from pinned Misaki 0.9.4 with
  SHA-256
  `c599ac58455263a9c9e100f175e9eaa07d1b9e77194a075dea6d02d3a1627a48`.
  It contains 26 exact outputs, null token lists, and the original long-number
  failure. Its typed backend input records the normalized text, all 126 raw
  fugashi nodes, nullable `pronunciation` and `kana`, selected hiragana, raw
  character type, unknown status, and all 12 longest-match joins. Direct
  read-only regeneration verifies 27/27 and raw pronunciation/kana 126/126.
- Fixed the observable Python substring-membership quirk in Cutlet punctuation
  spacing: an empty romanization is contained in both punctuation strings.
  The dedicated `あ」？い` regression now preserves the original `a ? i`
  output instead of applying set-membership semantics.
- Added `packages/misakid_mecab_ja` without adding I/O or FFI to the root
  package. Its offline builder accepts only the 1,397,999-byte
  `pyopenjtalk-0.4.1` source distribution, validates the complete 139-file
  Open JTalk source subtree and license identities, stages it outside the
  package, and compiles only the standard 16-file MeCab 0.996 runtime plus an
  Apache-2.0 owned-result shim. No Open JTalk frontend, HTS, voice, model,
  dictionary, word list, or binary is bundled.
- Dart streams and validates every file in the exact modified unidic-py CWJ
  tree: 20 files, 811,662,881 bytes, tree SHA-256
  `95bd65fa96955b644c15510932ca8439f463ac8b66f57bac6dfee5e29fa03115`.
  Native initialization independently checks one UTF-8 system dictionary,
  878,989 entries, and binary version 102. The dictionary is re-statted after
  opening to detect a validation/open race.
- `PinnedMisakiCutletWordMembership` requires an explicit regular file with
  SHA-256
  `a93a8e8aee24db307a32becb8bf01c4c2908ecf37e6c91f7a705fafdfeba67ff`,
  1,921,140 bytes, 147,571 unique scalar-sorted records, and no terminal LF.
  The file is not copied, generated from, discovered, downloaded, or
  redistributed. Its authoritative Misaki identity, inferred 99.4348%
  Kaikki/Wiktextract overlap, and conservative license guidance are recorded
  separately from the code licenses.
- ABI v1 owns copied surface/pronunciation/kana/type/unknown records and
  serializes MeCab create/analyze/destroy with a process-global mutex. It
  validates UTF-8 and NUL, contains C++ exceptions, bounds input at a
  configurable 1..64 MiB, words at 65,536, individual fields at 1 MiB,
  aggregate result bytes at 64 MiB, and diagnostics at 1 KiB. Dart provides
  idempotent close and a native-finalizer fallback.
- Two independent clean builds produced a byte-identical 216,344-byte arm64
  dylib with local SHA-256
  `1cc80def78742f8b7614750ed6268f0407886ea414fa3cc99a8f5e90263793ba`.
  The library has an `@rpath` install name, macOS 11 minimum, only system
  iconv/libc++/libSystem dependencies, exactly 23 reviewed ABI exports, no
  caller source/build paths, and no `_exit` or `_abort` import. This local
  binary hash is a reproducibility observation, not a runtime compatibility
  identity, and no binary is committed.
- Provisioned tests match all 27 cases, every raw field, every derived reading
  and grouping decision, every output/failure, and null-token semantics. They
  also cover copied ownership across later calls, byte limits, malformed
  scalar/NUL handling, repeated close/use-after-close, four concurrent
  isolates, exact resource identity/tampering, and byte-empty stdout/stderr on
  valid analysis, invalid dictionary initialization, and malformed native
  UTF-8. The aggregate oracle now verifies 259 cases across ten fixture files.
- Complete pyopenjtalk MIT, MeCab BSD, UniDic BSD-option, jaconv MIT, and
  Cutlet MIT notices are committed beside the adapter. A provisioned
  release/manual workflow rebuilds twice, checks binary reproducibility,
  exports, deployment target, dependencies, paths, notices, and exact native
  parity; normal CI remains resource-free.
- The supported tuple is precise: Misaki 0.9.4 Cutlet behavior, MeCab 0.996
  from pyopenjtalk 0.4.1, the exact modified unidic-py CWJ tree, the exact
  explicit external `ja_words.txt`, macOS 11+ arm64, and explicit resource
  paths.
  Linux, Windows, Intel macOS, embedded NUL, cancellation, bundled resources,
  discovery, and download remain unsupported.

## 2026-07-11: English eSpeak fallback parity

- Provisioned the exact Python 3.12 eSpeak oracle closure from
  `requirements-en-espeak-py312.txt` and ran it with network access rejected
  during upstream construction and conversion. The environment records
  spaCy 3.8.4, `en_core_web_sm` 3.8.0, num2words 0.5.14,
  phonemizer-fork 3.3.2, and espeakng-loader 0.2.4.
- Accepted separate 20-case American and British eSpeak-fallback fixtures.
  Each captures 43 original spaCy tokens and 29 ordered raw eSpeak calls; the
  matrices cover empty/known input, individual and grouped OOVs, punctuation,
  capitalization, possessives, hyphens, composed/decomposed accents,
  compatibility forms, supplementary scalars, dialect phone differences,
  legacy/2.0 behavior, disabled preprocessing, and a custom unknown marker.
- Pinned the executed eSpeak-ng 1.52.0 library at 504,168 bytes and SHA-256
  `bb635eee1ee9c456f4a5cf06fb6cb352ecdd4d61e1951743b423ef22bb57f470`,
  and the 364-file, 18,373,365-byte data tree at canonical SHA-256
  `730e20a0d06976b23b8344bac21dab6e1da447d0e16906bab6a0b54db89dd6e2`.
  Those GPL oracle resources are not redistributed.
- Replayed all 40 cases through the public `EnglishG2pEngine`,
  `PinnedEnglishLexicon`, and `EnglishEspeakFallback`. Exact output, token
  fields, call ordering, raw call exhaustion, dialect selection, and both
  phoneme versions pass. The accepted aggregate is now 299 cases across 12
  fixture files.
- This fixture milestone proved the deterministic Dart eSpeak branch before
  production adapters landed. The later supported small-model work below adds
  the exact tokenizer/tagger and raw eSpeak providers. Transformer parity
  remains unprovisioned and BART remains blocked by its separately documented
  provenance gap.

## 2026-07-11: Supported English small-model and eSpeak adapters

- Added `misakid_spacy_en`, a pure-Dart implementation of the exact spaCy
  3.8.4 tokenizer and Thinc 8.3.4 `en_core_web_sm==3.8.0` tok2vec/tagger path.
  It reads only four caller-supplied resources after exact size/SHA-256
  validation and performs no Python, native, process, discovery, download, or
  network operation.
- Captured CPython 3.12.11 lower/space/word/scalar-property behavior in a
  canonical generated artifact with deterministic extractor, generator,
  decoded digest, and manifest-integrity tests. The production package uses
  generated Dart tables and requires neither Python nor the canonical JSON.
- The provisioned small-model suite matches 146 accepted streams, all 744 raw
  tokens and tags, typed metadata, inline controls, and final American/British
  legacy/2.0 output. Direct tokenizer and model-intermediate tests cover the
  exact loaded parameters and reject changed resources.
- Added `misakid_espeak_en`, an explicit macOS 11+ arm64 adapter for the exact
  eSpeak NG 1.52.0 library/data tuple. Its package-owned Apache-2.0 C++ shim
  owns all returned data, serializes process-global state, validates resources
  and ABI identity, and neither links nor redistributes eSpeak.
- The composed production test uses the real pure-Dart spaCy adapter, real
  eSpeak adapter, and pinned lexicon. All 40 accepted fallback cases, every
  output/token field, and all 58 ordered raw calls match exactly. Native
  ownership, isolate locking, lifecycle, bounds, tampering, ABI/export,
  reproducibility, deployment-target, dependency, and no-stdio checks pass.
- Supported eSpeak calls are bounded by configured UTF-8 input/output limits,
  65,536 punctuation-preserved chunks, and 65,536 eSpeak callback chunks per
  direct native conversion. Exceeding a bound is an explicit typed failure,
  not partial output. Conversion has no cancellation hook; callers needing a
  hard timeout must isolate it in a supervised process.
- The supported configurations are American and British small-model modes,
  both legacy and 2.0 rendering, without fallback on Dart VM and with eSpeak
  fallback on the exact macOS-arm64 tuple. Transformer and BART modes remain
  unsupported, as does Chinese frontend-1.1 with an injected English callback
  until a combined authoritative fixture is accepted.

## 2026-07-11: Supported Chinese plus English callback profile

- Accepted the 14-case
  `zh/frontend-1.1-en-small-no-fallback` fixture with SHA-256
  `b5f6b39b489dc023a39ccb42f35cd5030acecb3426d474f9556ff876cceb7599`;
  its authoritative corpus SHA-256 is
  `e2d91145b5c2411e375af6c66755c98e16beebd74dfd9f381e78ec22bb4ee3f3`.
  The matrix covers American/British and legacy/2.0 English rendering,
  English-only and multiple mixed segments, punctuation/C++ splitting,
  apostrophes, hyphens, context, default/custom OOV markers, full-width and
  cn2an boundaries, whitespace-only input, and empty input.
- Added a distinct `zh-en` aggregate-oracle interpreter family using the
  canonical `requirements-zh-en-callback-py312.txt` lock. The separate local
  CPython 3.12.11 environment was built offline from the accepted English
  closure, then the six Chinese-exclusive pure-Python distributions were
  copied from the accepted Chinese environment only after every source and
  destination RECORD hash/size passed. Native/shared payloads and links are
  rejected; `pip check` reports all 63 installed packages compatible.
- The schema-2 combined backend input retains the complete Chinese frontend
  capture and all 14 ordered English callback inputs, phonemes, final tokens,
  and nested preprocess/raw-token streams. It contains 40 raw tokenizer
  records and 33 final English tokens. The exporter rejects callback type,
  grammar, order/count, result-shape, and tokenizer-call-count drift.
- Added `ChineseFrontend11EnglishG2pEngine`, composing the exact pure-Dart
  Chinese frontend backend with the pure-Dart `en_core_web_sm==3.8.0`
  tokenizer/tagger, pinned lexicons, preprocessing enabled, and no fallback.
  Provisioned parity matches every callback record and exact outer output;
  outer tokens remain `null`. The precise American/British legacy/2.0 matrix
  is supported on Dart VM platforms with all fifteen explicit checksum-pinned
  Chinese and English resource files. Other tokenizers or fallback policies
  remain unsupported.
- The accepted read-only aggregate is now 431 cases across 17 fixture files.
  The `en-trf`, `en-trf-espeak`, and `zh-en` manifest keys plus their dedicated
  CLI/environment options prevent replay under a resource-incompatible
  small-model, transformer-only, or Chinese-only interpreter.

## 2026-07-11: Python-free published runtime boundary

- The production libraries and supported adapters invoke no Python runtime.
  Repository development uses Python for the executable fixture oracle,
  read-only parity verification, and deterministic generated-data checks.
- Updated the root library boundary to exclude root `/test` and `/tool`.
  Published runtime code therefore contains no Python oracle scripts, fixture
  tests, virtual environments, or model resources. Runtime-generated Dart
  tables, provenance/notices, and sibling adapters' required Dart/native build
  sources and manifests remain in their publishable package trees.

## 2026-07-11: English transformer artifact preflight

- Added a strict development-time specification for the exact
  `en_core_web_trf==3.8.0` wheel, pinned upstream source/lock identities,
  Python 3.12 runtime delta, prepared American/British corpora, and the six
  required model-member suffixes.
- Added a bounded streaming wheel auditor. It verifies the 457,421,864-byte
  whole-file identity before reading members, rejects unsafe paths, links,
  special entries, encryption, unsupported compression, duplicate/case-
  colliding names, expansion bombs, wrong package roots, malformed metadata,
  and missing or duplicate required resources. It emits a deterministic
  inventory only through explicit `--accept` or compares one through
  `--check`; it never installs, imports, executes, extracts, or downloads the
  wheel.
- Downloaded the exact wheel as an explicit temporary development input and
  verified its 457,421,864-byte identity and SHA-256 before reading it. The
  deterministic accepted inventory has SHA-256
  `4e3cae8256e9e701739cdbd720ffe5f3047202e4a0ebace4bc469a33b1ae7eba`
  and covers all 33 members (500,728,746 uncompressed bytes), including the
  497,343,046-byte transformer model and 151,450-byte tagger model.
- Fixed model-root discovery after the real wheel exposed two legitimate
  `meta.json` members: the auditor now intersects suffix roots and selects the
  single complete expected package root while still rejecting absent or
  multiple complete roots. The regression fixture mirrors that wheel layout.
- No model payload is committed or published. The initial American/British
  no-fallback acceptance captured 64 cases and 308 raw records; the boundary
  extension below brings that matrix to 76 cases and 2,192 records. Exact
  final outputs and typed tokens use a distinct locked `en-trf` oracle. At
  this preflight milestone replay through the deterministic Dart English
  stages passed exactly while a Dart/native transformer tokenizer/tagger
  runtime was still unimplemented. The accepted
  inventory and implementation manifest prevent that work from being based on
  a guessed architecture or on MisakiSwift's behavior-divergent Apple
  `NLTagger` path.
- Added separate American/British transformer-plus-eSpeak fixtures: 40 cases,
  86 raw transformer token/tag records, 50 ordered raw eSpeak calls, and 78
  final tokens. Their exact resource closure is routed through the dedicated
  `en-trf-espeak` interpreter; the eSpeak lock now explicitly includes the
  upstream `joblib==1.4.2` transitive dependency. These fixtures extend oracle
  evidence but do not claim a transformer runtime.
- Extended each no-fallback transformer corpus from 32 to 38 cases with exact
  marked-piece boundaries at 104, 105, 144, 145, 208, and 249. The 145-piece
  case places a two-piece emoji entirely in the overlap; omitting only overlap
  averaging changes its observable tag from `UH` to `NFP`. The two fixtures
  now contain 76 cases and 2,192 raw transformer records before the separate
  eSpeak matrix is counted.

## 2026-07-11: Exact English lowercase tag weighting

- A full scalar audit found 411 differences between the host Dart SDK and
  CPython 3.12.11 lowercase mappings. The difference is observable when
  upstream merges controlled subtokens: `[a Ꭰ](/p/)` must select the Cherokee
  token's `NNP` tag, while host lowercasing produced a tie and retained `DT`.
- Promoted the already accepted CPython 3.12/Unicode 15 lowercase mappings and
  final-sigma context into the shared pure-Dart core through the deterministic
  Unicode generator. English tag weighting, retokenization checks, and lexical
  lowercase decisions now use that host-independent function.
- Added the exact case to both American and British adversarial corpora. The
  pinned Python fixtures prove the raw `a/DT` plus `Ꭰ/NNP` stream and final
  merged `NNP` token; unit, generated-data, and end-to-end replay tests cover
  the regression without Python at runtime.

## 2026-07-11: Experimental pure-Dart English BART architecture

- Added `packages/misakid_bart_en`, a Dart-VM-only implementation of the
  one-encoder-layer/one-decoder-layer F32 BART graph used by pinned
  `FallbackNetwork`. It implements the public `EnglishFallbackBackend`
  contract, returns upstream rating 1, maps missing grapheme scalars to ID 3,
  uses decoder start ID 1 and default maximum length 20, skips output IDs
  `0..3`, and enforces forced EOS ID 2 at the configured limit.
- Resources are never bundled, discovered, or downloaded. Callers supply
  absolute JSON and safetensors paths plus exact byte sizes and SHA-256
  identities. Configuration, strict duplicate-key JSON, all 50 tensor names
  and shapes, F32 values, contiguous offsets, scalar input, model dimensions,
  file reads, and generation are bounded. The accepted architecture limits
  input to 62 Unicode scalars, model files to 16 MiB, 64 positions, 128 hidden
  dimensions, 8 heads, 1024 feed-forward dimensions, and 256 vocabulary IDs.
- A deterministic license-clean synthetic model is generated independently of
  third-party weights. Its expected encoder states, complete causal decoder
  logits at lengths 1 through 4, four generation inputs (including unknown ID
  3 and empty input), and a separate early-EOS model come from CPU
  `BartForConditionalGeneration` under the exact CPython 3.12.11,
  Torch 2.6.0, Transformers 4.51.3, safetensors 0.5.3, Darwin-arm64 SDPA tuple.
  The generator defaults to a read-only byte check; explicit acceptance prints
  semantic text diffs and binary identity summaries before replacement.
- This proves the narrow runtime graph and safe explicit-resource boundary,
  not the named upstream model. The PeterReid US/GB weights remain unaccepted
  because their training data, lineage, license-file, copyright, and notice
  provenance are insufficient. No model-backed Misaki parity fixture or
  support claim is derived from the synthetic graph.
- Cross-platform CI now formats, analyzes, documents, and tests the package on
  Linux, macOS, and Windows. Direct publish validation contains production Dart
  source only; tests, Python tooling, synthetic models, caches, and generated
  documentation are excluded.

## 2026-07-11: Workspace publish-boundary correction

- Pub applies an ancestor `.pubignore` to workspace members. The former root
  `/packages/` rule therefore produced empty archives for every sibling even
  though their own package-local rules were correct. Removing that ancestor
  exclusion restores direct per-package publish validation.
- The root archive now contains the sibling packages' publishable source and
  notices. Each nested `.pubignore` still excludes tests, Python tooling,
  caches, generated docs, model fixtures, staged sources, and native binaries.
  Root and affected child dry runs pass; the root archive remains Python-free.

## 2026-07-11: Supported English transformer adapter

- Added `misakid_spacy_trf_en` for the exact
  `en_core_web_trf==3.8.0` tokenizer/tagger tuple on macOS 11+ arm64.
  Tokenization, `regex==2024.11.6` byte-BPE splitting/merging, alignment,
  resource validation, and tag assembly are Dart. A package-owned Apache-2.0
  C++17 dylib evaluates the reviewed RoBERTa-base 12x768 graph and 49-label
  tagger with Apple Accelerate. Conversion invokes no Python, spaCy, Torch,
  subprocess, discovery, download, or network.
- The caller explicitly supplies the canonical extracted model directory and
  package-built dylib. Dart streams and validates the exact 497,343,046-byte
  transformer model plus tokenizer, lookup, and tagger resources. Native code
  independently checks the whole model and all 149 little-endian F32 tensor
  ranges before copying 496,220,160 tensor bytes into aligned immutable
  storage. Contexts for one canonical model share that allocation.
- The public backend matches all 116 accepted American/British transformer
  cases, all 2,278 raw token/tag records, final phonemes and metadata, and all
  50 replayed fallback calls across legacy/2.0 rendering. The matrix includes
  exact 104/105/144/145/208/249-piece boundaries and an overlap-sensitive
  emoji tag. A second provisioned suite composes the real transformer and real
  eSpeak adapters for all 40 fallback cases, 86 raw transformer tokens, and
  50 exact native eSpeak calls.
- Native malformed-input, ownership, lifecycle, ABI identity, export,
  dependency, install-name, macOS deployment-target, path-leakage, and notice
  checks pass. Two clean builds produced byte-identical 113,552-byte arm64
  dylibs with local SHA-256
  `cd41250db988faba69994ae97176282449738741f57213787890c37bda842761`.
  This toolchain-specific hash is reproducibility evidence, not a distributed
  runtime identity; no compiled binary or model is committed.
- The default public limit is 4,096 marked pieces and is configurable from 2
  through 16,384. The configured aggregate cap is enforced incrementally with
  a provable pre-allocation byte lower bound; ranked linked-list batches replace
  the former quadratic whole-sequence merge scans while preserving exact
  simultaneous-pair behavior. Initialization hashes roughly 497 MB and one
  live model holds approximately 496 MB of native weights plus scratch space.
  Callers must explicitly close the backend. Inference is synchronous and has
  no safe timeout or cancellation point; hard cancellation or crash isolation
  requires a separately supervised process.
- The package format, analysis, documentation, normal and complete
  provisioned suites, real-adapter composition, deterministic manifest, and
  publish archive contents pass. The sandbox blocked only pub.dev's final
  network name lookup, so final publication readiness remains open and is not
  represented as a passed network-complete dry run.
- The supported transformer profiles are no fallback and the separately
  supported eSpeak fallback for American/British legacy/2.0 rendering on the
  exact macOS-arm64 tuple. PeterReid BART model fallback remains unsupported
  under its independent provenance blocker.

## 2026-07-11: Kokoro handoff and Japanese-first mobile native assets

- Reviewed Kokoro 0.9.4 at commit
  `dfb907a02bba8152ca444717ca5d78747ccb4bec`. Its Japanese pipeline constructs
  `JAG2P()` with the default Cutlet frontend. Its English path chunks after G2P
  with token-aware 510-code-point punctuation waterfalls; non-English paths
  group roughly 400 code points before G2P and truncate phonemes to 510.
- Added typed `KokoroEnglishG2pFrontend`, `KokoroNonEnglishG2pFrontend`, and
  immutable `KokoroG2pChunk` APIs that preserve those two distinct observable
  contracts. The boundary intentionally ends at phoneme strings. Model-specific
  vocabulary lookup, unknown-symbol filtering, BOS/EOS IDs, voices/styles,
  tensors, ONNX Runtime, and audio inference remain the inference library's
  responsibility.
- Hardened that handoff against four parity gaps found in review. The English
  frontend now requires the engine's typed, inspectable unknown marker to be
  empty, matching Kokoro's `en.G2P(..., unk='')`; chunks retain nullable
  `textIndex`; chunking accepts every token shape the upstream code consumes;
  and Python-code-point operations preserve isolated UTF-16 surrogates while
  counting valid surrogate pairs once.
- Added an accepted eleven-case Kokoro 0.9.4 fixture at commit
  `dfb907a02bba8152ca444717ca5d78747ccb4bec`. Its standard-library exporter
  verifies the checkout and `pipeline.py` digest, replaces optional imports
  with rejecting in-memory stubs, and executes the unmodified `KPipeline`.
  Read-only regeneration matches 510/511 phoneme boundaries, every English
  waterfall tier and fallthrough, `unk=''`, skipped-segment indices, 400/401
  non-English source packing, supplementary characters, and lone surrogates.
- Promoted Japanese Cutlet as the primary mobile implementation. The
  `misakid_mecab_ja` package now distributes the exact unmodified 54-file MeCab
  0.996 subtree from pyopenjtalk 0.4.1 and verifies its 4,499,769 bytes before
  every native-assets build. No source, binary, dictionary, or word list is
  downloaded by the hook.
- Added a portable C++17 build profile for Android, iOS, and macOS. It compiles
  the reviewed 16 MeCab runtime files plus the owned C ABI shim. The pinned
  modified unidic-py CWJ fixture tree is UTF-8, so iconv is omitted as an
  identity conversion; the portable artifact replays all 27 Cutlet cases, all
  126 raw records, every grouping decision, 26 outputs, and the pinned failure
  exactly.
- Android links libc++ statically with archive symbols hidden. A Flutter release
  APK built armv7, arm64, and x86-64 assets with exactly the 24 reviewed Cutlet
  dynamic exports, exact libc/libdl/libm dependencies, 0x4000 ELF LOAD
  alignment, and a
  passing `zipalign -c -P 16 4` check. The first Android runtime attempt exposed
  a missing explicit `libm` dependency through an unresolved `exp` symbol; the
  hook now links it deliberately, and the artifact verifier rejects missing or
  unexpected dynamic dependencies. Apple Clang cross-compiled the same 24
  exports into an unsigned iOS arm64 device app with platform IOS and minimum
  iOS 13. Its install name, system linkage, application rpath, native-assets
  manifest resolution, and exact export surface pass artifact verification.
- Ran the complete device integration contract with stable Flutter 3.41.7 on
  an Android 15/API 35 arm64 emulator and an iPhone 17 Pro iOS 26.4 Simulator.
  Each bundled native asset loaded the exact 20-file modified unidic-py CWJ
  tree and byte-backed `ja_words.txt`, then matched all 27 cases, all 126
  raw/grouped records, all 12 joins, all 26 phoneme/null-token results, and the
  pinned failure. Debug-only network/scene configuration is source-verified and
  absent from production manifests. Physical-device and clean hosted-matrix
  validation remain outstanding.
- Added `MecabJapaneseCutletBackend.openBundled` and
  `openBundledWithMembership`. The exact 1,921,140-byte grouping list can be
  loaded from owned bytes for Flutter assets; the existing path loader remains.
  UniDic stays an explicit absolute real-directory resource because MeCab
  memory-maps it. Initialization streams and validates all 20 files and
  811,662,881 bytes; the package does not silently install or discover them.
- Added owned byte-resource construction for the pure-Dart spaCy small English
  adapter and both Chinese profiles. File and byte paths share exact
  size/SHA/schema parsing and provisioned path-versus-byte equivalence tests.
  This makes the no-fallback English and supported Chinese resource modes
  usable with mobile asset/model stores without importing Flutter into core.

## 2026-07-11: Root package 0.1.0

- Promoted the root `misakid` package from `0.1.0-dev.1` to `0.1.0` without
  changing the independently versioned optional adapter packages.
- Applied the pinned Dart 3.11.5 formatter to the workspace and removed stale
  Flutter-template TODO comments from the repository-owned mobile build
  harness. No G2P behavior, fixture, generated data, or support claim changed.
- Recorded `https://github.com/ProjectKokage/misakid` as the canonical
  repository after configuring the matching Git remote, removing the publish
  metadata warning without changing package behavior.

## 2026-07-11: Open JTalk Android/iOS native assets

- Added `OpenJtalkFrontendBackend.openBundled` without changing the pure-Dart
  Japanese renderer or the legacy explicit-library macOS-arm64 contract. Dart
  resolves the package code asset through a complete 23-function `@Native`
  table, validates the same immutable ABI/source identities, and reports the
  exact native-assets ABI in `BackendInfo`.
- Committed the reviewed `misakid-openjtalk-safety-v1` source input as a
  byte-stable 139-file, 5,382,103-byte tree with SHA-256
  `8ce47a975dee79c078914df15c40df5906430e4a63be4fc2bc0987e7b5b2fccb`.
  The hook and an independent verifier reject changed source files and verify
  the byte-exact Open JTalk and MeCab notices within that tree. Reviewed copies
  of the pyopenjtalk and dictionary notices are retained separately. No native
  binary or dictionary is committed or downloaded by the build.
- Preserved upstream language semantics by compiling Open JTalk's frontend
  `.c` files as a private C11 archive and MeCab plus the owned ABI as C++17.
  Open JTalk's UTF-8 tables use a plain-`char` `-1` sentinel; Android ARM
  defaults that type to unsigned. The C profile therefore forces
  `-fsigned-char`, and a compile-time `CHAR_MIN`/`CHAR_MAX` contract prevents a
  silently unsafe build. Android also statically links LLVM libc++, links
  `libm`, hides archive symbols, and applies an exact export version script.
- Kept `open_jtalk_dic_utf_8-1.11` external. `openBundled` requires an absolute
  real directory and streams the exact nine files, 107,304,813 bytes, and tree
  SHA-256 before native initialization. Android applications must materialize
  APK/Flutter assets into app storage; an exact read-only directory in an iOS
  app bundle may be used directly.
- Stable Flutter 3.41.7 produced one release APK containing both Japanese
  adapters for armv7, arm64, and x86-64. Cutlet has its reviewed 24 exports and
  Open JTalk its reviewed 23 exports; both have only libc/libdl/libm dynamic
  dependencies, a NativeAssets mapping, and 16 KiB ELF-load and uncompressed-ZIP
  alignment. An unsigned iOS arm64
  device app contains both iOS-13+ frameworks with exact exports, reviewed
  `@rpath` install names, libc++/libSystem linkage, application framework rpath,
  and NativeAssets mappings.
- Ran the complete Open JTalk fixture through the public bundled backend and
  raw bindings on an Android 15/API 35 arm64 emulator and iPhone 17 iOS 26.5
  Simulator. Both runs provisioned and revalidated the external dictionary,
  then matched all 24 cases, all 155 NJD records and 14 fields, all 23 final
  phoneme strings and typed token graphs, and the exact pinned whitespace
  failure. The bundled macOS-arm64 path passes the same corpus plus lifecycle,
  bounds, four-isolate, export, and no-stdio checks.
- Added a separate authenticated loopback resource server and manual/tag
  Android-emulator/iOS-simulator workflow job. Normal tests remain offline;
  the workflow explicitly verifies the pinned dictionary archive and fixture
  before serving only fixed routes into each application sandbox.
- Android/iOS execution remains experimental as a release claim until physical
  devices and the clean hosted matrix pass. Android armv7/x86-64, iOS device,
  and iOS x64 currently have build/artifact evidence but not direct runtime
  parity evidence.

## 2026-07-11: Caller-selected UniDic layout and pinned CWJ parity profile

- Removed the pinned modified unidic-py CWJ identity from the default
  `misakid_mecab_ja` initialization path. All open methods now default to
  `MecabJapaneseDictionaryProfile.compatible`, which validates the explicit
  real directory, four required runtime files, and the shape and stability of
  an optional `dicrc` before native initialization. Extra source, notice,
  release-marker, and metadata files do not affect compatibility. The
  compatible profile does not infer corpus or exact
  resource identity: CWJ, CSJ, and custom dictionaries can share a feature
  layout and release number, so it reports corpus unknown and identity
  unverified.
- Added the explicit `pinnedUnidicPyCwjParity` profile for the accepted 27-case
  oracle. Only that profile hashes the complete 20-file, 811,662,881-byte
  modified unidic-py CWJ tree and reports the verified tree identity. Its
  `3.1.0+2021-08-31` release marker is descriptive metadata, not identity. No
  fixture or expected output changed.
- Bumped the owned native contract to ABI 3 and build profile
  `misakid-mecab-ja-build-v4-portable`. The 24-function ABI replaces its
  embedded dictionary hash and 878,989-entry check with a capability contract
  and reports the detected feature field count. Initialization accepts one
  nonempty UTF-8 MeCab-v102 system dictionary, probes `日本` before user input,
  and recognizes fugashi's 17-, 26-, and 29-field UniDic layouts.
  Pronunciation is field 9; kana is absent, field 17, or field 20 respectively.
- Exercised the generic default against the independently provisioned
  `unidic-lite==1.0.8` UniDic 2.1.2 tree and its 26-field layout. The native
  smoke test verifies raw `日本` pronunciation/kana and confirms the backend
  reports no pinned tree hash. This is feature-layout evidence, not a corpus,
  release, or identity claim.
- Generic dictionary output is dictionary-dependent and remains experimental;
  exact Misaki 0.9.4 support is attached only to
  `pinnedUnidicPyCwjParity`. The Open-JTalk-derived MeCab runtime retains its
  reviewed portable configuration and does not interpret arbitrary `dicrc`
  settings, so compatibility means the accepted binary/feature-layout contract
  rather than equivalence to every fugashi installation.

## 2026-07-12: `misakid_mecab_ja` 0.1.0 compatibility gate

- Promoted the sibling adapter from `0.1.0-dev.1` to `0.1.0` atomically across
  its pubspec, Dart/native identities, README, changelog, and mobile lock.
  ABI 3 and its 24 exported functions are unchanged; identity field 5 now
  advertises `unidic-features-26-29-v1`, so older development libraries are
  rejected.
- Removed the unprovisioned 17-field layout before the first stable adapter
  release. The generic contract now accepts only its independently exercised
  26- and 29-field projections.
- Exercised the supplied official NINJAL `unidic-cwj-202302.zip` and
  `unidic-csj-202302.zip` archives through the bundled native asset. Both are
  UTF-8 MeCab-v102 dictionaries with 876,803 entries and 29 fields, and both
  return the expected raw `講師` projection. Their archive, `sys.dic`, and
  `matrix.bin` hashes differ, proving that shared release/layout metadata is
  not corpus or resource identity. Generic backend metadata remains corpus
  unknown and identity unverified for both.
- Added the two exact archive sizes and SHA-256 values to the native source
  manifest and release workflow. The owner-provisioned macOS-arm64 job verifies
  and extracts both archives, runs their shared compatibility test, verifies
  the official unidic-lite 1.0.8 source distribution and five extracted-file
  hashes (the four required binaries plus optional `dicrc`) for the separate
  26-field test, and continues to run strict modified unidic-py CWJ fixture
  parity separately. No compatibility dictionary is bundled or downloaded by
  the package.
- Added repository-wide `.gitignore` plus root/adapter `.pubignore` guards for
  the two supplied archives and the unidic-lite source archive. The final
  adapter dry run is about 650 KB and the root dry run is 4 MB; none of the
  external resources enters a publishable source tree.
- Pinned `actions/checkout` 4.2.2 and `dart-lang/setup-dart` 1.7.2 to their
  immutable commit SHAs in the owner-provisioned native release workflow.

## 2026-07-22: Open JTalk non-code hook passes

- Return immediately when the native-assets hook is invoked without a code
  asset request, before verifying native sources or reading code-target
  configuration. This restores Flutter web builds and non-code follow-up
  passes in macOS development runs while leaving native builds unchanged.

## 2026-07-30: Open JTalk Linux/Windows source profiles

- Added exact native-assets tuples for Linux x64/arm64 and Windows x64 to
  `OpenJtalkFrontendBackend.openBundled`. The hook requires a native,
  same-architecture target host before compiler selection; the Windows profile
  additionally requires the reviewed MSVC `cl.exe`/`lib.exe` path.
- Kept the app-owned 23-function ABI unchanged. Linux emits
  `libmisakid_openjtalk.so` with that SONAME and the ELF version script;
  Windows emits `misakid_openjtalk.dll` with explicit adapter exports.
- Added a Windows LLP64 feature configuration without mutating the verified
  139-file vendor tree. The force-include maps CRT spellings, prevents Windows
  SDK macro collisions, converts canonical UTF-8 drive/UNC paths strictly to
  UTF-16, and uses the extended `CreateFileW` namespace independently of a
  consuming executable's `longPathAware` manifest. Linux strict C11 builds
  request the required POSIX declarations.
- On a macOS arm64 development host, Zig 0.16.0 cross-linked the exact source
  set into Linux x64 and arm64 ELF libraries and a Windows x64
  GNU-compatibility PE DLL. Each exposed exactly the reviewed 23 adapter names;
  both ELF files carried SONAME `libmisakid_openjtalk.so`. These model-free
  probes are source portability evidence only, not the supported native-host
  hook/toolchain path.
- Linux/Windows Flutter packaging, native-assets mapping, host dependency
  inspection, dictionary initialization, long Japanese and space-containing
  paths, and committed fixture parity remain unverified. Neither desktop tuple
  is promoted to supported runtime status.

## 2026-08-22: App-owned asynchronous en-US neural fallback

- Added `AsyncEnglishG2pEngine` and `KokoroAsyncEnglishG2pFrontend`. Only the
  unknown-word backend becomes asynchronous; deterministic lexicon,
  preprocessing, context, rendering, token metadata, unknown-marker, and
  Kokoro chunking behavior remain shared with the synchronous implementation.
- Added `misakid_fonix_en`, accepting only the closed
  `misakid-medium-conv-bigru-ctc` en-US manifest. One worker isolate owns one CPU Fonix
  session and at most one pending request. The adapter bounds grapheme scalars,
  copied messages, output shape, logits, and inventories; rejects unsupported
  scalars and non-finite or malformed output; cancels and drains native work;
  recovers after settled cancellation; and closes idempotently.
- Added a Python 3.12 UV tooling subproject that deterministically validates,
  merges, groups, and splits the exact pinned Apache-2.0 `us_silver.json` and
  `us_gold.json`; trains a 1,173,871-parameter medium convolutional/BiGRU CTC
  graph on CPU without padded bidirectional batches; exports ONNX opset 17;
  verifies Torch/ONNX numerical and decoded parity; evaluates only the held-out
  split; benchmarks warm batch-1 inference; and atomically emits model,
  manifest, report, and bounded parity records outside the checkout.
- Training emits only `candidate-*`. Promotion to V1 requires at least 67%
  exact-word accuracy, at most 7% PER, a model no larger than 6 MiB, warm raw
  ONNX Runtime p95 below 2 ms on the qualifying macOS arm64 host, Torch/ONNX
  parity, and an identity-bound receipt from the real Fonix-isolate test.
- V1 `v1-5ce8863c502d` is 4,708,739 bytes with SHA-256
  `5ce8863c502da27ad043e91bec1a6d8ff2b6b654d1e645d68645b1818e6230b9`.
  Its independently assigned 2,187-example test split produced 1,561 exact
  words (71.38%) and 1,066 edits across 20,069 reference phones (5.31% PER).
  Warm raw ONNX Runtime p95 was 896 microseconds. Torch/ORT decoded parity and
  the real Fonix adapter pass all 32 exported cases. The earlier 692,643-byte
  graph remains an unfrozen prototype. This validates the app-owned contract
  and basic function; it neither claims subjective TTS quality nor parity with
  Misaki's PeterReid BART mode.
- Model weights and generated reports remain external to Git. A consuming
  application must provide an immutable distribution location and verify the
  manifest, size, and SHA-256 before creating the adapter.

## Next parity slices

- Run the Open JTalk hook and Flutter packaging on native Linux x64/arm64 and
  Windows x64 hosts, inspect the routed assets/dependencies, and execute the
  complete fixture including a long Japanese and space-containing dictionary
  path before promoting either desktop runtime.
- Validate both Japanese native-assets release configurations on physical
  iOS/Android hardware and execute the clean hosted matrix before promoting
  broad mobile release support. Both complete Android/iOS emulated-runtime
  fixtures already pass and remain distinct backend contracts.
- Expand the Korean native adapter only when equivalent additional-platform
  resources and CI are explicitly provisioned.
- Expand the English transformer adapter only when equivalent Linux,
  Intel-macOS, or Windows implementations and provisioned parity CI exist. The
  BART provenance blocker remains unchanged.
- Obtain a compatible, precisely licensed
  underthesea-equivalent implementation/model and an exact Mishkal 0.3.2
  source/data license; and accept Vietnamese and Hebrew fixtures before either
  backend implementation begins.
