# Misakid

Misakid is a platform-neutral Dart port of
[`hexgrad/misaki`](https://github.com/hexgrad/misaki), the grapheme-to-phoneme
(G2P) engine used by Kokoro models. Implemented parity slices are pinned to
Misaki 0.9.4 at commit
`fba1236595f2d2bf21d414ba6e57d25256afada3`; the precise slices identified in
`PORTING_STATUS.md` are checked with exact JSONL fixtures exported from
Python.

Python is used only by repository-local development tooling for the pinned
upstream oracle and read-only fixture verification. The published root library
excludes those scripts, fixture tests, and Python environments; sibling adapter
build manifests needed by their published offline builders remain included.
Conversion and consumer use require no Python.

This package is under active pre-1.0 development. Japanese is the primary
mobile target: the Kokoro-default Cutlet mode now has a vendored, reproducible
MeCab native-assets build for Android and iOS plus byte-backed grouping data.
The same bundled build passes the complete pinned Cutlet oracle on macOS, an
Android 15/API 35 arm64 emulator, and an iOS 26.4 Simulator. Three-ABI Android
release artifacts and an unsigned iOS device app also pass native packaging
checks. Physical-device validation and the clean hosted mobile matrix remain
formal release gates. Japanese
pyopenjtalk-style and Korean g2pkc-default modes remain
supported for their precise macOS arm64 adapter configurations. Chinese legacy/default,
frontend-1.1 without an English callback, and the exact frontend-1.1
small-model/no-fallback English callback profile are supported by explicit
pure-Dart resource packages. English American and British small-model modes are
supported without fallback by a pure-Dart tokenizer/tagger using explicit
`en_core_web_sm==3.8.0` resources. An app-owned asynchronous en-US neural
fallback, its deterministic UV training/export project, and its bounded Fonix
adapter are available for Kokage without eSpeak; this is a separate product
profile, not parity with Misaki's PeterReid BART fallback. The eSpeak-fallback
variants are supported
on macOS arm64 with a second explicit native adapter. English transformer
no-fallback and eSpeak-fallback modes are also supported on macOS arm64 with
the exact external `en_core_web_trf==3.8.0` resources and package-owned
Accelerate adapter. PeterReid BART fallback and other complete language modes
remain unsupported. See
[PORTING_STATUS.md](PORTING_STATUS.md) for the precise capability matrix.

## Kokoro and ONNX handoff

Kokoro 0.9.4 defaults Japanese to Misaki's `JAG2P()`, whose default frontend is
Cutlet. `JapaneseCutletEngine` plus `misakid_mecab_ja` implements that G2P path.
`KokoroNonEnglishG2pFrontend` additionally reproduces Kokoro's line splitting,
roughly 400-code-point pre-G2P packing, and 510-code-point phoneme limit.
`KokoroEnglishG2pFrontend` implements the distinct token-aware English
punctuation waterfall. Kokoro constructs its English G2P with `unk=''`, so the
frontend accepts only an `UnknownMarkerG2pEngine` whose actual `unknownMarker`
is empty; construct `EnglishG2pEngine` with `unknownMarker: ''`. Both frontends
return immutable `KokoroG2pChunk` values whose nullable `textIndex` preserves
Kokoro's original default line-feed segment index, including skipped segments
and repeated indices for subchunks.

The accepted eleven-case Kokoro fixture executes the unmodified pinned
`kokoro/pipeline.py` under dependency-rejecting stdlib stubs. It covers the
English 510/511 boundaries, all punctuation-waterfall levels and fallthrough,
the fixed unknown policy, non-English 400/401 packing, segment indices, valid
supplementary characters, and isolated UTF-16 surrogates.

This repository deliberately stops at the G2P boundary. A separate ONNX
inference library consumes each chunk's `phonemes`, applies the selected
Kokoro model's vocabulary (including filtering unmapped symbols and adding
BOS/EOS IDs), selects voice/style data, constructs tensors, and runs inference.
No ONNX Runtime, model weight, voice pack, or platform inference dependency is
introduced here.

## English pipelines

