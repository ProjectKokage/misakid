# misakid_mecab_ja

Native-assets MeCab/UniDic backend for Japanese Cutlet-compatible G2P. By
default it accepts a caller-selected UTF-8 UniDic whose runtime files and
feature layout are compatible; it does not infer or verify the corpus,
distribution, release, or resource identity. CWJ and CSJ can share the same
release number while producing different segmentation, readings, and final
output. Exact Misaki 0.9.4 fixture parity is a separate profile for one
content-hashed, modified unidic-py CWJ tree.

The package is a Dart `package_ffi`: its build hook can compile the reviewed
MeCab 0.996 source for mobile application targets. It does not invoke Python,
require a system MeCab installation, or perform a network request at build
time or runtime. macOS arm64 is a supported exact-parity tuple, and the
complete strict-profile fixture also passes on Android and iOS emulated
runtimes. Mobile release tuples remain experimental pending physical-device
and clean hosted-matrix validation.

The primary API has build profiles for:

| Target | Current evidence |
| --- | --- |
| Android | A release APK contains armv7, arm64, and x86-64 assets with static libc++, exact libc/libdl/libm dependencies, and verified 16 KiB ELF/APK alignment; Android 15/API 35 arm64 passes the complete strict-profile runtime fixture. Physical-device validation is pending. |
| iOS | An unsigned arm64 device app passes native framework and manifest verification; an iOS 26.4 Simulator passes the complete 27-case strict-profile runtime fixture. Physical-device validation is pending. |
| macOS | arm64 has complete parity with the pinned modified unidic-py CWJ profile; x86-64 is a build-hook target without accepted runtime parity. |

The legacy `open(libraryPath: ...)` API remains available for an explicitly
built macOS arm64 dylib. Linux and Windows do not build a bundled native asset;
attempting to initialize one fails with `BackendUnavailableException` before
dictionary access.

## Installation

Add the adapter directly; it depends on `misakid` and re-exports the Japanese
core API:

```yaml
dependencies:
  misakid_mecab_ja: ^0.1.0
```

## Mobile and Flutter use

Keep the caller-selected UniDic directory in application-controlled storage.
MeCab needs real files because it memory-maps the dictionary; a compressed APK
asset or an iOS asset-bundle entry is not a usable dictionary path. An
application may copy or install the resource during its own explicit
provisioning flow, then pass the resulting absolute directory path.

Load the much smaller grouping list as bytes. For Flutter, that can come from
an `AssetBundle` without adding Flutter to this package:

```dart
import 'package:flutter/services.dart';
import 'package:misakid_mecab_ja/misakid_mecab_ja.dart';

final class JapanesePhonemizer {
  JapanesePhonemizer._(this._backend, this._frontend);

  final MecabJapaneseCutletBackend _backend;
  final KokoroNonEnglishG2pFrontend _frontend;

  static Future<JapanesePhonemizer> load(String installedUnidicPath) async {
    final data = await rootBundle.load('assets/g2p/ja_words.txt');
    final backend = await MecabJapaneseCutletBackend.openBundled(
      dictionaryPath: installedUnidicPath,
      wordListBytes: data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      ),
    );
    final frontend = KokoroNonEnglishG2pFrontend(
      engine: JapaneseCutletEngine(backend: backend),
    );
    return JapanesePhonemizer._(backend, frontend);
  }

  List<KokoroG2pChunk> convert(String text) => _frontend.convert(text);

  void close() => _backend.close();
}
```

Create one `JapanesePhonemizer` during application startup, reuse `convert` for
each utterance, and call `close` during application shutdown. Initialization
checks the required runtime files and probes the dictionary's native feature
layout, while MeCab memory-maps its large binary tables. The compatible profile
reports its corpus and exact identity as unknown. The exact parity profile
additionally streams and hashes the complete 811,662,881-byte modified
unidic-py CWJ tree. `close()` is idempotent and releases the native analyzer
context.

Each `KokoroG2pChunk` contains source graphemes and the exact phoneme string for
the next layer. Kokoro's non-English source packing and 510-code-point phoneme
limit are already applied. Model vocabulary lookup, BOS/EOS IDs, voice/style
selection, speed, tensor construction, ONNX Runtime, and waveform inference
belong to the separate inference library.

