# Third-Party Notices

This document is both the current notice file and the provenance review ledger
for material that may be used by the port. A name in the review ledger does
not mean that the named work is currently distributed by Misakid, and it does
not establish permission to copy it.

The Dart implementation now contains pure-Dart adaptations of the Japanese
number converter and pyopenjtalk-style rendering pipeline; English pipeline
stages; Chinese transcription, legacy rendering, and text normalization; and
the Korean rule pipeline, Vietnamese cleaner/phonology pipeline, and Hebrew
backend boundary. The repository includes
exact canonical copies and deterministic pure-Dart runtime embeddings of the
four Apache-licensed English lexicons, the reviewed Vietnamese dictionaries
and tables, and Unicode 15 normalization and scalar property data, plus
executable-reference tooling and derived parity fixtures. It contains no model,
compiled native artifact, or bundled external dictionary. The pure root
package has no production Pub dependency; optional sibling adapters use the
reviewed pure-Dart `crypto` package for SHA-256 validation. The root Apache
License 2.0 text has been carried into `LICENSE`. This file
must be updated whenever further upstream-derived code or data is introduced.

## Misaki reference implementation

- Work: Misaki, a G2P engine for Kokoro models
- Source: https://github.com/hexgrad/misaki
- Pinned revision: fba1236595f2d2bf21d414ba6e57d25256afada3
- Python package version: 0.9.4
- Project metadata author: hexgrad
- License declared by the pinned project: Apache License 2.0
- License file SHA-256:
  c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4

The pinned repository has no root NOTICE file. Apache-licensed material later
adapted into this port must retain applicable copyright and attribution
notices, carry a prominent modification notice, and remain accompanied by the
Apache License 2.0 text.

## Kokoro frontend compatibility source

- Work: Kokoro inference library and G2P frontend chunking
- Source: https://github.com/hexgrad/kokoro
- Reviewed revision: dfb907a02bba8152ca444717ca5d78747ccb4bec
- Python package version: 0.9.4
- License declared by the reviewed project: Apache License 2.0

The root Dart library adapts only the platform-neutral text and phoneme
chunking behavior from `kokoro/pipeline.py`: the English token-aware
510-code-point punctuation waterfall, the distinct non-English pre-G2P
400-code-point sentence target, and the default line-feed segmentation. It
does not include Kokoro model code, weights, voices, vocabulary data, ONNX,
PyTorch, audio processing, or download behavior. The adaptation uses immutable
Misaki types and explicitly matches Python code-point semantics, including
preservation of isolated UTF-16 surrogates; its source and modification header
is retained in `lib/src/core/kokoro_frontend.dart`.

## Provenance and license review ledger

### Japanese

- Pinned `misaki/cutlet.py` identifies
  https://github.com/polm/cutlet/blob/main/cutlet/cutlet.py and the original
  MIT license. Its algorithm follows Cutlet's pre-node-refactor structure. The
  exact reviewed source state is commit
  https://github.com/polm/cutlet/commit/d03f11c52a7cc7ed29a17d538e9271d693cb1cd0,
  dated 2022-12-03 and the direct parent of the node-building refactor. At that
  revision `cutlet/cutlet.py` has SHA-256
  `6d770296fdff8f68a8788da075004f9e93357088af465beda307e63a3bdb9b35`
  and `cutlet/mapping.py` has SHA-256
  `e6f70dfacbee56bdcefe230473b96da71b1d255b02d2b07be8185b7b9ca44162`.
  Pinned Misaki combines and substantially modifies those files; its
  `cutlet.py` has SHA-256
  `7695fc7d853ae4e99679dff4ca0c8404d4804a6fb1059a9d6ad02baeabc4d4de`.
  Changes include IPA-oriented mappings, number handling, custom grouping and
  spacing, reduced configuration, and different moraic-nasal/sokuon output.
  There is no byte-identical Cutlet revision.

  Cutlet's MIT `LICENSE` has SHA-256
  `8736ad0d4636cb6dabae3e97e99c08f5c0c08b8c451f1d489b29a0d63bebf074`
  and names “Copyright (c) 2020 Paul O'Leary McCann.” Its complete notice is
  retained below.
- misaki/num2kana.py says it was copied from
  https://github.com/Greatdane/Convert-Numbers-to-Japanese/blob/master/Convert-Numbers-to-Japanese.py
  and labels the original license MIT. The source repository has now been
  reviewed at
  https://github.com/Greatdane/Convert-Numbers-to-Japanese/commit/c01b072e8d52c89c307dcbcb69958d05e953d4c1,
  the master revision observed on 2026-07-10 and the closest source revision
  to the pinned Misaki file. At that revision:

  - Convert-Numbers-to-Japanese.py has SHA-256
    4ccfb28eba3a48986fbf259d35b8e677c3196cfb1805cf6bb1640e901f90256a.
    The permanent source URL is
    https://github.com/Greatdane/Convert-Numbers-to-Japanese/blob/c01b072e8d52c89c307dcbcb69958d05e953d4c1/Convert-Numbers-to-Japanese.py.
  - LICENSE has SHA-256
    a2d0e21948ca52f09926d17de411f1d989bf7b99ec05deb668c0358ce5196e57
    and contains the MIT License with “Copyright (c) 2018 David Wilson,
    https://github.com/Greatdane”. The permanent license URL is
    https://github.com/Greatdane/Convert-Numbers-to-Japanese/blob/c01b072e8d52c89c307dcbcb69958d05e953d4c1/LICENSE.
  - The license was introduced by Greatdane commit
    https://github.com/Greatdane/Convert-Numbers-to-Japanese/commit/11bd7afa787a91ab8a443fda173937288d2604ea.

  No exact Greatdane revision matches pinned Misaki num2kana.py. The reviewed
  Greatdane repository has 14 reachable commits, one remote branch, and no
  tags. Pinned Misaki num2kana.py has SHA-256
  26ca4b39ac7165104e53971bd2459df6466ff8140e1dac836a3bf1f9e811e2d2;
  after removing its two provenance header lines, its body has SHA-256
  5418ec0b22c8cbd1e6740175e8838b566185027eb050e6a16848051d162f7e45.
  That body differs from c01b072e8d52c89c307dcbcb69958d05e953d4c1 in
  exactly two lines:
  it raises an assertion instead of returning the “Not yet implemented”
  string for an oversized len_x input, and it gives Convert a default
  dict_choice of hiragana. Both changes were already present when num2kana.py
  first entered Misaki in
  https://github.com/hexgrad/misaki/commit/fdc9c5e5ec74a9fbb81e02bd487d0fb8bd8e4ec8.
  Later Misaki commits only strengthened the provenance header.

  Accordingly, provenance for the pinned behavior is Greatdane commit
  c01b072e8d52c89c307dcbcb69958d05e953d4c1 plus the two modifications first
  recorded in Misaki commit fdc9c5e5ec74a9fbb81e02bd487d0fb8bd8e4ec8;
  there is no single byte-identical Greatdane source revision. The MIT notice
  required for derived material appears below.
