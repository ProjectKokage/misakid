// Exact scalar properties from CPython 3.12.11's Unicode 15.0.0 database.

import 'dart:convert';
import 'dart:typed_data';

import '../generated/python312_nfkc_data.dart';

/// A Dart Unicode-mode regular-expression class matching Python 3.12.11
/// `re \d` exactly.
const String python312DecimalRegExpPattern = python312DecimalDigitPattern;

/// Whether [scalar] satisfies Python 3.12.11 `str.isalpha()`.
bool isPython312AlphabeticScalar(int scalar) =>
    _containsRange(python312AlphabeticRanges, scalar);

/// Whether [scalar] satisfies Python 3.12.11 `str.isdecimal()` and `re \d`.
bool isPython312DecimalScalar(int scalar) =>
    python312DecimalValue(scalar) != null;

/// Returns Python 3.12.11's decimal value for [scalar], or `null`.
int? python312DecimalValue(int scalar) =>
    _rangeValue(python312DecimalDigitRanges, scalar);

/// Whether [scalar] satisfies Python 3.12.11 `str.isdigit()`.
bool isPython312DigitScalar(int scalar) => python312DigitValue(scalar) != null;

/// Returns Python 3.12.11's digit value for [scalar], or `null`.
int? python312DigitValue(int scalar) =>
    _rangeValue(python312DigitRanges, scalar);

/// Whether [scalar] satisfies Python 3.12.11 `str.isspace()`.
bool isPython312WhitespaceScalar(int scalar) =>
    _containsRange(python312WhitespaceRanges, scalar);

/// Lowercases [text] exactly like CPython 3.12.11 / Unicode 15.0.0.
String python312Lower(String text) {
  if (text.isEmpty) {
    return text;
  }
  final source = _codePointsPreservingSurrogates(text);
  final output = StringBuffer();
  var changed = false;
  for (var index = 0; index < source.length; index++) {
    final scalar = source[index];
    if (scalar == 0x03a3 && _isFinalSigma(source, index)) {
      output.writeCharCode(0x03c2);
      changed = true;
      continue;
    }
    final mapped = _python312LowercaseMappings[scalar];
    if (mapped == null) {
      output.writeCharCode(scalar);
    } else {
      output.write(mapped);
      changed = true;
    }
  }
  return changed ? output.toString() : text;
}

bool _isFinalSigma(List<int> source, int sigmaIndex) {
  var before = sigmaIndex - 1;
  while (before >= 0 &&
      _containsRange(_python312CaseIgnorableRanges, source[before])) {
    before--;
  }
  if (before < 0 || !_containsRange(_python312CasedRanges, source[before])) {
    return false;
  }

  var after = sigmaIndex + 1;
  while (after < source.length &&
      _containsRange(_python312CaseIgnorableRanges, source[after])) {
    after++;
  }
  return after == source.length ||
      !_containsRange(_python312CasedRanges, source[after]);
}

bool _containsRange(List<int> ranges, int scalar) {
  var low = 0;
  var high = ranges.length ~/ 2 - 1;
  while (low <= high) {
    final middle = (low + high) >> 1;
    final start = ranges[middle * 2];
    final end = ranges[middle * 2 + 1];
    if (scalar < start) {
      high = middle - 1;
    } else if (scalar > end) {
      low = middle + 1;
    } else {
      return true;
    }
  }
  return false;
}

int? _rangeValue(List<int> ranges, int scalar) {
  var low = 0;
  var high = ranges.length ~/ 3 - 1;
  while (low <= high) {
    final middle = (low + high) >> 1;
    final offset = middle * 3;
    final start = ranges[offset];
    final end = ranges[offset + 1];
    if (scalar < start) {
      high = middle - 1;
    } else if (scalar > end) {
      low = middle + 1;
    } else {
      return ranges[offset + 2] + scalar - start;
    }
  }
  return null;
}

List<int> _decodeCaseRanges(String encoded, int expectedCount) {
  final bytes = base64Decode(encoded);
  final cursor = _Python312CaseDataCursor(bytes);
  final result = <int>[];
  var previousEnd = -1;
  for (var index = 0; index < expectedCount; index++) {
    final start = previousEnd + 1 + cursor.readUnsignedLeb128();
    final end = start + cursor.readUnsignedLeb128();
    if (start <= previousEnd || end < start || end > 0x10ffff) {
      throw StateError('Malformed generated Unicode case-range data.');
    }
    result
      ..add(start)
      ..add(end);
    previousEnd = end;
  }
  cursor.expectEnd();
  return List<int>.unmodifiable(result);
}

