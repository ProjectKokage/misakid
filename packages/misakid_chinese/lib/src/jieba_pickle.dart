// The non-executable parser for the protocol-0 pickle subset that jieba
// 0.42.1's HMM probability files use. It was split out of jieba.dart, whose
// header records the upstream source and license of the adapted segmenter.

import 'dart:convert';
import 'dart:typed_data';

const int _maximumPickleLineBytes = 256;

const int _maximumPickleStackDepth = 128;

/// The most memo entries one probability file may define.
const int maximumPickleMemoEntries = 300000;

/// The most map entries one probability file may hold, across all its maps.
const int maximumPickleMapEntries = 100000;

const int _maximumPickleTupleLength = 1024;

/// Parses the inert protocol-0 opcodes of a jieba probability file into maps,
/// lists, strings, numbers and [PickleTuple]s. It executes nothing: an opcode
/// outside the subset is rejected.
final class PickleProtocol0ProbabilityParser {
  /// Creates a parser over the whole file's [bytes].
  PickleProtocol0ProbabilityParser(this.bytes);

  /// The file being parsed.
  final Uint8List bytes;
  final List<Object> _stack = <Object>[];
  final Map<int, Object> _memo = <int, Object>{};
  var _offset = 0;
  var _mapEntryCount = 0;

  /// Parses the file once and returns its single top-level value.
  ///
  /// Throws [FormatException] for a malformed file, an unsupported opcode or
  /// a bound that is exceeded.
  Object parse() {
    while (_offset < bytes.length) {
      final opcode = bytes[_offset++];
      switch (opcode) {
        case 0x28: // MARK
          _push(_pickleMark);
        case 0x64: // DICT
          if (_stack.isEmpty || !identical(_stack.last, _pickleMark)) {
            throw const FormatException(
              'Only empty protocol-0 dictionary construction is allowed.',
            );
          }
          _stack.removeLast();
          _push(<Object, Object>{});
        case 0x70: // PUT
          final index = _memoIndex(_readAsciiLine());
          if (_stack.isEmpty ||
              _memo.containsKey(index) ||
              _memo.length >= maximumPickleMemoEntries) {
            throw const FormatException('Invalid protocol-0 memo PUT.');
          }
          _memo[index] = _stack.last;
        case 0x67: // GET
          final index = _memoIndex(_readAsciiLine());
          final value = _memo[index];
          if (value == null) {
            throw const FormatException('Invalid protocol-0 memo GET.');
          }
          _push(value);
        case 0x53: // STRING
          _push(_parseAsciiString(_readAsciiLine()));
        case 0x56: // UNICODE
          _push(_parseRawUnicode(_readAsciiLine()));
        case 0x46: // FLOAT
          final source = _readAsciiLine();
          if (!_floatPattern.hasMatch(source)) {
            throw const FormatException('Invalid protocol-0 float literal.');
          }
          final value = double.parse(source);
          if (!value.isFinite) {
            throw const FormatException('Non-finite pickle float rejected.');
          }
          _push(value);
        case 0x74: // TUPLE
          final markIndex = _stack.lastIndexWhere(
            (value) => identical(value, _pickleMark),
          );
          if (markIndex < 0 ||
              markIndex + 1 == _stack.length ||
              _stack.length - markIndex - 1 > _maximumPickleTupleLength) {
            throw const FormatException('Invalid protocol-0 TUPLE stack.');
          }
          final values = _stack.sublist(markIndex + 1);
          _stack.removeRange(markIndex, _stack.length);
          _push(PickleTuple(List<Object>.unmodifiable(values)));
        case 0x73: // SETITEM
          if (_stack.length < 3) {
            throw const FormatException('Invalid protocol-0 SETITEM stack.');
          }
          final value = _stack.removeLast();
          final key = _stack.removeLast();
          final target = _stack.last;
          if ((key is! String && key is! PickleTuple) ||
              target is! Map<Object, Object>) {
            throw const FormatException(
              'Probability pickle dictionaries require inert scalar or tuple keys.',
            );
          }
          if (target.containsKey(key) ||
              ++_mapEntryCount > maximumPickleMapEntries) {
            throw const FormatException(
              'Duplicate or excessive probability-map entry.',
            );
          }
          target[key] = value;
        case 0x2E: // STOP
          if (_offset != bytes.length ||
              _stack.length != 1 ||
              _stack.single is! Map<Object, Object>) {
            throw const FormatException(
              'Protocol-0 probability pickle has trailing or stacked data.',
            );
          }
          return _stack.single;
        default:
          throw FormatException(
            'Unsupported protocol-0 probability opcode 0x${opcode.toRadixString(16)}.',
          );
      }
    }
    throw const FormatException('Protocol-0 probability pickle has no STOP.');
  }

