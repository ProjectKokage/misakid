# Pinned Python reference exporter

This directory contains the executable oracle for Dart parity fixtures. It
always validates and runs `hexgrad/misaki` at commit
`fba1236595f2d2bf21d414ba6e57d25256afada3` (package version `0.9.4`). A
different checkout or package version is rejected before any case runs.

The exporter itself is standard-library Python. Backend packages are imported
only for modes that need them. In particular, `ja-num2kana` and
`ja-kanji-number` need no third-party Python packages.

## Kokoro frontend oracle

Kokoro's frontend contract is pinned independently at package version 0.9.4,
commit `dfb907a02bba8152ca444717ca5d78747ccb4bec`. Create an explicit checkout:

```sh
git clone https://github.com/hexgrad/kokoro /private/tmp/kokoro-review
git -C /private/tmp/kokoro-review checkout \
  dfb907a02bba8152ca444717ca5d78747ccb4bec
```

The dedicated exporter requires that exact Git head and the reviewed
`kokoro/pipeline.py` SHA-256 before loading source. It uses only the Python
standard library: optional Torch, Hugging Face, logging, and Misaki imports are
replaced by deterministic in-memory stubs that reject model or download use.
The unmodified `KPipeline` still performs construction, default string
splitting, English token chunking, non-English source packing, truncation, and
result-index assignment. Normal verification is read-only:

```sh
python3.12 tool/reference/export_kokoro_frontend.py \
  --upstream-repository /private/tmp/kokoro-review \
  --cases tool/reference/cases/kokoro_frontend.jsonl \
  --output test/fixtures/upstream/dfb907a02bba8152ca444717ca5d78747ccb4bec/kokoro_frontend.jsonl
```

For an explicitly reviewed upstream-sync or fixture-acceptance change, add
`--accept`. Without it the exporter never writes and fails on any byte diff.
The adjacent provenance file pins the source, exporter, corpus, fixture,
Python, and Unicode-data identities.

## Reference environment

Use a dedicated checkout. The dependency-free Japanese number modes need no
virtual environment or package installation:

```sh
git clone https://github.com/hexgrad/misaki /private/tmp/misaki-upstream
git -C /private/tmp/misaki-upstream checkout fba1236595f2d2bf21d414ba6e57d25256afada3
```

For the pinned English no-fallback mode, use Python 3.12 and the committed
lock extracted from this upstream commit's `uv.lock`. It also pins
`en_core_web_sm` 3.8.0 by URL and the wheel SHA-256 published on its official
GitHub release:

```sh
python3.12 -m venv /private/tmp/misaki-oracle-en
uv pip sync \
  --python /private/tmp/misaki-oracle-en/bin/python \
  tool/reference/requirements-en-no-fallback-py312.txt
```

The transformer tokenizer/tagger is a distinct, explicitly provisioned
environment. It uses Explosion's `en_core_web_trf==3.8.0` with the curated
transformer packages selected by the pinned upstream lock:

```sh
python3.12 -m venv /private/tmp/misaki-oracle-en-trf
uv pip sync \
  --python /private/tmp/misaki-oracle-en-trf/bin/python \
  tool/reference/requirements-en-trf-py312.txt
```

The direct model wheel is
`en_core_web_trf-3.8.0-py3-none-any.whl`, size 457,421,864 bytes, SHA-256
`272a31e9d8530d1e075351d30a462d7e80e31da23574f1b274e200f3fff35bf5`.
The lock additionally pins `spacy-curated-transformers==0.3.0`,
`curated-tokenizers==0.0.9`, and `curated-transformers==0.1.1`. Keep this
environment separate from the small-model oracle so verification cannot
silently change tokenizer/tagger mode.

Before installing or importing the transformer wheel, inventory it with the
bounded auditor. The tool checks the reviewed whole-wheel identity, rejects
unsafe or ambiguous ZIP members, hashes every member, and validates the six
required model resources and metadata without extracting or executing
anything. It also validates the complete pinned spec, including the upstream
identity, runtime delta, requirements hash, prepared-corpus hashes and row
counts, and acceptance-state types.

Candidate generation and acceptance are deliberately separate. The reviewed
inventory is committed as
`tool/reference/en_core_web_trf-3.8.0.inventory.json`, with SHA-256
`4e3cae8256e9e701739cdbd720ffe5f3047202e4a0ebace4bc469a33b1ae7eba`.
It records all 33 wheel members and the exact six runtime resources. For a
focused upstream-sync change, first reset the acceptance fields and generate a
candidate outside the repository:

```sh
python3 tool/reference/audit_en_trf_wheel.py \
  --wheel /absolute/path/en_core_web_trf-3.8.0-py3-none-any.whl \
  --output /private/tmp/en_core_web_trf-3.8.0.inventory.json \
  --accept
```