Map<int, String> _decodeLowercaseMappings(String encoded, int expectedCount) {
  final bytes = base64Decode(encoded);
  final cursor = _Python312CaseDataCursor(bytes);
  final result = <int, String>{};
  var previous = -1;
  for (var index = 0; index < expectedCount; index++) {
    final scalar = previous + 1 + cursor.readUnsignedLeb128();
    final length = cursor.readUnsignedLeb128();
    final raw = cursor.readBytes(length);
    if (scalar <= previous || scalar > 0x10ffff) {
      throw StateError('Malformed generated lowercase mapping data.');
    }
    result[scalar] = utf8.decode(raw, allowMalformed: false);
    previous = scalar;
  }
  cursor.expectEnd();
  return Map<int, String>.unmodifiable(result);
}

List<int> _codePointsPreservingSurrogates(String text) {
  final result = <int>[];
  final codeUnits = text.codeUnits;
  for (var index = 0; index < codeUnits.length; index++) {
    final first = codeUnits[index];
    if (first >= 0xd800 && first <= 0xdbff && index + 1 < codeUnits.length) {
      final second = codeUnits[index + 1];
      if (second >= 0xdc00 && second <= 0xdfff) {
        result.add(0x10000 + ((first - 0xd800) << 10) + (second - 0xdc00));
        index++;
        continue;
      }
    }
    result.add(first);
  }
  return result;
}

final class _Python312CaseDataCursor {
  _Python312CaseDataCursor(this.bytes);

  final Uint8List bytes;
  var offset = 0;

  int readUnsignedLeb128() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (offset >= bytes.length || shift > 28) {
        throw StateError('Malformed generated Unicode case varint data.');
      }
      final byte = bytes[offset++];
      result |= (byte & 0x7f) << shift;
      if (byte & 0x80 == 0) {
        return result;
      }
      shift += 7;
    }
  }

  Uint8List readBytes(int length) {
    if (length < 0 || length > bytes.length - offset) {
      throw StateError('Truncated generated Unicode case mapping data.');
    }
    final result = Uint8List.sublistView(bytes, offset, offset + length);
    offset += length;
    return result;
  }

  void expectEnd() {
    if (offset != bytes.length) {
      throw StateError('Trailing generated Unicode case data.');
    }
  }
}

// BEGIN GENERATED SHARED CASE DATA.
// Generator:
//   tool/generators/generate_python312_spacy_unicode.dart
// Canonical source:
//   tool/upstream_data/python-3.12.11-unicode-15.0.0/spacy_unicode_tables.json
// Source SHA-256: 1e7928f616c36560748f466b047720011faa0c49db1b459a443eec318e01da6f
// Decoded behavior SHA-256: 68d7a4099fb5f72477218518178e89c1e8446b65dfdb2790f4747efb11bf4ffc

const int _python312CasedDataCount = 157;
// Decoded SHA-256: 1a02bd8fff89eb3753d7ffb28b08ba3590ddfc4582a33c196b12852221f76590
const String _python312CasedData =
    'QRkGGS8ACgAEAAUWAR4BwgEBAwTPAQEjBwEeBGAAKgMCAQIDAQAGAAECAQABEwFSAYoBCKUBASUJKJcW'
    'JQEABQACKgEDoAVVAgWCEQgHKgICQL8BQJUCAgUCJQIFAgcBAAEAAQABHgI0AQYBAAMCAQYDAwIFBAwF'
    'AgEGdAANABAMZQAEAAIJAQADBAYAAQABAAEDAQUEAAIDBQQEABEfAwGxBjOWDuQBBgMDAQwlAQAFAJLy'
    'AS0SHYQBZQMDAToFAQEAAQQYBAECtQYqAQ0GT8CeAQYMBIkIGQYZpQlPYCMEI3QKAQ4BBgEBAQoBDgEG'
    'AQHDAwACAgEpAQjFCTINMq0XP+CqAT+AywFUAUYBAQIAAgECAwELAQABBgFAAQMCBwEGARsBAwEEAQAD'
    'BgHTAgIYARgBHgEYAR4BGAEeARgBHgEYAQe0DgkBEwYFhQI9khFD7A8ZBhkGGQ==';

