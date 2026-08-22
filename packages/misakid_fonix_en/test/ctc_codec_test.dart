import 'dart:typed_data';

import 'package:misakid/misaki.dart';
import 'package:misakid_fonix_en/src/ctc_codec.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

void main() {
  final codec = EnglishCtcCodec(testProfile());

  test('encodes exact Unicode scalars without substitution', () {
    expect(codec.encode('ab'), Int64List.fromList(<int>[2, 3]));
    expect(
      () => codec.encode('é'),
      throwsA(
        isA<BackendFailureException>().having(
          (error) => error.message,
          'message',
          contains('U+00E9'),
        ),
      ),
    );
    expect(() => codec.encode(''), throwsA(isA<BackendFailureException>()));
    expect(
      () => codec.encode(String.fromCharCode(0xd800)),
      throwsA(isA<BackendFailureException>()),
    );
  });

  test('greedily collapses CTC repeats separated by blanks', () {
    final ids = <int>[1, 1, 0, 1, 2, 2, 0, 2];
    final values = Float32List(ids.length * 3);
    for (var step = 0; step < ids.length; step++) {
      values[step * 3 + ids[step]] = 1;
    }

    final result = codec.decode(
      EnglishCtcLogits(shape: const <int>[1, 8, 3], values: values),
      inputLength: 1,
    );

    expect(result, 'ppqq');
  });

  test('rejects malformed, non-finite, and empty output', () {
    expect(
      () => codec.decode(
        EnglishCtcLogits(shape: const <int>[1, 7, 3], values: Float32List(21)),
        inputLength: 1,
      ),
      throwsA(isA<BackendFailureException>()),
    );

    final nonFinite = Float32List(24)..[2] = double.nan;
    expect(
      () => codec.decode(
        EnglishCtcLogits(shape: const <int>[1, 8, 3], values: nonFinite),
        inputLength: 1,
      ),
      throwsA(isA<BackendFailureException>()),
    );

    expect(
      () => codec.decode(
        EnglishCtcLogits(shape: const <int>[1, 8, 3], values: Float32List(24)),
        inputLength: 1,
      ),
      throwsA(isA<BackendFailureException>()),
    );
  });
}