`--accept` creates the candidate exclusively, or reuses an existing
byte-identical candidate; it never replaces different contents and never
edits the spec. Review the complete inventory and its printed SHA-256. Then
make an explicit reviewed change to
`tool/reference/en_trf_resource_spec.json`:

```json
"memberInventoryAccepted": true,
"memberInventorySha256": "<the printed candidate SHA-256>"
```

The normal read-only verification gate uses the committed inventory:

```sh
python3 tool/reference/audit_en_trf_wheel.py \
  --wheel /absolute/path/en_core_web_trf-3.8.0-py3-none-any.whl \
  --output tool/reference/en_core_web_trf-3.8.0.inventory.json \
  --check
```

`--check` refuses an unaccepted state, verifies the recorded inventory digest,
re-audits the exact wheel, and requires a byte-identical deterministic
inventory without modifying the wheel, inventory, or spec. Once an inventory
is accepted, `--accept` refuses to replace it. A missing or wrong wheel fails
before any candidate is written. The two accepted transformer fixtures remain
independently bound through the fixture manifest and adjacent provenance
sidecars; model-inventory acceptance alone never changes fixture bytes.

After extracting the reviewed wheel into the exact oracle environment, the
read-only model inspector can reproduce the implementation contract without
executing the embedded Torch pickle:

```sh
/private/tmp/misaki-oracle-en-trf/bin/python \
  tool/reference/inspect_en_trf_model.py \
  --model-root \
  /private/tmp/misaki-oracle-en-trf/lib/python3.12/site-packages/en_core_web_trf/en_core_web_trf-3.8.0
```

It validates every consumed resource and runtime version, then prints JSON to
standard output with the serialized byte-BPE identity, all 149 F32 tensor
names, shapes, hashes and direct byte offsets, the strided-span graph, and the
49-label mean-pooling tagger head. It also emits the exact Unicode-16 Letter,
Number, and White_Space ranges used by pinned `regex==2024.11.6` for GPT-2
splitting; these are not interchangeable with CPython 3.12's Unicode-15
properties. It does not write a manifest, alter the model, or accept fixtures.

The eSpeak-fallback matrices extend that exact environment with the pinned
`phonemizer-fork` and bundled eSpeak-ng loader closure:

```sh
uv pip sync \
  --python /private/tmp/misaki-oracle-en/bin/python \
  tool/reference/requirements-en-espeak-py312.txt
```

The exporter rejects any other eSpeak package versions, blocks network access
during backend construction and conversion, and records SHA-256 identities for
both the loaded native library and the complete eSpeak-ng data tree.

Create separate, explicitly provisioned environments for the other language
extras and native backends. Do not install all extras in one command. Install
backend resources before going offline. Examples include NLTK `cmudict`,
UniDic/MeCab data, and any eSpeak runtime used by a declared mode. The exporter
preflights the spaCy model and NLTK corpus so upstream's automatic download
paths are not entered.

The Japanese pyopenjtalk environment is locked separately for Python 3.12:

```sh
python3.12 -m venv /private/tmp/misaki-oracle-ja
uv pip sync \
  --python /private/tmp/misaki-oracle-ja/bin/python \
  tool/reference/requirements-ja-py312.txt
```

`pyopenjtalk` 0.4.1 uses Open JTalk dictionary 1.11 from release `v1.11.1`:

```text
https://github.com/r9y9/open_jtalk/releases/download/v1.11.1/open_jtalk_dic_utf_8-1.11.tar.gz
SHA-256: fe6ba0e43542cef98339abdffd903e062008ea170b04e7e2a35da805902f382a
Size: 23646843 bytes
```

Download this during explicit environment bootstrap. Verification must use the
already-installed dictionary and must not enter pyopenjtalk's automatic
download path.

The accepted Japanese Cutlet oracle has its own Python 3.12 lock:

```sh
python3.12 -m venv /private/tmp/misaki-oracle-ja-cutlet
uv pip sync \
  --python /private/tmp/misaki-oracle-ja-cutlet/bin/python \
  tool/reference/requirements-ja-cutlet-py312.txt
```

Its full UniDic resource is the content-addressed backup of the original 3.1.0
archive, not the mutable official S3 object or the `latest` lookup used by
`python -m unidic download`:

```text
https://huggingface.co/drewThomasson/unidic_3.1.0_backup/resolve/9fcae6f3676c255dac3b81d8fbc83b16cc192d20/unidic-3.1.0.zip
SHA-256: 39ea0eae3b1f10ba8986483592cbc83bcc92f1898bb43ecbc607010f2e98cd22
Size: 524664138 bytes
Installed version marker: unidic-3.1.0+2021-08-31
Installed tree: sha256:95bd65fa96955b644c15510932ca8439f463ac8b66f57bac6dfee5e29fa03115+files:20+bytes:811662881
Live sys.dic: charset:utf8+entries:878989+binary-version:102
```

