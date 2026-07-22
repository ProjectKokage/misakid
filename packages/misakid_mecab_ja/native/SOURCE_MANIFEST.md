# Native and resource manifest

The exact MeCab source described below is distributed with this package. No
source, dictionary, word list, or binary is downloaded by the package.

## Native source distribution

- Project: `pyopenjtalk`
- Version: `0.4.1`
- Archive: `pyopenjtalk-0.4.1.tar.gz`
- Size: 1,397,999 bytes
- SHA-256:
  `d5ada46f7fc2b52c1c79c273eb9668ff6ad7ab276a8db9d8be119ef93440f0dc`
- PyPI URL:
  `https://files.pythonhosted.org/packages/58/74/ccd31c696f047ba381f9b11a504bf1199756c3f30f3de64e3eeb83e10b4a/pyopenjtalk-0.4.1.tar.gz`
- pyopenjtalk license SHA-256:
  `c38083a4d51c1ea86e08b3303a984d0c23718c5ac214058af705814d30f4bb5b`
- embedded MeCab notice SHA-256:
  `05e94c185a3e31f0c658f7011132be952b6d1a4d588b682f92da380e0a290650`

The package distributes the upstream archive's unmodified
`lib/open_jtalk/src/mecab/` subtree at `native/vendor/mecab/`: exactly 54
regular files and 4,499,769 bytes. No patches or generated files are present.
The verifier sorts relative POSIX paths and hashes each record as the UTF-8
path, NUL, lowercase file SHA-256, and LF. The aggregate SHA-256 is
`473f27f510fbcb70ab6a73c556a56cf00b0fac23091dd3656efbee05cf032258`.
Run the normal offline check with:

```sh
dart run tool/verify_vendored_mecab.dart
```

The distributed `native/vendor/mecab/COPYING` and reviewed
`native/licenses/mecab-COPYING` are byte-identical and retain the complete
upstream BSD/LGPL/GPL choice notice with the SHA-256 recorded above.

The retained standalone macOS build verifier selects the 139 sorted paths below
`lib/open_jtalk/src/` named by `pyopenjtalk.egg-info/SOURCES.txt`. For each it
hashes the relative path, NUL, lowercase file SHA-256, and LF. The exact tree
is 5,381,473 bytes with SHA-256
`dea0f240fad8dc8b9ea1984920a4d64a48227a40c2924a3c545eaeca50357857`.

CMake independently hashes that unmodified staged tree as relative path, tab,
file SHA-256, and LF. The expected digest is
`b963ef63d435e3bba884d5943ee60ac5621cdf1323195140757e1a5f37ca7dd4`.
The primary `misakid-mecab-ja-build-v4-portable` native-assets profile verifies
the distributed 54-file subtree directly and compiles only the standard
16-file MeCab runtime plus the Apache-2.0 adapter shim. Its static portable
configuration is UTF-8-only and intentionally omits iconv. Android builds link
libc++ statically, link the platform math library explicitly, and hide archive
symbols; Apple builds use the platform C++ runtime. Open JTalk, HTS, voices,
audio, and dictionaries are not built or bundled. The standalone macOS arm64
CMake path compiles the same 16 source files, shim, and portable configuration
after the stronger full-source check.

## UniDic compatibility and parity resource

The default `MecabJapaneseDictionaryProfile.compatible` contract is not pinned
to a UniDic corpus, distribution, release, or tree checksum. It requires an
explicit real directory,
the non-empty `char.bin`, `matrix.bin`, `sys.dic`, and `unk.dic` runtime files,
an absent or regular non-link `dicrc`, one UTF-8 system dictionary using MeCab
binary format version 102, and a known-word feature layout with 26 or 29
fields. The native initializer probes that layout before caller text is
processed. It reads `pron` from field 9 and `kana` from field 17 or 20 for the
26- or 29-field layout. Field count does not identify the corpus: CWJ, CSJ, and
custom dictionaries can share a layout or release marker. The backend
therefore reports the compatible profile's corpus as unknown and its exact
identity as unverified. Different compatible dictionaries may produce
different segmentation, readings, and phonemes and carry no exact Misaki
fixture-parity claim.

NINJAL's official archive lists both `unidic-cwj-3.1.0` and
`unidic-csj-3.1.0` as distinct resources with the same release number:
`https://clrd.ninjal.ac.jp/unidic/en/back_number_en.html`. Their shared
29-field layout is a parser contract, not corpus identity.

### unidic-lite 1.0.8 compatibility resource

The 26-field provisioned test uses the external official
`unidic-lite-1.0.8.tar.gz` source distribution from
`https://pypi.org/project/unidic-lite/1.0.8/`: 47,356,746 bytes, SHA-256
`db9d4572d9fdd4d00a97949d4b0741ec480ee05a7e7e2e32f547500dae27b245`.
Its package metadata identifies the contained dictionary as UniDic 2.1.2. The
test verifies the four required runtime files plus `dicrc` before
initialization:

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `char.bin` | 262,496 | `dd31396563d8924645b80fd3c9aa7b13ca089d7748f25553a1d6bc3f9b511ae8` |
| `dicrc` | 1,444 | `fcd17f35752de1417859a15e2e1f043d666da03f36dc632e8c0ed46887883a59` |
| `matrix.bin` | 71,544,726 | `88fb99efe1075d9b8b40e01bb2751e4095f1612618f2490af776eb5ed39190a9` |
| `sys.dic` | 187,680,870 | `122c4c91f026bf4b65bbe2dfd8b9f8eeb6ab56d8eb2a7287a68bca75708ba513` |
| `unk.dic` | 5,475 | `e3b92803feeb6c2712c796b905317ec192a59729d2c1e92b2728d454169541c4` |

