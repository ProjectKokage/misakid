// A deliberately small MessagePack decoder for reviewed spaCy resources.
//
// This is not a general serialization framework. It accepts only the scalar
// and container kinds present in the pinned spaCy resources, rejects extension
// objects and duplicate map keys, and checks every allocation against explicit
// limits.

import 'dart:convert';
import 'dart:typed_data';

/// Resource bounds enforced by [BoundedMessagePackDecoder].
final class MessagePackLimits {
  /// Creates immutable MessagePack decoding limits.
  const MessagePackLimits({
    this.maxInputBytes = 16 * 1024 * 1024,
    this.maxDepth = 32,
    this.maxContainerLength = 1 << 20,
    this.maxStringBytes = 4 * 1024 * 1024,
    this.maxValues = 2 * 1024 * 1024,
  });

  /// Maximum encoded input size.
  final int maxInputBytes;

  /// Maximum nested array/map depth.
  final int maxDepth;

  /// Maximum number of entries in any one array or map.
  final int maxContainerLength;

  /// Maximum UTF-8 byte length of any one string.
  final int maxStringBytes;

  /// Maximum total number of decoded scalar and container values.
  final int maxValues;
}

/// A non-executable, bounded decoder for the MessagePack subset used by spaCy.
///
/// Supported values are `null`, booleans, signed/unsigned integers, UTF-8
/// strings, arrays, and maps. Unsigned 64-bit values are represented by the
/// equivalent signed Dart `int` bit pattern, which is the representation used
/// by the adapter for spaCy's `uint64` string hashes.
final class BoundedMessagePackDecoder {
  /// Creates a decoder using [limits].
  const BoundedMessagePackDecoder({this.limits = const MessagePackLimits()});

  /// Bounds applied before reading or allocating decoded values.
  final MessagePackLimits limits;

  /// Decodes exactly one value and rejects trailing bytes.
  Object? decode(Uint8List bytes) {
    _validateLimits(limits);
    if (bytes.length > limits.maxInputBytes) {
      throw const FormatException('MessagePack input exceeds its byte limit.');
    }
    final reader = _MessagePackReader(bytes, limits);
    final value = reader.read(depth: 0);
    if (!reader.isAtEnd) {
      throw FormatException(
        'Trailing bytes after MessagePack value at offset ${reader.offset}.',
      );
    }
    return value;
  }
}

void _validateLimits(MessagePackLimits limits) {
  if (limits.maxInputBytes < 0 ||
      limits.maxDepth < 0 ||
      limits.maxContainerLength < 0 ||
      limits.maxStringBytes < 0 ||
      limits.maxValues <= 0) {
    throw ArgumentError('MessagePack limits must be non-negative and nonzero.');
  }
}

final class _MessagePackReader {
  _MessagePackReader(this.bytes, this.limits)
    : _data = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final MessagePackLimits limits;
  final ByteData _data;
  var offset = 0;
  var _values = 0;

  bool get isAtEnd => offset == bytes.length;

  Object? read({required int depth}) {
    _values++;
    if (_values > limits.maxValues) {
      throw const FormatException('MessagePack value count exceeds its limit.');
    }
    final marker = _readByte();
    if (marker <= 0x7f) {
      return marker;
    }
    if (marker >= 0xe0) {
      return marker - 0x100;
    }
    if (marker >= 0xa0 && marker <= 0xbf) {
      return _readString(marker & 0x1f);
    }
    if (marker >= 0x90 && marker <= 0x9f) {
      return _readArray(marker & 0x0f, depth);
    }
    if (marker >= 0x80 && marker <= 0x8f) {
      return _readMap(marker & 0x0f, depth);
    }
    return switch (marker) {
      0xc0 => null,
      0xc2 => false,
      0xc3 => true,
      0xcc => _readUnsigned(1),
      0xcd => _readUnsigned(2),
      0xce => _readUnsigned(4),
      0xcf => _readUnsigned64AsSigned(),
      0xd0 => _readSigned(1),
      0xd1 => _readSigned(2),
      0xd2 => _readSigned(4),
      0xd3 => _readSigned(8),
      0xd9 => _readString(_readUnsigned(1)),
      0xda => _readString(_readUnsigned(2)),
      0xdb => _readString(_readLength32('string')),
      0xdc => _readArray(_readUnsigned(2), depth),
      0xdd => _readArray(_readLength32('array'), depth),
      0xde => _readMap(_readUnsigned(2), depth),
      0xdf => _readMap(_readLength32('map'), depth),
      _ => throw FormatException(
        'Unsupported MessagePack marker 0x${marker.toRadixString(16)} '
        'at offset ${offset - 1}.',
      ),
    };
  }