Download and checksum that archive only during explicit bootstrap, then
install from the local verified file. A fresh environment can reproduce the
exact layout used by the oracle with:

```sh
set -eu
archive=/private/tmp/unidic-3.1.0-pinned.zip
dictionary=/private/tmp/unidic-3.1.0-pinned
test ! -e "$archive" && test ! -L "$archive"
test ! -e "$dictionary" && test ! -L "$dictionary"
curl --fail --location \
  --output "$archive" \
  https://huggingface.co/drewThomasson/unidic_3.1.0_backup/resolve/9fcae6f3676c255dac3b81d8fbc83b16cc192d20/unidic-3.1.0.zip
test "$(wc -c < "$archive" | tr -d '[:space:]')" = 524664138
printf '%s  %s\n' \
  39ea0eae3b1f10ba8986483592cbc83bcc92f1898bb43ecbc607010f2e98cd22 \
  "$archive" | shasum -a 256 --check
mkdir "$dictionary"
unzip -q "$archive" -d "$dictionary"
unidic_package=$(
  /private/tmp/misaki-oracle-ja-cutlet/bin/python -c \
    'from pathlib import Path; import unidic; print(Path(unidic.__file__).resolve().parent)'
)
test ! -e "$unidic_package/dicdir"
test ! -L "$unidic_package/dicdir"
ln -s "$dictionary" "$unidic_package/dicdir"
```

The destination paths must not already exist; this bootstrap deliberately
does not replace or merge an old dictionary. The exporter hashes relative
paths, lengths, and contents across the complete installed tree, requires the
exact version marker, and checks fugashi's live `dictionary_info` contains
only that tree's `sys.dic` with the exact charset, entry count, and binary
version. These three identities are recorded separately in `backendVersions`.
The dependency lock, resource preflight, capture schema, and authoritative
27-case golden are committed. The separate `ja_words.txt` grouping list is an
explicit external compatibility artifact: Misakid validates its pinned
identity for the oracle and adapter but does not redistribute it. Its
undocumented upstream prehistory and inferred Kaikki/Wiktextract lineage are
recorded in `THIRD_PARTY_NOTICES.md` without being overstated as proof.

The authoritative Korean `g2pkc-default` mode uses a separate Python 3.12
environment. Misaki's lock includes Jamo and NLTK but omits the morphology
package that its POSIX path imports, so this repository additionally pins
`python-mecab-ko==1.3.7` and `python-mecab-ko-dic==2.1.1.post2`, whose
`mecab.MeCab().pos` API is the exact API consumed by the pinned source:

```sh
python3.12 -m venv /private/tmp/misaki-oracle-ko
uv pip sync \
  --python /private/tmp/misaki-oracle-ko/bin/python \
  tool/reference/requirements-ko-g2pkc-py312.txt
mkdir -p /private/tmp/misaki-oracle-ko/nltk_data
NLTK_DATA=/private/tmp/misaki-oracle-ko/nltk_data \
  /private/tmp/misaki-oracle-ko/bin/python -m nltk.downloader \
  -d /private/tmp/misaki-oracle-ko/nltk_data cmudict
```

The required NLTK resource is CMUdict 0.7a at
`https://raw.githubusercontent.com/nltk/nltk_data/gh-pages/packages/corpora/cmudict.zip`,
with SHA-256
`d07cca47fd72ad32ea9d8ad1219f85301eeaf4568f8b6b73747506a71fb5afd6`.
The exporter requires the ZIP with that exact digest before importing Korean
Misaki and replaces `nltk.download` with a rejecting guard throughout each
oracle call. Regeneration and verification therefore never download resources
at runtime. Set `NLTK_DATA=/private/tmp/misaki-oracle-ko/nltk_data` for both.

Both Chinese-only contracts use one locked Python 3.12 environment.
The lock contains the source checkout's Chinese runtime closure from the pinned
`uv.lock`: `cn2an` 0.5.23, `jieba` 0.42.1, `pypinyin` 0.53.0,
`pypinyin-dict` 0.9.0, and `ordered-set` 4.1.0.

```sh
python3.12 -m venv /private/tmp/misaki-oracle-zh
uv pip sync \
  --python /private/tmp/misaki-oracle-zh/bin/python \
  tool/reference/requirements-zh-py312.txt
```

Jieba's packaged default `dict.txt` is an observable segmentation resource.
For 0.42.1 its required SHA-256 is
`7197c3211ddd98962b036cdf40324d1ea2bfaa12bd028e68faa70111a88e12a8`.
The exporter verifies that exact file before each Chinese call and records its
identity. It rejects Python minors other than 3.12. Chinese import, frontend
initialization, and conversion also reject any dependency version that differs
from the committed lock and run under a rejecting socket/URL guard, so neither
regeneration nor verification can download packages or resources.

