// Dart adaptation of pure helpers in hexgrad/misaki/misaki/zh.py at
// fba1236595f2d2bf21d414ba6e57d25256afada3 (Misaki 0.9.4,
// Apache-2.0).
//
// Modifications: use explicit Unicode-scalar whitespace handling and replace
// the upstream assertion with a typed malformed-data failure.

import '../../core/errors.dart';
import '../../core/python_whitespace.dart';

/// Replaces legacy Mandarin tone contours and syllabic-r variants.
String retoneLegacyChinese(String phonemes) {
  final result = phonemes
      .replaceAll('˧˩˧', '↓')
      .replaceAll('˧˥', '↗')
      .replaceAll('˥˩', '↘')
      .replaceAll('˥', '→')
      .replaceAll('ɻ̩', 'ɨ')
      .replaceAll('ɹ̩', 'ɨ');
  if (result.contains('̩')) {
    throw const MalformedDataException(
      'Legacy Chinese transcription left an unsupported syllabic mark.',
    );
  }
  return result;
}

/// Maps pinned Chinese punctuation and trims Python-style outer whitespace.
String mapLegacyChinesePunctuation(String text) {
  final mapped = text
      .replaceAll('、', ', ')
      .replaceAll('，', ', ')
      .replaceAll('。', '. ')
      .replaceAll('．', '. ')
      .replaceAll('！', '! ')
      .replaceAll('：', ': ')
      .replaceAll('；', '; ')
      .replaceAll('？', '? ')
      .replaceAll('«', ' “')
      .replaceAll('»', '” ')
      .replaceAll('《', ' “')
      .replaceAll('》', '” ')
      .replaceAll('「', ' “')
      .replaceAll('」', '” ')
      .replaceAll('【', ' “')
      .replaceAll('】', '” ')
      .replaceAll('（', ' (')
      .replaceAll('）', ') ');
  return _pythonTrim(mapped);
}

String _pythonTrim(String value) {
  final runes = value.runes.toList(growable: false);
  var start = 0;
  while (start < runes.length && isPythonWhitespace(runes[start])) {
    start++;
  }
  var end = runes.length;
  while (end > start && isPythonWhitespace(runes[end - 1])) {
    end--;
  }
  return String.fromCharCodes(runes.sublist(start, end));
}