- The authoritative Cutlet compatibility artifact is
  `misaki/data/ja_words.txt` at the pinned Misaki revision:
  https://github.com/hexgrad/misaki/blob/fba1236595f2d2bf21d414ba6e57d25256afada3/misaki/data/ja_words.txt.
  It first appears in Misaki commit
  https://github.com/hexgrad/misaki/commit/fdc9c5e5ec74a9fbb81e02bd487d0fb8bd8e4ec8
  (`CJK`, 2025-01-12). The commit history has no earlier revision, and neither
  the file, that commit's README additions, nor the introducing pull request
  https://github.com/hexgrad/misaki/pull/4 identifies a source, generator, or
  data license. The exact artifact has Git blob
  `fb3b5b1f87e8dcf113857f96ffe845869a616908`, is 1,921,140 bytes, contains
  147,571 sorted unique UTF-8 records without a terminal newline, and has
  SHA-256
  `a93a8e8aee24db307a32becb8bf01c4c2908ecf37e6c91f7a705fafdfeba67ff`.

  A differential review provides strong but non-authoritative evidence that
  this is a filtered January 2025-era snapshot of the Japanese data published
  by Kaikki/Wiktextract from English Wiktionary. The reviewed current
  postprocessed Kaikki JSONL was downloaded from
  https://kaikki.org/dictionary/Japanese/kaikki.org-dictionary-Japanese.jsonl;
  it is 375,723,746 bytes with SHA-256
  `b3ed9c3e44f7fa37f3dbc96725b217cdd7e6dd1fc1a35027df0e35252819283c`.
  Collecting every top-level `word` and every `forms[].form`, retaining strings
  of length at least two that fully match
  `[々\u3040-\u30FF\u4E00-\u9FFF]+`, and deduplicating produces a current
  candidate set containing 146,737 of the 147,571 pinned records: 99.4348%.
  Of those matches, 85,647 now occur only as forms rather than top-level
  words. The current candidate set also has 433,041 additional values, and 834
  pinned records are absent. These facts and the old-looking generated
  inflections among the missing records support the snapshot hypothesis; they
  do not prove the exact historical dump, extractor revisions, or generation
  command. No byte-identical January Kaikki input was recovered, so this
  relationship must remain labeled an inference.

  Kaikki states that its data is extracted from Wiktionary and made available
  under the same CC-BY-SA and GFDL licenses:
  https://kaikki.org/dictionary/index.html. English Wiktionary identifies the
  versions as Creative Commons Attribution-ShareAlike 4.0 International and
  GNU Free Documentation License 1.1 or later:
  https://en.wiktionary.org/wiki/Wiktionary:Copyrights. CC BY-SA 4.0's
  attribution, ShareAlike, and database-right conditions are at
  https://creativecommons.org/licenses/by-sa/4.0/legalcode.en. Because the
  exact Kaikki derivation is inferred rather than proven, this notice does not
  relicense the Misaki artifact or claim byte-identical Kaikki provenance.
  Anyone redistributing it should conservatively preserve Misaki and
  Wiktionary/Kaikki attribution and comply with an applicable upstream data
  license.

  Misakid deliberately does not vendor, generate from, download, or
  redistribute `ja_words.txt`. An optional adapter may instead require the
  caller to provide this exact external artifact explicitly and validate its
  pinned SHA-256, byte length, record count, and format before use. The adapter
  must not discover or substitute a mutable copy. This external-resource
  resolution avoids redistribution by Misakid; it is not a license grant for
  the caller's copy.
- The optional `packages/misakid_openjtalk` adapter builds against the exact
  `pyopenjtalk==0.4.1`
  source distribution: 1,397,999 bytes, SHA-256
  `d5ada46f7fc2b52c1c79c273eb9668ff6ad7ab276a8db9d8be119ef93440f0dc`.
  Its MIT `LICENSE.md` has SHA-256
  `c38083a4d51c1ea86e08b3303a984d0c23718c5ac214058af705814d30f4bb5b`.
  The vendored Open JTalk modified-BSD `COPYING` has SHA-256
  `14f380a0db8dce139fdcfb731d21e993a31a00b68907515d1c54a5f356241343`,
  and its embedded MeCab BSD notice has SHA-256
  `05e94c185a3e31f0c658f7011132be952b6d1a4d588b682f92da380e0a290650`.
  The Open JTalk 1.11 dictionary's NAIST, UniDic Consortium, and HTS Working
  Group notice has SHA-256
  `f4eca42ebd930e2c6e57fca58319d989bebcd1510cb7714b149c50f5425135ea`.
  The extracted 139-file Open JTalk source tree has canonical relative-path
  aggregate SHA-256
  `dea0f240fad8dc8b9ea1984920a4d64a48227a40c2924a3c545eaeca50357857`.
  The adapter distributes the exact 139-file, 5,382,103-byte post-safety-patch
  source tree with aggregate SHA-256
  `8ce47a975dee79c078914df15c40df5906430e4a63be4fc2bc0987e7b5b2fccb`,
  its new Apache-2.0 shim/build tooling, and exact copies of the four reviewed
  license notices. It distributes no dictionary, compiled binary, HTS engine,
  or voice. Android consumer builds statically link the NDK LLVM libc++ under
  Apache-2.0 with the LLVM exception; that exception is retained under
  `native/licenses/`. The offline source verifier, compiled component list,
  `misakid-openjtalk-safety-v1` patch set, prominent modification record, and
  complete notices are in
  `packages/misakid_openjtalk/native/` and its `THIRD_PARTY_NOTICES.md`.
