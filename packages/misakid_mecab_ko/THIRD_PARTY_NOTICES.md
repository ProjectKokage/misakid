# Third-party notices

`misakid_mecab_ko` builds explicitly supplied MeCab-ko source and reads two
explicitly supplied data resources. It does not bundle the source archive,
dictionary, CMUdict data, Python, or a compiled native binary.

Exact notices retained under `native/licenses/` are:

- `mecab-ko-COPYING` — upstream license-choice notice, SHA-256
  `9ed8a017f2226b6f0d6dd6a1d25404800374a12c70e14a56ca9613176f78778e`;
- `mecab-ko-BSD` — selected MeCab/MeCab-ko BSD redistribution terms,
  SHA-256
  `62f4b23450a9ad40e4db8063d45c1d13c78d07ca27c9ada62c4ca9c11c1f3e7b`;
- `python-mecab-ko-dic-LICENSE` — Apache License 2.0 distributed with
  `python-mecab-ko-dic==2.1.1.post2`, SHA-256
  `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30`;
  and
- `cmudict-README` — CMUdict 0.7a copyright, attribution, and redistribution
  notice, SHA-256
  `b0556be7a2b12bea6a667277b75864f802dd4854480657ce298c62e6897e766b`.

The MeCab-ko source archive is the official Eunjeon
`mecab-0.996-ko-0.9.2` release. The library is redistributed under the BSD
option stated in upstream `COPYING`; the exact source identity and the
Misakid modification notice are recorded in `native/SOURCE_MANIFEST.md`.

The Korean dictionary was created by Yongwoon Lee and Yungho Yu as part of
the Eunjeon project and packaged by `python-mecab-ko-dic`. Applications that
redistribute the dictionary must retain its Apache-2.0 terms. Applications
that redistribute CMUdict must retain its complete notice.

`python-mecab-ko==1.3.7` and NLTK 3.9.1 are used only in the pinned Python
oracle that produced committed fixtures. Their code is not linked, copied,
or invoked by this production adapter.

## Dart `crypto` dependency

The adapter uses `crypto` only for streaming SHA-256 validation of source and
data resources. Release 3.0.7 was reviewed as a pure-Dart package maintained
in `dart-lang/core`. Its included BSD-style license has SHA-256
`ad6a71997da90924b2cfb1fb47ec46537f70faf469efe016168794ae45ed6888`.
Pub distributes the dependency and its license separately; none of its source
is copied into this package.
