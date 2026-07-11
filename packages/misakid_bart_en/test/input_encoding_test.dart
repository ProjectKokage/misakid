import 'package:misakid/misaki.dart';
import 'package:misakid_bart_en/src/config.dart';
import 'package:misakid_bart_en/src/input_encoding.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

void main() {
  late Map<int, int> graphemeMap;

  setUpAll(() {
    graphemeMap = buildBartGraphemeMap(
      BartConfig.parse(syntheticConfigBytes()),
    );
  });

  test('encodes known, duplicate-placeholder, and unknown scalars exactly', () {
    List<int> encode(String text) => encodeBartEnglishInput(
      text: text,
      graphemeToToken: graphemeMap,
      maximumCodePoints: 6,
    );

    expect(encode('ab'), <int>[1, 4, 5, 2]);
    expect(encode('?'), <int>[1, 7, 2]);
    expect(encode('_'), <int>[1, 3, 2]);
    expect(encode('😀'), <int>[1, 3, 2]);
    expect(() => encode('ab').add(4), throwsUnsupportedError);
  });

  test('rejects invalid Unicode and stops at the scalar bound', () {
    expect(
      () => encodeBartEnglishInput(
        text: String.fromCharCode(0xD800),
        graphemeToToken: graphemeMap,
        maximumCodePoints: 6,
      ),
      throwsA(isA<BackendFailureException>()),
    );
    expect(
      () => encodeBartEnglishInput(
        text: 'a' * 100000,
        graphemeToToken: graphemeMap,
        maximumCodePoints: 6,
      ),
      throwsA(isA<BackendFailureException>()),
    );
  });
}