- The optional `packages/misakid_mecab_ja` adapter uses the same exact
  `pyopenjtalk==0.4.1` source distribution but compiles only its standard
  16-file MeCab 0.996 runtime plus a new Apache-2.0 owned-result shim. The
  complete staged 139-file source identity is
  `dea0f240fad8dc8b9ea1984920a4d64a48227a40c2924a3c545eaeca50357857`.
  Its explicit UniDic 3.1.0 resource is the 20-file, 811,662,881-byte tree
  with SHA-256
  `95bd65fa96955b644c15510932ca8439f463ac8b66f57bac6dfee5e29fa03115`;
  no dictionary bytes are distributed. The adapter retains the exact
  pyopenjtalk MIT notice, MeCab BSD notice, UniDic BSD-option notice, jaconv
  MIT notice, and Cutlet MIT notice under `native/licenses/`. Their SHA-256
  values are respectively
  `c38083a4d51c1ea86e08b3303a984d0c23718c5ac214058af705814d30f4bb5b`,
  `05e94c185a3e31f0c658f7011132be952b6d1a4d588b682f92da380e0a290650`,
  `770a75de30705439084f869dbcb0bc4ebcffcb7c7124c0d74f5083170318a9bb`,
  `3ce05b9340c7f51a5085c657dd790ea1e864290b66a88fe07bb6ffa1b8681ad0`,
  and `8736ad0d4636cb6dabae3e97e99c08f5c0c08b8c451f1d489b29a0d63bebf074`.
  The adapter distributes no source tree, dictionary, grouping list, or
  compiled binary; its independent manifest and notices travel with the
  sibling package.

The Greatdane/Misaki number-conversion behavior is included in the Dart
library at lib/src/languages/ja/number_converter.dart. That file carries a
source and modification header, and the copyright and permission notice below
applies to it. Cutlet code may now be adapted under the reviewed MIT notice.
`ja_words.txt` remains excluded from Misakid's distributed files; a Cutlet
adapter may either receive already-grouped morphology records through a typed
backend or validate the exact caller-supplied external artifact described
above.

#### Cutlet MIT notice

MIT License

Copyright (c) 2020 Paul O'Leary McCann

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

#### Convert-Numbers-to-Japanese MIT notice

The MIT License (MIT)

Copyright (c) 2018 David Wilson, https://github.com/Greatdane

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

### Korean

Pinned Misaki `misaki/g2pkc/README.md` identifies
https://github.com/5Hyeons/StyleTTS2/tree/vocos/g2pK/g2pkc as its immediate
source and https://github.com/Kyubyong/g2pK as the earlier project. The exact
immediate source snapshot reviewed for this port is StyleTTS2 `vocos` commit
https://github.com/5Hyeons/StyleTTS2/commit/a895e5bff1d7a22dff2f2d32dafb7c4c4e0ee4b7,
dated 2024-12-20. Its last two commits affecting `g2pK/g2pkc` are the initial
import `eed9ef2c59e4a3f1e6f3100d308fb718abed777f` and the idiom update
`3e8a5c8b0623be4b2c432cec9ac8b499c0aba1cd`.

Every code and data file below is byte-for-byte identical between that
StyleTTS2 snapshot and pinned Misaki. Misaki adds only its provenance README:

| `g2pkc` file | SHA-256 |
| --- | --- |
| `__init__.py` | `da28d02dc1522ffa1ee96c44cc9aa954b85a1945c289c4ea4a594cfab95a2097` |
| `english.py` | `b484b8dbd9cd3f8296a200255874072cf021147e495f1017f65d4e0a342df062` |
| `g2pk.py` | `e2685e1fbc5ef32addd43edbef833734f311d47060533e6c8b0014ef70269970` |
| `idioms.txt` | `d49682e430bf7743715d0510a5e1b32cd902db80fcdeaea783d9abcaec3f7ac5` |
| `numerals.py` | `cf0d8bbca3750ff53289a9386afc223bfcd8ed3ce9c6a288a9ee997899000581` |
| `regular.py` | `8e376b276548d915d281cf75d2b1574e03eb660f00b8b04d7086434d5b030fe9` |
| `rules.txt` | `b7e6b3ddeec1b1406aac0ba98665da9921a2088faaf4843a1f8120e83c4ce33f` |
| `special.py` | `b582ba792e3e63776f78ea5e535223bede0bd379cf35a7b4092c602d6597a9cb` |
| `table.csv` | `61aca8535fd75f16ca71df59bc5eeab625073edfd50732fda3f12b30ccade31f` |
| `utils.py` | `4fc55b1cdee023b48ba5b91f7a628e9c0bb573ed618d942d8e50519bb4f9a4a5` |

The immediate source includes `g2pK/LICENSE`, Apache License 2.0, with SHA-256
`c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4`.
It is byte-identical to both Kyubyong/g2pK's license at reviewed commit
https://github.com/Kyubyong/g2pK/commit/3bb9d5afc5159220d5d16492aca7a58f121b6073
and this package's root `LICENSE`. Kyubyong/g2pK's package metadata identifies
Kyubyong Park as author and declares Apache License 2.0; no NOTICE file is
present in either reviewed subtree.

This resolves the Korean code-and-data license blocker for material derived
from these exact files. A Dart adaptation must identify the two source
revisions above, carry a prominent modification notice, retain applicable
attribution, and keep the root Apache License. This package now includes Dart
adaptations of those files plus byte-for-byte canonical copies of
`idioms.txt` and `table.csv` under `tool/upstream_data/`; runtime tables are
deterministically generated from those checksum-pinned inputs.

The optional `packages/misakid_mecab_ko` adapter does not reuse the opaque
wheel dylib from the feasibility proof. Its offline verifier accepts only the
official Eunjeon `mecab-0.996-ko-0.9.2` release archive, SHA-256
`d0e0f696fc33c2183307d4eb87ec3b17845f90b81bf843bd0981e574ee3c38cb`,
tagged at commit `908db8de3cb5f4931b4e3a7a5a3894daefb98c37`, and redistributes the
native build under upstream's BSD option. The safety-modified source and
binary notices, exact source-tree identities, and selected BSD text are in
that package's `native/` directory.

The adapter accepts only the exact 11-file UTF-8 dictionary distributed by
`python-mecab-ko-dic==2.1.1.post2`: 112,191,702 bytes, canonical tree SHA-256
`d851fab8708745442ac3a2d970851dbd0ef598e786a363f406847461d77a6f51`,
816,283 entries, and binary version 102. The data is not bundled; its
Apache-2.0 license and full per-file manifest are retained by the sibling
package.

The exact extracted CMUdict 0.7a data used by the feasibility proof is
3,820,830 bytes with SHA-256
`cad209c39eb87677d64e93d97f8eed10b7e6f9bdd42de8e7ca8efc8e17d62e8a`;
its source ZIP identity is already recorded by the Korean fixture as SHA-256
`d07cca47fd72ad32ea9d8ad1219f85301eeaf4568f8b6b73747506a71fb5afd6`.
Its packaged README contains the CMUdict redistribution notice. The sibling
package retains that exact notice and provides a pure-Dart checksum/count
validated parser, but no CMUdict data is shipped by Misakid. The notice must
accompany any redistribution.

