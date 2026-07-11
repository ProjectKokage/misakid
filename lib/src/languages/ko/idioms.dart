// Dart adaptation of hexgrad/misaki/misaki/g2pkc/g2pk.py idioms processing
// and idioms.txt at fba1236595f2d2bf21d414ba6e57d25256afada3.
// Copied/adapted through 5Hyeons/StyleTTS2 from Kyubyong/g2pK under
// Apache-2.0. Modifications: consumes a generated immutable ordered table.

import '../../generated/korean_g2pkc_data.dart';

/// Applies all pinned g2pkc idiom replacements in source-file order.
String applyKoreanG2pkcIdioms(String input) {
  var output = input;
  for (final (source, replacement) in koreanG2pkcIdioms) {
    output = output.replaceAll(source, replacement);
  }
  return output;
}
