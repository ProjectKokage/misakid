import 'package:misakid/misaki_vi.dart';
import 'package:misakid/src/languages/vi/phonology.dart';
import 'package:misakid/src/languages/vi/subtoken.dart';
import 'package:test/test.dart';

void main() {
  const options = VietnameseOptions();

  test('replays pinned Blôk and Êban substring examples', () {
    expect(_parts('Blôk', options), <(String?, String, String)>[
      ('Blôk', 'b', 'b/e//1'),
      ('Blôk', 'lôk', 'l/o/k͡p/1'),
    ]);
    expect(_parts('Êban', options), <(String?, String, String)>[
      ('Êban', 'ê', '/e//1'),
      ('Êban', 'ban', 'b/a/n/1'),
    ]);
  });

  test('spells unresolved uppercase ASCII and Vietnamese letters', () {
    expect(_parts('FBI', options), <(String?, String, String)>[
      ('FBI', 'f', '/ɛ/p/5'),
      ('FBI', 'b', 'b/i//1'),
      ('FBI', 'i', '/a/j/1'),
    ]);
    expect(_parts('Đ', options), <(String?, String, String)>[
      ('Đ', 'đ', 'd/e//1'),
    ]);
  });

  test('preserves one bracketed token when substring mode is disabled', () {
    const disabled = VietnameseOptions(substringTokenization: false);
    final firstAttempt = convertVietnameseWord('blôk', disabled);
    final parts = splitVietnameseToken('Blôk', firstAttempt, disabled);

    expect(parts, hasLength(1));
    expect(parts.single.parent, isNull);
    expect(parts.single.text, 'blôk');
    expect(parts.single.phonemes, '[blôk]');
  });
}

List<(String?, String, String)> _parts(
  String token,
  VietnameseOptions options,
) {
  final firstAttempt = convertVietnameseWord(token.toLowerCase(), options);
  return <(String?, String, String)>[
    for (final part in splitVietnameseToken(token, firstAttempt, options))
      (part.parent, part.text, part.phonemes),
  ];
}
