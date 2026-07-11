# Third-party notices

`misakid_openjtalk` builds an explicitly supplied subset of the Open JTalk
frontend distributed in the `pyopenjtalk==0.4.1` source archive. It does not
bundle that source archive, a dictionary, an HTS voice, or a compiled native
binary.

The complete exact notices used for review and binary redistribution are
included under `native/licenses/`:

- `pyopenjtalk-LICENSE.md` — pyopenjtalk MIT license, SHA-256
  `c38083a4d51c1ea86e08b3303a984d0c23718c5ac214058af705814d30f4bb5b`;
- `open_jtalk-COPYING` — Open JTalk modified BSD notice, SHA-256
  `14f380a0db8dce139fdcfb731d21e993a31a00b68907515d1c54a5f356241343`;
- `mecab-COPYING` — embedded MeCab BSD notice, SHA-256
  `05e94c185a3e31f0c658f7011132be952b6d1a4d588b682f92da380e0a290650`;
  and
- `open_jtalk_dictionary-COPYING` — Open JTalk 1.11 dictionary notices for
  NAIST, the UniDic Consortium, and the HTS Working Group, SHA-256
  `f4eca42ebd930e2c6e57fca58319d989bebcd1510cb7714b149c50f5425135ea`.

The dictionary notice is retained even though the 107 MB dictionary is not
distributed by this package. Applications distributing the built library or
dictionary must retain the applicable notices.

The new ABI, Dart bindings, source verifier, and build safety overlay are
Misakid modifications under Apache-2.0. The exact upstream identities and
modifications are recorded in `native/SOURCE_MANIFEST.md`. The adapter builds
only morphology/pronunciation/accent frontend components; HTS engine and voice
materials are excluded.

## Dart `crypto` dependency

The adapter uses `crypto` only for streaming SHA-256 validation of the native
source and dictionary resources. Release 3.0.7 was reviewed as a pure-Dart
Dart-core package with one small `typed_data` dependency and repository
metadata pointing to `dart-lang/core`. Its included BSD-3-Clause-style license
has SHA-256
`ad6a71997da90924b2cfb1fb47ec46537f70faf469efe016168794ae45ed6888`.
Pub distributes that dependency and its license separately; none of its source
is copied into this package.