The package includes an offline pinned American/British pronunciation provider
with contextual lexicon, morphology, currency, and number behavior. It can be
used directly:

```dart
import 'package:misakid/misaki_en.dart';

void main() {
  const lexicon = PinnedEnglishLexicon();
  final pronunciation = lexicon.lookup(
    const MisakiToken(
      text: 'hello',
      tag: 'NN',
      whitespace: '',
      metadata: EnglishTokenMetadata(isHead: true),
    ),
    const EnglishTokenContext(),
  );
  print(pronunciation?.phonemes); // həlˈO
}
```

`EnglishG2pEngine` composes this provider with an explicitly supplied typed
tokenizer/tagger. The committed American and British no-fallback suites each
replay 53 exact pinned-Python cases: the original 32-case matrix plus 21
adversarial cases covering number flags, morphology, controls, Unicode, mixed
scripts, symbols, and large values. They include the legacy and 2.0 phoneme
versions. Two additional accepted 20-case American/British eSpeak-fallback
suites replay the exact raw eSpeak-ng calls through the public Dart fallback,
covering OOV grouping, punctuation, capitalization, Unicode, dialect-specific
phones, preprocessing disabled, custom unknown markers, and both phoneme
versions. The compiling
[`example/english_injected.dart`](example/english_injected.dart) shows the full
public engine with a fixed tokenizer record.

`AsyncEnglishG2pEngine` preserves the same deterministic English stages while
allowing only the unknown-word backend to be asynchronous. Its frontend,
`KokoroAsyncEnglishG2pFrontend`, preserves Kokoro's distinct English chunking
contract without blocking the calling isolate. The optional
[`misakid_fonix_en`](packages/misakid_fonix_en/README.md) package implements
that backend with one isolate-owned CPU Fonix session, one pending request,
explicit cancellation/drain, strict manifest and ONNX identity checks, and
bounded copied messages. Unsupported input scalars fail explicitly rather
than being silently omitted.

The repository-owned UV project at
[`tool/english_g2p_training`](tool/english_g2p_training/README.md) trains and
exports the `misakid-medium-conv-bigru-ctc` en-US graph solely from the exact
pinned Apache-2.0 `us_gold.json` and `us_silver.json` inputs. V1,
`v1-5ce8863c502d`, has 1,173,871 parameters and is a 4,708,739-byte opset-17
ONNX graph with SHA-256
`5ce8863c502da27ad043e91bec1a6d8ff2b6b654d1e645d68645b1818e6230b9`.
Its independently assigned 2,187-word held-out test split measured 71.38%
whole-word accuracy and 5.31% phone error rate, clearing the fixed 67%/7%
gates. Warm raw ONNX Runtime p95 was 896 microseconds on the qualifying macOS
arm64 host, under the fixed 2 ms gate. Torch/ONNX decoded parity and the real
Fonix adapter both pass the 32 bounded exported cases. The prior 692,643-byte
graph was an unfrozen prototype and is not V1. Weights and reports remain
external to Git; a consuming application must distribute and verify the exact
model separately.

`englishPhonemeInventory` exposes the frozen American/British inventory for
either rendering version. It covers built-in lexicon/eSpeak output; custom
inline pronunciations, punctuation, whitespace, and unknown markers remain
caller-visible additions rather than silently accepted inventory symbols.

The sibling `misakid_spacy_en` package is the supported production
tokenizer/tagger for the small-model configurations. It implements the pinned
spaCy 3.8.4 tokenizer and Thinc 8.3.4 `en_core_web_sm==3.8.0` inference path in
pure Dart. Callers provide the four exact checksum-validated model files; the
adapter invokes no Python, native code, subprocess, or network. Provisioned
parity covers all 146 accepted raw streams, 744 tokens/tags, metadata, and
final results for American and British output with legacy and 2.0 rendering.
The same four exact resources can be supplied as owned byte buffers, so a
Flutter asset loader or mobile model store does not need to expose desktop
filesystem paths. Unknown-word eSpeak fallback remains a separate macOS-only
adapter; mobile English support is therefore the exact no-fallback profile.

