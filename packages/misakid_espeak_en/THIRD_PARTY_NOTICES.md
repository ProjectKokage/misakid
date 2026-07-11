# Third-party notices

`misakid_espeak_en` contains only Apache-2.0 Dart code and a package-owned
Apache-2.0 native shim. The shim declares the public eSpeak C functions it
needs and loads them dynamically; it does not copy an eSpeak or phonemizer
header, source file, table, model, voice, data file, or binary.

## Caller-supplied eSpeak NG runtime

The supported compatibility tuple uses eSpeak NG 1.52.0. eSpeak NG is
GPL-3.0-or-later:

https://github.com/espeak-ng/espeak-ng

The exact external macOS-arm64 library is 504,168 bytes with SHA-256
`bb635eee1ee9c456f4a5cf06fb6cb352ecdd4d61e1951743b423ef22bb57f470`.
The exact external data tree contains 364 files and 18,373,365 bytes with
canonical SHA-256
`730e20a0d06976b23b8344bac21dab6e1da447d0e16906bab6a0b54db89dd6e2`.
Neither artifact is included, downloaded, discovered, or redistributed by
this package. Applications must obtain and comply with the runtime's license
separately and pass both absolute paths explicitly.

## Observable phonemizer contract

Pinned Misaki uses `phonemizer-fork==3.3.2`, which declares GPL-3.0. This
package includes no phonemizer code. Its small formatting stage is a clean-room
implementation of the observable option tuple captured in authoritative
fixtures: English US/GB, punctuation preservation, stress preservation, and
`^` ties. Exact raw-call fixtures are factual interoperability records.

The `espeakng-loader==0.2.4` wheel used only to provision the reference oracle
does not declare a package license in its installed metadata. This adapter
does not depend on or redistribute that loader.

## Provisioned composition test

The provisioned end-to-end test also opens the exact MIT-licensed
`en_core_web_sm==3.8.0` resource subset through the sibling pure-Dart
`misakid_spacy_en` development dependency. No spaCy model artifact is bundled
or published by this package. Its four external file identities and model
attribution are documented in `misakid_spacy_en/RESOURCE_MANIFEST.md` and that
package's third-party notices.

A separate provisioned development test opens the reviewed caller-supplied
`en_core_web_trf==3.8.0` resources and package-owned native adapter through the
sibling `misakid_spacy_trf_en` development dependency. No transformer model or
native binary is bundled or published by this package. The wheel's declared
license, complete source ledger, exact external identities, and associated
license caveats are documented in `misakid_spacy_trf_en/RESOURCE_MANIFEST.md`
and that package's third-party notices.