The accepted frontend-1.1 plus English small-model callback uses a distinct
combined CPython 3.12.11 environment and manifest key `zh-en`. Start from the
offline-synchronized English no-fallback closure, then copy only the six
Chinese-exclusive pure-Python distributions from the separately accepted
Chinese environment with complete RECORD hash/size validation:

```sh
uv venv --offline --no-python-downloads --no-project \
  --python /private/tmp/misaki-oracle-en-espeak/bin/python \
  /private/tmp/misaki-oracle-zh-en
uv pip sync --offline --no-python-downloads --strict \
  --python /private/tmp/misaki-oracle-zh-en/bin/python \
  tool/reference/requirements-en-no-fallback-py312.txt
/private/tmp/misaki-oracle-zh/bin/python \
  tool/reference/prepare_zh_en_callback_oracle.py \
  --destination /private/tmp/misaki-oracle-zh-en
uv pip check --python /private/tmp/misaki-oracle-zh-en/bin/python
```

`requirements-zh-en-callback-py312.txt` is the canonical combined lock. The
copy helper rejects unexpected versions, missing or changed RECORD entries,
links, special files, and native/shared-library payloads before and after the
copy. This environment is local oracle provisioning, not a distributable
artifact.

Vietnamese no-English-fallback modes use a separate Python 3.11 environment.
Underthesea-core 1.0.4 has no CPython 3.12 wheel, so this is an intentional
backend constraint rather than the Python version used by the other modes:

```sh
uv python install 3.11.13
uv venv --python 3.11.13 /private/tmp/misaki-oracle-vi
uv pip sync \
  --python /private/tmp/misaki-oracle-vi/bin/python \
  tool/reference/requirements-vi-py311.txt
```

The exporter requires CPython 3.11.13 with Unicode data 14.0.0, records both
identities in every fixture, and requires the complete exact underthesea 6.8.4
closure and `vietnam-number==1.0.3`, the last release available when the pinned
Misaki commit was authored. Misaki imports `vietnam-number` but omits it from both
`pyproject.toml` and `uv.lock`. It also imports English G2P unconditionally
even when `enable_en_g2p=False`, although the Vietnamese extra omits English's
transformers dependencies. For these explicit no-English modes, the exporter
reads the exact `LINK_REGEX` literal from pinned `en.py`, supplies a rejecting
G2P sentinel during `vi.py` import, and fails if English construction occurs.
No English behavior is substituted. Dependency checks, import, initialization,
tokenization, and conversion run under a rejecting network guard.

The production Dart cleaner does not delegate observable case conversion to
the host runtime. Its candidate Unicode-14 lower/upper, whitespace, and
Final_Sigma tables were exported from CPython 3.11.15 and can be reproduced
only with that exact runtime:

```sh
python3.11 tool/reference/export_python311_case.py \
  --output tool/upstream_data/python-3.11-unicode-14.0.0/case_maps.json \
  --check
dart run tool/generators/generate_python311_case.dart --check
```

Changing the accepted JSON requires the exporter's explicit `--accept` flag
and review of the manifest counts and exhaustive digests. It is derived
Unicode behavior, not a Vietnamese phoneme golden.

The locked target remains CPython 3.11.13. Once that runtime is provisioned,
the target check is:

```sh
python3.11 tool/reference/compare_python31113_case.py
```

It compares every mapping, property range, count, and exhaustive digest and
must report no mismatches before the candidate can be described as exact
3.11.13 behavior.

The Hebrew `default` mode uses a separate Python 3.12 environment. The
committed lock contains Mishkal and its complete pinned dependency closure from
the upstream `uv.lock`:

```sh
python3.12 -m venv /private/tmp/misaki-oracle-he
uv pip sync \
  --python /private/tmp/misaki-oracle-he/bin/python \
  tool/reference/requirements-he-py312.txt
```

The exporter requires `mishkal-hebrew==0.3.2`, `colorlog==6.9.0`,
`num2words==0.5.14`, and `docopt==0.6.2` exactly. It rejects Python minors
other than 3.12. The pure-Python Mishkal wheel is pinned by its upstream-lock
URL, 154859-byte size, and SHA-256
`1b25dc61c2ac1ca2898c288adbd8d81399260fd4d82124bbce5f0d031c785997`.
Import, engine construction, and phonemization all run under the same rejecting
socket/URL guard used by the other offline oracle modes. Mishkal is the whole
Hebrew adapter boundary, so Hebrew fixture records do not contain a
`backendInput` object and always preserve `tokens: null`.

Set `PYTHONHASHSEED=0` when invoking the exporter. This must be set before the
Python process starts; assigning it inside Python does not make set iteration
deterministic.

## Input schema

The input is UTF-8 JSONL with one object per case:

```json
{"caseId":"readme-en","language":"en","mode":"american-no-fallback","options":{},"input":"Misaki is a G2P engine."}
```

Required fields are `language`, `mode`, and `input`. `options` defaults to an
empty object. Optional `caseId` values must be unique. Optional integer `seed`
is recorded in output and seeds already-loaded Python, NumPy, and Torch random
generators before the case runs.

Supported modes are:

- `ja-num2kana` and `ja-kanji-number` under language `ja` (dependency-free);
- `cutlet` and `pyopenjtalk` under `ja`;
- `american-no-fallback`, `british-no-fallback`, and explicit eSpeak fallback
  variants under `en`;
- `legacy` and `frontend-1.1` under `zh`;
- `g2pkc-default` under `ko` and `default` under `he`; and
- `north-no-english-fallback`, `central-no-english-fallback`, and
  `south-no-english-fallback` under `vi`.

The pinned English constructor has a counterintuitive truthiness check:
`fallback=None` and `fallback=False` both instantiate the Hugging Face fallback
network. The `*-no-fallback` exporter modes pass a truthy callable sentinel to
the constructor and then set `engine.fallback` to `None`. This preserves the
rest of the pinned constructor behavior while guaranteeing that fixture
generation neither initializes nor downloads the fallback model.

Model-fallback exporter modes are intentionally absent. The two named Hub
repositories can be revision- and weight-checksum-pinned, but their empty
model cards and missing training-data, lineage, license-file, copyright, and
notice evidence do not satisfy this repository's provenance policy. See
`THIRD_PARTY_NOTICES.md`; do not download or accept model-backed fixtures until
that blocker is resolved.

The committed starter corpus is
[`cases/ja_num2kana.jsonl`](cases/ja_num2kana.jsonl). It covers leading zeros,
irregular readings, group-boundary spacing quirks, decimals, the nine-digit
limit, and reverse Kanji-number conversion.

The first English corpus is
[`cases/en_american_no_fallback.jsonl`](cases/en_american_no_fallback.jsonl).
It covers empty and whitespace input, README inline controls, punctuation,
unknowns, casing, inflection, numbers and currencies, context-sensitive words,
malformed controls, and adversarial Unicode. Most cases explicitly select the
legacy `version: null`; paired cases select `version: "2.0"` to preserve the
observable flap and glottal-stop difference.

The British corpus,
[`cases/en_british_no_fallback.jsonl`](cases/en_british_no_fallback.jsonl), is
the reviewed mode-only twin of that 32-case matrix: case IDs, inputs, and
options (including both phoneme versions) are unchanged. Its accepted fixture
has the same 154 raw spaCy replay tokens as the American fixture, while the
British lexicons and morphology change final phonemes and tokens in 24 cases.
Keeping the raw boundary identical makes dialect behavior independently
testable without conflating it with tokenization drift.

The separately accepted adversarial twins,
[`cases/en_american_no_fallback_adversarial.jsonl`](cases/en_american_no_fallback_adversarial.jsonl)
and
[`cases/en_british_no_fallback_adversarial.jsonl`](cases/en_british_no_fallback_adversarial.jsonl),
add 21 cases per dialect without changing the original transformer comparison
matrix. They cover inline number flags, signed/year/large values, currency
edges, contractions and possessives, suffix and homograph branches,
capitalization, multiword and adjacent controls, compatibility normalization,
Python whitespace, mixed scripts, non-BMP combining sequences, symbol
clusters, and CPython-specific Cherokee lowercase tag weighting. Their 175
captured raw tokenizer records are identical across
dialects; provenance sidecars pin both case and fixture byte streams.

The American and British eSpeak corpora are likewise mode-only twins:
[`cases/en_american_espeak_fallback.jsonl`](cases/en_american_espeak_fallback.jsonl)
and
[`cases/en_british_espeak_fallback.jsonl`](cases/en_british_espeak_fallback.jsonl).
They cover zero-call known/empty paths, ordered single and multiple OOV calls,
punctuation and subtoken grouping, casing, apostrophes, composed/decomposed and
width Unicode forms, custom unknown rendering, disabled preprocessing, and
both phoneme versions.

The Japanese pyopenjtalk corpus is
[`cases/ja_pyopenjtalk.jsonl`](cases/ja_pyopenjtalk.jsonl). It covers empty and
whitespace input, kana and kanji, small kana, sokuon, moraic nasal, long vowels,
accent chains, numbers, Japanese punctuation and spacing, mixed scripts,
unknowns, supplementary characters, variation selectors, and width forms.

