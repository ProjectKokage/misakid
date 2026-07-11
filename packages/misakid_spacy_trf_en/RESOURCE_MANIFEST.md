# `en_core_web_trf==3.8.0` resource manifest

## Source artifact

```text
Distribution: en-core-web-trf
Version: 3.8.0
URL: https://github.com/explosion/spacy-models/releases/download/en_core_web_trf-3.8.0/en_core_web_trf-3.8.0-py3-none-any.whl
Bytes: 457421864
SHA-256: 272a31e9d8530d1e075351d30a462d7e80e31da23574f1b274e200f3fff35bf5
Release repository commit: 374ece89b2099818244f5a65ef466b89c0c392ae
Declared license: MIT
```

The accepted 33-member wheel inventory is committed in the repository as
`tool/reference/en_core_web_trf-3.8.0.inventory.json`. Its SHA-256 is
`4e3cae8256e9e701739cdbd720ffe5f3047202e4a0ebace4bc469a33b1ae7eba`.
The inventory records 500,728,746 total uncompressed bytes. Neither the wheel
nor any extracted model member is distributed by this package.

The wheel's own license files have these identities:

| Relative wheel member | Bytes | SHA-256 |
| --- | ---: | --- |
| `en_core_web_trf-3.8.0.dist-info/LICENSE` | 1,056 | `3933c176979b68bc6d0bcc902c7d6c130f1d127f476f17ba5cdba8d99cfd0012` |
| `en_core_web_trf-3.8.0.dist-info/LICENSES_SOURCES` | 2,627 | `e94b3033acaecc8b3515a9b8d59917ef0d0ded835a281dbe7185afaf2953122a` |

## Runtime resource identities

The non-native model-directory boundary validates exactly these extracted
members before parsing or retaining data:

| Relative model path | Bytes | SHA-256 |
| --- | ---: | --- |
| `tokenizer` | 77,066 | `b014e8bba4958b120af2d0c1c63eabb7c00379f2bacaf10df7c5325efd2ea467` |
| `vocab/lookups.bin` | 70,040 | `fce9c883c56165f29573cc938c2a1c9d417ac61bd8f56b671dd5f7996de70682` |
| `transformer/model` | 497,343,046 | `2b7061c623f424486e5dddcff79276927127cee339cc6a9d26d87837c3e6074a` |
| `tagger/model` | 151,450 | `a489a41d998a6c042eaa279b6b823cd24b40854faf602e696d280788ed62f84c` |

`transformer/model` is streamed through SHA-256 rather than loaded as one
byte array. The validator then retains only this reviewed byte-BPE subrange:

```text
Start offset: 416
End offset, exclusive: 1064279
Length: 1063863
SHA-256: 3a937453afcd04229fc5e32d7304c117781d4c48f1e7c87a603194e2077576f0
Vocabulary entries: 50265
Ranked merges: 50000
BOS ID: 0
EOS ID: 2
```

The model metadata identifies a RoBERTa-base transformer with width 768,
stride 104, window 144, and vocabulary size 50,265. Repository inspection
records 149 exact little-endian F32 tensor ranges. The supported macOS-arm64
native implementation consumes only those reviewed ranges and revalidates
their individual identities while loading.

## Tagger projection

The bounded tagger decoder accepts only the pinned six-node MessagePack graph
and its exact attributes, references, parameter ownership, NumPy encodings,
shapes, and finite little-endian F32 values.

| Parameter | Shape | Raw bytes | Raw-byte SHA-256 |
| --- | --- | ---: | --- |
| `W` | `[49, 768]` | 150,528 | `e1ebf98491c0124fcb38b0e72c1d8d81ab3a72d1e33055975530bae2ba424738` |
| `b` | `[49]` | 196 | `c57c0420c83a8ab8f34a54d5f03d4e29f789e2b6d2285a5182f58b26c0e62ba2` |

This decoder remains an internal component. The public composite transformer
tokenizer/tagger uses it behind the exact supported resource contract.

## Generated regex property tables

Byte-BPE splitting uses tables generated from exactly `regex==2024.11.6`,
whose metadata reports Unicode 16.0.0. The committed decoded behavior digest
is:

```text
e7d2d9a6dd95d4553ab6693cf82157ea3b994c755119ef14bf81a1f2d9777a14
```

| Property | Inclusive ranges | Scalars |
| --- | ---: | ---: |
| General_Category=Letter | 677 | 141,028 |
| General_Category=Number | 144 | 1,911 |
| White_Space=Yes | 10 | 25 |

The deterministic repository generator is
`tool/generators/generate_en_trf_regex_unicode.py`. Normal package use reads
only the committed Dart constants and never imports Python or `regex`.

## Loading policy

The caller must provide the resource bytes or an absolute canonical
extracted-model path explicitly. There is no package lookup, environment
search, automatic discovery, installation, download, fallback model, or
resource mutation. Symlinked and changed resources fail closed with typed
Misakid errors. The full composite adapter is supported only on macOS 11+
arm64; the independently public byte-BPE stage is pure Dart.
