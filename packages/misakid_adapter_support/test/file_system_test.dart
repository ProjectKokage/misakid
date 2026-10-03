import 'dart:io';

import 'package:misakid_adapter_support/file_system.dart';
import 'package:test/test.dart';

void main() {
  test('an absolute path follows the current platform', () {
    expect(isAbsoluteFilePath(''), isFalse);
    expect(isAbsoluteFilePath('relative/path'), isFalse);
    if (Platform.isWindows) {
      expect(isAbsoluteFilePath(r'C:\models'), isTrue);
      expect(isAbsoluteFilePath('C:/models'), isTrue);
      expect(isAbsoluteFilePath(r'\\server\share'), isTrue);
      expect(isAbsoluteFilePath('/models'), isFalse);
    } else {
      expect(isAbsoluteFilePath('/models'), isTrue);
      expect(isAbsoluteFilePath(r'C:\models'), isFalse);
    }
  });

  test('a snapshot matches its file until the file changes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'misakid_adapter_support_',
    );
    try {
      final file = File('${directory.path}${Platform.pathSeparator}data.bin');
      await file.writeAsBytes(<int>[1, 2, 3]);
      final snapshot = FileSnapshot.fromStat(await file.stat());

      expect(snapshot.size, 3);
      expect(snapshot.matches(await file.stat()), isTrue);

      await file.writeAsBytes(<int>[1, 2, 3, 4]);
      expect(snapshot.matches(await file.stat()), isFalse);

      expect(snapshot.matches(await directory.stat()), isFalse);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
