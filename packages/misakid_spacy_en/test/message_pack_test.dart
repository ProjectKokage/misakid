import 'dart:typed_data';

import 'package:misakid_spacy_en/src/message_pack.dart';
import 'package:test/test.dart';

void main() {
  group('bounded MessagePack subset', () {
    const decoder = BoundedMessagePackDecoder();

    test('decodes the scalar and container kinds used by spaCy', () {
      final value = decoder.decode(
        Uint8List.fromList(<int>[
          0x83,
          0xa1,
          0x61,
          0x93,
          0xc0,
          0xc2,
          0xc3,
          0xa1,
          0x62,
          0xd0,
          0xff,
          0xa1,
          0x63,
          0xd9,
          0x02,
          0xc3,
          0xa9,
        ]),
      );
      expect(value, <Object?, Object?>{
        'a': <Object?>[null, false, true],
        'b': -1,
        'c': 'é',
      });
    });

    test('represents uint64 values with signed Dart bits', () {
      expect(
        decoder.decode(
          Uint8List.fromList(<int>[
            0xcf,
            0xff,
            0xff,
            0xff,
            0xff,
            0xff,
            0xff,
            0xff,
            0xff,
          ]),
        ),
        -1,
      );
      expect(
        decoder.decode(
          Uint8List.fromList(<int>[
            0xcf,
            0x80,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
          ]),
        ),
        -0x8000000000000000,
      );
    });

    test('rejects executable/opaque extension and binary types', () {
      expect(
        () => decoder.decode(Uint8List.fromList(<int>[0xd4, 0x01, 0x00])),
        throwsFormatException,
      );
      expect(
        () => decoder.decode(Uint8List.fromList(<int>[0xc4, 0x00])),
        throwsFormatException,
      );
    });

    test('rejects malformed UTF-8, truncation, and trailing bytes', () {
      expect(
        () => decoder.decode(Uint8List.fromList(<int>[0xd9, 0x01, 0xff])),
        throwsFormatException,
      );
      expect(
        () => decoder.decode(Uint8List.fromList(<int>[0xda, 0x00])),
        throwsFormatException,
      );
      expect(
        () => decoder.decode(Uint8List.fromList(<int>[0x01, 0x02])),
        throwsFormatException,
      );
    });

    test('rejects duplicate and container-valued map keys', () {
      expect(
        () => decoder.decode(
          Uint8List.fromList(<int>[0x82, 0xa1, 0x61, 0x01, 0xa1, 0x61, 0x02]),
        ),
        throwsFormatException,
      );
      expect(
        () => decoder.decode(Uint8List.fromList(<int>[0x81, 0x90, 0x01])),
        throwsFormatException,
      );
    });

    test('enforces input, depth, allocation, and total-value limits', () {
      expect(
        () => const BoundedMessagePackDecoder(
          limits: MessagePackLimits(maxInputBytes: 1),
        ).decode(Uint8List.fromList(<int>[0x91, 0x00])),
        throwsFormatException,
      );
      expect(
        () => const BoundedMessagePackDecoder(
          limits: MessagePackLimits(maxDepth: 1),
        ).decode(Uint8List.fromList(<int>[0x91, 0x90])),
        throwsFormatException,
      );
      expect(
        () => const BoundedMessagePackDecoder(
          limits: MessagePackLimits(maxContainerLength: 1),
        ).decode(Uint8List.fromList(<int>[0x92, 0x00, 0x00])),
        throwsFormatException,
      );
      expect(
        () => const BoundedMessagePackDecoder(
          limits: MessagePackLimits(maxStringBytes: 1),
        ).decode(Uint8List.fromList(<int>[0xa2, 0x61, 0x62])),
        throwsFormatException,
      );
      expect(
        () => const BoundedMessagePackDecoder(
          limits: MessagePackLimits(maxValues: 2),
        ).decode(Uint8List.fromList(<int>[0x92, 0x00, 0x00])),
        throwsFormatException,
      );
    });
  });
}
