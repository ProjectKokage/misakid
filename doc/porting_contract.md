# Porting and parity contract

This document owns the detailed behavior, fixture and adapter requirements
previously embedded in `AGENTS.md`. Read the sections for the language or
boundary being changed. Code paths below are relative to the repository root.
[PORTING_STATUS.md](../PORTING_STATUS.md) owns supported modes;
[PORTING_NOTES.md](../PORTING_NOTES.md) records accepted divergences and the
remaining work. [Reference tooling](../tool/reference/README.md) owns the
executable oracle procedures. Ordinary tests replay committed fixtures;
provisioning or regenerating an oracle is a separate, explicit operation.

## Pinned upstream reference

Use this upstream snapshot unless a dedicated upstream-sync change updates it:

- Repository: `https://github.com/hexgrad/misaki`
- Commit: `fba1236595f2d2bf21d414ba6e57d25256afada3`
- Python package version: `0.9.4`
- Upstream license: Apache-2.0

Normal porting work must not silently follow upstream `main`. The executable
Python behavior at the pinned commit is authoritative when source code,
comments, README examples, and intuition disagree.

An upstream update must be a focused change that:

1. changes the recorded commit;
2. rebuilds the Python reference environment;
3. regenerates and reviews all affected parity fixtures;
4. records behavior changes in `PORTING_NOTES.md`;
5. updates third-party notices and copied data when necessary; and
6. contains no unrelated Dart refactoring.

## Priorities

Apply these priorities in order:

1. Exact behavior for every mode declared supported.
2. Reproducible, offline, deterministic execution.
3. Idiomatic, null-safe, strongly typed Dart APIs.
4. A platform-neutral pure-Dart core with optional backends at the edges.
5. Clear provenance and license compliance for code and data.
6. Performance improvements that do not alter output.

Do not “clean up,” linguistically correct, normalize, or optimize an upstream
quirk during the parity phase. First capture the behavior in a test. An
intentional divergence requires a documented rationale, an explicit
compatibility decision, and tests for the new contract.

## Definition of support

A language, backend, dialect, or version is supported only when all of the
following are true:

- its public configuration is documented;
- required dependencies and platform limits are explicit;
- committed parity fixtures cover representative and adversarial inputs;
- exact output and token semantics pass against the pinned reference;
- unsupported backend conditions fail with a typed, actionable error;
- format, analysis, and tests pass without ignored warnings; and
- `PORTING_STATUS.md` marks the precise mode as supported.

A partial implementation must remain clearly marked experimental or
unsupported. Do not advertise “Misaki parity” based only on a few README
examples.

## Upstream subsystem map

Inspect the relevant Python source and data before changing its Dart port.

| Area | Pinned sources | Backend boundary |
| --- | --- | --- |
| Shared | `misaki/token.py` | Dynamic metadata, timestamps, whitespace |
| English | `en.py`, `espeak.py`, English JSON lexicons, `EN_PHONES.md` | spaCy, `num2words`, BART, eSpeak |
| Japanese | `ja.py`, `cutlet.py`, `num2kana.py`, `ja_words.txt` | pyopenjtalk or fugashi/MeCab/UniDic |
| Korean | `ko.py`, `g2pkc/**` | MeCab, CMUdict, Jamo, rule/idiom files |
| Chinese | `zh.py`, `zh_frontend.py`, `tone_sandhi.py`, `transcription.py`, `zh_normalization/**` | jieba, pypinyin, number normalization |
| Vietnamese | `vi.py`, `vi_cleaner/**`, Vietnamese JSON data | underthesea and English fallback |
| Hebrew | `he.py` | mishkal |

Several files were adapted or copied from other projects. Preserve their source
headers and verify original code and data licenses before porting them.

## Compatibility contract

Unless an intentional divergence is recorded, preserve:

- Default unknown marker `❓`.
- Exact phoneme symbols, stress/tone/pitch marks, punctuation, whitespace, and
  token order.
- The distinction between unavailable token data (`null`) and an
  available-but-empty token list.
- Shared token fields, quality/rating information, and language-specific
  metadata when the selected upstream mode provides them.
