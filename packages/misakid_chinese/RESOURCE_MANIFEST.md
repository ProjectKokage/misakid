# Chinese resource manifest

`misakid_chinese` bundles no dictionaries. Production constructors accept
absolute paths to the exact files below, validate the file kind, byte length,
SHA-256, schema, record counts, and file stability, then retain only parsed
pure-Dart data. They do not discover, download, execute, or modify resources.

## Jieba 0.42.1

- Source: `https://github.com/fxsjy/jieba`
- Tag commit: `1e20c89b66f56c9301b0feed211733ffaa1bd72a`
- License: MIT, Copyright (c) 2013 Sun Junyi

| Repository path | Bytes | SHA-256 |
| --- | ---: | --- |
| `jieba/dict.txt` | 5,071,852 | `7197c3211ddd98962b036cdf40324d1ea2bfaa12bd028e68faa70111a88e12a8` |
| `jieba/finalseg/prob_start.p` | 109 | `dfd45976dd4f8f2bc12535a680a178bf9e75eaa38bdfdcb844469e54468d6245` |
| `jieba/finalseg/prob_trans.p` | 260 | `ea7f50162ffa01db4973c7a8120b3c0233fbc5819fc0d617513535f1f2c7fedc` |
| `jieba/finalseg/prob_emit.p` | 1,275,441 | `1e1d1d835b0c77d234acaa6afa23a13ffce597a295be0d7a1ece6a0d440dcf08` |
| `jieba/posseg/char_state_tab.p` | 2,113,902 | `c0ef4bb3d698eed188225d430ac291000b30c3d6e253a538d26b7ac9687424b1` |
| `jieba/posseg/prob_start.p` | 8,312 | `0fb0fbc6b1840d35a5a8499cff0ae75e06af788e348f9b4b8b9630804cd6cf09` |
| `jieba/posseg/prob_trans.p` | 141,551 | `236726f5a4efc2f023652925ca1e94f1fe4bfcb9d60224e9db3de0135b21385b` |
| `jieba/posseg/prob_emit.p` | 3,231,234 | `449b2304b6c73034187d3c8a6f26a7a20037f4ab45659844acd0ef2114171fa8` |

The dictionary contains 349,046 records, expands to 498,113 word/prefix
entries, and has a total frequency of 60,101,967. The HMM files use protocol-0
pickle syntax. The Dart loader accepts only the inert dictionary, scalar
string, finite-float, memo, and set-item opcodes present in these files; it has
no object construction, global lookup, reducer, persistent-ID, extension, or
code-execution facility.

The frontend-1.1 POS model contains 6,648 character records, 66,162
character/state pairs, 256 states, 5,218 transition entries, and 89,290
emission entries. Its four files are parsed by the same non-executable
protocol-0 reader.

## pypinyin 0.53.0

- Source: `https://github.com/mozillazg/python-pinyin`
- Tag commit: `e42dede51abbc40e225da9a8ec8e5bd0043eed21`
- License: MIT, Copyright (c) 2016 mozillazg and 闲耘

| Repository path | Records | Bytes | SHA-256 |
| --- | ---: | ---: | --- |
| `pypinyin/pinyin_dict.json` | 41,651 | 783,823 | `19ac93a11b0cf2d1b42741c2956dcb8632944e87d2ebcd1ba7cc4d3a936b9fb5` |
| `pypinyin/phrases_dict.json` | 47,098 | 2,544,982 | `d71fe97165dfd3eb9d8dff86ce5f62787d530b6b9f38c898779fcaf16d2522d1` |

The generated single-character data derives from MIT-licensed
`mozillazg/pinyin-data` at commit
`27dc54a206326e0d8d91428010325f50f614508d`. The phrase data derives from
MIT-licensed `mozillazg/phrase-pinyin-data` at commit
`1114cb9372804062e79d8b78affd333df41bf599`. Their exact license texts are
distributed beside the adapter notices.

### Frontend 1.1 phrase overlay

Misaki's 1.1 frontend additionally calls `large_pinyin.load()` from
MIT-licensed `mozillazg/pypinyin-dict` 0.9.0, tag commit
`d8a12d70ea14a929f296f21f4c493b3ce5d0b14a`. The Dart adapter accepts the
canonical source data rather than executing its generated Python modules:

| Repository/path | Records | Unique phrases | Bytes | SHA-256 |
| --- | ---: | ---: | ---: | --- |
| `mozillazg/phrase-pinyin-data@3fa3308aeeadec0736d84f31b28ac3da6e98d0d9/large_pinyin.txt` | 411,959 | 411,957 | 9,140,316 | `f1f00a0682120f4052eb9ab03c632b040677dd9675bade5b8cb6a3bb7c0b8fd3` |

The pypinyin-dict generator was independently checked to produce exactly the
same 411,957-entry phrase map from this source file. After loading it, the
adapter applies the 16 phrase overrides recorded in pinned Misaki
`zh_frontend.py`, then the `地=de,di4` single-character ordering override, in
the same observable order as the Python constructor. Exact pypinyin-dict and
phrase-pinyin-data MIT license texts are distributed under `licenses/`.

The pinned phrase-pinyin-data README records `large_pinyin.txt` as a merge of
its `zdic_cibs.txt`, `zdic_cybs.txt`, `cc_cedict.txt`, `di.txt`, `pinyin.txt`,
and `overwrite.txt` inputs. It names earlier hotoo/pinyin and pypinyin phrase
tables, Zdic, zisea.com, guoxuedashi.com, CC-CEDICT, and 漢語大詞典 as data
references. The adapter does not redistribute that 9.14 MB compilation; the
caller provisions the exact snapshot explicitly. The pinned
phrase-pinyin-data repository publishes the compilation under its included
MIT license, retained verbatim here.

## cn2an 0.5.23

The `an2cn` sentence-normalization path is deterministic code and needs no
runtime resource. Its Dart adaptation is attributed to the MIT-licensed cn2an
project and is limited to behavior exercised by pinned Misaki 0.9.4.
