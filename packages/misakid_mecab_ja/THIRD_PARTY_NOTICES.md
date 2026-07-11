# Third-party notices

This package's Dart API, native shim, build tooling, and tests are licensed
under Apache-2.0. It distributes the exact embedded MeCab source described
below. It does not distribute a compiled native library, UniDic, or
`ja_words.txt`.

## pyopenjtalk 0.4.1 and MeCab 0.996

The optional native library is built from the MeCab runtime embedded in the
exact `pyopenjtalk` 0.4.1 source distribution. pyopenjtalk is MIT licensed;
the complete reviewed notice is installed as
`native/licenses/pyopenjtalk-LICENSE.md`. The embedded MeCab source retains
its BSD/LGPL/GPL choice. The unmodified 54-file embedded MeCab subtree is
distributed at `native/vendor/mecab/`; no pyopenjtalk source outside that
subtree is distributed. This package uses the BSD option and preserves the
complete notice byte-for-byte as both `native/vendor/mecab/COPYING` and
`native/licenses/mecab-COPYING`. Exact archive, tree, and notice identities
are recorded in `native/SOURCE_MANIFEST.md`.

## UniDic 3.1.0

The caller supplies the exact UniDic 3.1.0 installed tree. UniDic offers a
GPL/LGPL/New BSD choice; this adapter uses the New BSD terms. The complete
notice copied byte-for-byte from the pinned resource is
`native/licenses/unidic-BSD`. No dictionary bytes are distributed.

## jaconv 0.4.0

`lib/src/kata_to_hiragana.dart` is an Apache-2.0 Dart adaptation of jaconv
0.4.0's MIT-licensed `K2H_TABLE`. The table is represented as equivalent
Unicode scalar ranges. The complete MIT notice is
`native/licenses/jaconv-LICENSE`.

## Cutlet

The grouping pass follows the algorithm adapted by pinned Misaki from Cutlet
commit `d03f11c52a7cc7ed29a17d538e9271d693cb1cd0`. The Dart implementation uses
typed records and an injected membership boundary. The complete Cutlet MIT
notice is `native/licenses/cutlet-LICENSE`.

## Pinned Misaki grouping list

Pinned Misaki's `misaki/data/ja_words.txt` first appears in Misaki commit
`fdc9c5e5ec74a9fbb81e02bd487d0fb8bd8e4ec8`; neither the file nor that change
documents the underlying source or license. Its exact pinned identity is
recorded in `native/SOURCE_MANIFEST.md`. This package does not copy, derive,
bundle, or download the list. `PinnedMisakiCutletWordMembership.open` and
`fromBytes` only validate an explicit caller-provided resource. Use of that
external data does not grant or imply redistribution rights.

A differential review provides strong but non-authoritative evidence of an
older Kaikki/Wiktextract snapshot derived from English Wiktionary. From the
current postprocessed Japanese JSONL at
https://kaikki.org/dictionary/Japanese/kaikki.org-dictionary-Japanese.jsonl,
collecting all top-level `word` and `forms[].form` values, retaining strings of
length at least two that fully match
`[々\u3040-\u30FF\u4E00-\u9FFF]+`, and deduplicating produces candidates for
146,737 of the 147,571 pinned records (99.4348%); 85,647 now occur only as
forms. The 834 missing pinned values and old-looking generated inflections
support the snapshot hypothesis, but no byte-identical historical input,
extractor revision, or generator command was recovered. This remains an
inference, not proven provenance.

Kaikki says its Wiktionary-derived data is available under Wiktionary's
CC-BY-SA and GFDL licenses at
https://kaikki.org/dictionary/index.html. English Wiktionary specifies CC
BY-SA 4.0 International and GFDL 1.1 or later at
https://en.wiktionary.org/wiki/Wiktionary:Copyrights; CC BY-SA 4.0's legal
terms are at https://creativecommons.org/licenses/by-sa/4.0/legalcode.en.
Because the exact relationship is unproven, this notice neither relicenses the
Misaki artifact nor claims a byte-identical Kaikki source. Anyone
redistributing the external list should conservatively preserve Misaki and
Wiktionary/Kaikki attribution and comply with an applicable upstream data
license.