## Dictionary profiles and required data

The build hook vendors only the licensed MeCab runtime source. Applications
must explicitly provision a UniDic directory and Cutlet grouping data.

`MecabJapaneseDictionaryProfile.compatible` is the default. It accepts one
non-empty UTF-8 MeCab system dictionary using binary format version 102 and a
supported UniDic feature layout. The required binary files must be regular
files; an optional `dicrc` must also be a real regular file when present.
Known-word records may contain 26 or 29 fields; `pron` is read from field 9,
while `kana` is read from field 17 or 20, respectively.

Initialization probes this contract before processing caller text. Field count
does not identify a dictionary corpus: CWJ, CSJ, and custom dictionaries can
share a layout and release marker. Accordingly, this profile reports
`dictionaryCorpus=unknown` and `dictionaryIdentity=unverified`; it does not
claim that the selected dictionary reproduces the pinned Misaki segmentation,
readings, or phonemes.

For exact fixture parity, select the strict profile explicitly:

```dart
final backend = await MecabJapaneseCutletBackend.openBundled(
  dictionaryPath: installedPinnedUnidicPyCwjPath,
  wordListBytes: wordListBytes,
  dictionaryProfile:
      MecabJapaneseDictionaryProfile.pinnedUnidicPyCwjParity,
);
```

That profile requires the tested parity artifacts:

- The modified `unidic-py` CWJ tree whose descriptive release marker is
  `3.1.0+2021-08-31`: exactly 20 files, 811,662,881 bytes, tree SHA-256
  `95bd65fa96955b644c15510932ca8439f463ac8b66f57bac6dfee5e29fa03115`.
  The release marker is metadata; the complete tree hash establishes identity.
- Pinned Misaki `misaki/data/ja_words.txt` at commit
  `fba1236595f2d2bf21d414ba6e57d25256afada3`: 1,921,140 bytes, 147,571
  unique sorted records, SHA-256
  `a93a8e8aee24db307a32becb8bf01c4c2908ecf37e6c91f7a705fafdfeba67ff`,
  with no terminal LF.

`openBundled` always validates the pinned grouping-list identity. Its default
dictionary profile validates runtime-file and feature-layout compatibility;
only `pinnedUnidicPyCwjParity` validates the complete modified unidic-py CWJ
manifest and checksum. Neither path searches the device, silently substitutes
a dictionary, or downloads data.
`openBundledWithMembership` accepts a separately reviewed implementation of
`JapaneseCutletWordMembership` when an application cannot redistribute the
pinned list.

The grouping list is not included because its underlying generator and
redistribution terms are undocumented. Supplying the bytes does not grant
redistribution rights. Review `THIRD_PARTY_NOTICES.md` and
`native/SOURCE_MANIFEST.md` before packaging data in an application.

## Behavior and exact parity

`analyzeRaw` exposes owned MeCab surface, nullable UniDic `pron`/`kana`, raw
character type, and unknown status records. `analyze` then performs the pinned
jaconv 0.4.0 Katakana-to-Hiragana conversion and Cutlet longest-match grouping.
`JapaneseCutletEngine` preserves normalization, punctuation, romanization,
sokuon, moraic-nasal, long-vowel, unknown, and null-token behavior from Misaki
0.9.4 after morphology is supplied. Under the default compatible profile, the
caller-selected dictionary can change that morphology and therefore the final
output.

The accepted fixture has 27 adversarial cases and 126 raw UniDic words. With
`MecabJapaneseDictionaryProfile.pinnedUnidicPyCwjParity`, the portable
no-iconv profile, compiled and exercised on macOS arm64 and through bundled
native assets on Android 15/API 35 arm64 and an iOS 26.4 Simulator, matches
every raw field, grouping decision, 26 output strings, and the pinned failure.
Provisioned tests cover strict 29-field modified unidic-py CWJ parity, the
47,356,746-byte official `unidic-lite==1.0.8` source distribution containing a
26-field UniDic 2.1.2 resource (SHA-256
`db9d4572d9fdd4d00a97949d4b0741ec480ee05a7e7e2e32f547500dae27b245`),
and both official NINJAL 2023.02 29-field resources:

- `unidic-cwj-202302.zip`: 603,549,853 bytes, SHA-256
  `601bc4b0af794d3c20c2089771b8771209390e1b35b0f20c85cf0a10c9a98c6d`;
- `unidic-csj-202302.zip`: 638,074,705 bytes, SHA-256
  `9fee27c64738a440ca7340e4243014d6151bfd00da8f01c4ef35b416e3fac1d9`.

The two official archives have different system dictionaries and connection
matrices even though both report release 2023.02, contain 876,803 entries, and
use 29 fields. These are layout/projection tests, not exact phoneme-parity or
runtime identity claims. The unprovisioned 17-field layout is not accepted.
Source/resource identity, input limits, ownership, repeated close, concurrent
isolates, and bounded diagnostics are covered. Physical-device and clean
hosted-matrix validation remain outstanding.

## Failure contract

Configuration errors such as relative paths or invalid input limits throw
`InvalidConfigurationException`. Missing or unloadable native/dictionary
resources and an unsupported native tuple throw `BackendUnavailableException`.
Malformed or identity-mismatched resources throw `MalformedDataException`.
Failures after successful initialization throw `BackendFailureException`.
Every exception is typed and retains a bounded cause without including caller
text or configured paths in native diagnostics.

## Native build

Normal consumers do not run a custom build command. Dart and Flutter invoke
`hook/build.dart`, which:

1. verifies the vendored 54-file, 4,499,769-byte MeCab subtree;
2. compiles only the 16-file UTF-8 MeCab runtime plus the ABI 3 C shim;
3. uses static libc++ on Android and hides its archive symbols;
4. emits only the 24 reviewed ABI functions; and
5. lets the application toolchain select architecture and deployment target.

The `misakid-mecab-ja-build-v4-portable` configuration intentionally omits
iconv and accepts only UTF-8 dictionaries, so the corresponding MeCab
conversion is an identity operation. Its strict modified unidic-py CWJ suite
proves that this does not change the accepted fixture output.

For standalone macOS diagnostics, the retained source-verifying CMake path is:

```sh
dart run bin/build_misakid_mecab_ja.dart \
  --source /absolute/path/pyopenjtalk-0.4.1 \
  --build-dir /absolute/path/dedicated-build
```

That command accepts only macOS arm64 and writes outside the source/package
trees. Production mobile applications should use `openBundled`, not copy this
dylib into their bundles manually.

## Provisioned parity test

```sh
MISAKID_MECAB_JA_DICTIONARY=/absolute/path/pinned-unidic-py-cwj \
MISAKID_MECAB_JA_WORD_LIST=/absolute/path/misaki/data/ja_words.txt \
dart test test/native_parity_test.dart
```

Set `MISAKID_MECAB_JA_LIBRARY` as well to exercise the standalone macOS path.
The provisioned parity test selects
`MecabJapaneseDictionaryProfile.pinnedUnidicPyCwjParity`; it does not treat the
default compatible profile as exact. Normal offline CI skips provisioned
external-resource groups; the owner-provisioned release workflow supplies and
verifies their exact resources.

The release workflow verifies and extracts the official unidic-lite 1.0.8
source distribution for the 26-field path and the official 2023.02 archives
above for the two distinct 29-field corpora. After extracting each resource
into its own directory, run:

```sh
MISAKID_MECAB_JA_COMPATIBLE_DICTIONARY=/absolute/path/unidic-lite \
dart test test/native_compatible_dictionary_test.dart

MISAKID_MECAB_JA_CWJ_202302_DICTIONARY=/absolute/path/unidic-cwj-202302 \
MISAKID_MECAB_JA_CSJ_202302_DICTIONARY=/absolute/path/unidic-csj-202302 \
dart test test/native_official_dictionary_test.dart
```

The official-resource test verifies projection compatibility and rejection by
the different pinned modified-CWJ profile. The test configuration knows which
archive it supplied; generic backend metadata intentionally does not infer
CWJ or CSJ from version or field layout.
