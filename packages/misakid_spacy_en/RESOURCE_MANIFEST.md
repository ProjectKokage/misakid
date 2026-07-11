# `en_core_web_sm==3.8.0` resource manifest

Source artifact:

```text
https://github.com/explosion/spacy-models/releases/download/
en_core_web_sm-3.8.0/en_core_web_sm-3.8.0-py3-none-any.whl
```

The official release is tag `en_core_web_sm-3.8.0` at repository commit
`374ece89b2099818244f5a65ef466b89c0c392ae`; its published wheel SHA-256 is
`1932429db727d4bff3deed6b34cfc05df17794f4a52eeb26cf8928f7c1a0fb85`.

The model metadata identifies Explosion as author, declares MIT, requires
spaCy `>=3.8.0,<3.9.0`, and records OntoNotes 5, ClearNLP conversion, and
WordNet 3.0 as sources. The model and none of the files below are distributed
by this package.

| Relative path | Bytes | SHA-256 |
| --- | ---: | --- |
| `tokenizer` | 77,066 | `b014e8bba4958b120af2d0c1c63eabb7c00379f2bacaf10df7c5325efd2ea467` |
| `vocab/lookups.bin` | 70,040 | `fce9c883c56165f29573cc938c2a1c9d417ac61bd8f56b671dd5f7996de70682` |
| `tok2vec/model` | 6,269,370 | `e84fc06eb319c94d28e460fc334e292120b01f18baa5dc8b50c977459820a090` |
| `tagger/model` | 19,829 | `1ec3d93f38cebe172f2b5c89d84be72856ce42c8f1a64f1699f1d98a771f36b7` |

The adapter accepts a caller-supplied absolute model-directory path and uses
these fixed relative paths. It performs no package lookup, environment search,
download, installation, or model-directory mutation.