The Japanese Cutlet corpus is
[`cases/ja_cutlet.jsonl`](cases/ja_cutlet.jsonl). Its 27 cases separately cover
empty and whitespace input, hiragana/kanji/katakana, digraphs, sokuon,
moraic-nasal assimilation, long vowels, Japanese punctuation and spacing,
numbers and the over-limit diagnostic, mixed ASCII and width forms, combining
marks, iteration marks, emoji, supplementary characters, variation selectors,
phonetic extensions, a three-node longest grouping match, and spacing around a
substring whose romanization is empty. Its accepted golden contains 26 exact
outputs and the pinned long-number failure from the fully validated resource
environment.

The first Korean corpus is
[`cases/ko_g2pkc_default.jsonl`](cases/ko_g2pkc_default.jsonl). It covers empty
and whitespace input, Hangul rule boundaries, spaces and newlines, ordered
idioms, Arabic numerals and native counters, CMUdict-backed English and
acronyms, punctuation, compatibility and conjoining Jamo, emoji, variation
selectors, width forms, and the upstream caret rule blocker. Nine focused
adversarial cases additionally cover overlapping idiom/unit order,
POS-sensitive complex batchim and palatalization, `ui`, Unicode decimals,
native-counter boundaries, 16/17-digit place handling, broad ARPABET branches,
English case and overlapping words, plus the observable CPython 3.12
seed-zero tuple-set replacement order for overlapping numeral/counter spans.
The 17-digit case records pinned
`process_num`'s stable upstream failure instead of inventing output. This mode
is the real `KOG2P` path with morphology enabled; it is not a no-morphology
surrogate.

Chinese keeps its two upstream contracts in separate corpora. The
[`cases/zh_legacy.jsonl`](cases/zh_legacy.jsonl) corpus covers the legacy IPA
renderer, normalization, traditional and full-width text, punctuation,
lexical tones and polyphones, mixed English preservation, numbers, dates,
times, phone-like strings, whitespace, rare Han, variation selectors, and
supplementary-plane input. The
[`cases/zh_frontend_1_1.jsonl`](cases/zh_frontend_1_1.jsonl) corpus covers the
1.1 Bopomofo-style frontend independently, including `不`, `一`, third-tone,
neutral-tone, reduplication, and erhua rules; custom polyphone data; mixed
English with no English engine; number normalization; and the same Unicode and
punctuation adversaries. A mode name never selects the other contract.
All three Chinese fixtures are accepted independently in
`accepted_fixtures.json`. The 14-case callback corpus additionally covers the
American/British and legacy/2.0 matrix, ordered mixed segments, punctuation,
apostrophes/hyphens, context, no-fallback unknowns, width/number boundaries,
and empty fast paths.

Vietnamese keeps north, central, and south in three 33-case mode-only twin
corpora:
[`cases/vi_north_no_english_fallback.jsonl`](cases/vi_north_no_english_fallback.jsonl),
[`cases/vi_central_no_english_fallback.jsonl`](cases/vi_central_no_english_fallback.jsonl),
and
[`cases/vi_south_no_english_fallback.jsonl`](cases/vi_south_no_english_fallback.jsonl).
They independently cover dialect-sensitive finals, all six tones, glides,
substring handling, custom pronunciation, abbreviation/acronym toggles,
numbers, phone forms, currencies, measurements, dates, time, punctuation,
tone-type forcing and simultaneous Phạm/Cao flags, glottal and palatal modes,
NFC composition, width forms, emoji, variation selectors, and the explicit
no-English fallback path.

The Hebrew corpus,
[`cases/he_default.jsonl`](cases/he_default.jsonl), covers the documented
pointed hello-world reading, unpointed input, every basic vowel and final
letter form, shin/sin and dagesh/rafe distinctions, geresh/gershayim,
punctuation, cantillation, explicit Hat'ama (`U+05AB`) and vocal-shva/meteg
(`U+05BD`) marks, numbers and a date, mixed Latin text, emoji, variation
selectors, noncanonical combining-mark order, unknown symbols, and the full
punctuation/stress option matrix. It deliberately records rather than repairs
Mishkal behavior for unpointed or adversarial input.

Each output line contains schema version, upstream repository/commit/version,
mode and options, relevant installed backend versions, exact input and output,
and tokens. `tokens: null` is kept distinct from an empty token list. Token
serialization includes every declared upstream dataclass field, the `_`
language metadata mapping, and any dynamic top-level fields added by upstream.
Maps and sets are serialized deterministically and UTF-8 is not ASCII-escaped.

English records additionally contain a `backendInput` object whose kind is
`misaki.en.G2P.preprocess-tokenize` and whose nested schema version is 1. Its
`preprocess` object records whether preprocessing was applied, the exact
preprocessed text, the ordered source words used by spaCy alignment, and the
raw integer-keyed feature map encoded as ordered `sourceWordIndex`/`value`
entries. Its `tokens` array is a snapshot of the exact `MToken` list returned
by `G2P.tokenize`, before folding, retokenization, lexicon resolution, or final
rendering. Every initial token field and every `_` metadata key actually
present are retained. The exporter wraps the tokenizer used by the cached
engine, so each case performs one spaCy tokenization rather than a separate
capture pass.