`EnglishEspeakFallback` ports the deterministic replacement and
postprocessing layer behind `EnglishEspeakBackend`. The sibling
`misakid_espeak_en` package supplies the supported raw eSpeak provider for the
documented macOS 11+ arm64 eSpeak NG 1.52.0 resource tuple. A composed test
using both real adapters matches all 40 accepted fallback cases, every token
field, and all 58 ordered native calls. Neither adapter discovers, downloads,
or bundles its external resources. The eSpeak adapter's byte, punctuation-
split, and 65,536 native callback-chunk limits fail explicitly with typed
errors; conversion has no cancellation hook and should be process-isolated
when hard cancellation is required.

The sibling `misakid_spacy_trf_en` package supplies the supported transformer
tokenizer/tagger on macOS 11+ arm64. Its Dart stages implement the exact spaCy
tokenizer, RoBERTa byte-BPE, and alignment; a package-owned native library
evaluates the 12-layer graph and tagger with Apple Accelerate. It invokes no
Python, spaCy, Torch, subprocess, or network. Callers explicitly provide the
checksum-pinned `en_core_web_trf==3.8.0` model directory and build the native
library from reviewed source; neither artifact is bundled or discovered.

All 116 accepted American/British transformer cases pass against the real
backend: 76 no-fallback cases plus 40 eSpeak-fallback cases, covering 2,278
raw transformer token/tag records and 50 ordered raw eSpeak calls. A second
composition test runs both real native adapters for all 40 fallback cases.
The transformer holds approximately 496 MB of native weights, is synchronous,
has no cancellation hook, and must be explicitly closed. See
[`packages/misakid_spacy_trf_en/README.md`](packages/misakid_spacy_trf_en/README.md)
for the build command, exact resource tuple, configurable piece bounds, and
platform limits.

The two BART fallback repositories named by pinned Misaki have immutable
weight checksums but empty model cards and no adequate training-data, lineage,
license-file, copyright, or notice provenance. They are therefore not accepted
as fixture or adapter inputs; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for the reviewed revisions and
exact blocker.

The optional `misakid_bart_en` package nevertheless provides an experimental
pure-Dart implementation of the exact one-encoder-layer/one-decoder-layer BART
architecture behind that boundary. Callers supply absolute paths plus exact
byte sizes and SHA-256 identities for a JSON configuration and F32
safetensors file; the adapter never discovers, downloads, or bundles weights.
Its graph is checked against a license-clean synthetic model using CPU Torch
2.6.0 and Transformers 4.51.3, including full causal decoder logits, multiple
generation inputs, unknown-ID handling, and early EOS. This validates the
runtime architecture only: it does not clear the PeterReid provenance blocker
or make pinned Misaki's model-fallback modes supported.

## Japanese number conversion

The first pure parity slice converts Arabic-number text to kanji, kana, or
romaji and converts Japanese number text back to Arabic text:

```dart
import 'package:misakid/misaki_ja.dart';

void main() {
  const numbers = JapaneseNumberConverter();

  print(numbers.convert('12345')); // いちまんにせんさんびゃくよんじゅうご
  print(
    numbers.convert('20.5', format: JapaneseNumberFormat.romaji),
  ); // ni jutten go 
  print(numbers.kanjiToArabic('一億一万一')); // 100010001
}
```

The trailing romaji space shown above is intentional upstream behavior.
Over-limit input returns upstream's literal diagnostic string; other inputs
outside the pinned converter's domain fail with an
`InvalidConfigurationException` instead of an incidental Python indexing or
lookup error.

## Japanese pyopenjtalk-style pipeline

`JapanesePyopenjtalkEngine` consumes typed morphology, pronunciation, accent,
mora-count, and chain data from an explicitly supplied
`JapaneseFrontendBackend`. Its pure renderer preserves all 193 pinned mora
mappings, punctuation and whitespace behavior, unknown markers, token
metadata, accent chains, and the equal-scalar-length pitch trace appended to
the returned phoneme string. The 24-case committed oracle matrix replays the
raw frontend word stream exactly.