### Chinese

#### pinyin-to-IPA transcription

Pinned Misaki misaki/transcription.py says it was adapted from
https://github.com/stefantaubert/pinyin-to-ipa/blob/master/src/pinyin_to_ipa/transcription.py
and identifies the original license as MIT.

The reviewed source revision is
https://github.com/stefantaubert/pinyin-to-ipa/commit/ef81b82bfa42601300463c50a5db063d3b47e347,
dated 2024-06-12. It was the last transcription.py revision before Misaki
introduced its copy on 2025-01-12. Permanent source and license links are:

- https://github.com/stefantaubert/pinyin-to-ipa/blob/ef81b82bfa42601300463c50a5db063d3b47e347/src/pinyin_to_ipa/transcription.py
- https://github.com/stefantaubert/pinyin-to-ipa/blob/ef81b82bfa42601300463c50a5db063d3b47e347/LICENSE

At that revision, transcription.py has SHA-256
ccd34a249a718759451a9e6240332eb9b54d1ecad88a1b939efb0b7bad3cb114
and LICENSE has SHA-256
0bc847bdc29b0ba04afb7ef9660dc0ba9b8796a9a7a814d106db5aa373a8a86d.
The license is MIT with “Copyright (c) 2024 Stefan Taubert.”

No pinyin-to-IPA revision exactly matches the pinned Misaki body. All 13
reachable transcription.py revisions were compared. Pinned Misaki
transcription.py has SHA-256
14f0f1b5eb89c5b684229a30ae8b0c19c8266b537967786a2079ba887f5fbc32;
after removing its two provenance lines, its body has SHA-256
332a842672ceedeb7bdec8c8d0275639ce174b243967522d073e9bb08a5b967e.
Relative to ef81b82bfa42601300463c50a5db063d3b47e347, Misaki changes exactly
six INITIAL_MAPPING entries: tsʰ to ʦʰ, ʈʂʰ to U+AB67 followed by ʰ, tɕ to
ʨ, tɕʰ to ʨʰ, ts to ʦ, and ʈʂ to U+AB67. Those changes were already present
when the file entered Misaki in
https://github.com/hexgrad/misaki/commit/fdc9c5e5ec74a9fbb81e02bd487d0fb8bd8e4ec8.

Accordingly, the precise provenance is pinyin-to-IPA commit
ef81b82bfa42601300463c50a5db063d3b47e347 plus the six symbol changes first
recorded in Misaki commit fdc9c5e5ec74a9fbb81e02bd487d0fb8bd8e4ec8.
The required MIT notice appears below.

##### pinyin-to-IPA MIT notice

MIT License

Copyright (c) 2024 Stefan Taubert

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

#### PaddleSpeech Mandarin frontend

Pinned Misaki misaki/zh_frontend.py and misaki/tone_sandhi.py say they were
adapted from PaddleSpeech. misaki/zh_normalization/README.md says that its
directory was copied from PaddleSpeech.

The coherent source snapshot is PaddleSpeech commit
https://github.com/PaddlePaddle/PaddleSpeech/commit/d7bf91561d5a8a025f3cfc4bd7b28368fd98d102,
dated 2025-02-26T16:46:34+08:00. It is the last develop commit before Misaki
introduced all three components together in
https://github.com/hexgrad/misaki/commit/5eacea3db093e80a0e74913a10b724526158c008.
The last prior commit changing zh_frontend.py and tone_sandhi.py was
https://github.com/PaddlePaddle/PaddleSpeech/commit/cb0ba54d6ed592d8e00d4db5a32aa24a00b7477b;
the last prior commit changing zh_normalization was
https://github.com/PaddlePaddle/PaddleSpeech/commit/6f8438818936380dde33d445cabe0e2626e05573.

Permanent source links at the coherent snapshot are:

- https://github.com/PaddlePaddle/PaddleSpeech/blob/d7bf91561d5a8a025f3cfc4bd7b28368fd98d102/paddlespeech/t2s/frontend/zh_frontend.py
- https://github.com/PaddlePaddle/PaddleSpeech/blob/d7bf91561d5a8a025f3cfc4bd7b28368fd98d102/paddlespeech/t2s/frontend/tone_sandhi.py
- https://github.com/PaddlePaddle/PaddleSpeech/tree/d7bf91561d5a8a025f3cfc4bd7b28368fd98d102/paddlespeech/t2s/frontend/zh_normalization
- https://github.com/PaddlePaddle/PaddleSpeech/blob/d7bf91561d5a8a025f3cfc4bd7b28368fd98d102/LICENSE

PaddleSpeech's LICENSE at that revision is Apache License 2.0, has SHA-256
c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4,
and is byte-identical to this package's root LICENSE. The source snapshot has
no root NOTICE file.

PaddleSpeech zh_frontend.py has SHA-256
d5f2391637ff103a2063c4458ab43457e44ec66731f054e21a29d13a9bdb9b94.
No exact source revision matches pinned Misaki zh_frontend.py. After removing
Misaki's two provenance lines, the pinned body has SHA-256
b468b7c3a4f62f32a5dff26fbb622c1b8ebc6ea480803263b2fe1b52a209ba46
and differs from the coherent source by 91 inserted and 612 deleted lines.
The file is therefore a substantial adaptation, not a copy.

PaddleSpeech tone_sandhi.py has SHA-256
61a11983e42b98c3d6ddcae1108d1f628f439e44569382932b68f68f23dc3e51.
No exact source revision matches pinned Misaki tone_sandhi.py. After removing
Misaki's two provenance lines, the pinned body has SHA-256
1897618f4e39035dad3e291781dc16756e46cc6ec6c499e2b5ba4f915158a400
and differs from the coherent source by 37 inserted and 24 deleted lines. The
changes primarily add mixed-English boundaries to the 不, 一, third-tone,
erhua, and reduplication merge logic.

The normalization directory is much closer to an exact copy:

| Pinned Misaki file | PaddleSpeech file | SHA-256 at d7bf9156 | Match status |
| --- | --- | --- | --- |
| README.md | README.md | f861937c41df6fbe711923a1829e12d62b3abe5300fc173091cd87d115e10d28 | Exact after removing Misaki's two-line provenance prefix. |
| __init__.py | __init__.py | 3fd43b04ff5379045ebe1dbf3411e2c0a6f8e4ae0ddb267b5fb2f97c4f9a131c | One import line changed from PaddleSpeech's absolute misspelled path to Misaki's relative corrected path. |
| char_convert.py | char_convert.py | 84341ec93b420a28467ccfee223d23e262f7ee0a4da00402f662c656b119e190 | Byte-identical. |
| chronology.py | chronology.py | 29d1ec8e40cffa5b16df3363fc8ac2365835b7bfaffd4d25a0f566f202fb03fc | Byte-identical. |
| constants.py | constants.py | ece961dc87507038fbbe88d5342159570aa5b2c5b40d74c3110ae1eb9a663523 | Byte-identical. |
| num.py | num.py | 68e020afa07fb0649fd6bf7be8658011f112465bbdf1b3e8cf13dbd10efff539 | Byte-identical. |
| phonecode.py | phonecode.py | f85112737ead372fc834cf189fcb076b9fdf0821a55191168df8f15d2471348b | Byte-identical. |
| quantifier.py | quantifier.py | e2eb980bb14f485f0f828b0c762b73742606638b65433257de421d0e061c3336 | Byte-identical. |
| text_normalization.py | text_normlization.py | af667225b44b5ef1ba70f427ab9f48bdb2af736cbd56c3e895bc8025507598d9 | Byte-identical content under a corrected filename. |

The copied files retain either “Copyright (c) 2020 PaddlePaddle Authors. All
Rights Reserved.” or “Copyright (c) 2021 PaddlePaddle Authors. All Rights
Reserved.” and the full Apache License 2.0 source header. Any Dart adaptation
must retain the applicable copyright and attribution notice, carry a prominent
modification notice, and remain accompanied by the package's root Apache
License 2.0 text. The exact notices to retain are:

Copyright (c) 2020 PaddlePaddle Authors. All Rights Reserved.

Copyright (c) 2021 PaddlePaddle Authors. All Rights Reserved.

Each applicable copyright line appears with this source notice:

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

The Chinese transcription, legacy engine, text normalization, generated
`char_convert.py` mapping, tone-sandhi rules, and full pure 1.1 frontend
described above are included as Dart adaptations.

#### Pure-Dart legacy resource backend

The optional `packages/misakid_chinese` workspace package adds exact Dart
adaptations of the three external stages used by legacy/default mode. It
bundles no dictionary or probability data and never discovers or downloads a
resource. Its complete resource manifest and notices are in that package.

- cn2an 0.5.23's `an2cn` sentence path is MIT-licensed, Copyright (c) 2017
  Ailln. The retained exact license has SHA-256
  `b18d8d4ad8bc57e00ae80d08d9da80a32176f031062f87c739ea7557c1b5d759`.
- Jieba 0.42.1 is pinned at commit
  `1e20c89b66f56c9301b0feed211733ffaa1bd72a` under its MIT license,
  Copyright (c) 2013 Sun Junyi. The committed license differs from upstream's
  1,075-byte file only by one terminal LF and has SHA-256
  `522d429662141688e69562df3ef47acb29ed1a3d28147e1c643420740e4e94cc`.
  Callers supply the exact 5,071,852-byte `dict.txt` plus three finalseg
  probability files; all four identities are recorded in
  `packages/misakid_chinese/RESOURCE_MANIFEST.md`.
- pypinyin 0.53.0 is pinned at commit
  `e42dede51abbc40e225da9a8ec8e5bd0043eed21` under MIT terms, Copyright
  (c) 2016 mozillazg and 闲耘. Its license SHA-256 is
  `1e6c90014b4912815c296ee64bb6f6280af47e6d4c5d80e86232dfc5defe764c`.
  The exact caller-supplied JSONs derive from MIT-licensed pinyin-data commit
  `27dc54a206326e0d8d91428010325f50f614508d` and phrase-pinyin-data commit
  `1114cb9372804062e79d8b78affd333df41bf599`; their retained license hashes
  are respectively
  `9c048697be2502a16e8bcb282d5d465a07295b2def0ffb05a269c5d39dbe1586`
  and
  `89ac55df747e4776088c3e77531ef61b973a1a59dd8e6a4548a58996da9a4f70`.

The frontend-1.1 part-of-speech/search/large-pinyin runtime stages remain
injected only and are not included.

### Vietnamese

#### Viphoneme phonemizer

Pinned Misaki's README identifies https://github.com/v-nhandt21/Viphoneme as
the Vietnamese phonemizer's source. The reviewed source revision is
https://github.com/v-nhandt21/Viphoneme/commit/616a505fdbe83b23bd30a358819e6dded0e1de4a,
dated 2024-06-21 and preceding Misaki's first Vietnamese commit. Its
`viphoneme/T2IPA.py` has SHA-256
`53b905af48efd455f2a89de7fede302058c08b4520c219ed012e7871eba8dd15`.
Pinned Misaki `vi.py` has SHA-256
`be333eac8211063eafd3304b13eafa2f2250af0a950b47f231f7758fb08d951e`
and is a substantial adaptation and reduction, not an exact copy.

Viphoneme's `LICENSE` has SHA-256
`ce1e3ba903180af595f06d37ad94e858bfb62d647bb35b8760d580585a51d4cd`
and contains an MIT permission grant with “Copyright (c) 2019 The Python
Packaging Authority” followed by “This project is belong to AILAB, Ho Chi
Minh University of Science.” That complete notice is retained below.

#### Vietnamese cleaner and dictionaries

Pinned `misaki/vi_cleaner/README.md` identifies
https://github.com/CodeLinkIO/Vietnamese-text-normalization as the cleaner's
source. The reviewed source revision is
https://github.com/CodeLinkIO/Vietnamese-text-normalization/commit/4f7b9ea525de73b95838700abab33b68a96bfe85,
dated 2022-07-28. Its MIT `LICENSE` has SHA-256
`5d575b176338ada1bdae09bc827f6b5de36c8db00fb9a6f83f2c9295b265bad8`
and names “Copyright (c) 2021 James Calam Briggs.” Six pinned cleaner modules
are byte-identical to that revision (`datestime_vi.py`, `letter_vi.py`,
`measurement_vi.py`, `passage_utils.py`, `sentence_utils.py`, and
`symbol_vi.py`); the remaining modules are Misaki adaptations.

The same README identifies
https://github.com/v-nhandt21/Vinorm/tree/master/vinorm/Mapping as the extended
dictionary source. The reviewed revision is
https://github.com/v-nhandt21/Vinorm/commit/577c9cd9bf499e074801b703a5fd1eaad8300d43,
dated 2025-01-01. It carries the same license text and SHA-256 as Viphoneme.
Deterministic parsing confirms:

- `vi_teencode.json` is exactly the last-value-wins mapping from
  `Teencode.txt` (482 entries);
- `vi_acronyms.json` is exactly `Acronyms_shorten.txt` with keys uppercased
  (3,098 entries); and
- `vi_symbols.json` is the union of `Symbol.txt` and `CurrencyUnit.txt`, with
  the backslash entry removed and `:` → `hai chấm` added (62 entries).

The source mapping checksums are `10874fc85ad9731cfe12a510abc43d22cfe0fec45cb573173522b97155dd0671`
(`Teencode.txt`), `7b572d6660ce07923deab4154f1e5849755a967c10b24e15d2cebf5c61afa219`
(`Acronyms_shorten.txt`), `21c8727393383e71081431e1b74ee40ceab3f5de916c6ccd3e10d122d258ab95`
(`Symbol.txt`), and `711ffd485473efc55122f725ae9ae4e9b5cc24749e8a48f791f0440b14428ad4`
(`CurrencyUnit.txt`). The corresponding pinned JSON checksums are
`e35baf886a44a92e08c5d900abbcf921eb69efa198821e2a9de85ca8f5dfa7f3`,
`5da337cdde5231e72680fa4bf29f5dfe906f769492e9ee950ac2d73a28eba529`,
and `d963c9261f6ae0211c5941a357dff58f3599b5db98ed38e4cc722bc67ffcb728`.

#### Unlicensed number-converter blocker

Pinned `misaki/vi_cleaner/num2vi.py` names
https://github.com/ngthuong45/vietnam-number as its source and explicitly
states “No license.” The reviewed repository still has no license file. That
source has not been copied or translated. The Dart number speller was written
independently from black-box behavior and does not use the unlicensed source
as a code template.

Pinned `datestime_vi.py` separately imports the external `vietnam-number`
distribution but omits it from Misaki's dependency lock. The prepared,
development-only oracle lock selects PyPI release 1.0.3, the latest release
available at the upstream commit date, by exact wheel SHA-256
`549d8db75a1fca94786b5534e5aa129dc08d8104e848d9d0662baae925eb31b1`.
Its PyPI metadata declares GPL-3.0-or-later. Misakid neither distributes that
wheel nor invokes it during package use or normal tests; the exact oracle
environment and authoritative Vietnamese fixtures remain unprovisioned.

#### Underthesea tokenizer adapter blocker

The prepared oracle selects `underthesea==6.8.4`. Its 20,914,512-byte PyPI
wheel has SHA-256
`ddc1387f99320e4a2bbee2bfd34d7cd39fad54802b6752941cbc47d8e79ee9c7`;
the 21,434,162-byte source archive has SHA-256
`ed14b82c7acfc1b11e025494fe941dac572b588ae92e3bc5d9ac909f0b3954c8`.
That release is GNU GPL v3.0, and its word-tokenization path also depends on
`underthesea-core==1.0.4` plus a packaged CRF model/resource. The project's
resource listings describe datasets generically as “Open” but do not provide
the exact model lineage, training-data license, or redistribution terms needed
for this repository's generated-data policy.

Misakid does not copy, translate, link, or distribute the GPL implementation,
native extension, or tokenizer model. A production Python bridge is also
prohibited. A future separately licensed adapter would require a compatible
non-Python implementation and an independently cleared exact model/resource;
an alternate Vietnamese segmenter would define a different mode rather than
underthesea parity.

The Viphoneme, CodeLinkIO, and Vinorm reviews resolve the other named
Vietnamese code/data sources subject to retaining the notices below and
prominent modification notices. The Dart library now includes adaptations of
the reviewed Viphoneme and cleaner stages, deterministic generated runtime
tables, and byte-for-byte canonical generator inputs under `tool/`.

##### CodeLinkIO cleaner MIT notice

MIT License

Copyright (c) 2021 James Calam Briggs

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

##### Viphoneme and Vinorm MIT notice

Copyright (c) 2019 The Python Packaging Authority

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

This project is belong to AILAB, Ho Chi Minh University of Science

### English and shared language data

- The pinned package contains `us_gold.json`, `us_silver.json`, `gb_gold.json`,
  and `gb_silver.json`. Their author, hexgrad, also publishes those four files
  as the `hexgrad/misaki` dataset on Hugging Face with explicit
  `license:apache-2.0` metadata. Dataset revision
  https://huggingface.co/datasets/hexgrad/misaki/tree/b65a6b4398e053983b9c360f0682b720e362859d,
  dated 2025-04-05, is byte-for-byte identical to all four files at the pinned
  Misaki commit. The later dataset main revision tracks an unmerged Misaki dev
  dictionary bump and must not be substituted for this pin.
- The exact pinned/dataset SHA-256 values are
  `29e62f4b60261c88f7f3c2c7811ca3825978948090b72d2b27d565b729282f71`
  (`gb_gold.json`),
  `48131e2d92ccc41655f4543e87e0f938e71463eb5a54be7f0693bb712ebb6bce`
  (`gb_silver.json`),
  `dc414872a49a28ae6c141463d502fd945f3b2fde040484fdc47d00cc4612686f`
  (`us_gold.json`), and
  `de8f67be911bb6c659187b4a65fd966b6a30e56350e0f790d763210b053ac475`
  (`us_silver.json`). The author-published dataset was created immediately
  before Misaki's English baseline and its revision history mirrors the
  dictionary-update history through the pinned main-branch snapshot.
- misaki/en.py references spaCy tag definitions and relies on spaCy,
  num2words, transformer/model components, and optional phonemization/eSpeak
  tooling. The sibling `misakid_spacy_en` package contains Apache-licensed
  behavior-preserving Dart adaptations of the MIT-licensed spaCy 3.8.4
  tokenizer and Thinc 8.3.4 small-model execution path. The sibling
  `misakid_espeak_en` package contains an Apache-licensed owned-result adapter;
  it does not contain or link eSpeak resources.

This author-published dataset resolves the four lexicons' data-specific
license and revision blocker for the exact checksums above. Any generated
runtime representation must retain this provenance, be reproducible from
canonical byte copies, and keep the root Apache License. Any future model,
dictionary, or executable adapter still requires its own version, license,
checksum, and distribution review.

#### English small tokenizer/tagger model and pure-Dart adapter

