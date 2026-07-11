// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

/// Decodes bounded JSON while rejecting duplicate object keys.
///
/// Dart's standard decoder intentionally keeps the last duplicate key. Model
/// resources are untrusted, so this package uses a small strict parser instead.
Object? decodeStrictJson(String source) => _StrictJsonParser(source).parse();

const int _maximumJsonDepth = 32;
const int _maximumJsonValues = 20000;
const int _maximumJsonNumberCharacters = 128;

final class _StrictJsonParser {
  _StrictJsonParser(this.source);

  final String source;
  var _index = 0;
  var _values = 0;

  Object? parse() {
    _skipWhitespace();
    final result = _parseValue(0);
    _skipWhitespace();
    if (_index != source.length) {
      throw FormatException(
        'Unexpected trailing JSON content.',
        source,
        _index,
      );
    }
    return result;
  }

  Object? _parseValue(int depth) {
    if (depth > _maximumJsonDepth) {
      throw FormatException('JSON nesting is too deep.', source, _index);
    }
    _values++;
    if (_values > _maximumJsonValues) {
      throw FormatException('JSON contains too many values.', source, _index);
    }
    if (_index >= source.length) {
      throw FormatException('Unexpected end of JSON.', source, _index);
    }
    return switch (source.codeUnitAt(_index)) {
      0x7B => _parseObject(depth + 1),
      0x5B => _parseArray(depth + 1),
      0x22 => _parseString(),
      0x74 => _parseLiteral('true', true),
      0x66 => _parseLiteral('false', false),
      0x6E => _parseLiteral('null', null),
      final int unit when unit == 0x2D || (unit >= 0x30 && unit <= 0x39) =>
        _parseNumber(),
      _ => throw FormatException('Unexpected JSON token.', source, _index),
    };
  }

  Map<String, Object?> _parseObject(int depth) {
    _index++;
    _skipWhitespace();
    final result = <String, Object?>{};
    if (_consume(0x7D)) return result;
    while (true) {
      if (_index >= source.length || source.codeUnitAt(_index) != 0x22) {
        throw FormatException(
          'JSON object key must be a string.',
          source,
          _index,
        );
      }
      final keyOffset = _index;
      final key = _parseString();
      if (result.containsKey(key)) {
        throw FormatException(
          'Duplicate JSON object key `$key`.',
          source,
          keyOffset,
        );
      }
      _skipWhitespace();
      if (!_consume(0x3A)) {
        throw FormatException(
          'Expected a colon after JSON object key.',
          source,
          _index,
        );
      }
      _skipWhitespace();
      result[key] = _parseValue(depth);
      _skipWhitespace();
      if (_consume(0x7D)) return result;
      if (!_consume(0x2C)) {
        throw FormatException(
          'Expected a comma in JSON object.',
          source,
          _index,
        );
      }
      _skipWhitespace();
    }
  }

  List<Object?> _parseArray(int depth) {
    _index++;
    _skipWhitespace();
    final result = <Object?>[];
    if (_consume(0x5D)) return result;
    while (true) {
      result.add(_parseValue(depth));
      _skipWhitespace();
      if (_consume(0x5D)) return result;
      if (!_consume(0x2C)) {
        throw FormatException(
          'Expected a comma in JSON array.',
          source,
          _index,
        );
      }
      _skipWhitespace();
    }
  }

