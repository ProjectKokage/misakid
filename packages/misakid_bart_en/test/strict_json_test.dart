import 'package:misakid_bart_en/src/strict_json.dart';
import 'package:test/test.dart';

void main() {
  test('decodes every supported JSON value with Unicode escapes', () {
    final result =
        decodeStrictJson(
              r'{"text":"a\uD83D\uDE00","values":[null,true,false,-2,3.5,1e2]}',
            )!
            as Map<String, Object?>;
    expect(result['text'], 'a😀');
    expect(result['values'], <Object?>[null, true, false, -2, 3.5, 100.0]);
  });

  test('rejects duplicate keys at all nesting levels', () {
    expect(
      () => decodeStrictJson('{"a":1,"a":2}'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => decodeStrictJson('{"outer":{"a":1,"a":2}}'),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects malformed strings, numbers, and trailing data', () {
    for (final source in <String>[
      r'"\uD800"',
      '01',
      '1e309',
      '{} false',
      '[1,]',
    ]) {
      expect(
        () => decodeStrictJson(source),
        throwsA(isA<FormatException>()),
        reason: source,
      );
    }
  });
}
