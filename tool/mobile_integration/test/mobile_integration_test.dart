import 'package:flutter/material.dart' show Key;
import 'package:flutter_test/flutter_test.dart';
import 'package:misakid/misaki.dart';
import 'package:misakid_mobile_integration/main.dart';

void main() {
  testWidgets('passes explicit resource paths to the bundled-backend probe', (
    tester,
  ) async {
    String? capturedDictionaryPath;
    String? capturedWordListPath;
    await tester.pumpWidget(
      MobileIntegrationApp(
        probe:
            ({
              required String dictionaryPath,
              required String wordListPath,
            }) async {
              capturedDictionaryPath = dictionaryPath;
              capturedWordListPath = wordListPath;
              return BundledBackendProbeResult(
                backend: BackendInfo(name: 'mecab-test', version: '1'),
                input: '日本語です',
                phonemes: 'ɲiʔpoŋɡo desɨ',
              );
            },
      ),
    );

    await tester.enterText(
      find.byKey(const Key('dictionaryPath')),
      '/data/unidic-3.1.0',
    );
    await tester.enterText(
      find.byKey(const Key('wordListPath')),
      '/data/ja_words.txt',
    );
    await tester.tap(find.byKey(const Key('probeButton')));
    await tester.pumpAndSettle();

    expect(capturedDictionaryPath, '/data/unidic-3.1.0');
    expect(capturedWordListPath, '/data/ja_words.txt');
    expect(
      find.text('G2P ready: mecab-test 1\n日本語です → ɲiʔpoŋɡo desɨ'),
      findsOneWidget,
    );
  });

  testWidgets('does not probe without both external paths', (tester) async {
    var called = false;
    await tester.pumpWidget(
      MobileIntegrationApp(
        probe:
            ({
              required String dictionaryPath,
              required String wordListPath,
            }) async {
              called = true;
              return BundledBackendProbeResult(
                backend: BackendInfo(name: 'unexpected', version: '1'),
                input: '日本語です',
                phonemes: 'unexpected',
              );
            },
      ),
    );

    await tester.tap(find.byKey(const Key('probeButton')));
    await tester.pump();

    expect(called, isFalse);
    expect(
      find.text('Both absolute resource paths are required.'),
      findsOneWidget,
    );
  });

  testWidgets('passes the Open JTalk dictionary to its bundled probe', (
    tester,
  ) async {
    String? capturedDictionaryPath;
    await tester.pumpWidget(
      MobileIntegrationApp(
        openJtalkProbe: ({required String dictionaryPath}) async {
          capturedDictionaryPath = dictionaryPath;
          return BundledBackendProbeResult(
            backend: BackendInfo(name: 'pyopenjtalk-test', version: '1'),
            input: '日本語です',
            phonemes: 'test-phones',
          );
        },
      ),
    );

    await tester.enterText(
      find.byKey(const Key('openJtalkDictionaryPath')),
      '/data/open_jtalk_dic_utf_8-1.11',
    );
    await tester.ensureVisible(find.byKey(const Key('openJtalkProbeButton')));
    await tester.tap(find.byKey(const Key('openJtalkProbeButton')));
    await tester.pumpAndSettle();

    expect(capturedDictionaryPath, '/data/open_jtalk_dic_utf_8-1.11');
    expect(
      find.text('G2P ready: pyopenjtalk-test 1\n日本語です → test-phones'),
      findsOneWidget,
    );
  });

  testWidgets('does not probe Open JTalk without its dictionary path', (
    tester,
  ) async {
    var called = false;
    await tester.pumpWidget(
      MobileIntegrationApp(
        openJtalkProbe: ({required String dictionaryPath}) async {
          called = true;
          return BundledBackendProbeResult(
            backend: BackendInfo(name: 'unexpected', version: '1'),
            input: '日本語です',
            phonemes: 'unexpected',
          );
        },
      ),
    );

    await tester.ensureVisible(find.byKey(const Key('openJtalkProbeButton')));
    await tester.tap(find.byKey(const Key('openJtalkProbeButton')));
    await tester.pump();

    expect(called, isFalse);
    expect(
      find.text('The Open JTalk dictionary path is required.'),
      findsOneWidget,
    );
  });
}
