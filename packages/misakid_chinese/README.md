# misakid_chinese

`misakid_chinese` supplies complete pure-Dart backends for Misaki 0.9.4's
legacy/default and frontend-1.1 Chinese G2P modes. It implements the exact
cn2an 0.5.23 number normalization, Jieba 0.42.1 accurate/HMM/POS/search
behavior, pypinyin 0.53.0 pronunciation styles, and pypinyin-dict 0.9.0 large
phrase overlay required by the platform-neutral `misakid` renderers.

There is no Python or native dependency. No dictionary is bundled, discovered,
or downloaded. Applications explicitly supply the checksum-pinned resources
from the tagged upstream releases as absolute file paths or immutable byte
bundles. Path loading uses a conditional `dart:io` implementation. Byte-backed
construction performs the same identity and schema validation without
`dart:io`, so callers can provide Flutter assets, web responses, or embedded
host data directly.

## Resources

Obtain these files from the immutable upstream source revisions:

- Jieba 0.42.1 commit
  `1e20c89b66f56c9301b0feed211733ffaa1bd72a`:
  `jieba/dict.txt`, `jieba/finalseg/{prob_start,prob_trans,prob_emit}.p`, and,
  for frontend 1.1, `jieba/posseg/{char_state_tab,prob_start,prob_trans,
  prob_emit}.p`;
- pypinyin 0.53.0 commit
  `e42dede51abbc40e225da9a8ec8e5bd0043eed21`:
  `pypinyin/pinyin_dict.json` and `pypinyin/phrases_dict.json`; and
- pypinyin-dict 0.9.0 commit
  `d8a12d70ea14a929f296f21f4c493b3ce5d0b14a` with its pinned
  phrase-pinyin-data submodule commit
  `3fa3308aeeadec0736d84f31b28ac3da6e98d0d9`:
  `tools/phrase-pinyin-data/large_pinyin.txt` for frontend 1.1.

See [RESOURCE_MANIFEST.md](RESOURCE_MANIFEST.md) for every exact byte length,
SHA-256, schema/count invariant, source-data commit, and license. Changed,
linked, truncated, malformed, or substituted resources fail during `open` or
`fromResources` with a typed Misaki exception.

## Use it

```dart
import 'package:misakid_chinese/misakid_chinese.dart';

Future<void> main() async {
  final backend = await PureDartChineseLegacyBackend.open(
    jiebaDictionaryPath: '/absolute/path/jieba/dict.txt',
    jiebaProbabilityStartPath:
        '/absolute/path/jieba/finalseg/prob_start.p',
    jiebaProbabilityTransitionPath:
        '/absolute/path/jieba/finalseg/prob_trans.p',
    jiebaProbabilityEmissionPath:
        '/absolute/path/jieba/finalseg/prob_emit.p',
    pypinyinDictionaryPath: '/absolute/path/pypinyin/pinyin_dict.json',
    pypinyinPhrasesPath: '/absolute/path/pypinyin/phrases_dict.json',
  );
  final engine = ChineseLegacyG2pEngine(backend: backend);
  print(engine.convert('你好，世界！').phonemes);
}
```

Frontend 1.1 uses a separate constructor because its resource and output
contract is observably different:

```dart
final backend = await PureDartChineseFrontend11Backend.open(
  jiebaDictionaryPath: '/absolute/path/jieba/dict.txt',
  jiebaProbabilityStartPath:
      '/absolute/path/jieba/finalseg/prob_start.p',
  jiebaProbabilityTransitionPath:
      '/absolute/path/jieba/finalseg/prob_trans.p',
  jiebaProbabilityEmissionPath:
      '/absolute/path/jieba/finalseg/prob_emit.p',
  jiebaPartOfSpeechCharacterStatePath:
      '/absolute/path/jieba/posseg/char_state_tab.p',
  jiebaPartOfSpeechProbabilityStartPath:
      '/absolute/path/jieba/posseg/prob_start.p',
  jiebaPartOfSpeechProbabilityTransitionPath:
      '/absolute/path/jieba/posseg/prob_trans.p',
  jiebaPartOfSpeechProbabilityEmissionPath:
      '/absolute/path/jieba/posseg/prob_emit.p',
  pypinyinDictionaryPath: '/absolute/path/pypinyin/pinyin_dict.json',
  pypinyinPhrasesPath: '/absolute/path/pypinyin/phrases_dict.json',
  pypinyinLargePhrasesPath:
      '/absolute/path/phrase-pinyin-data/large_pinyin.txt',
);
final engine = ChineseFrontend11G2pEngine(backend: backend);
print(engine.convert('你好，世界！').phonemes);
```

When resources already exist in memory, construct an immutable typed snapshot
and parse it synchronously without filesystem access:

```dart
import 'dart:typed_data';

PureDartChineseLegacyBackend legacyFromBytes({
  required Uint8List jiebaDictionary,
  required Uint8List jiebaProbabilityStart,
  required Uint8List jiebaProbabilityTransition,
  required Uint8List jiebaProbabilityEmission,
  required Uint8List pypinyinDictionary,
  required Uint8List pypinyinPhrases,
}) => PureDartChineseLegacyBackend.fromResources(
  ChineseLegacyResourceBundle(
    jiebaDictionaryBytes: jiebaDictionary,
    jiebaProbabilityStartBytes: jiebaProbabilityStart,
    jiebaProbabilityTransitionBytes: jiebaProbabilityTransition,
    jiebaProbabilityEmissionBytes: jiebaProbabilityEmission,
    pypinyinDictionaryBytes: pypinyinDictionary,
    pypinyinPhrasesBytes: pypinyinPhrases,
  ),
);
```

`ChineseFrontend11ResourceBundle` provides the corresponding eleven-resource
snapshot for `PureDartChineseFrontend11Backend.fromResources`. Both bundle
types defensively copy their inputs and expose only unmodifiable typed copies.

Path initialization is asynchronous because it reads and validates about 9.7
MB of source data. Byte-backed initialization is synchronous. Conversion is
synchronous, offline, and in-process afterward.
Reuse a backend rather than reparsing resources for every string. The parsed
tables are immutable to callers and retained for the backend's lifetime.

Jieba segmentation accepts at most 65,536 Unicode scalars per Basic-CJK run;
pypinyin accepts at most 65,536 scalars per word. Paths must be absolute,
valid Unicode without NUL, at most 32,768 UTF-8 bytes, and point directly to
regular non-link files. The probability loader recognizes only the inert
protocol-0 map/float/string/memo opcode subset used by the pinned Jieba files;
it cannot construct objects or execute pickle reducers or globals.

Frontend-1.1 initialization validates about 24.3 MB across eleven files.
With no `englishG2p`, each outer ASCII-English segment becomes the selected
unknown marker, exactly as pinned Misaki behaves after its constructor
warning.

For the accepted pure-Dart small-model callback profile, also depend on and
import `package:misakid_spacy_en/misakid_spacy_en.dart`, then compose the two
explicit resource backends:

```dart
final english = await PureDartSpacyEnglishTokenizerBackend.open(
  modelDirectoryPath: '/absolute/path/en_core_web_sm-3.8.0',
);
final mixedEngine = ChineseFrontend11EnglishG2pEngine(
  chineseBackend: backend,
  englishTokenizer: english,
  englishDialect: EnglishDialect.american,
  englishPhonemeVersion: EnglishPhonemeVersion.legacy,
);
print(mixedEngine.convert('你好 Hello world').phonemes);
```

This profile always enables pinned English preprocessing and disables English
fallback. American/British and legacy/2.0 rendering are explicit. The outer
token list remains `null`; English token details are an internal callback
result and are covered by the parity fixture.

## Verified behavior

The provisioned test suite compares all provider stages and final output with
the committed fixture generated by original Misaki 0.9.4 at commit
`fba1236595f2d2bf21d414ba6e57d25256afada3`:

- all 24 legacy inputs;
- all 22 successful exact phoneme strings and `tokens == null` values;
- both pinned transcription failures;
- 22 cn2an normalization calls;
- 41 Jieba runs and 82 segmented words;
- 82 pypinyin calls and 152 syllables; and
- a direct live replay of those 41 runs through original Jieba 0.42.1.

The frontend-1.1 profile additionally matches all 26 accepted inputs and null
outer-token results, 24 cn2an calls, 25 POS runs with 131 records, 365 captured
pypinyin calls with 746 values, and 107 Jieba search calls with 164 values.
This includes tone sandhi, neutral tone, erhua, large/custom phrase overrides,
rare characters, punctuation, number/date/phone normalization, and mixed
English without an English callback.

The small-model mixed-English profile additionally matches all 14 accepted
cases, all 14 ordered callback invocations, 40 raw tokenizer records, and 33
final English token records. Its matrix covers American/British and
legacy/2.0 rendering, multiple mixed segments, punctuation splitting,
apostrophes, hyphens, context, OOV markers, full-width boundaries, cn2an
boundaries, and both empty fast paths.

The cn2an stage also passed a deterministic 44,000-case differential against
the pinned Python package. Synthetic tests cover DAG/Viterbi tie-breaking,
strict UTF-8/JSON/resource parsing, immutable outputs, Unicode boundaries,
tampering, symbolic links, bounds, and rejection of executable pickle
opcodes.

## Licensing

New Dart code is Apache-2.0. The adapted cn2an, Jieba, pypinyin, pinyin-data,
and phrase-pinyin-data behavior/data are MIT-licensed. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and `licenses/`.
