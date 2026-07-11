import 'dart:io';
import 'dart:typed_data';

import 'package:misakid_mecab_ja/misakid_mecab_ja.dart';
import 'package:test/test.dart';

void main() {
  test('publishes the exact immutable list identity', () {
    expect(
      pinnedMisakiCutletWordsSha256,
      'a93a8e8aee24db307a32becb8bf01c4c2908ecf37e6c91f7a705fafdfeba67ff',
    );
    expect(pinnedMisakiCutletWordsSizeBytes, 1921140);
    expect(pinnedMisakiCutletWordsRecordCount, 147571);
  });

  test('rejects relative, missing, and wrong-size resources', () async {
    await expectLater(
      PinnedMisakiCutletWordMembership.open('relative'),
      throwsA(isA<InvalidConfigurationException>()),
    );
    await expectLater(
      PinnedMisakiCutletWordMembership.open(
        '${Directory.systemTemp.absolute.path}/does-not-exist-$pid',
      ),
      throwsA(isA<BackendUnavailableException>()),
    );

    final temporary = await Directory.systemTemp.createTemp('ja-words-test-');
    try {
      final file = File('${temporary.path}/ja_words.txt');
      await file.writeAsString('あ\nい');
      await expectLater(
        PinnedMisakiCutletWordMembership.open(file.path),
        throwsA(isA<MalformedDataException>()),
      );
    } finally {
      await temporary.delete(recursive: true);
    }
  });

  test('byte-backed loading applies exact identity validation', () {
    expect(
      () => PinnedMisakiCutletWordMembership.fromBytes(Uint8List(0)),
      throwsA(isA<MalformedDataException>()),
    );
    expect(
      () => PinnedMisakiCutletWordMembership.fromBytes(
        Uint8List(pinnedMisakiCutletWordsSizeBytes),
      ),
      throwsA(isA<MalformedDataException>()),
    );
  });

  test(
    'rejects a symbolic-link resource',
    () async {
      final temporary = await Directory.systemTemp.createTemp('ja-words-test-');
      try {
        final target = File('${temporary.path}/target')..writeAsStringSync('x');
        final link = Link('${temporary.path}/ja_words.txt')
          ..createSync(target.path);
        await expectLater(
          PinnedMisakiCutletWordMembership.open(link.path),
          throwsA(isA<MalformedDataException>()),
        );
      } finally {
        await temporary.delete(recursive: true);
      }
    },
    skip: Platform.isWindows ? 'Creating links may require elevation.' : false,
  );
}
