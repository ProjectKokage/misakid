import 'dart:io';

import 'package:test/test.dart';

import '../tool/verify_vendored_openjtalk.dart';

void main() {
  final vendoredRoot = Directory('native/vendor/open_jtalk');

  test(
    'vendored safety-patched Open JTalk tree has its exact identity',
    () async {
      final identity = await verifyVendoredOpenJtalkTree(vendoredRoot);
      expect(identity.fileCount, expectedVendoredOpenJtalkIdentity.fileCount);
      expect(identity.totalBytes, expectedVendoredOpenJtalkIdentity.totalBytes);
      expect(identity.treeSha256, expectedVendoredOpenJtalkIdentity.treeSha256);
    },
  );

  test('vendored source notices are preserved byte for byte', () async {
    expect(
      await File('${vendoredRoot.path}/COPYING').readAsBytes(),
      orderedEquals(
        await File('native/licenses/open_jtalk-COPYING').readAsBytes(),
      ),
    );
    expect(
      await File('${vendoredRoot.path}/mecab/COPYING').readAsBytes(),
      orderedEquals(await File('native/licenses/mecab-COPYING').readAsBytes()),
    );
  });

  test('portable build enforces signed-char frontend semantics', () async {
    final hook = await File('hook/build.dart').readAsString();
    final assertion = await File('native/src/silent_stdio.c').readAsString();
    expect(hook, contains("language: Language.c"));
    expect(hook, contains("'-fsigned-char'"));
    expect(hook, contains('output.dependencies.addAll(vendorDependencies)'));
    expect(hook, contains('followLinks: false'));
    expect(assertion, contains('CHAR_MIN != -128 || CHAR_MAX != 127'));
  });
}