For eSpeak modes the same object uses nested schema version 2 and adds
`espeakCalls`. Each ordered call records the exact token text and the raw first
IPA result before trimming or Misaki replacement; `null` preserves an empty
backend result list. The Dart parity suite replays these raw calls through its
own deterministic postprocessor.

Japanese `pyopenjtalk` records additionally contain a `backendInput` object.
Its `kind` is `pyopenjtalk.run_frontend.words`, its nested schema version is 1,
and `words` is the ordered raw NJD word stream with eleven required string
fields (`string`, POS/morphology, original/read/pronunciation, and chain rule)
and three required integer fields (`acc`, `mora_size`, and `chain_flag`). The
exporter calls the native frontend once, validates and snapshots this stream,
then replays a deep copy through pinned Misaki so Dart can test the pure
post-frontend pipeline against the same typed input.

Japanese `cutlet` records use the distinct
`misaki.cutlet.normalized-morphology` backend-input contract at schema version
1. It records the exact normalized string passed to fugashi and each ordered
raw node's surface, nullable `pronunciation` and `kana` fields, selected
hiragana reading, raw character type, and unknown flag. `joinWithNext` captures
only the longest-match grouping decisions made by pinned `ja_words.txt`; the
external 1.9 MB list itself is never copied into a fixture or the Dart runtime.
The exporter wraps the actual cached
`Cutlet.tagger`, so each non-empty case performs exactly one morphology call,
while empty input records the upstream no-call fast path. Cutlet's outer token
list remains `null`. `backendVersions` independently pins
`unidic-dictionary-tree`, `unidic-dictionary-version`, and the live
`fugashi-system-dictionary` identity in addition to the Cutlet grouping-list
identity.

Korean `g2pkc-default` records contain a `backendInput` object with kind
`python-mecab-ko.MeCab.pos` and nested schema version 2. It records the exact
post-idiom/post-English string passed to the external analyzer and the ordered
`surface`/`tag` tuples it returned. It also records every ordered, normalized
CMUdict lookup as a lowercase ASCII `key` plus the selected first `arpabet`
pronunciation, or `null` for a miss. Uppercase words do not produce lookups
because pinned g2pkc spells them before consulting CMUdict. The exporter wraps
both dependencies on the cached upstream engine, snapshots their actual output
before downstream rules run, and requires exactly one morphology call per
case. The resource identity remains pinned in `backendVersions` by NLTK data
version and ZIP SHA-256.

Chinese records capture the actual external stages used during the single
upstream conversion pass. Legacy records use kind
`misaki.zh.legacy.external-stages` and schema version 1. They record the exact
`cn2an.transform(..., "an2cn")` input/output, each CJK run passed to
`jieba.lcut(cut_all=False)`, the ordered words, and every raw TONE3
`lazy_pinyin` result. Frontend 1.1 records use kind
`misaki.zh.frontend-1.1.external-stages` and schema version 1. For every
Chinese segment they record the raw `jieba.posseg.lcut` word/POS stream and an
ordered external-call stream containing pre-merge finals,
`jieba.cut_for_search` results, and render-time initials/finals. Pinyin arrays
are copied before sandhi mutates them. Both top-level modes must return
`tokens: null`; empty and whitespace input retain a typed backend object with
no normalization call.

The combined callback fixture uses kind
`misaki.zh.frontend-1.1-en-small-no-fallback.external-stages` and schema
version 2. It retains the same Chinese frontend stages plus the fixed English
dialect/version, small-model, preprocessing, and no-fallback configuration.
Every ordered callback records its exact input, phonemes, final tokens, and a
complete nested schema-1 English preprocess/raw-token stream. The exporter
rejects unexpected callback inputs, order/count drift, result types, or any
callback that does not invoke `G2P.tokenize` exactly once.

When accepted, Vietnamese records use backend-input kind
`underthesea.pipeline.word_tokenize.tokenize` and nested schema version 1.
Each successful record will contain the exact fully cleaned string passed to
underthesea and the exact ordered non-empty token strings it returned. The
wrapper captures the actual call on the cached upstream engine, requires
exactly one tokenizer call per case, and restores the original function before
returning. Final Vietnamese `MToken` fields and dynamic
onset/nucleus/coda/tone/parent metadata
will remain serialized in the normal top-level `tokens` array. The three case
corpora are committed, but authoritative output fixtures remain unaccepted
until the exact locked environment can be provisioned.

Expected failures contain only a stable category in the fixture. Use
`--verbose-errors` for environment-specific diagnostics on stderr; tracebacks
and paths are never embedded into goldens.

## Regeneration is an explicit write

`regenerate` requires distinct input/output paths and `--accept`. Output is
written atomically; an existing fixture is never overwritten without explicit
acceptance.