const int _python312CaseIgnorableDataCount = 437;
// Decoded SHA-256: 33617a5fe5a62cdce94c2a9fe3ead81d30c1b227bffe72cc4aaf195a640a79e2
const String _python312CaseIgnorableData =
    'JwAGAAsAIwABAEcABAABAAQAAgH3A78BBAEEAAkBAQD7AQbPAQAFADEsAQABAQEBAQAsAAsFCgoBACMA'
    'ChQQAGUHAQkBAyEAAQAeGlsKOgoEAAIAGBcrAiwABwEGByk5NwABAAQHBAADBgoBDQAPADoABAMIABQB'
    'GgACATkABAEEAQICAwAeAQMACwE5AAQEAQEEABQBFgUBADoAAgABAwgABwELAR4APQAMADIAAwA3AAEC'
    'BQIBAwcBCwEdADoAAgAGAAUBFAEcATkBBAMIABQBHQBIAAcCAQBaAAIGCwhiAAIICQABBkkBGwABAAEA'
    'Nw0BBAEBBQoBIwkAZgMBBQEBAgEZAQQCEAMNAAIBBgAPAF4A4AQCsgcCHQEeAR4BQAEBBggAAgoDAAUA'
    'LQQzAEEBIgB2AgQBCQAGAtsBAQIAOgABBgEAAQACBwYJAgAnAAgeMQMwAAEEAQAFACgIDAEgAwIBAQI4'
    'AAEBAwABAjoHAgFABVICAQwBBgQABgADATI+DQAiZL0DAAECCwINAg0CDQEMBAgBCgACAAIEMQQBCQEA'
    'DQAQDDMgixcBcQJ9AA8AYB8vANUDACQDAwQFAF0FXQKW3gEA4gkFjgIAYgMBCQEAHANQAQ4hTgAXAmcC'
    'AwEIAAMABAAZAQUAlwEBGhENACYHGQouAjAAAgMCAREAFQFCBQIBAgEMAAgAIwALADMAAQICAQUBAQAb'
    'AA4BBQEBAGQECQJ5AAIABACwngEAkwEQvQQPAwAMDyIAAgCpAQAHAAYACwAjAAEALwAtAUMAFQKBBADi'
    'AQCVAQSFCAUBKQEIxgQCAQEFAygCBAClAQG9BAODAwFQAkYKMQN7ADYOKQACAQoCMQMCAQIABAAKADIC'
    'JAQBBz4ADAE0CAoDAgBfAgIAAQEGAAIAnQEAAwcVATkBAwAlBgMEwwEHAgIBABcAVAUBAAQBAQHuAQMG'
    'AQEBGwFVBwIAAQFqAAEAAgUBAGUCAgMBBIMCCAEBgAIBAQAEAJABAwIBBAAgCSgFAgMIAAkFAgIuDAEB'
    'lgMGAQUBAFIVAgYBAQEBegUDAAEBAQYBAEgBAwABANsCAQsBNAQFAAEA7SkQBg6abQQ7BgkDiwgAPxBA'
    'AQEBi4ABAwEGAQGeGQEBA9wkLQIWoAQCCQ8CBh4DlAECuw82BDEIAA4AFgQBDtAKBgEQAgYBAQEEBT0h'
    'AKABDfACAD0D+wME4AcGbQevFQSBmDAAHl+AAe8B';