`japanesePhonemeInventory` exposes frozen source-derived phonetic-scalar sets
for the distinct Cutlet and pyopenjtalk-style contracts (35 and 40 symbols,
respectively). Punctuation, configurable unknown markers, Cutlet pass-through,
and pitch-only trace markers are documented exclusions.

The pure package still bundles and discovers no native frontend or dictionary.
The sibling `misakid_openjtalk` package provides a no-Python adapter with a
source-built `openBundled` native asset for Android, iOS, Linux, macOS, and
Windows, while retaining its legacy explicit-library macOS-arm64-only API.
Callers always supply an absolute Open JTalk 1.11 dictionary path. The default
entry points stream and validate the exact source/ABI/dictionary identities
before opening; an explicit bundled verified-install entry point avoids
rehashing an app-private dictionary already validated in staging and installed
atomically. The owned-result ABI passes all 24 cases, all 155
raw words and 14 fields, all 23 successful final results and typed token
fields, concurrent-isolate stress, and silent success/failure checks. The
complete fixture also passes through `openBundled` on an Android 15/API 35
arm64 emulator and iPhone 17 iOS 26.5 Simulator. Mobile physical devices and
the clean hosted matrix remain experimental release gates. Linux x64/arm64 and
Windows x64 are source-configured native-host profiles with foreign-host,
model-free cross-link evidence only; target-host Flutter packaging, dictionary
loading, long Japanese/space-path behavior, and parity are still unverified.
No native binary or 107 MB dictionary is committed.

The compiling
[`example/japanese_pyopenjtalk_injected.dart`](example/japanese_pyopenjtalk_injected.dart)
uses a fixed frontend record to demonstrate the public contract without
claiming to be pyopenjtalk. The adapter package includes its own real-backend
example, offline source build, full resource identities, platform limits, and
third-party notices. Linux and Windows are not promoted runtime tuples until
their target-host evidence gates pass; Cutlet is provided separately as
described below.

## Japanese Cutlet pipeline

`JapaneseCutletEngine` ports the pinned Cutlet normalizer and complete
189-entry IPA-oriented kana/symbol mapping, including digraphs, sokuon,
moraic-nasal assimilation, long vowels, iteration marks, punctuation spacing,
and the upstream `tokens == null` result contract. It consumes typed
`JapaneseCutletMorphologyWord` records from an explicit
`JapaneseCutletMorphologyBackend`.

The backend receives the exact normalized text and provides raw character
types, unknown flags, hiragana readings, and explicit `joinWithNext` grouping
decisions. The compiling
[`example/japanese_cutlet_injected.dart`](example/japanese_cutlet_injected.dart)
uses one fixed record to demonstrate that public boundary.

The accepted 27-case oracle contains 26 exact outputs and the pinned
long-number failure. Pure-Dart replay matches every phoneme string and null
token result. Its raw contract captures 126 fugashi records with both nullable
UniDic `pronunciation` and `kana` fields, selected hiragana, character type,
unknown status, and all 12 longest-match joins.

The sibling `misakid_mecab_ja` package completes Kokoro's default Japanese mode
without Python. It distributes the exact licensed MeCab 0.996 source subtree
from `pyopenjtalk` 0.4.1 and compiles the 24-function ABI v3
`misakid-mecab-ja-build-v4-portable` owned-result boundary through Dart's
native-assets hook for Android armv7/arm64/x86-64, iOS device/simulator, and
macOS. Its default profile accepts an explicit caller-selected UTF-8 UniDic
using a provisioned 26- or 29-field layout. That check does not
identify the corpus, distribution, release, or exact resource: CWJ and CSJ can
share a layout and release number, and output may vary with the selected
dictionary. The compatible profile therefore reports corpus unknown and
identity unverified and carries no exact parity claim. The explicit
`MecabJapaneseDictionaryProfile.pinnedUnidicPyCwjParity` profile validates the
complete 20-file modified unidic-py CWJ tree used by the accepted fixture by
tree hash. Callers also supply the pinned Misaki `ja_words.txt` bytes or an
injected grouping membership; no
dictionary or grouping data is discovered or downloaded. The package's pinned
path and byte loaders validate the word list's exact compatibility identity at
initialization; injected memberships retain their caller-owned identity. The
word list is not redistributed; its undocumented upstream prehistory and inferred
Wiktionary/Kaikki lineage are recorded conservatively in
`THIRD_PARTY_NOTICES.md`.

