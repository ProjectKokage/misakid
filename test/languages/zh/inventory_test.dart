import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:misakid/misaki_zh.dart';
import 'package:test/test.dart';

void main() {
  test('exposes exact immutable source-derived inventories by mode', () {
    final legacy = chinesePhonemeInventory(ChinesePhonemeMode.legacy);
    final frontend11 = chinesePhonemeInventory(ChinesePhonemeMode.frontend11);

    expect(legacy.every((symbol) => symbol.runes.length == 1), isTrue);
    expect(frontend11.every((symbol) => symbol.runes.length == 1), isTrue);
    expect(legacy, hasLength(38));
    expect(frontend11, hasLength(80));
    expect(
      _digest(legacy),
      '50303411b50559142cdaeaeef8adcad628830242f56325222c545711a7e46e73',
    );
    expect(
      _digest(frontend11),
      '213cf5b301ad267dd323fcc943dbaf1412ca1874c41f4518fe06af46a088c1eb',
    );

    expect(
      legacy,
      containsAll(<String>{'p', 'ʦ', 'ꭧ', 'ɻ', 'ɨ', 'ɚ', '→', '↗', '↓', '↘'}),
    );
    for (final excluded in <String>{
      ' ',
      '/',
      '.',
      '❓',
      'ʐ',
      '̩',
      '̯',
      '˥',
      '˧',
      '˩',
    }) {
      expect(legacy, isNot(contains(excluded)));
    }

    expect(
      frontend11,
      containsAll(<String>{
        'ㄅ',
        'ㄦ',
        'ㄭ',
        '十',
        '月',
        '元',
        '云',
        ' ',
        '/',
        '…',
        '1',
        '5',
        'R',
      }),
    );
    expect(frontend11, isNot(contains(anyOf('b', 'zh', '_', 'A', '❓'))));

    expect(() => legacy.add('x'), throwsUnsupportedError);
    expect(() => frontend11.add('x'), throwsUnsupportedError);
    expect(
      identical(legacy, chinesePhonemeInventory(ChinesePhonemeMode.legacy)),
      isTrue,
    );
    expect(
      identical(
        frontend11,
        chinesePhonemeInventory(ChinesePhonemeMode.frontend11),
      ),
      isTrue,
    );
  });
}

String _digest(Set<String> inventory) {
  final canonical = inventory.toList(growable: false)..sort();
  return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
}
