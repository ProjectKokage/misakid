/// The longest path, in UTF-8 bytes, that the adapters and their native shims
/// accept.
const int maximumPathUtf8Bytes = 32768;

/// Whether [path] is well-formed text that fits [maximumPathUtf8Bytes].
///
/// Rejects NUL, unpaired surrogates and text whose UTF-8 encoding is longer
/// than the limit. An empty string is accepted; callers that require a path
/// check for that themselves.
bool isValidPathText(String path) {
  var utf8Bytes = 0;
  final units = path.codeUnits;
  for (var index = 0; index < units.length; index++) {
    final unit = units[index];
    if (unit == 0) return false;
    if (unit <= 0x7F) {
      utf8Bytes++;
    } else if (unit <= 0x7FF) {
      utf8Bytes += 2;
    } else if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (index + 1 >= units.length ||
          units[index + 1] < 0xDC00 ||
          units[index + 1] > 0xDFFF) {
        return false;
      }
      utf8Bytes += 4;
      index++;
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      return false;
    } else {
      utf8Bytes += 3;
    }
    if (utf8Bytes > maximumPathUtf8Bytes) return false;
  }
  return true;
}