  int _readByte() {
    _require(1);
    return bytes[offset++];
  }

  int _readUnsigned(int width) {
    _require(width);
    final start = offset;
    offset += width;
    return switch (width) {
      1 => _data.getUint8(start),
      2 => _data.getUint16(start, Endian.big),
      4 => _data.getUint32(start, Endian.big),
      _ => throw StateError('Unsupported unsigned width $width.'),
    };
  }

  int _readUnsigned64AsSigned() {
    _require(8);
    var value = BigInt.zero;
    for (var index = 0; index < 8; index++) {
      value = (value << 8) | BigInt.from(bytes[offset + index]);
    }
    offset += 8;
    if ((value & _uint64SignBit) != BigInt.zero) {
      value -= _uint64Modulus;
    }
    return value.toInt();
  }

  int _readSigned(int width) {
    _require(width);
    final start = offset;
    offset += width;
    return switch (width) {
      1 => _data.getInt8(start),
      2 => _data.getInt16(start, Endian.big),
      4 => _data.getInt32(start, Endian.big),
      8 => _data.getInt64(start, Endian.big),
      _ => throw StateError('Unsupported signed width $width.'),
    };
  }

  int _readLength32(String kind) {
    final value = _readUnsigned(4);
    if (value > limits.maxContainerLength && kind != 'string') {
      throw FormatException('MessagePack $kind length exceeds its limit.');
    }
    return value;
  }

  String _readString(int length) {
    if (length > limits.maxStringBytes) {
      throw const FormatException('MessagePack string exceeds its byte limit.');
    }
    _require(length);
    final start = offset;
    offset += length;
    try {
      return utf8.decode(
        Uint8List.sublistView(bytes, start, start + length),
        allowMalformed: false,
      );
    } on FormatException catch (error) {
      throw FormatException(
        'Invalid UTF-8 in MessagePack string at offset $start.',
        error,
      );
    }
  }

  List<Object?> _readArray(int length, int depth) {
    _checkContainer(length, depth, 'array');
    final result = <Object?>[];
    for (var index = 0; index < length; index++) {
      result.add(read(depth: depth + 1));
    }
    return List<Object?>.unmodifiable(result);
  }

  Map<Object?, Object?> _readMap(int length, int depth) {
    _checkContainer(length, depth, 'map');
    final result = <Object?, Object?>{};
    for (var index = 0; index < length; index++) {
      final key = read(depth: depth + 1);
      if (key is List<Object?> || key is Map<Object?, Object?>) {
        throw const FormatException('MessagePack map key is not scalar.');
      }
      if (result.containsKey(key)) {
        throw FormatException('Duplicate MessagePack map key `$key`.');
      }
      result[key] = read(depth: depth + 1);
    }
    return Map<Object?, Object?>.unmodifiable(result);
  }

  void _checkContainer(int length, int depth, String kind) {
    if (depth >= limits.maxDepth) {
      throw FormatException('MessagePack $kind nesting exceeds its limit.');
    }
    if (length > limits.maxContainerLength) {
      throw FormatException('MessagePack $kind length exceeds its limit.');
    }
  }

  void _require(int length) {
    if (length < 0 || length > bytes.length - offset) {
      throw FormatException('Truncated MessagePack value at offset $offset.');
    }
  }
}

final BigInt _uint64SignBit = BigInt.one << 63;
final BigInt _uint64Modulus = BigInt.one << 64;