- English dialect, phoneme-version, morphology, number/currency, context, and
  inline-control behavior such as `[text](/phonemes/)`.
- Distinct Japanese Cutlet and pyopenjtalk contracts, including accent, mora,
  chain, and pitch data where available.
- Distinct Chinese legacy/new frontend behavior and mixed-English handling.
- Vietnamese dialect, tone, cleaning, custom-pronunciation, and fallback
  options.
- Backend-specific cases where Python returns no token list.

Do not normalize expected and actual values to make a test pass. Normalization
is observable behavior and belongs only at the stages where upstream performs
it.

## Public API design

Prefer a small explicit API over a literal transcription of Python classes and
keyword arguments. The default synchronous shape should resemble:

```dart
abstract interface class G2pEngine {
  G2pResult convert(String text);
}

final class G2pResult {
  const G2pResult({required this.phonemes, required this.tokens});

  final String phonemes;

  /// `null`: this backend cannot provide token details.
  /// Empty: tokenization was available and produced no tokens.
  final List<MisakiToken>? tokens;
}
```

- Use immutable `final` classes and unmodifiable collections at API boundaries.
- Use enums and option objects instead of positional/nullable booleans.
- Keep Dart package versioning separate from the pinned upstream version; expose
  upstream version/commit constants when useful.
- Preserve shared token fields, but replace Python's dynamic `MToken._` map with
  a sealed typed hierarchy such as `EnglishTokenMetadata` and
  `JapaneseTokenMetadata`.
- Do not expose `Map<String, dynamic>` as the normal metadata API. A stable map
  is acceptable only in fixture tooling.
- Give values documented units, for example `startTimeSeconds`.
- Use typed package exceptions for invalid configuration, unavailable
  backends, malformed generated data, and adapter failures.
- Library code must not `print`; return diagnostics, use an injected logger, or
  throw.
- Do not return `FutureOr`. Keep in-process engines synchronous and define a
  separate async interface for process/model-backed engines.
- Inject tokenizers, taggers, morphology analyzers, pinyin providers, number
  normalizers, and fallbacks through narrow interfaces.
- Avoid service locators and mutable global configuration.
- Document every public API with a minimal example and backend/platform limits.

## Pipeline boundaries

Do not implement each language as one monolithic translated file. Separate the
pipeline into testable stages where the upstream permits it:

1. input and inline-control parsing;
2. Unicode/text normalization;
3. segmentation or tokenization;
4. POS/morphology annotation;
5. number, symbol, abbreviation, and mixed-script normalization;
6. lexicon/rule lookup;
7. context, stress, tone, accent, or sandhi transformation;
8. optional fallback;
9. token merging; and
10. final rendering.

A pure stage must not import a native adapter. Backend interfaces should carry
the minimum structured data required by the next stage, not backend-specific
objects.

For English, independently test preprocessing, subtokenization, lexicon lookup,
suffix rules, numbers/currencies, context propagation, fallback mapping, and
rendering. End-to-end parity may initially consume token/POS streams exported
from Python; this is preferable to pretending that a heuristic tokenizer
matches spaCy.

## Unicode and text correctness

Dart strings are UTF-16. Treat direct code-unit indexing as suspect.

- Iterate over Unicode scalar values with `runes` when the algorithm is defined
  over code points.
- Use grapheme clusters only where behavior is defined over user-perceived
  characters.
- Preserve combining marks and normalization form unless the upstream stage
  explicitly applies NFC, NFKC, width conversion, or another transform.
- Add tests containing decomposed accents, supplementary-plane characters,
  variation selectors, full-width/half-width forms, smart quotes, and mixed
  scripts.
- Do not assume Python `isalpha`, `isdigit`, case conversion, slicing, or
  regular-expression semantics match Dart.
- Python's third-party `regex` expressions use Unicode properties in English
  subtokenization. Do not transliterate those expressions blindly into Dart
  `RegExp`; verify behavior case by case or implement explicit Unicode
  classification.
- Make phoneme inventory validation operate on code points, not bytes or UTF-16
  halves.
- Keep fixture files UTF-8 and do not ASCII-escape IPA or source-script text
  unless a serialization format requires it.