Pinned Misaki's non-transformer configuration selects the official
`en_core_web_sm==3.8.0` model with spaCy 3.8.4 and Thinc 8.3.4. Explosion's
release tag resolves to commit
`374ece89b2099818244f5a65ef466b89c0c392ae`; its wheel has SHA-256
`1932429db727d4bff3deed6b34cfc05df17794f4a52eeb26cf8928f7c1a0fb85`.
The model declares MIT and identifies OntoNotes 5, ClearNLP conversion, and
WordNet 3.0 as source inputs. The caller supplies the extracted model and
retains its packaged `LICENSES_SOURCES`; Misakid redistributes none of it.

`misakid_spacy_en` adapts only the observable tokenizer and small
tok2vec/tagger execution paths under the spaCy and Thinc MIT licenses. Its
package notice carries both licenses, the model notice, MurmurHash public-
domain provenance, and the applicable Unicode/CPython notices. The four
consumed model-file sizes and hashes are fixed in that package's
`RESOURCE_MANIFEST.md` and checked before parsing.

#### English eSpeak fixture oracle and adapter

The accepted American and British eSpeak-fallback fixtures were produced by
executing, without modification or redistribution, the exact optional oracle
closure selected by pinned Misaki: `phonemizer-fork==3.3.2` and
`espeakng-loader==0.2.4`. The former declares GPL-3.0 in its installed package
metadata. The loaded eSpeak-ng 1.52.0 library is 504,168 bytes with SHA-256
`bb635eee1ee9c456f4a5cf06fb6cb352ecdd4d61e1951743b423ef22bb57f470`;
the complete 364-file, 18,373,365-byte data tree has canonical SHA-256
`730e20a0d06976b23b8344bac21dab6e1da447d0e16906bab6a0b54db89dd6e2`.
eSpeak NG declares GPL-3.0-or-later in its upstream repository.

No phonemizer source, eSpeak library, loader, voice data, or generated resource
is included in this repository or published package. Only the oracle's factual
input/output records and the package-owned Apache-2.0 adapter source are
committed. The `espeakng-loader` 0.2.4 installed metadata does not declare its
own package license, so the adapter does not redistribute that wheel. Callers
must supply the exact reviewed eSpeak NG library/data tuple independently and
comply with its GPL-3.0-or-later terms.

#### English transformer tokenizer/tagger model

Pinned Misaki selects `en_core_web_trf` when its `trf` option is true. spaCy
3.8.4's compatible official model is Explosion's `en_core_web_trf==3.8.0`,
published in the `explosion/spacy-models` release repository at tag commit
`374ece89b2099818244f5a65ef466b89c0c392ae`. Its wheel is 457,421,864 bytes
with SHA-256
`272a31e9d8530d1e075351d30a462d7e80e31da23574f1b274e200f3fff35bf5`:

https://github.com/explosion/spacy-models/releases/download/en_core_web_trf-3.8.0/en_core_web_trf-3.8.0-py3-none-any.whl

The immutable model metadata declares MIT, identifies OntoNotes 5 as
commercial data licensed by Explosion, cites the ClearNLP conversion, records
WordNet 3.0 under the WordNet 3.0 license, and identifies `roberta-base` as the
transformer source. The FacebookAI-hosted `roberta-base` repository declares
MIT and identifies its pretraining corpora; the original fairseq repository
also distributes the implementation under MIT. This identifies the exact
external resource accepted by the supported macOS-arm64 transformer adapter.
The artifact is not redistributed by Misakid, and callers must review and
retain the wheel's complete `LICENSE` and `LICENSES_SOURCES` records.

The exact wheel was downloaded only as an explicit temporary development input
and its deterministic 33-member inventory is committed; the 497,343,046-byte
transformer model itself is not committed or published. The exact pinned
Python 3.12 runtime delta is
`spacy-curated-transformers==0.3.0`, `curated-tokenizers==0.0.9`, and
`curated-transformers==0.1.1`; `torch==2.6.0` is already in the base English
closure. `spacy-transformers` and `en_core_web_hftrf` are different packages
and must not be substituted.

#### English fallback-model provenance blocker

Pinned `en.py` names the Hugging Face models
`PeterReid/graphemes_to_phonemes_en_us` and
`PeterReid/graphemes_to_phonemes_en_gb`. A metadata-only review on 2026-07-10
resolved their mutable `main` branches to immutable revisions
`a5631b285d18d59483c32c0c3379cb9fac924f4b` (US) and
`d8357d5067fa26a5c34134d6bbcf4bbf000c0ac8` (GB). Their safetensors LFS
SHA-256 values are respectively
`dc4a02e62d4fcb4bb4097ecf00db89b8e1a12a549a52ab6adfbba220b80a55c5`
and
`4994f474bb6f4584076a4e98189caaec11aa3f773a0d82d5bc263a03dd07e703`.
Primary immutable metadata is available at
https://huggingface.co/api/models/PeterReid/graphemes_to_phonemes_en_us/revision/a5631b285d18d59483c32c0c3379cb9fac924f4b?blobs=true
and
https://huggingface.co/api/models/PeterReid/graphemes_to_phonemes_en_gb/revision/d8357d5067fa26a5c34134d6bbcf4bbf000c0ac8?blobs=true.

Both repositories declare Apache-2.0 in Hub metadata, but their rendered model
cards are empty and their snapshots contain no `LICENSE` or `NOTICE`, training
dataset identification, lineage, evaluation, copyright statement, or evidence
that the uploader can license the weights and training inputs. Neither
snapshot includes tokenizer assets, and only the US snapshot includes a
training script. Under this repository's provenance policy, that metadata is
not enough to accept, redistribute, or use the weights as an authoritative
fixture oracle. A maintainer declaration covering training data, lineage,
weight/code licensing authority, and required notices is needed first. No
model artifact was downloaded or copied during this review.

#### Experimental pure-Dart BART architecture adapter

The optional `misakid_bart_en` package contains an original Dart
implementation of the narrow one-layer BART operations used by pinned
`misaki/en.py` lines 497–519 at commit
`fba1236595f2d2bf21d414ba6e57d25256afada3` (Apache-2.0). Its behavior and
tensor contract were studied against Hugging Face Transformers 4.51.3 BART
(Apache-2.0) and MisakiSwift commit
`b7477b15fc46cf8e20b32c008126611b38ec6b79` (Apache-2.0). The runtime uses
`crypto` 3.0.7 for SHA-256 resource identity under its BSD-3-Clause license.
Complete package-local notices are distributed in
`packages/misakid_bart_en/THIRD_PARTY_NOTICES.md`.

The committed tiny test model is formula-generated synthetic data; only its
expected activations and generated IDs are produced by the pinned Transformers
tooling. No PeterReid configuration, weight, tokenizer, training datum, or
derived model parameter is copied or redistributed. This adapter does not
alter the provenance blocker above or establish support for the named model.