This resource loads with a 26-field layout. It is external test evidence and
is not distributed by this package.

### Official 2023.02 compatibility resources

The provisioned release test independently exercises both lightweight NINJAL
2023.02 resources from `https://clrd.ninjal.ac.jp/unidic_archive/2302/`:

| Resource | Archive bytes | Archive SHA-256 | Extracted files/bytes | `sys.dic` SHA-256 | `matrix.bin` SHA-256 |
| --- | ---: | --- | ---: | --- | --- |
| `unidic-cwj-202302.zip` | 603,549,853 | `601bc4b0af794d3c20c2089771b8771209390e1b35b0f20c85cf0a10c9a98c6d` | 13 / 1,124,469,285 | `048f93a7f6aed6dd1c108cdd7b947a0f3a5a3d0d1012dd1f7d3c7b133b5867d7` | `85c6fe10e81417df2257951192a391e5768981a2280f1c606f0c3f404a45e9d4` |
| `unidic-csj-202302.zip` | 638,074,705 | `9fee27c64738a440ca7340e4243014d6151bfd00da8f01c4ef35b416e3fac1d9` | 13 / 1,150,985,193 | `83ea4290c31f74f72f974edc8c44ed37b0cbee9d1148438daa174fa06cc95db0` | `2705c0dc2865a1ce0f347bc589506c5fd9a9ccdaa749ebcfd6647cb5dafaa425` |

Both dictionaries load as UTF-8 MeCab-v102 system dictionaries with 876,803
entries and a 29-field feature layout. Their different binary hashes prove
that the shared 2023.02 marker and layout are not resource identity. The test
checks raw projection compatibility and keeps generic backend corpus and
identity metadata unknown; it does not establish exact Misaki output parity.
The archives are external provisioned resources and are not distributed by
this package.

### Exact modified unidic-py CWJ parity profile

`MecabJapaneseDictionaryProfile.pinnedUnidicPyCwjParity` additionally requires
the following complete modified unidic-py CWJ tree. These hashes identify the
resource used to produce and verify the committed fixtures; they are not
generic adapter requirements.

- Distribution: `unidic-py`
- Corpus: contemporary written Japanese (`cwj`)
- Descriptive release marker: `3.1.0+2021-08-31` (not an identity)
- Immutable recovery archive size: 524,664,138 bytes
- Archive SHA-256:
  `39ea0eae3b1f10ba8986483592cbc83bcc92f1898bb43ecbc607010f2e98cd22`
- Immutable recovery source commit:
  `https://huggingface.co/drewThomasson/unidic_3.1.0_backup/commit/9fcae6f3676c255dac3b81d8fbc83b16cc192d20`
- Installed tree: 20 files, 811,662,881 bytes
- Installed tree SHA-256:
  `95bd65fa96955b644c15510932ca8439f463ac8b66f57bac6dfee5e29fa03115`
- Live MeCab identity: charset `utf8`, 878,989 entries, binary version 102
- `sys.dic`: 243,373,840 bytes, SHA-256
  `f019f95838242cd614953a25201ad0b623b9c1cbca90de2507df4510db1b192c`
- New BSD notice SHA-256:
  `770a75de30705439084f869dbcb0bc4ebcffcb7c7124c0d74f5083170318a9bb`

The installed-tree fingerprint is SHA-256 over each sorted relative POSIX path
encoded as: 8-byte big-endian path length, UTF-8 path, 8-byte big-endian file
size, and the exact file bytes. The mutable unidic-py download endpoint no
longer serves the pinned archive bytes; the immutable recovery commit above is
the reviewed source for this exact artifact.

## Grouping membership

- Repository: `hexgrad/misaki`
- Commit: `fba1236595f2d2bf21d414ba6e57d25256afada3`
- Path: `misaki/data/ja_words.txt`
- Size: 1,921,140 bytes
- SHA-256:
  `a93a8e8aee24db307a32becb8bf01c4c2908ecf37e6c91f7a705fafdfeba67ff`
- Records: 147,571, non-empty, unique, Unicode-scalar sorted
- Terminal LF: absent

The package never distributes or discovers this file. The path loader and
mobile byte loader validate the same exact identity. Its underlying source
and exact generator remain undocumented. A current Kaikki/Wiktextract
word/forms differential overlaps 146,737 records (99.4348%), strongly
supporting but not proving older English-Wiktionary-derived lineage. Kaikki
identifies CC-BY-SA and GFDL terms; see the package's complete due-diligence
record and URLs in `THIRD_PARTY_NOTICES.md`. The identity above says only which
executable-specification resource an explicit caller path must match.

## Native ABI ownership and limits

ABI version 3 and build identity `misakid-mecab-ja-build-v4-portable` advertise
the dictionary contract as `unidic-features-26-29-v1`, independently of a
particular UniDic corpus or release. Its 24-function surface additionally
reports the detected field count for the opened context. The ABI owns copies of
surface, nullable pronunciation, nullable kana, character type, and unknown
status for each word.
Results remain valid across later calls until destroyed. A process-global mutex
serializes MeCab create, layout probing, analysis, and destroy across Dart
isolates. The boundary validates UTF-8 and NUL, caps input at 64 MiB, words at
65,536, individual returned fields at 1 MiB, aggregate copied result data at
64 MiB, and bounded diagnostics at 1 KiB. C++ exceptions are contained at the
C boundary.