const int _python312LowercaseDataCount = 1433;
// Decoded SHA-256: f60e418079a42504bdcd1e670d895e46268bc3698299b3dbfdd92515ac2aaef0
const String _python312LowercaseData =
    'QQFhAAFiAAFjAAFkAAFlAAFmAAFnAAFoAAFpAAFqAAFrAAFsAAFtAAFuAAFvAAFwAAFxAAFyAAFzAAF0'
    'AAF1AAF2AAF3AAF4AAF5AAF6ZQLDoAACw6EAAsOiAALDowACw6QAAsOlAALDpgACw6cAAsOoAALDqQAC'
    'w6oAAsOrAALDrAACw60AAsOuAALDrwACw7AAAsOxAALDsgACw7MAAsO0AALDtQACw7YBAsO4AALDuQAC'
    'w7oAAsO7AALDvAACw70AAsO+IQLEgQECxIMBAsSFAQLEhwECxIkBAsSLAQLEjQECxI8BAsSRAQLEkwEC'
    'xJUBAsSXAQLEmQECxJsBAsSdAQLEnwECxKEBAsSjAQLEpQECxKcBAsSpAQLEqwECxK0BAsSvAQNpzIcB'
    'AsSzAQLEtQECxLcCAsS6AQLEvAECxL4BAsWAAQLFggECxYQBAsWGAQLFiAICxYsBAsWNAQLFjwECxZEB'
    'AsWTAQLFlQECxZcBAsWZAQLFmwECxZ0BAsWfAQLFoQECxaMBAsWlAQLFpwECxakBAsWrAQLFrQECxa8B'
    'AsWxAQLFswECxbUBAsW3AQLDvwACxboBAsW8AQLFvgMCyZMAAsaDAQLGhQECyZQAAsaIAQLJlgACyZcA'
    'AsaMAgLHnQACyZkAAsmbAALGkgECyaAAAsmjAQLJqQACyagAAsaZAwLJrwACybIBAsm1AALGoQECxqMB'
    'AsalAQLKgAACxqgBAsqDAgLGrQECyogAAsawAQLKigACyosAAsa0AQLGtgECypIAAsa5AwLGvQcCx4YA'
    'AseGAQLHiQACx4kBAseMAALHjAECx44BAseQAQLHkgECx5QBAseWAQLHmAECx5oBAsecAgLHnwECx6EB'
    'AsejAQLHpQECx6cBAsepAQLHqwECx60BAsevAgLHswACx7MBAse1AQLGlQACxr8AAse5AQLHuwECx70B'
    'Ase/AQLIgQECyIMBAsiFAQLIhwECyIkBAsiLAQLIjQECyI8BAsiRAQLIkwECyJUBAsiXAQLImQECyJsB'
    'AsidAQLInwECxp4BAsijAQLIpQECyKcBAsipAQLIqwECyK0BAsivAQLIsQECyLMHA+KxpQACyLwBAsaa'
    'AAPisaYCAsmCAQLGgAACyokAAsqMAALJhwECyYkBAsmLAQLJjQECyY+hAgLNsQECzbMDAs23CALPswYC'
    'zqwBAs6tAALOrgACzq8BAs+MAQLPjQACz44BAs6xAALOsgACzrMAAs60AALOtQACzrYAAs63AALOuAAC'
    'zrkAAs66AALOuwACzrwAAs69AALOvgACzr8AAs+AAALPgQECz4MAAs+EAALPhQACz4YAAs+HAALPiAAC'
    'z4kAAs+KAALPiyMCz5cIAs+ZAQLPmwECz50BAs+fAQLPoQECz6MBAs+lAQLPpwECz6kBAs+rAQLPrQEC'
    'z68FAs64AgLPuAECz7IAAs+7AgLNuwACzbwAAs29AALRkAAC0ZEAAtGSAALRkwAC0ZQAAtGVAALRlgAC'
    '0ZcAAtGYAALRmQAC0ZoAAtGbAALRnAAC0Z0AAtGeAALRnwAC0LAAAtCxAALQsgAC0LMAAtC0AALQtQAC'
    '0LYAAtC3AALQuAAC0LkAAtC6AALQuwAC0LwAAtC9AALQvgAC0L8AAtGAAALRgQAC0YIAAtGDAALRhAAC'
    '0YUAAtGGAALRhwAC0YgAAtGJAALRigAC0YsAAtGMAALRjQAC0Y4AAtGPMALRoQEC0aMBAtGlAQLRpwEC'
    '0akBAtGrAQLRrQEC0a8BAtGxAQLRswEC0bUBAtG3AQLRuQEC0bsBAtG9AQLRvwEC0oEJAtKLAQLSjQEC'
    '0o8BAtKRAQLSkwEC0pUBAtKXAQLSmQEC0psBAtKdAQLSnwEC0qEBAtKjAQLSpQEC0qcBAtKpAQLSqwEC'
    '0q0BAtKvAQLSsQEC0rMBAtK1AQLStwEC0rkBAtK7AQLSvQEC0r8BAtOPAALTggEC04QBAtOGAQLTiAEC'
    '04oBAtOMAQLTjgIC05EBAtOTAQLTlQEC05cBAtOZAQLTmwEC050BAtOfAQLToQEC06MBAtOlAQLTpwEC'
    '06kBAtOrAQLTrQEC068BAtOxAQLTswEC07UBAtO3AQLTuQEC07sBAtO9AQLTvwEC1IEBAtSDAQLUhQEC'
    '1IcBAtSJAQLUiwEC1I0BAtSPAQLUkQEC1JMBAtSVAQLUlwEC1JkBAtSbAQLUnQEC1J8BAtShAQLUowEC'
    '1KUBAtSnAQLUqQEC1KsBAtStAQLUrwIC1aEAAtWiAALVowAC1aQAAtWlAALVpgAC1acAAtWoAALVqQAC'
    '1aoAAtWrAALVrAAC1a0AAtWuAALVrwAC1bAAAtWxAALVsgAC1bMAAtW0AALVtQAC1bYAAtW3AALVuAAC'
    '1bkAAtW6AALVuwAC1bwAAtW9AALVvgAC1b8AAtaAAALWgQAC1oIAAtaDAALWhAAC1oUAAtaGyRYD4rSA'
    'AAPitIEAA+K0ggAD4rSDAAPitIQAA+K0hQAD4rSGAAPitIcAA+K0iAAD4rSJAAPitIoAA+K0iwAD4rSM'
    'AAPitI0AA+K0jgAD4rSPAAPitJAAA+K0kQAD4rSSAAPitJMAA+K0lAAD4rSVAAPitJYAA+K0lwAD4rSY'
    'AAPitJkAA+K0mgAD4rSbAAPitJwAA+K0nQAD4rSeAAPitJ8AA+K0oAAD4rShAAPitKIAA+K0owAD4rSk'
    'AAPitKUBA+K0pwUD4rSt0gUD6q2wAAPqrbEAA+qtsgAD6q2zAAPqrbQAA+qttQAD6q22AAPqrbcAA+qt'
    'uAAD6q25AAPqrboAA+qtuwAD6q28AAPqrb0AA+qtvgAD6q2/AAPqroAAA+qugQAD6q6CAAPqroMAA+qu'
    'hAAD6q6FAAPqroYAA+quhwAD6q6IAAPqrokAA+quigAD6q6LAAPqrowAA+qujQAD6q6OAAPqro8AA+qu'
    'kAAD6q6RAAPqrpIAA+qukwAD6q6UAAPqrpUAA+qulgAD6q6XAAPqrpgAA+qumQAD6q6aAAPqrpsAA+qu'
    'nAAD6q6dAAPqrp4AA+qunwAD6q6gAAPqrqEAA+quogAD6q6jAAPqrqQAA+qupQAD6q6mAAPqrqcAA+qu'
    'qAAD6q6pAAPqrqoAA+quqwAD6q6sAAPqrq0AA+qurgAD6q6vAAPqrrAAA+qusQAD6q6yAAPqrrMAA+qu'
    'tAAD6q61AAPqrrYAA+qutwAD6q64AAPqrrkAA+quugAD6q67AAPqrrwAA+quvQAD6q6+AAPqrr8AA+GP'
    'uAAD4Y+5AAPhj7oAA+GPuwAD4Y+8AAPhj72aEQPhg5AAA+GDkQAD4YOSAAPhg5MAA+GDlAAD4YOVAAPh'
    'g5YAA+GDlwAD4YOYAAPhg5kAA+GDmgAD4YObAAPhg5wAA+GDnQAD4YOeAAPhg58AA+GDoAAD4YOhAAPh'
    'g6IAA+GDowAD4YOkAAPhg6UAA+GDpgAD4YOnAAPhg6gAA+GDqQAD4YOqAAPhg6sAA+GDrAAD4YOtAAPh'
    'g64AA+GDrwAD4YOwAAPhg7EAA+GDsgAD4YOzAAPhg7QAA+GDtQAD4YO2AAPhg7cAA+GDuAAD4YO5AAPh'
    'g7oCA+GDvQAD4YO+AAPhg7/AAgPhuIEBA+G4gwED4biFAQPhuIcBA+G4iQED4biLAQPhuI0BA+G4jwED'
    '4biRAQPhuJMBA+G4lQED4biXAQPhuJkBA+G4mwED4bidAQPhuJ8BA+G4oQED4bijAQPhuKUBA+G4pwED'
    '4bipAQPhuKsBA+G4rQED4bivAQPhuLEBA+G4swED4bi1AQPhuLcBA+G4uQED4bi7AQPhuL0BA+G4vwED'
    '4bmBAQPhuYMBA+G5hQED4bmHAQPhuYkBA+G5iwED4bmNAQPhuY8BA+G5kQED4bmTAQPhuZUBA+G5lwED'
    '4bmZAQPhuZsBA+G5nQED4bmfAQPhuaEBA+G5owED4bmlAQPhuacBA+G5qQED4bmrAQPhua0BA+G5rwED'
    '4bmxAQPhubMBA+G5tQED4bm3AQPhubkBA+G5uwED4bm9AQPhub8BA+G6gQED4bqDAQPhuoUBA+G6hwED'
    '4bqJAQPhuosBA+G6jQED4bqPAQPhupEBA+G6kwED4bqVCQLDnwED4bqhAQPhuqMBA+G6pQED4bqnAQPh'
    'uqkBA+G6qwED4bqtAQPhuq8BA+G6sQED4bqzAQPhurUBA+G6twED4bq5AQPhursBA+G6vQED4bq/AQPh'
    'u4EBA+G7gwED4buFAQPhu4cBA+G7iQED4buLAQPhu40BA+G7jwED4buRAQPhu5MBA+G7lQED4buXAQPh'
    'u5kBA+G7mwED4budAQPhu58BA+G7oQED4bujAQPhu6UBA+G7pwED4bupAQPhu6sBA+G7rQED4buvAQPh'
    'u7EBA+G7swED4bu1AQPhu7cBA+G7uQED4bu7AQPhu70BA+G7vwkD4byAAAPhvIEAA+G8ggAD4byDAAPh'
    'vIQAA+G8hQAD4byGAAPhvIcIA+G8kAAD4byRAAPhvJIAA+G8kwAD4byUAAPhvJUKA+G8oAAD4byhAAPh'
    'vKIAA+G8owAD4bykAAPhvKUAA+G8pgAD4bynCAPhvLAAA+G8sQAD4byyAAPhvLMAA+G8tAAD4by1AAPh'
    'vLYAA+G8twgD4b2AAAPhvYEAA+G9ggAD4b2DAAPhvYQAA+G9hQsD4b2RAQPhvZMBA+G9lQED4b2XCAPh'
    'vaAAA+G9oQAD4b2iAAPhvaMAA+G9pAAD4b2lAAPhvaYAA+G9pxgD4b6AAAPhvoEAA+G+ggAD4b6DAAPh'
    'voQAA+G+hQAD4b6GAAPhvocIA+G+kAAD4b6RAAPhvpIAA+G+kwAD4b6UAAPhvpUAA+G+lgAD4b6XCAPh'
    'vqAAA+G+oQAD4b6iAAPhvqMAA+G+pAAD4b6lAAPhvqYAA+G+pwgD4b6wAAPhvrEAA+G9sAAD4b2xAAPh'
    'vrMLA+G9sgAD4b2zAAPhvbQAA+G9tQAD4b+DCwPhv5AAA+G/kQAD4b22AAPhvbcMA+G/oAAD4b+hAAPh'
    'vboAA+G9uwAD4b+lCwPhvbgAA+G9uQAD4b28AAPhvb0AA+G/s6kCAs+JAwFrAALDpQYD4oWOLQPihbAA'
    'A+KFsQAD4oWyAAPihbMAA+KFtAAD4oW1AAPihbYAA+KFtwAD4oW4AAPihbkAA+KFugAD4oW7AAPihbwA'
    'A+KFvQAD4oW+AAPihb8TA+KGhLIGA+KTkAAD4pORAAPik5IAA+KTkwAD4pOUAAPik5UAA+KTlgAD4pOX'
    'AAPik5gAA+KTmQAD4pOaAAPik5sAA+KTnAAD4pOdAAPik54AA+KTnwAD4pOgAAPik6EAA+KTogAD4pOj'
    'AAPik6QAA+KTpQAD4pOmAAPik6cAA+KTqAAD4pOpsA4D4rCwAAPisLEAA+KwsgAD4rCzAAPisLQAA+Kw'
    'tQAD4rC2AAPisLcAA+KwuAAD4rC5AAPisLoAA+KwuwAD4rC8AAPisL0AA+KwvgAD4rC/AAPisYAAA+Kx'
    'gQAD4rGCAAPisYMAA+KxhAAD4rGFAAPisYYAA+KxhwAD4rGIAAPisYkAA+KxigAD4rGLAAPisYwAA+Kx'
    'jQAD4rGOAAPisY8AA+KxkAAD4rGRAAPisZIAA+KxkwAD4rGUAAPisZUAA+KxlgAD4rGXAAPisZgAA+Kx'
    'mQAD4rGaAAPisZsAA+KxnAAD4rGdAAPisZ4AA+KxnzAD4rGhAQLJqwAD4bW9AALJvQID4rGoAQPisaoB'
    'A+KxrAECyZEAAsmxAALJkAACyZIBA+KxswID4rG2CALIvwACyYAAA+KygQED4rKDAQPisoUBA+KyhwED'
    '4rKJAQPisosBA+KyjQED4rKPAQPispEBA+KykwED4rKVAQPispcBA+KymQED4rKbAQPisp0BA+KynwED'
    '4rKhAQPisqMBA+KypQED4rKnAQPisqkBA+KyqwED4rKtAQPisq8BA+KysQED4rKzAQPisrUBA+KytwED'
    '4rK5AQPisrsBA+KyvQED4rK/AQPis4EBA+KzgwED4rOFAQPis4cBA+KziQED4rOLAQPis40BA+KzjwED'
    '4rORAQPis5MBA+KzlQED4rOXAQPis5kBA+KzmwED4rOdAQPis58BA+KzoQED4rOjCAPis6wBA+KzrgQD'
    '4rOzzfIBA+qZgQED6pmDAQPqmYUBA+qZhwED6pmJAQPqmYsBA+qZjQED6pmPAQPqmZEBA+qZkwED6pmV'
    'AQPqmZcBA+qZmQED6pmbAQPqmZ0BA+qZnwED6pmhAQPqmaMBA+qZpQED6pmnAQPqmakBA+qZqwED6pmt'
    'EwPqmoEBA+qagwED6pqFAQPqmocBA+qaiQED6pqLAQPqmo0BA+qajwED6pqRAQPqmpMBA+qalQED6pqX'
    'AQPqmpkBA+qam4cBA+qcowED6pylAQPqnKcBA+qcqQED6pyrAQPqnK0BA+qcrwMD6pyzAQPqnLUBA+qc'
    'twED6py5AQPqnLsBA+qcvQED6py/AQPqnYEBA+qdgwED6p2FAQPqnYcBA+qdiQED6p2LAQPqnY0BA+qd'
    'jwED6p2RAQPqnZMBA+qdlQED6p2XAQPqnZkBA+qdmwED6p2dAQPqnZ8BA+qdoQED6p2jAQPqnaUBA+qd'
    'pwED6p2pAQPqnasBA+qdrQED6p2vCgPqnboBA+qdvAED4bW5AAPqnb8BA+qegQED6p6DAQPqnoUBA+qe'
    'hwQD6p6MAQLJpQID6p6RAQPqnpMDA+qelwED6p6ZAQPqnpsBA+qenQED6p6fAQPqnqEBA+qeowED6p6l'
    'AQPqnqcBA+qeqQECyaYAAsmcAALJoQACyawAAsmqAQLKngACyocAAsqdAAPqrZMAA+qetQED6p63AQPq'
    'nrkBA+qeuwED6p69AQPqnr8BA+qfgQED6p+DAQPqnpQAAsqCAAPhto4AA+qfiAED6p+KBgPqn5EFA+qf'
    'lwED6p+ZHAPqn7arrgED772BAAPvvYIAA++9gwAD772EAAPvvYUAA++9hgAD772HAAPvvYgAA++9iQAD'
    '772KAAPvvYsAA++9jAAD772NAAPvvY4AA++9jwAD772QAAPvvZEAA++9kgAD772TAAPvvZQAA++9lQAD'
    '772WAAPvvZcAA++9mAAD772ZAAPvvZrFCQTwkJCoAATwkJCpAATwkJCqAATwkJCrAATwkJCsAATwkJCt'
    'AATwkJCuAATwkJCvAATwkJCwAATwkJCxAATwkJCyAATwkJCzAATwkJC0AATwkJC1AATwkJC2AATwkJC3'
    'AATwkJC4AATwkJC5AATwkJC6AATwkJC7AATwkJC8AATwkJC9AATwkJC+AATwkJC/AATwkJGAAATwkJGB'
    'AATwkJGCAATwkJGDAATwkJGEAATwkJGFAATwkJGGAATwkJGHAATwkJGIAATwkJGJAATwkJGKAATwkJGL'
    'AATwkJGMAATwkJGNAATwkJGOAATwkJGPiAEE8JCTmAAE8JCTmQAE8JCTmgAE8JCTmwAE8JCTnAAE8JCT'
    'nQAE8JCTngAE8JCTnwAE8JCToAAE8JCToQAE8JCTogAE8JCTowAE8JCTpAAE8JCTpQAE8JCTpgAE8JCT'
    'pwAE8JCTqAAE8JCTqQAE8JCTqgAE8JCTqwAE8JCTrAAE8JCTrQAE8JCTrgAE8JCTrwAE8JCTsAAE8JCT'
    'sQAE8JCTsgAE8JCTswAE8JCTtAAE8JCTtQAE8JCTtgAE8JCTtwAE8JCTuAAE8JCTuQAE8JCTugAE8JCT'
    'u5wBBPCQlpcABPCQlpgABPCQlpkABPCQlpoABPCQlpsABPCQlpwABPCQlp0ABPCQlp4ABPCQlp8ABPCQ'
    'lqAABPCQlqEBBPCQlqMABPCQlqQABPCQlqUABPCQlqYABPCQlqcABPCQlqgABPCQlqkABPCQlqoABPCQ'
    'lqsABPCQlqwABPCQlq0ABPCQlq4ABPCQlq8ABPCQlrAABPCQlrEBBPCQlrMABPCQlrQABPCQlrUABPCQ'
    'lrYABPCQlrcABPCQlrgABPCQlrkBBPCQlrsABPCQlrzqDQTwkLOAAATwkLOBAATwkLOCAATwkLODAATw'
    'kLOEAATwkLOFAATwkLOGAATwkLOHAATwkLOIAATwkLOJAATwkLOKAATwkLOLAATwkLOMAATwkLONAATw'
    'kLOOAATwkLOPAATwkLOQAATwkLORAATwkLOSAATwkLOTAATwkLOUAATwkLOVAATwkLOWAATwkLOXAATw'
    'kLOYAATwkLOZAATwkLOaAATwkLObAATwkLOcAATwkLOdAATwkLOeAATwkLOfAATwkLOgAATwkLOhAATw'
    'kLOiAATwkLOjAATwkLOkAATwkLOlAATwkLOmAATwkLOnAATwkLOoAATwkLOpAATwkLOqAATwkLOrAATw'
    'kLOsAATwkLOtAATwkLOuAATwkLOvAATwkLOwAATwkLOxAATwkLOy7RcE8JGjgAAE8JGjgQAE8JGjggAE'
    '8JGjgwAE8JGjhAAE8JGjhQAE8JGjhgAE8JGjhwAE8JGjiAAE8JGjiQAE8JGjigAE8JGjiwAE8JGjjAAE'
    '8JGjjQAE8JGjjgAE8JGjjwAE8JGjkAAE8JGjkQAE8JGjkgAE8JGjkwAE8JGjlAAE8JGjlQAE8JGjlgAE'
    '8JGjlwAE8JGjmAAE8JGjmQAE8JGjmgAE8JGjmwAE8JGjnAAE8JGjnQAE8JGjngAE8JGjn4CrAQTwlrmg'
    'AATwlrmhAATwlrmiAATwlrmjAATwlrmkAATwlrmlAATwlrmmAATwlrmnAATwlrmoAATwlrmpAATwlrmq'
    'AATwlrmrAATwlrmsAATwlrmtAATwlrmuAATwlrmvAATwlrmwAATwlrmxAATwlrmyAATwlrmzAATwlrm0'
    'AATwlrm1AATwlrm2AATwlrm3AATwlrm4AATwlrm5AATwlrm6AATwlrm7AATwlrm8AATwlrm9AATwlrm+'
    'AATwlrm/oPUBBPCepKIABPCepKMABPCepKQABPCepKUABPCepKYABPCepKcABPCepKgABPCepKkABPCe'
    'pKoABPCepKsABPCepKwABPCepK0ABPCepK4ABPCepK8ABPCepLAABPCepLEABPCepLIABPCepLMABPCe'
    'pLQABPCepLUABPCepLYABPCepLcABPCepLgABPCepLkABPCepLoABPCepLsABPCepLwABPCepL0ABPCe'
    'pL4ABPCepL8ABPCepYAABPCepYEABPCepYIABPCepYM=';

// END GENERATED SHARED CASE DATA.

final List<int> _python312CasedRanges = _decodeCaseRanges(
  _python312CasedData,
  _python312CasedDataCount,
);
final List<int> _python312CaseIgnorableRanges = _decodeCaseRanges(
  _python312CaseIgnorableData,
  _python312CaseIgnorableDataCount,
);
final Map<int, String> _python312LowercaseMappings = _decodeLowercaseMappings(
  _python312LowercaseData,
  _python312LowercaseDataCount,
);
