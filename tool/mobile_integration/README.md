# misakid_mobile_integration

Repository-owned Flutter build harness for the bundled native assets in
`misakid_mecab_ja` and `misakid_openjtalk`. It is intentionally an app rather
than a Flutter dependency of the root package.

The UI reaches both public bundled-backend paths using runtime-provided
absolute paths and converts `日本語です` with real `JapaneseCutletEngine` and
`JapanesePyopenjtalkEngine` instances. This keeps both native assets and
conversion paths reachable in release builds while preserving their
explicit-resource contracts.

No UniDic, `ja_words.txt`, or Open JTalk dictionary bytes belong in this
directory. A real app may provide any licensed UniDic accepted by the Cutlet
adapter's compatible profile; the provisioned parity gate deliberately selects
and validates the pinned modified unidic-py CWJ profile by complete tree hash.
Feature-layout compatibility alone does not identify CWJ, CSJ, a release, or
the exact resource. Applications must materialize the required dictionary trees
at absolute filesystem paths and supply the Cutlet word-list bytes explicitly.

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
`tool/verify_mobile_artifacts.py` to verify both libraries across the Android
ABIs, ELF and APK 16-KiB alignment, libc/libdl/libm-only linkage, exact
24-symbol Cutlet and 23-symbol Open JTalk export surfaces, and both NativeAssets
mappings. Its iOS
check requires both arm64 `IOS` frameworks with iOS 13 or newer metadata,
their expected install names and system linkage, an application framework
rpath, exact exports, and both manifest mappings. These are packaging checks,
not runtime parity tests.

## Provisioned device parity gates

`integration_test/japanese_mobile_parity_test.dart` is deliberately outside
the normal `test/` directory. It runs only when explicitly selected on an
Android emulator or iOS simulator. The test:

- streams the exact 20-file modified unidic-py CWJ tree, pinned `ja_words.txt`,
  and committed fixture through an authenticated host-loopback server into
  application temporary storage;
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
immutable modified unidic-py CWJ recovery archive and pinned word list, checks
archive/file sizes and SHA-256 values, extracts the dictionary, starts the
loopback server, and then runs the device test. It neither commits nor uploads
the linguistic resources.

The expensive network/bootstrap work therefore stays outside normal offline
tests.

`integration_test/japanese_openjtalk_mobile_parity_test.dart` is the parallel
Open JTalk gate. Its separate authenticated server,
`tool/serve_openjtalk_mobile_resources.py`, provisions the exact nine-file,
107,304,813-byte Open JTalk 1.11 dictionary and the committed fixture into the
application sandbox. The test opens the public bundled backend and raw native
bindings, then compares all 24 cases, all 155 raw words and 14 fields, all 23
successful phoneme strings and typed token graphs, and the exact pinned
whitespace failure. The manual/tag workflow validates the 23,646,843-byte
dictionary archive and fixture before starting that server.

Local evidence recorded on 2026-07-11 with stable Flutter 3.41.7:

- Cutlet passed on an Android 15/API 35 arm64 emulator and iPhone 17 Pro iOS
  26.4 Simulator: 27 cases, 126 raw/grouped records, 12 links, 26 outputs, and
  the pinned failure.
- Open JTalk passed on an Android 15/API 35 arm64 emulator and iPhone 17 iOS
  26.5 Simulator: 24 cases, 155 raw records and 14 fields, 23 outputs with
  typed tokens, and the pinned failure.

Both tests loaded package-built native assets and checksum-validated external
resources in the application sandbox. The clean hosted x86-64 Android/iOS
matrix and physical devices remain release gates.

For a locally provisioned device run, first prepare the exact resources using
the identities and bootstrap instructions in `../../tool/reference/README.md`,
then start the loopback server and pass its URL and token as compile-time
defines:

```sh
flutter test integration_test/japanese_mobile_parity_test.dart \
  -d <device-id> \
  --dart-define=MISAKID_TEST_RESOURCE_BASE_URL=http://<loopback-host>:<port> \
  --dart-define=MISAKID_TEST_RESOURCE_TOKEN=<token>

flutter test integration_test/japanese_openjtalk_mobile_parity_test.dart \
  -d <device-id> \
  --dart-define=MISAKID_OPENJTALK_TEST_RESOURCE_BASE_URL=http://<loopback-host>:<port> \
  --dart-define=MISAKID_OPENJTALK_TEST_RESOURCE_TOKEN=<token>
```

Host filesystem paths are never passed to the app. The server provisions the
resources into the app/simulator sandbox before `openBundled` is called.
