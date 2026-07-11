# misakid_mobile_integration

Repository-owned Flutter build harness for the bundled native asset in
`misakid_mecab_ja`. It is intentionally an app rather than a Flutter dependency
of the root package.

The UI reaches the public `MecabJapaneseCutletBackend.openBundled` path using
two runtime-provided absolute paths and converts `日本語です` with a real
`JapaneseCutletEngine`. This keeps the native backend and conversion path
reachable in release builds while preserving the adapter's explicit-resource
contract.

No UniDic files or `ja_words.txt` bytes belong in this directory. A real app
must obtain the separately reviewed resources itself, materialize UniDic in
application support storage, and supply the word-list bytes explicitly.

From this directory:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release \
  --target-platform android-arm,android-arm64,android-x64
flutter build ios --release --no-codesign
```

The normal `mobile_integration.yml` workflow runs the same builds and then uses
`tool/verify_mobile_artifacts.py` to verify the native Android ABIs, ELF and APK
16-KiB alignment, and the exact 23-symbol adapter export surface. Its iOS check
also requires an arm64 `IOS` framework with iOS 13 or newer load metadata, the
expected install name and system linkage, an application framework rpath, and
an exact native-assets manifest mapping to the packaged framework. These are
packaging checks, not runtime parity tests.

## Provisioned device parity gate

`integration_test/japanese_mobile_parity_test.dart` is deliberately outside
the normal `test/` directory. It runs only when explicitly selected on an
Android emulator or iOS simulator. The test:

- streams the exact 20-file UniDic tree, pinned `ja_words.txt`, and committed
  fixture through an authenticated host-loopback server into application
  temporary storage;
- verifies every streamed byte count and SHA-256 before opening the public
  bundled backend;
- compares all 27 fixture cases and all 126 raw records, including nullable
  pronunciation/kana, all grouped fields, and the 12 grouping links;
- compares all 26 successful phoneme strings and null-token results exactly;
  and
- requires the pinned `long-number-diagnostic` `BackendFailureException` and
  exact diagnostic message.

The test-only server is `tool/serve_mobile_resources.py`. It binds only
`127.0.0.1`, requires a bearer token, exposes no directory listing, validates
all external sources before listening, and serves only its fixed manifest and
resource routes. Android reaches that host listener through the emulator's
`10.0.2.2` alias; the iOS simulator uses `localhost`. Cleartext exceptions are
debug-only (`android/app/src/debug` and `ios/Runner/Info-Debug.plist`), so the
release application configuration remains unchanged.

The separate `mobile_runtime_parity.yml` workflow runs this gate on an actual
Android emulator and iOS simulator. It is manual and release-tag triggered,
not part of normal pull-request testing. Each job explicitly downloads the
immutable UniDic recovery archive and pinned word list, checks archive/file
sizes and SHA-256 values, extracts UniDic, starts the loopback server, and then
runs the device test. It neither commits nor uploads the linguistic resources.
The expensive network/bootstrap work therefore stays outside normal offline
tests.

Local evidence recorded on 2026-07-11: stable Flutter 3.41.7 ran the complete
gate successfully on an Android 15/API 35 arm64 emulator and an iPhone 17 Pro
iOS 26.4 Simulator. Each test loaded its bundled native asset, provisioned and
validated all external resources in the application sandbox, and passed all 27
cases, 126 raw/grouped records, 12 links, 26 exact outputs/null-token results,
and the pinned failure. The clean hosted x86-64 Android/iOS matrix and physical
devices remain release gates.

For a locally provisioned device run, first prepare the exact resources using
the identities and bootstrap instructions in `../../tool/reference/README.md`,
then start the loopback server and pass its URL and token as compile-time
defines:

```sh
flutter test integration_test/japanese_mobile_parity_test.dart \
  -d <device-id> \
  --dart-define=MISAKID_TEST_RESOURCE_BASE_URL=http://<loopback-host>:<port> \
  --dart-define=MISAKID_TEST_RESOURCE_TOKEN=<token>
```

Host filesystem paths are never passed to the app. The server provisions the
resources into the app/simulator sandbox before `openBundled` is called.
