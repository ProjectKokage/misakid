import 'dart:io';

import 'package:misakid/misaki.dart';
import 'package:misakid_bart_en/src/bounded_file_reader.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('misakid-bart-read-');
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test('returns only an exact bounded file', () async {
    final file = File('${temporary.path}/exact')
      ..writeAsBytesSync(<int>[1, 2, 3]);
    expect(await readExactlyBoundedFile(file, 3), <int>[1, 2, 3]);
  });

  test('rejects EOF before the expected byte count', () async {
    final file = File('${temporary.path}/short')..writeAsBytesSync(<int>[1, 2]);
    await expectLater(
      readExactlyBoundedFile(file, 3),
      throwsA(isA<MalformedDataException>()),
    );
  });

  test('rejects one extra byte instead of reading an unbounded file', () async {
    final file = File('${temporary.path}/long')
      ..writeAsBytesSync(<int>[1, 2, 3, 4]);
    await expectLater(
      readExactlyBoundedFile(file, 3),
      throwsA(isA<MalformedDataException>()),
    );
  });
}