## External backend policy

The pure-Dart package must remain usable without native binaries, model
downloads, Python, or network access.

Define narrow contracts for capabilities such as:

- English tokenization and POS tagging;
- English number spelling and unknown-word fallback;
- eSpeak phonemization;
- Japanese morphological/accent frontend;
- Chinese segmentation, POS tagging, and pinyin;
- Korean morphology;
- Vietnamese tokenization and English fallback; and
- Hebrew phonemization.

For every adapter:

- construction is explicit and side-effect free except for validation;
- the caller provides an executable path, library path, model directory, or
  other required resource;
- report backend name and version for diagnostics and fixture metadata;
- never auto-install, auto-download, or mutate global process configuration;
- never invoke a shell with interpolated input; pass an executable and argument
  list directly;
- set timeouts for subprocesses and surface exit code and bounded stderr;
- validate native ABI/model/data compatibility before processing text;
- make unsupported platforms fail at initialization, not halfway through a
  document; and
- test the interface with fakes in normal CI, with real-adapter tests in an
  explicitly provisioned job.

Model-backed fallbacks belong in an optional adapter package. Model artifacts
must be obtained by an explicit user/tooling step, pinned by version and
checksum, and excluded from normal source control unless their license and size
make vendoring intentional.

The sole model-publication exception is the exact promoted en-US G2P pair
`models/en-us-g2p/v1-5ce8863c502d/model.onnx` and `model-manifest.json`, governed
by that directory's README and notices. Preserve both files byte for byte,
exclude `/models/` from Pub packages, and keep training candidates, reports,
caches, and native binaries external. This permits explicit repository
publication of that pair; it does not permit automatic downloads or changes
to package/runtime support. Public push still requires the owner's review of
the complete unpublished commit range.

## Data and derived tables

The English lexicons and language data are part of behavior, not incidental
resources.

- Record source repository, path, revision, and license for derived data.
- Keep the committed runtime tables as the implementation source of truth;
  normal development does not retain a second copy of their upstream inputs.
- Verify observable table behavior with focused tests and parity fixtures.
- If an explicit upstream-sync task needs temporary extraction or generation,
  review the resulting table diff and remove the temporary inputs afterward.
- Load large immutable data lazily and cache it per isolate. Never parse the
  full lexicon for every conversion.
- Keep the pure core free of `dart:io`. If a compact binary representation is
  chosen, provide platform-appropriate loaders or generated Dart data for all
  declared platforms.
- Measure package size, startup time, lookup speed, and memory before choosing
  code generation versus a compact data format.
- Do not remove duplicate or apparently unnecessary entries until parity tests
  demonstrate that the change is behavior-neutral.

## Licensing and provenance

License work is part of implementation work.

- Retain the upstream Apache-2.0 license.
- Preserve copyright and attribution headers in adapted files.
- Add a prominent modification notice where the source license requires it.
- Maintain `THIRD_PARTY_NOTICES.md` for code and data derived from Cutlet,
  number-to-Japanese code, g2pK/g2pkc, PaddleSpeech, pinyin-to-IPA, Vietnamese
  sources, and any other upstream dependency.
- Verify the license of rule tables, dictionaries, corpora, and generated model
  data separately from the surrounding code.
- Do not paste code or data with an unknown or incompatible license.
- A generated file does not erase the provenance or obligations of its input.
- Include provenance in the PR/change summary whenever new copied material is
  introduced.

## Python oracle and parity fixtures

The upstream repository has no conventional comprehensive test suite. Golden
differential fixtures are therefore mandatory.

Create a pinned Python exporter under `tool/reference/`. It must execute the
upstream implementation at the recorded commit and write one JSON object per
line with at least:

```json
{
  "schemaVersion": 1,
  "upstreamRepository": "hexgrad/misaki",
  "upstreamCommit": "fba1236595f2d2bf21d414ba6e57d25256afada3",
  "upstreamVersion": "0.9.4",
  "language": "en",
  "mode": "american-no-fallback",
  "options": {},
  "backendVersions": {},
  "input": "source text",
  "phonemes": "exact output",
  "tokens": []
}
```

Fixture rules:

- Serialize every available token field and language-specific metadata.
- Use stable key ordering and UTF-8.
- Record backend versions for outputs influenced by spaCy, pyopenjtalk, jieba,
  pypinyin, MeCab, underthesea, eSpeak, mishkal, or a model.
- Store corpora and fixture provenance beside the output.
- Capture expected failures with a stable error category rather than relying on
  a full environment-specific traceback.
- Keep random generation seeded and record the seed.
- Never generate expected output from the Dart implementation.
- Never overwrite fixtures as a side effect of `dart test`.
- Regeneration must require an explicit acceptance flag and print a
  human-reviewable summary of changed cases.
- A fixture update without either an upstream-pin change or a documented
  intentional divergence is presumed incorrect.

Use exact comparisons for output strings and token fields. Add a separate
diagnostic diff that reports the first differing code point, Unicode name when
available, surrounding context, and token index.

## Test requirements

Every behavior change needs a test at the lowest useful layer and, when
user-visible, an end-to-end parity case.

Required groups:

- pure unit tests for mappings, normalization, numbers, morphology,
  stress/tone/accent rules, and rendering;
- contract tests for every injected backend;
- exact parity tests against committed Python fixtures;
- data-integrity and phoneme-inventory tests;
- regression tests for each fixed bug; and
- compiled public examples.

Cover empty/whitespace input, punctuation and quotes, malformed/custom controls,
unknowns and unavailable backends, composed/decomposed Unicode, width forms,
mixed scripts, numbers/currencies/abbreviations, and each language's option
matrix. Add focused cases for English inflection and dialects; Japanese small
kana, sokuon, moraic nasal, long vowels and pitch; Chinese polyphones, sandhi,
neutral tone and erhua; Korean rule ordering and Jamo; Vietnamese dialects,
tones, acronyms and foreign names; and Hebrew niqqud/stress when supported.

Useful invariants:

- token rendering reproduces the returned output for modes using that model;
- tokens retain source order;
- output symbols belong to the declared inventory, punctuation/whitespace, or
  unknown marker;
- derived table behavior is covered; and
- related metadata arrays have consistent lengths.

Translate upstream `assert` invariants into tests and explicit validation when
they protect runtime data. Do not rely on Dart assertions for production input
or data validation.

Do not weaken exact tests with trimming, folding, normalization, sorting, or
broad regex matching. Normal CI must not use the network. Real-backend tests
must be tagged and run only in explicitly provisioned jobs.

## Performance and resource use

Correctness comes first, but avoid preventable hot-path costs.

- Precompile immutable regular expressions and lookup tables.
- Use `StringBuffer` for repeated concatenation.
- Avoid quadratic substring scans unless parity requires them; characterize and
  bound any retained behavior.
- Parse and validate large data once per isolate, not per call.
- Do not retain entire documents through accidental substring or closure
  references.
- Keep engine initialization separate from conversion so callers can reuse
  expensive state.
- Benchmark cold initialization, warm conversion throughput, p50/p95 latency,
  allocations, memory, and package/data size on a versioned corpus.
- Add a benchmark before accepting a performance-motivated algorithm change,
  and run parity tests before and after it.
- Avoid catastrophic regular-expression backtracking on untrusted text.
- Process/model adapters must support cancellation or a caller-configurable
  timeout where the platform permits it.

Do not introduce isolates by default. Use them only after measurement shows a
benefit and the API makes ownership, initialization, and data transfer clear.

## Security and reliability

- Treat input text, custom pronunciation controls, data files, model paths, and
  subprocess output as untrusted.
- Never construct shell commands from input text.
- Bound captured subprocess output and include safe diagnostic excerpts.
- Validate generated-data checksums and schema versions.
- Do not deserialize arbitrary objects or execute generated source from data.
- Do not log full user text by default.
- Do not use the network during conversion.
- Do not catch `Object` and continue with partial output. Catch the narrow
  failure you can handle and preserve the cause.
- Make fallback behavior explicit; an unavailable fallback must not silently
  become deletion or the unknown marker unless that is the selected policy.
- Keep global data immutable and avoid ordering that depends on hash iteration.