#### Unicode 14/15 normalization, case, and scalar-property data

The pure-Dart NFC/NFKC runtime contains generated normalization and scalar
property data corresponding exactly to the Unicode Character Database 15.0.0
used by CPython 3.12.11. The
canonical derived JSON, deterministic extractor/generator identities, counts,
and SHA-256 values are recorded in
`tool/upstream_data/python-3.12.11-unicode-15.0.0/manifest.json`. No Python
runtime or `unorm_dart` code is distributed or invoked by the package.
The pure-Dart spaCy adapter adds a separate accepted capture of CPython
3.12.11's `str.lower`, `str.isspace`, Unicode `re` word class, and internal
alphabetic, digit, uppercase, cased, and case-ignorable predicates. Its
canonical `spacy_unicode_tables.json` has SHA-256
`1e7928f616c36560748f466b047720011faa0c49db1b459a443eec318e01da6f`
and decoded behavior digest
`68d7a4099fb5f72477218518178e89c1e8446b65dfdb2790f4747efb11bf4ffc`.
The same manifest records the checksum-pinned CPython 3.12.11 executable,
extractor, deterministic generator, counts, generated runtime, and
reproducibility test. CPython is covered by the Python Software Foundation
License Version 2; no CPython source or binary is redistributed.
Vietnamese's CPython-3.11.15/Unicode-14 NFC candidate reuses those stable
canonical tables and carries the complete reviewed delta: ten Unicode-15
combining marks are treated as unassigned class-zero starters. Exhaustive
scalar and sequence digests cover both database versions; the exact-3.11.13
comparison remains a support gate.

Vietnamese lower/upper/whitespace behavior also uses a separately accepted
CPython-3.11.15/Unicode-14 candidate payload under
`tool/upstream_data/python-3.11-unicode-14.0.0/manifest.json`. It records all
non-identity mappings and the Cased/Case_Ignorable ranges required for
context-sensitive Final_Sigma behavior. The generated runtime is 74 KB;
normal package use neither invokes Python nor reads the canonical JSON.
The manifest marks exact CPython 3.11.13 verification pending and pins the
separate comparator that must pass before these tables are treated as target
oracle evidence.

Unicode data files are licensed under Unicode License v3 (Unicode-3.0). The
complete applicable notice is:

UNICODE LICENSE V3 COPYRIGHT AND PERMISSION NOTICE

Copyright © 1991-2026 Unicode, Inc.

NOTICE TO USER: Carefully read the following legal agreement. BY DOWNLOADING,
INSTALLING, COPYING OR OTHERWISE USING DATA FILES, AND/OR SOFTWARE, YOU
UNEQUIVOCALLY ACCEPT, AND AGREE TO BE BOUND BY, ALL OF THE TERMS AND
CONDITIONS OF THIS AGREEMENT. IF YOU DO NOT AGREE, DO NOT DOWNLOAD, INSTALL,
COPY, DISTRIBUTE OR USE THE DATA FILES OR SOFTWARE.

Permission is hereby granted, free of charge, to any person obtaining a copy
of data files and any associated documentation (the "Data Files") or software
and any associated documentation (the "Software") to deal in the Data Files
or Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, and/or sell copies of the Data
Files or Software, and to permit persons to whom the Data Files or Software
are furnished to do so, provided that either (a) this copyright and permission
notice appear with all copies of the Data Files or Software, or (b) this
copyright and permission notice appear in associated Documentation.

THE DATA FILES AND SOFTWARE ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF THIRD
PARTY RIGHTS.

IN NO EVENT SHALL THE COPYRIGHT HOLDER OR HOLDERS INCLUDED IN THIS NOTICE BE
LIABLE FOR ANY CLAIM, OR ANY SPECIAL INDIRECT OR CONSEQUENTIAL DAMAGES, OR
ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN
AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR
IN CONNECTION WITH THE USE OR PERFORMANCE OF THE DATA FILES OR SOFTWARE.

Except as contained in this notice, the name of a copyright holder shall not
be used in advertising or otherwise to promote the sale, use or other dealings
in these Data Files or Software without prior written authorization of the
copyright holder.

### Hebrew Mishkal 0.3.2 provenance blocker

Pinned Misaki depends on `mishkal-hebrew==0.3.2`. Its locked PyPI wheel is
154,859 bytes with SHA-256
`1b25dc61c2ac1ca2898c288adbd8d81399260fd4d82124bbce5f0d031c785997`;
the corresponding 161,128-byte source archive has SHA-256
`4c4999288c5ef735763b8f069068fe499cf38d68c45a295435e4670c146feb2a`.
The release's PyPI metadata declares no license, and the historical package
contains substantially more material than the later small rule-only wheels.

The original `thewh1teagle/mishkal` repository now redirects to Phonikud. Its
current source declares CC BY 4.0, but that later declaration does not by
itself establish redistribution or adaptation terms for the exact 0.3.2
source/data snapshot published on 2025-03-23. Until the maintainer identifies
the exact source revision and license covering that release and its packaged
data, Mishkal code/data must not be copied, translated, or generated into the
Dart package. Temporary oracle execution still requires the explicitly
provisioned checksum-pinned wheel and does not authorize production use or
redistribution.

### External runtime projects

The pinned implementation names or depends on projects including spaCy,
num2words, pyopenjtalk, UniDic, Cutlet, fugashi, MeCab, jaconv, mojimoji,
g2pK/g2pkc, NLTK CMUdict, PaddleSpeech, jieba, pypinyin, cn2an,
underthesea, Viphoneme, and Mishkal. The pure root package does not distribute
or link their external runtimes. Optional `misakid_openjtalk` and
`misakid_mecab_ko` packages build reviewed native subsets only from explicit
checksum-pinned source and install the applicable notices beside their
libraries. Optional `misakid_chinese` parses caller-supplied exact resources
with reviewed pure-Dart adaptations. No compiled binary or external dictionary
is committed. Reviewed source adaptations and canonical data copied into this
repository are identified in the component-specific notices above.

Every optional adapter requires its own dependency license, data/model
license, platform requirements, and redistribution review. An executable,
dictionary, or model supplied by a user remains subject to its own license;
this notice must not imply otherwise.

## Generated material

Future generated Dart tables must identify every input path, source repository,
source revision, license, and SHA-256 checksum. Generation does not remove
copyright, attribution, notice, or redistribution obligations. Inputs whose
license is unknown or incompatible must not be used.
