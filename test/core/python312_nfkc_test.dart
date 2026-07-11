import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:misakid/src/core/python312_nfkc.dart';
import 'package:misakid/src/core/python312_unicode.dart';
import 'package:misakid/src/generated/python312_nfkc_data.dart';
import 'package:test/test.dart';

void main() {
  group('normalizePython312Nfkc', () {
    final cases = <String, String>{
      '': '',
      'plain ASCII': 'plain ASCII',
      'ＡＢＣ１２３': 'ABC123',
      'ﬃ': 'ffi',
      'A\u030a\u0301': 'Ǻ',
      'Å': 'Å',
      '\u1100\u1161\u11a8': '각',
      'a\u0315\u0300': 'à\u0315',
      '𝐀': 'A',
      // CYRILLIC SUBSCRIPT SMALL LETTER A was added after Unicode 8. This is
      // the regression that an older host-independent table misses.
      '𞀰': 'а',
    };
    for (final entry in cases.entries) {
      test('normalizes ${entry.key}', () {
        expect(normalizePython312Nfkc(entry.key), entry.value);
      });
    }

    test('preserves isolated UTF-16 surrogates like Python strings do', () {
      final input = String.fromCharCodes(<int>[0xd800, 0x41, 0xdc00]);
      expect(normalizePython312Nfkc(input).codeUnits, input.codeUnits);
    });

    test('matches the accepted Python digest for every Unicode scalar', () {
      final digest = _RecordDigest();
      var records = 0;
      for (var codePoint = 0; codePoint <= 0x10ffff; codePoint++) {
        if (codePoint >= 0xd800 && codePoint <= 0xdfff) {
          continue;
        }
        digest.add(
          <int>[codePoint],
          normalizePython312Nfkc(
            String.fromCharCode(codePoint),
          ).runes.toList(growable: false),
        );
        records++;
      }
      expect(records, 1112064);
      expect(digest.close(), python312NfkcScalarDigestSha256);
    });

    test('matches cross-scalar composition and ordering digest', () {
      final relevant = <int>{
        ...python312NfkdDecompositions.keys,
        ...python312CanonicalCombiningClasses.keys,
        ...python312CanonicalCompositions.values,
      };
      for (final pairKey in python312CanonicalCompositions.keys) {
        relevant
          ..add(pairKey >> 21)
          ..add(pairKey & ((1 << 21) - 1));
      }
      final digest = _RecordDigest();
      var records = 0;
      for (final codePoint in relevant.toList()..sort()) {
        for (final source in <List<int>>[
          <int>[0x41, codePoint, 0x301],
          <int>[0x1100, codePoint, 0x1161],
          <int>[codePoint, 0x323, 0x301],
        ]) {
          digest.add(
            source,
            normalizePython312Nfkc(
              String.fromCharCodes(source),
            ).runes.toList(growable: false),
          );
          records++;
        }
      }
      expect(records, 21111);
      expect(digest.close(), python312NfkcSequenceDigestSha256);
    });

    test('NFC composes canonically without compatibility folding', () {
      expect(normalizePython312Nfc('A\u030a\u0301'), 'Ǻ');
      expect(normalizePython312Nfc('\u1100\u1161\u11a8'), '각');
      expect(normalizePython312Nfc('Ａ ﬃ 𞀰'), 'Ａ ﬃ 𞀰');
      final surrogate = String.fromCharCode(0xd800);
      expect(normalizePython312Nfc(surrogate).codeUnits, surrogate.codeUnits);
    });

    test('NFC matches the accepted Python scalar and sequence digests', () {
      final scalarDigest = _RecordDigest();
      var scalarRecords = 0;
      for (var codePoint = 0; codePoint <= 0x10ffff; codePoint++) {
        if (codePoint >= 0xd800 && codePoint <= 0xdfff) {
          continue;
        }
        scalarDigest.add(
          <int>[codePoint],
          normalizePython312Nfc(
            String.fromCharCode(codePoint),
          ).runes.toList(growable: false),
        );
        scalarRecords++;
      }
      expect(scalarRecords, 1112064);
      expect(scalarDigest.close(), python312NfcScalarDigestSha256);

      final relevant = <int>{
        ...python312NfkdDecompositions.keys,
        ...python312CanonicalCombiningClasses.keys,
        ...python312CanonicalCompositions.values,
      };
      for (final pairKey in python312CanonicalCompositions.keys) {
        relevant
          ..add(pairKey >> 21)
          ..add(pairKey & ((1 << 21) - 1));
      }
      final sequenceDigest = _RecordDigest();
      var sequenceRecords = 0;
      for (final codePoint in relevant.toList()..sort()) {
        for (final source in <List<int>>[
          <int>[0x41, codePoint, 0x301],
          <int>[0x1100, codePoint, 0x1161],
          <int>[codePoint, 0x323, 0x301],
        ]) {
          sequenceDigest.add(
            source,
            normalizePython312Nfc(
              String.fromCharCodes(source),
            ).runes.toList(growable: false),
          );
          sequenceRecords++;
        }
      }
      expect(sequenceRecords, 21111);
      expect(sequenceDigest.close(), python312NfcSequenceDigestSha256);
    });

    test('Python 3.11 NFC matches Unicode 14 scalar and sequence digests', () {
      final scalarDigest = _RecordDigest();
      var scalarRecords = 0;
      for (var codePoint = 0; codePoint <= 0x10ffff; codePoint++) {
        if (codePoint >= 0xd800 && codePoint <= 0xdfff) {
          continue;
        }
        scalarDigest.add(
          <int>[codePoint],
          normalizePython311Nfc(
            String.fromCharCode(codePoint),
          ).runes.toList(growable: false),
        );
        scalarRecords++;
      }
      expect(scalarRecords, 1112064);
      expect(scalarDigest.close(), python312NfcScalarDigestSha256);

      final relevant = <int>{
        ...python312NfkdDecompositions.keys,
        ...python312CanonicalCombiningClasses.keys,
        ...python312CanonicalCompositions.values,
      };
      for (final pairKey in python312CanonicalCompositions.keys) {
        relevant
          ..add(pairKey >> 21)
          ..add(pairKey & ((1 << 21) - 1));
      }
      final sequenceDigest = _RecordDigest();
      var sequenceRecords = 0;
      for (final codePoint in relevant.toList()..sort()) {
        for (final source in <List<int>>[
          <int>[0x41, codePoint, 0x301],
          <int>[0x1100, codePoint, 0x1161],
          <int>[codePoint, 0x323, 0x301],
        ]) {
          sequenceDigest.add(
            source,
            normalizePython311Nfc(
              String.fromCharCodes(source),
            ).runes.toList(growable: false),
          );
          sequenceRecords++;
        }
      }
      expect(sequenceRecords, 21111);
      expect(
        sequenceDigest.close(),
        'ffefdbecb7c23fc2e588e042eb5f055ee4809c918c2c63eea52ada4af6369113',
      );
    });

    test('matches all accepted Python scalar-property records', () {
      final decimalExpression = RegExp(
        '^$python312DecimalRegExpPattern\$',
        unicode: true,
      );
      final digest = _RecordDigest();
      var records = 0;
      for (var codePoint = 0; codePoint <= 0x10ffff; codePoint++) {
        if (codePoint >= 0xd800 && codePoint <= 0xdfff) {
          continue;
        }
        final decimal = python312DecimalValue(codePoint);
        final digit = python312DigitValue(codePoint);
        if (decimalExpression.hasMatch(String.fromCharCode(codePoint)) !=
            (decimal != null)) {
          fail(
            'decimal RegExp mismatch at U+'
            '${codePoint.toRadixString(16).toUpperCase()}',
          );
        }
        digest.add(
          <int>[codePoint],
          <int>[
            isPython312AlphabeticScalar(codePoint) ? 1 : 0,
            (decimal ?? -1) + 1,
            (digit ?? -1) + 1,
            isPython312WhitespaceScalar(codePoint) ? 1 : 0,
          ],
        );
        records++;
      }
      expect(records, 1112064);
      expect(digest.close(), python312PropertyDigestSha256);
    });
  });
}

final class _RecordDigest {
  final BytesBuilder _bytes = BytesBuilder(copy: false);

  void add(List<int> source, List<int> normalized) {
    _addUint32(source.length);
    for (final codePoint in source) {
      _addUint32(codePoint);
    }
    _addUint32(normalized.length);
    for (final codePoint in normalized) {
      _addUint32(codePoint);
    }
  }

  String close() => sha256.convert(_bytes.takeBytes()).toString();

  void _addUint32(int value) {
    _bytes.add(<int>[
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ]);
  }
}
