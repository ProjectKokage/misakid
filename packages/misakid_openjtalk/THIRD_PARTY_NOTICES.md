# Third-party notices

`misakid_openjtalk` distributes the reviewed Open JTalk frontend and embedded
MeCab source subset originally shipped in the `pyopenjtalk==0.4.1` source
archive. The package contains the safety-v1 patched source tree so Android,
iOS, Linux, macOS, and Windows native-assets builds do not download source. It
does not bundle the source archive, an Open JTalk dictionary, an HTS voice, or
a precompiled native binary.

The complete notices used for source review and binary redistribution are
included under `native/licenses/`:

- `pyopenjtalk-LICENSE.md` — pyopenjtalk MIT license, SHA-256
  `c38083a4d51c1ea86e08b3303a984d0c23718c5ac214058af705814d30f4bb5b`;
- `open_jtalk-COPYING` — Open JTalk modified BSD notice, SHA-256
  `14f380a0db8dce139fdcfb731d21e993a31a00b68907515d1c54a5f356241343`;
- `mecab-COPYING` — embedded MeCab BSD notice, SHA-256
  `05e94c185a3e31f0c658f7011132be952b6d1a4d588b682f92da380e0a290650`;
- `open_jtalk_dictionary-COPYING` — Open JTalk 1.11 dictionary notices for
  NAIST, the UniDic Consortium, and the HTS Working Group, SHA-256
  `f4eca42ebd930e2c6e57fca58319d989bebcd1510cb7714b149c50f5425135ea`;
  and
- `llvm-exception.txt` — LLVM exception to the Apache License 2.0, SHA-256
  `203238b0760c9b4d4c9c7dc90bd65621b1b66085460bed464cb08bbd2f316e21`.

The vendored tree preserves Open JTalk's `COPYING`, embedded MeCab's `COPYING`,
and `mecab-naist-jdic/COPYING` byte for byte. The last of those has the same
SHA-256 as `open_jtalk_dictionary-COPYING`. The dictionary notice is retained
even though the nine-file, 107,304,813-byte dictionary is not distributed by
this package. Applications distributing the built native asset or dictionary
must retain all applicable notices.

The new ABI, Dart bindings, source verifier, native-assets hook, portable
configuration, and safety overlay are Misakid modifications under Apache-2.0.
The exact upstream identities and modifications are recorded in
`native/SOURCE_MANIFEST.md`. Only morphology, pronunciation, and accent
frontend components are linked; HTS engine and voice materials are excluded.

## Android LLVM libc++

The Android build profile requests the NDK C++ standard library as
`c++_static`. Consequently, portions of LLVM libc++ supplied by the consuming
Android NDK are embedded in each Android `libmisakid_openjtalk.so` instead of
being a separate `libc++_shared.so` dependency.

LLVM libc++ is licensed under Apache License 2.0 with the LLVM exception. The
full Apache License 2.0 text is the package `LICENSE`; the exact LLVM exception
is retained as `native/licenses/llvm-exception.txt`. Applications distributing
an Android binary produced by the hook are responsible for carrying those
terms and any additional notices required by the exact NDK/toolchain they use.
Apple profiles use the platform C++ runtime rather than embedding this Android
static runtime. Linux and Windows likewise use the consuming platform
toolchain's C++ runtime; applications must retain any terms required by the
exact compiler/runtime they distribute.

## Dart native-assets toolchain dependencies

The package uses the Dart team's `code_assets==1.2.1`, `hooks==2.0.2`, and
`native_toolchain_c==0.19.2` packages only to declare, orchestrate, and compile
its reproducible native code asset. Their maintained upstream is
`dart-lang/native`; these versions were reviewed against the package's Dart
3.11 native-hooks contract and replace bespoke platform build orchestration.
All three use the Dart project's BSD-3-Clause-style license. The `code_assets`
and `hooks` license files each have SHA-256
`21ae23b0b9ff67a2dc75ab085d1e8db8ac548c5faf370af17f28dd2ef3b52b7b`;
the `native_toolchain_c` license has SHA-256
`aa81abb1ac43e40d2f5a606385edd37e974a5858d4109f7f439dd43d964487a7`.
Pub distributes those dependencies and their licenses separately; none of
their source is copied into this package.

## Dart `crypto` dependency

The adapter uses `crypto` only for streaming SHA-256 validation of native
source and dictionary resources. Release 3.0.7 was reviewed as a pure-Dart
Dart-core package with one small `typed_data` dependency and repository
metadata pointing to `dart-lang/core`. Its included BSD-3-Clause-style license
has SHA-256
`ad6a71997da90924b2cfb1fb47ec46537f70faf469efe016168794ae45ed6888`.
Pub distributes that dependency and its license separately; none of its source
is copied into this package.
