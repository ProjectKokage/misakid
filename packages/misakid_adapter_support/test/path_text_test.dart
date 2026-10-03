import 'package:misakid_adapter_support/path_text.dart';
import 'package:test/test.dart';

void main() {
  test('accepts well-formed text up to the byte limit', () {
    expect(isValidPathText(''), isTrue);
    expect(isValidPathText('/models/日本語/辞書'), isTrue);
    expect(isValidPathText('/emoji/\u{1F600}'), isTrue);
    expect(isValidPathText('a' * maximumPathUtf8Bytes), isTrue);
  });

  test('counts UTF-8 bytes, not UTF-16 units', () {
    // U+00E9 is one UTF-16 unit and two UTF-8 bytes.
    expect(isValidPathText('\u00e9' * (maximumPathUtf8Bytes ~/ 2)), isTrue);
    expect(
      isValidPathText('\u00e9' * (maximumPathUtf8Bytes ~/ 2 + 1)),
      isFalse,
    );
    // A surrogate pair is two UTF-16 units and four UTF-8 bytes.
    expect(isValidPathText('\u{1F600}' * (maximumPathUtf8Bytes ~/ 4)), isTrue);
    expect(
      isValidPathText('\u{1F600}' * (maximumPathUtf8Bytes ~/ 4 + 1)),
      isFalse,
    );
  });

  test('rejects NUL, unpaired surrogates and text over the limit', () {
    expect(isValidPathText('/a\u0000b'), isFalse);
    expect(isValidPathText('/a${String.fromCharCode(0xD800)}'), isFalse);
    expect(isValidPathText('/a${String.fromCharCode(0xD800)}b'), isFalse);
    expect(isValidPathText('/a${String.fromCharCode(0xDC00)}b'), isFalse);
    expect(isValidPathText('a' * (maximumPathUtf8Bytes + 1)), isFalse);
  });
}