```sh
PYTHONHASHSEED=0 python3 tool/reference/export_fixtures.py regenerate \
  --upstream-root /private/tmp/misaki-upstream \
  --input tool/reference/cases/ja_num2kana.jsonl \
  --output test/fixtures/upstream/fba1236595f2d2bf21d414ba6e57d25256afada3/ja_num2kana.jsonl \
  --accept
```

Review the resulting diff before committing it. Fixture acceptance must not be
a side effect of tests or verification.

## Verification is read-only

`verify` executes the same cases and byte-compares them with a committed
fixture. It never writes the expected file. A mismatch exits `1` and prints the
first differing Unicode code point, Unicode name, surrounding context, the
zero-based token index when determinable, and a bounded unified diff. Invalid
configuration exits `2`.

### Verify every accepted fixture

`accepted_fixtures.json` is the authoritative manifest of committed goldens.
The aggregate verifier consumes all seventeen accepted files by default. Before
running the oracle it requires exact pinned-directory coverage, matches every
corpus record to its fixture identity, checks both record counts, and verifies
the adjacent corpus/fixture provenance hashes. It then invokes only the
exporter's read-only `verify` operation and never accepts or regenerates output.
Point each language family at its exact locked interpreter.

The small-model English interpreter must contain the complete
`requirements-en-espeak-py312.txt` closure. That environment is a strict
superset of the accepted small-model/no-fallback closure and verifies both
English fallback policies without changing their configuration. Transformer
no-fallback and transformer-plus-eSpeak fixtures use separate locked
interpreters because their closures intentionally differ:

```sh
MISAKI_ORACLE_EN_PYTHON=/private/tmp/misaki-oracle-en-espeak/bin/python \
MISAKI_ORACLE_EN_TRF_PYTHON=/private/tmp/misaki-oracle-en-trf/bin/python \
MISAKI_ORACLE_EN_TRF_ESPEAK_PYTHON=/private/tmp/misaki-oracle-en-trf-espeak/bin/python \
MISAKI_ORACLE_JA_PYTHON=/private/tmp/misaki-oracle-ja/bin/python \
MISAKI_ORACLE_JA_CUTLET_PYTHON=/private/tmp/misaki-oracle-ja-cutlet/bin/python \
MISAKI_ORACLE_KO_PYTHON=/private/tmp/misaki-oracle-ko/bin/python \
MISAKI_ORACLE_ZH_PYTHON=/private/tmp/misaki-oracle-zh/bin/python \
MISAKI_ORACLE_ZH_EN_PYTHON=/private/tmp/misaki-oracle-zh-en/bin/python \
PYTHONDONTWRITEBYTECODE=1 \
python3 tool/reference/verify_committed.py \
  --upstream-root /private/tmp/misaki-upstream
```

The manifest keys `en-trf`, `en-trf-espeak`, `ja-cutlet`, and `zh-en` are
deliberately distinct from their lighter or resource-incompatible
environments. The verifier rejects a transformer, transformer/eSpeak, Cutlet,
or combined Chinese/English corpus routed through another key and exposes
corresponding dedicated interpreter options.

The success summary must report 431 cases across seventeen fixture files. Use a
repeatable `--language en`, `--language ja`, `--language ko`, or
`--language zh` only for a focused development check; the unfiltered command
is the completion gate.

```sh
PYTHONHASHSEED=0 python3 tool/reference/export_fixtures.py verify \
  --upstream-root /private/tmp/misaki-upstream \
  --input tool/reference/cases/ja_num2kana.jsonl \
  --expected test/fixtures/upstream/fba1236595f2d2bf21d414ba6e57d25256afada3/ja_num2kana.jsonl
```

For example, regenerate and then read-only verify the Chinese 1.1 contract
with the locked interpreter:

```sh
PYTHONHASHSEED=0 /private/tmp/misaki-oracle-zh/bin/python \
  tool/reference/export_fixtures.py regenerate \
  --upstream-root /private/tmp/misaki-upstream \
  --input tool/reference/cases/zh_frontend_1_1.jsonl \
  --output test/fixtures/upstream/fba1236595f2d2bf21d414ba6e57d25256afada3/zh_frontend_1_1.jsonl \
  --accept

PYTHONHASHSEED=0 /private/tmp/misaki-oracle-zh/bin/python \
  tool/reference/export_fixtures.py verify \
  --upstream-root /private/tmp/misaki-upstream \
  --input tool/reference/cases/zh_frontend_1_1.jsonl \
  --expected test/fixtures/upstream/fba1236595f2d2bf21d414ba6e57d25256afada3/zh_frontend_1_1.jsonl
```

Run the tool's dependency-free unit tests with:

```sh
python3 -m unittest discover -s tool/reference/tests -v
```