  void _push(Object value) {
    if (_stack.length >= _maximumPickleStackDepth) {
      throw const FormatException('Protocol-0 pickle stack is too deep.');
    }
    _stack.add(value);
  }

  String _readAsciiLine() {
    final start = _offset;
    while (_offset < bytes.length && bytes[_offset] != 0x0A) {
      final value = bytes[_offset++];
      if (value < 0x20 || value > 0x7E) {
        throw const FormatException(
          'Protocol-0 argument must be printable ASCII.',
        );
      }
      if (_offset - start > _maximumPickleLineBytes) {
        throw const FormatException('Protocol-0 argument line is too long.');
      }
    }
    if (_offset >= bytes.length) {
      throw const FormatException('Unterminated protocol-0 argument line.');
    }
    final result = ascii.decode(bytes.sublist(start, _offset));
    _offset++;
    return result;
  }
}

int _memoIndex(String source) {
  if (!_memoPattern.hasMatch(source)) {
    throw const FormatException('Invalid protocol-0 memo index.');
  }
  final value = int.parse(source);
  if (value >= maximumPickleMemoEntries) {
    throw const FormatException('Protocol-0 memo index exceeds the bound.');
  }
  return value;
}

String _parseAsciiString(String source) {
  if (source.length < 3 ||
      source.codeUnitAt(0) != 0x27 ||
      source.codeUnitAt(source.length - 1) != 0x27) {
    throw const FormatException(
      'Protocol-0 STRING must be one quoted inert ASCII atom.',
    );
  }
  final value = source.substring(1, source.length - 1);
  if (!_pickleAsciiAtomPattern.hasMatch(value)) {
    throw const FormatException(
      'Protocol-0 STRING contains unsupported or excessive data.',
    );
  }
  return value;
}

String _parseRawUnicode(String source) {
  if (source.isEmpty) {
    throw const FormatException('Protocol-0 UNICODE must not be empty.');
  }
  final output = StringBuffer();
  for (var index = 0; index < source.length;) {
    final unit = source.codeUnitAt(index++);
    if (unit != 0x5C) {
      output.writeCharCode(unit);
      continue;
    }
    if (index >= source.length) {
      throw const FormatException('Incomplete raw-Unicode escape.');
    }
    final kind = source.codeUnitAt(index++);
    final width = switch (kind) {
      0x75 => 4, // u
      0x55 => 8, // U
      _ => throw const FormatException('Unsupported raw-Unicode escape.'),
    };
    if (index + width > source.length) {
      throw const FormatException('Incomplete raw-Unicode scalar escape.');
    }
    final digits = source.substring(index, index + width);
    if (!RegExp('^[0-9A-Fa-f]{$width}\$').hasMatch(digits)) {
      throw const FormatException('Invalid raw-Unicode scalar escape.');
    }
    final scalar = int.parse(digits, radix: 16);
    if (scalar > 0x10FFFF || (scalar >= 0xD800 && scalar <= 0xDFFF)) {
      throw const FormatException('Invalid raw-Unicode scalar value.');
    }
    output.writeCharCode(scalar);
    index += width;
  }
  return output.toString();
}

/// A pickle tuple, compared by its [values] so it can be a map key.
final class PickleTuple {
  /// Creates a tuple of [values].
  const PickleTuple(this.values);

  /// The tuple's items in order.
  final List<Object> values;

  @override
  bool operator ==(Object other) {
    if (other is! PickleTuple || other.values.length != values.length) {
      return false;
    }
    for (var index = 0; index < values.length; index++) {
      if (values[index] != other.values[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(values);
}

const Object _pickleMark = Object();

final RegExp _memoPattern = RegExp(r'^(?:0|[1-9][0-9]*)$');

final RegExp _pickleAsciiAtomPattern = RegExp(r'^[A-Za-z0-9_.+-]{1,32}$');

final RegExp _floatPattern = RegExp(
  r'^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:e[+-]?[0-9]+)?$',
);
