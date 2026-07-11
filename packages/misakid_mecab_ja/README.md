# misakid_mecab_ja

Native-assets MeCab/UniDic backend for the exact Japanese Cutlet pipeline used
by Kokoro 0.9.4. The package is a Dart `package_ffi`: its build hook can compile
the reviewed MeCab 0.996 source for mobile application targets. It does not
invoke Python, require a system MeCab installation, or perform a network
request at build time or runtime. macOS arm64 is a supported runtime tuple, and
the complete exact fixture also passes on Android and iOS emulated runtimes.
Mobile release tuples remain experimental pending physical-device and clean
hosted-matrix validation.

The primary API has build profiles for:

| Target | Current evidence |
| --- | --- |
| Android | A release APK contains armv7, arm64, and x86-64 assets with static libc++, exact libc/libdl/libm dependencies, and verified 16 KiB ELF/APK alignment; Android 15/API 35 arm64 passes the complete runtime fixture. Physical-device validation is pending. |
| iOS | An unsigned arm64 device app passes native framework and manifest verification; an iOS 26.4 Simulator passes the complete 27-case runtime fixture. Physical-device validation is pending. |
| macOS | arm64 has complete exact parity; x86-64 is a build-hook target without accepted runtime parity. |

The legacy `open(libraryPath: ...)` API remains available for an explicitly
built macOS arm64 dylib. Linux and Windows do not build a bundled native asset;
attempting to initialize one fails with `BackendUnavailableException` before
dictionary access.

## Mobile and Flutter use

Keep the exact UniDic directory in application-controlled storage. MeCab needs
real files because it memory-maps the dictionary; a compressed APK asset or an
iOS asset-bundle entry is not a usable dictionary path. An application may
copy or install the resource during its own explicit provisioning flow, then
pass the resulting absolute directory path.

Load the much smaller grouping list as bytes. For Flutter, that can come from
an `AssetBundle` without adding Flutter to this package:

```dart
import 'package:flutter/services.dart';
import 'package:misakid_mecab_ja/misakid_mecab_ja.dart';

Future<List<KokoroG2pChunk>> phonemizeJapanese(
  String text,
  String installedUnidicPath,
) async {
  final data = await rootBundle.load('assets/g2p/ja_words.txt');
  final wordListBytes = data.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );
  final backend = await MecabJapaneseCutletBackend.openBundled(
    dictionaryPath: installedUnidicPath,
    wordListBytes: wordListBytes,
  );
  try {
    final g2p = JapaneseCutletEngine(backend: backend);
    return KokoroNonEnglishG2pFrontend(engine: g2p).convert(text);
  } finally {
    backend.close();
  }
}
```

Reuse one open backend instead of reopening it per utterance. Initialization
streams and hashes the complete 811,662,881-byte dictionary tree, while MeCab
memory-maps its large binary tables. `close()` is idempotent and releases the
native analyzer context.

Each `KokoroG2pChunk` contains source graphemes and the exact phoneme string for
the next layer. Kokoro's non-English source packing and 510-code-point phoneme
limit are already applied. Model vocabulary lookup, BOS/EOS IDs, voice/style
selection, speed, tensor construction, ONNX Runtime, and waveform inference
belong to the separate inference library.

## Required data

The build hook vendors only the licensed MeCab runtime source. Applications
must explicitly provision both data resources:

- UniDic `3.1.0+2021-08-31`: exactly 20 files, 811,662,881 bytes, tree
  SHA-256
  `95bd65fa96955b644c15510932ca8439f463ac8b66f57bac6dfee5e29fa03115`.
- Pinned Misaki `misaki/data/ja_words.txt` at commit
  `fba1236595f2d2bf21d414ba6e57d25256afada3`: 1,921,140 bytes, 147,571
  unique sorted records, SHA-256
  `a93a8e8aee24db307a32becb8bf01c4c2908ecf37e6c91f7a705fafdfeba67ff`,
  with no terminal LF.

`openBundled` validates both identities before returning. It never searches
the device, silently substitutes a different dictionary, or downloads data.
`openBundledWithMembership` accepts a separately reviewed implementation of
`JapaneseCutletWordMembership` when an application cannot redistribute the
pinned list.

The grouping list is not included because its underlying generator and
redistribution terms are undocumented. Supplying the bytes does not grant
redistribution rights. Review `THIRD_PARTY_NOTICES.md` and
`native/SOURCE_MANIFEST.md` before packaging data in an application.

## Exact behavior

`analyzeRaw` exposes owned MeCab surface, nullable UniDic `pron`/`kana`, raw
character type, and unknown status records. `analyze` then performs the pinned
jaconv 0.4.0 Katakana-to-Hiragana conversion and Cutlet longest-match grouping.
`JapaneseCutletEngine` preserves normalization, punctuation, romanization,
sokuon, moraic-nasal, long-vowel, unknown, and null-token behavior from Misaki
0.9.4.

The accepted fixture has 27 adversarial cases and 126 raw UniDic words. The
portable no-iconv profile, compiled and exercised on macOS arm64 and through
bundled native assets on Android 15/API 35 arm64 and an iOS 26.4 Simulator,
matches every raw field, grouping decision, 26 output strings, and the pinned
failure. Normal tests also cover source/resource identity, input limits,
ownership, repeated close, concurrent isolates, and bounded diagnostics.
Physical-device and clean hosted-matrix validation remain outstanding.

## Native build

Normal consumers do not run a custom build command. Dart and Flutter invoke
`hook/build.dart`, which:

1. verifies the vendored 54-file, 4,499,769-byte MeCab subtree;
2. compiles only the 16-file UTF-8 MeCab runtime plus the C ABI shim;
3. uses static libc++ on Android and hides its archive symbols;
4. emits only the 23 reviewed ABI functions; and
5. lets the application toolchain select architecture and deployment target.

The portable configuration intentionally omits iconv. The accepted dictionary
and runtime are both UTF-8, so the corresponding MeCab conversion is an
identity operation; the portable build's exact parity suite proves that this
does not change observable output.

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
MISAKID_MECAB_JA_DICTIONARY=/absolute/path/unidic-3.1.0 \
MISAKID_MECAB_JA_WORD_LIST=/absolute/path/misaki/data/ja_words.txt \
dart test test/native_parity_test.dart
```

Set `MISAKID_MECAB_JA_LIBRARY` as well to exercise the standalone macOS path.
Normal offline CI skips only tests that require the two large external data
resources.