  String _parseString() {
    _index++;
    final result = StringBuffer();
    while (_index < source.length) {
      final unit = source.codeUnitAt(_index++);
      if (unit == 0x22) return result.toString();
      if (unit < 0x20) {
        throw FormatException(
          'Unescaped control character in JSON string.',
          source,
          _index - 1,
        );
      }
      if (unit != 0x5C) {
        if (unit >= 0xD800 && unit <= 0xDBFF) {
          if (_index >= source.length ||
              source.codeUnitAt(_index) < 0xDC00 ||
              source.codeUnitAt(_index) > 0xDFFF) {
            throw FormatException(
              'Unpaired high surrogate in JSON string.',
              source,
              _index - 1,
            );
          }
          result
            ..writeCharCode(unit)
            ..writeCharCode(source.codeUnitAt(_index++));
        } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
          throw FormatException(
            'Unpaired low surrogate in JSON string.',
            source,
            _index - 1,
          );
        } else {
          result.writeCharCode(unit);
        }
        continue;
      }
      if (_index >= source.length) {
        throw FormatException('Incomplete JSON string escape.', source, _index);
      }
      final escape = source.codeUnitAt(_index++);
      switch (escape) {
        case 0x22:
        case 0x2F:
        case 0x5C:
          result.writeCharCode(escape);
        case 0x62:
          result.writeCharCode(0x08);
        case 0x66:
          result.writeCharCode(0x0C);
        case 0x6E:
          result.writeCharCode(0x0A);
        case 0x72:
          result.writeCharCode(0x0D);
        case 0x74:
          result.writeCharCode(0x09);
        case 0x75:
          final first = _parseHexCodeUnit();
          if (first >= 0xD800 && first <= 0xDBFF) {
            if (_index + 2 > source.length ||
                source.codeUnitAt(_index) != 0x5C ||
                source.codeUnitAt(_index + 1) != 0x75) {
              throw FormatException(
                'Escaped high surrogate is not paired.',
                source,
                _index,
              );
            }
            _index += 2;
            final second = _parseHexCodeUnit();
            if (second < 0xDC00 || second > 0xDFFF) {
              throw FormatException(
                'Escaped high surrogate is not paired.',
                source,
                _index - 4,
              );
            }
            result
              ..writeCharCode(first)
              ..writeCharCode(second);
          } else if (first >= 0xDC00 && first <= 0xDFFF) {
            throw FormatException(
              'Unpaired escaped low surrogate.',
              source,
              _index - 4,
            );
          } else {
            result.writeCharCode(first);
          }
        default:
          throw FormatException(
            'Unknown JSON string escape.',
            source,
            _index - 1,
          );
      }
    }
    throw FormatException('Unterminated JSON string.', source, _index);
  }

  int _parseHexCodeUnit() {
    if (_index + 4 > source.length) {
      throw FormatException('Incomplete JSON Unicode escape.', source, _index);
    }
    var result = 0;
    for (var offset = 0; offset < 4; offset++) {
      final unit = source.codeUnitAt(_index++);
      final digit = switch (unit) {
        >= 0x30 && <= 0x39 => unit - 0x30,
        >= 0x41 && <= 0x46 => unit - 0x41 + 10,
        >= 0x61 && <= 0x66 => unit - 0x61 + 10,
        _ => -1,
      };
      if (digit < 0) {
        throw FormatException(
          'Invalid JSON Unicode escape.',
          source,
          _index - 1,
        );
      }
      result = result * 16 + digit;
    }
    return result;
  }

  Object? _parseLiteral(String literal, Object? value) {
    if (_index + literal.length > source.length ||
        source.substring(_index, _index + literal.length) != literal) {
      throw FormatException('Invalid JSON literal.', source, _index);
    }
    _index += literal.length;
    return value;
  }

  num _parseNumber() {
    final start = _index;
    _consume(0x2D);
    if (_consume(0x30)) {
      if (_index < source.length && _isDigit(source.codeUnitAt(_index))) {
        throw FormatException(
          'JSON number has a leading zero.',
          source,
          _index,
        );
      }
    } else {
      _requireDigits();
    }
    var floating = false;
    if (_consume(0x2E)) {
      floating = true;
      _requireDigits();
    }
    if (_index < source.length &&
        (source.codeUnitAt(_index) == 0x65 ||
            source.codeUnitAt(_index) == 0x45)) {
      floating = true;
      _index++;
      if (_index < source.length &&
          (source.codeUnitAt(_index) == 0x2B ||
              source.codeUnitAt(_index) == 0x2D)) {
        _index++;
      }
      _requireDigits();
    }
    if (_index - start > _maximumJsonNumberCharacters) {
      throw FormatException('JSON number is too long.', source, start);
    }
    final text = source.substring(start, _index);
    if (!floating) {
      final integer = int.tryParse(text);
      if (integer != null) return integer;
    }
    final result = double.tryParse(text);
    if (result == null || !result.isFinite) {
      throw FormatException(
        'JSON number is outside the supported range.',
        source,
        start,
      );
    }
    return result;
  }

  void _requireDigits() {
    final start = _index;
    while (_index < source.length && _isDigit(source.codeUnitAt(_index))) {
      _index++;
    }
    if (_index == start) {
      throw FormatException('Expected digits in JSON number.', source, _index);
    }
  }

  bool _consume(int unit) {
    if (_index < source.length && source.codeUnitAt(_index) == unit) {
      _index++;
      return true;
    }
    return false;
  }

  void _skipWhitespace() {
    while (_index < source.length) {
      final unit = source.codeUnitAt(_index);
      if (unit != 0x20 && unit != 0x09 && unit != 0x0A && unit != 0x0D) return;
      _index++;
    }
  }

  bool _isDigit(int unit) => unit >= 0x30 && unit <= 0x39;
}