With the pinned modified unidic-py CWJ profile, the portable UTF-8/no-iconv
build matches all 27 original cases, all 126 raw records and fields, every
grouping decision, output, and failure. A separate native test exercises the
default compatible profile against unidic-lite 2.1.2's 26-field layout. Two
more provisioned tests exercise the distinct official NINJAL
`unidic-cwj-202302.zip` and `unidic-csj-202302.zip` resources, both 29-field;
their archive and binary hashes differ even though the release marker and
field count match. This is projection compatibility evidence, not a corpus
inference or exact-output claim. Tests also
cover byte-resource mutation isolation, owned result lifetime, repeated close,
input bounds, concurrent isolates, reproducible source identity, exported
symbols, resource tampering, and silent native execution. The Cutlet library in
a release Flutter APK contains only its 24 reviewed exports for all three
Android ABIs, links exactly `libc`/`libdl`/`libm`, and passes 16 KiB alignment
checks. An unsigned iOS device app passes framework, native-assets-manifest,
deployment-target, rpath, linkage, and exact-export verification. The complete
27-case fixture passes
through the bundled asset on both an Android 15/API 35 arm64 emulator and an
iOS 26.4 Simulator.
Physical-device and clean hosted-matrix validation remain explicit gates for
broad mobile support.
Linux, Windows, embedded NUL, and cancellation are unsupported. See
[`packages/misakid_mecab_ja/README.md`](packages/misakid_mecab_ja/README.md)
for the exact resource tuple and build command.

## Korean injected pipeline

`KoreanG2pkcEngine` ports the deterministic idiom, English conversion,
morphology annotation, numeral, Jamo, special-rule, table-rule, linking, and
rendering stages. It preserves upstream's `tokens == null` contract and is
covered by a 34-case exact matrix: 33 successful outputs plus the pinned
17-digit numeral failure. The typed replay includes ordered CMUdict hit/miss
records and exact MeCab morphology streams. Numeral replacement also preserves
the observable CPython 3.12 seed-zero set order for overlapping bare numbers,
prefixes, and counter spans.

```dart
import 'package:misakid/misaki_ko.dart';

G2pResult convertKorean(
  String text,
  KoreanMorphologyBackend morphology,
  KoreanCmuPronunciationProvider cmu,
) {
  return KoreanG2pkcEngine(
    morphology: morphology,
    cmuPronunciations: cmu,
  ).convert(text);
}
```

The pure package bundles and discovers none of MeCab, its dictionary, NLTK,
or CMUdict. The sibling `misakid_mecab_ko` package supplies an explicit
no-Python macOS arm64 adapter. Its offline build verifies official MeCab-ko
source and applies a non-terminating safety overlay; callers pass absolute
paths to the resulting dylib, the exact 11-file Korean dictionary, and the
exact CMUdict data file. CMUdict parsing itself is pure Dart.

The production adapter matches all 34 original morphology streams and 293
surface/tag records, all 23 CMU lookups, all 33 successful final phoneme
outputs, and the pinned 17-digit failure. It also covers copied-result
ownership, concurrent isolates, lifecycle and bounds, resource tampering, and
silent native failure. No native binary or 116 MB of data is committed.
Support is precisely macOS 11+ arm64 with the documented resource tuple;
Linux, Windows, Intel macOS, embedded NUL, and runtime cancellation remain
unsupported.

`koreanPhonemeInventory` exposes the frozen 67-symbol modern conjoining-Jamo
inventory emitted by the default `to_syl=false` pipeline. Preserved non-Hangul
text, punctuation, and whitespace remain outside that phoneme inventory.

## Chinese modes

