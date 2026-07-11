# Third-party notices

`misakid_chinese` contains cleanly separated Dart adaptations of the narrow
cn2an, Jieba, and pypinyin behaviors used by pinned Misaki 0.9.4. It bundles no
dictionary or probability data; applications explicitly obtain and supply the
checksum-pinned resources listed in `RESOURCE_MANIFEST.md`.

Exact retained license files under `licenses/` are:

- `cn2an-LICENSE` — MIT terms for cn2an 0.5.23, Copyright (c) 2017 Ailln,
  SHA-256
  `b18d8d4ad8bc57e00ae80d08d9da80a32176f031062f87c739ea7557c1b5d759`;
- `jieba-LICENSE.txt` — MIT terms for Jieba 0.42.1, Copyright (c) 2013
  Sun Junyi, committed SHA-256
  `522d429662141688e69562df3ef47acb29ed1a3d28147e1c643420740e4e94cc`.
  It differs from upstream's 1,075-byte
  `18ba0984839f85853b29fadaf992f7dba8fd0ca0fbeae34de2b8735222dc7a37`
  file only by one terminal LF;
- `pypinyin-LICENSE.txt` — MIT terms for pypinyin 0.53.0, Copyright (c)
  2016 mozillazg and 闲耘, SHA-256
  `1e6c90014b4912815c296ee64bb6f6280af47e6d4c5d80e86232dfc5defe764c`;
- `pinyin-data-LICENSE.txt` — MIT terms for the pinyin-data source of the
  generated single-character dictionary, Copyright (c) 2016 mozillazg,
  SHA-256
  `9c048697be2502a16e8bcb282d5d465a07295b2def0ffb05a269c5d39dbe1586`;
  and
- `phrase-pinyin-data-LICENSE.txt` — MIT terms for the phrase-pinyin-data
  source of the generated phrase dictionary, Copyright (c) 2017 mozillazg,
  SHA-256
  `89ac55df747e4776088c3e77531ef61b973a1a59dd8e6a4548a58996da9a4f70`;
  and
- `pypinyin-dict-LICENSE.txt` — MIT terms for pypinyin-dict 0.9.0,
  Copyright (c) 2017 mozillazg, SHA-256
  `239199faa0e3098c6b7fc7c5d4c50d623c44b7c4c0d8990c1a030266aa558f2c`.

The Dart source headers identify the precise upstream version/commit and
describe modifications. Callers redistributing the explicitly supplied
resources must retain their applicable MIT notices.

## Dart `crypto` dependency

The adapter uses `crypto` only for streaming SHA-256 validation of data
resources. Release 3.0.7 was reviewed as a pure-Dart package maintained in
`dart-lang/core`. Its included BSD-style license has SHA-256
`ad6a71997da90924b2cfb1fb47ec46537f70faf469efe016168794ae45ed6888`.
Pub distributes the dependency and its license separately; none of its source
is copied into this package.