Chinese keeps the pinned legacy IPA renderer and version 1.1 Bopomofo-style
frontend as separate contracts. The sibling `misakid_chinese` package
completes legacy/default mode without Python or native code. It validates
explicit paths or immutable byte bundles for the exact Jieba 0.42.1 and
pypinyin 0.53.0 resources, while cn2an 0.5.23 normalization runs entirely from
Dart code:

```dart
import 'package:misakid_chinese/misakid_chinese.dart';

Future<G2pResult> convertChinese(String text) async {
  final backend = await PureDartChineseLegacyBackend.open(
    jiebaDictionaryPath: '/absolute/path/jieba/dict.txt',
    jiebaProbabilityStartPath: '/absolute/path/prob_start.p',
    jiebaProbabilityTransitionPath: '/absolute/path/prob_trans.p',
    jiebaProbabilityEmissionPath: '/absolute/path/prob_emit.p',
    pypinyinDictionaryPath: '/absolute/path/pinyin_dict.json',
    pypinyinPhrasesPath: '/absolute/path/phrases_dict.json',
  );
  return ChineseLegacyG2pEngine(backend: backend).convert(text);
}
```

The six files are not bundled, discovered, or downloaded. Their exact source
commits, sizes, checksums, counts, and MIT notices are recorded in
[`packages/misakid_chinese/RESOURCE_MANIFEST.md`](packages/misakid_chinese/RESOURCE_MANIFEST.md).
After asynchronous validation/loading, conversion is synchronous and offline.
All 24 accepted original-Misaki legacy cases pass exactly, including 22
phoneme strings, two pinned failures, 41 Jieba runs, 82 words/pinyin calls,
152 syllables, and null tokens.

Version 1.1 composes typed cn2an, exact Jieba POS/search, the pypinyin large
phrase overlay, and the pure ordered tone-sandhi and erhua stages. The sibling
package's `PureDartChineseFrontend11Backend.open` requires the four legacy
Jieba files, four POS HMM files, two pypinyin JSON dictionaries, and the exact
`large_pinyin.txt` resource. All eleven resources are explicit and validated;
`fromResources` accepts owned mobile byte bundles when paths are unavailable.
No Python or native library is used.

The accepted Chinese-only 26-case matrix matches every final phoneme string
and null outer token result, 24 number-normalization calls, 25 POS runs with
131 records, 365 pinyin calls with 746 values, and 107 search calls with 164
segments. The
supported no-callback configuration renders each mixed ASCII segment as the
selected unknown marker, exactly as pinned upstream. The callback profile is
separately accepted through `ChineseFrontend11EnglishG2pEngine`
and the pure-Dart `misakid_spacy_en` small-model adapter. Its 14-case matrix
matches all 14 ordered callback invocations, 40 raw tokenizer records, 33
final English tokens, exact outer phonemes, and null outer token lists across
American/British and legacy/2.0 rendering, multiple mixed segments,
punctuation, apostrophes/hyphens, context, OOV markers, full-width boundaries,
cn2an boundaries, and empty inputs. English preprocessing is fixed on and
fallback is fixed off for this precise supported profile.
`ChineseFrontend11.convertSegment` continues to expose the exact internal
Chinese tokens for diagnostics.

`chinesePhonemeInventory` exposes frozen source-derived scalar sets for the
distinct contracts: 38 legacy IPA/tone scalars and all 80 frontend-1.1 phone
map values. The legacy set excludes punctuation, whitespace, mixed-script
pass-through, and backend text. The 1.1 set includes its explicitly mapped
tone digits and structural punctuation, space, and slash. Configurable unknown
markers and injected English output are outside both inventories.

The compiling
[`example/chinese_injected.dart`](example/chinese_injected.dart) program shows
the injected core contracts; the adapter package has its own complete
resource-backed example and security/platform limits.

## Vietnamese injected pipeline

`VietnameseG2pEngine` bundles the reviewed cleaner dictionaries and pure
phonology for north, central, and south dialects. It exposes typed tone,
glottal, Phạm/Cao, palatal, substring, abbreviation, and acronym options,
preserves custom pronunciation controls and onset/nucleus/coda/tone/parent
metadata, and accepts an explicit underthesea-compatible tokenizer:

```dart
import 'package:misakid/misaki_vi.dart';

G2pResult convertVietnamese(
  String text,
  VietnameseTokenizerBackend tokenizer,
) {
  return VietnameseG2pEngine(
    tokenizer: tokenizer,
    options: const VietnameseOptions(dialect: VietnameseDialect.north),
  ).convert(text);
}
```

The cleaner runs offline with deterministic generated data and independent
clean-room number spelling. Its NFC, whitespace, lowercase/uppercase
expansions, supplementary casing, and Final_Sigma decisions do not depend on
the host Dart Unicode version. The NFC, case, and whitespace tables are an
exhaustively captured CPython-3.11.15/Unicode-14 candidate that still requires
the committed exact-3.11.13 comparisons before Vietnamese parity can be
claimed. `vietnamesePhonemeInventory()` returns the
frozen 139-entry upstream inventory. The compiling
[`example/vietnamese_injected.dart`](example/vietnamese_injected.dart) uses a
fixed tokenizer record.

Three 33-case no-English corpora and a strict typed underthesea replay schema
are prepared, but no output was fabricated when downloading the exact Python
3.11.13 oracle environment was not authorized. Consequently no authoritative
Vietnamese fixture or complete-mode parity is claimed. The package does not
bundle underthesea or an English fallback adapter; underthesea 6.8.4 is GPLv3
and its packaged CRF model lacks the precise independent lineage/license
record required for a Dart adapter. This remains an experimental injected
core.

## Hebrew injected facade

`HebrewG2pEngine` preserves the pinned `HEG2P` surface: exact text is forwarded
with explicit punctuation and stress flags, successful results always have
`tokens == null`, and backend inventory access is defensive and validated.

```dart
import 'package:misakid/misaki_he.dart';

G2pResult convertHebrew(String text, HebrewPhonemizerBackend backend) {
  return HebrewG2pEngine(
    backend: backend,
    options: const HebrewOptions(
      preservePunctuation: true,
      preserveStress: true,
    ),
  ).convert(text);
}
```

The package does not bundle, discover, invoke, or download Mishkal. Callers
must provide and validate a compatible backend explicitly, so the facade is an
experimental integration surface rather than a supported complete Hebrew
mode. Mishkal 0.3.2's exact artifacts are checksum-pinned, but its release
metadata declares no license and the later renamed Phonikud project does not
establish terms for that historical source/data snapshot. The compiling
[`example/hebrew_injected.dart`](example/hebrew_injected.dart) uses a fixed
record to demonstrate the public contract without pretending to be a real
Hebrew phonemizer.

## Shared G2P contract

Pure in-process engines implement `G2pEngine`; process- or model-backed
adapters implement the separate `AsyncG2pEngine` contract. Results preserve
the important distinction between unavailable token data (`null`) and an
available empty token list:

```dart
import 'package:misakid/misaki.dart';

G2pResult convertWith(G2pEngine engine, String text) {
  final result = engine.convert(text);
  // `result.phonemes` is exact: do not trim or normalize it.
  return result;
}
```

Language tokenizers, morphology analyzers, pinyin providers, native frontends,
and model fallbacks are explicit injected backends. The pure library does not
download resources, discover executables, invoke Python, or require Flutter.

## Development

Normal verification is offline after Dart dependencies have been resolved:

```sh
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
dart pub publish --dry-run
```

Python fixture generation is a separate, explicit workflow under
`tool/reference/`; parity tests consume committed fixtures rather than
regenerating expected results. Porting decisions and provenance are recorded
in [PORTING_NOTES.md](PORTING_NOTES.md) and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
The manifest-driven read-only aggregate currently verifies 431 cases across
17 accepted fixture files, with separate interpreters for English transformer,
transformer-plus-eSpeak, Cutlet, and the combined Chinese/English callback
oracles.

The versioned offline microbenchmark reports cold lexicon loading, warm p50/p95
latency, throughput, resident-memory deltas, and generated runtime-data size:

```sh
dart run benchmark/misakid_benchmark.dart --iterations=200
```

## License

Apache License 2.0. Adapted components and data retain their own notices in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
