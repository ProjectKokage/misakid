// Dart adaptation of EspeakFallback in hexgrad/misaki/misaki/espeak.py at
// fba1236595f2d2bf21d414ba6e57d25256afada3 (Misaki 0.9.4,
// Apache-2.0).
//
// Modifications: the eSpeak-ng invocation is an explicit typed backend. This
// file contains only the deterministic postprocessing and rating behavior.

import '../../core/backend.dart';
import '../../core/errors.dart';
import '../../core/python312_unicode.dart';
import '../../core/token.dart';
import 'backends.dart';
import 'morphology.dart';
import 'render.dart';

/// Raw eSpeak-ng capability required by [EnglishEspeakFallback].
///
/// An adapter must phonemize one [text] with the eSpeak-ng language matching
/// [dialect], preserving punctuation and stress and using `^` as its tie
/// character. `null` represents an empty backend result list; an empty string
/// is a present result and remains distinguishable.
abstract interface class EnglishEspeakBackend implements MisakiBackend {
  /// Returns one raw eSpeak IPA result for [text].
  String? phonemize(String text, {required EnglishDialect dialect});
}

/// Deterministic pinned eSpeak fallback postprocessor.
///
/// This class does not load eSpeak-ng or discover a library. Callers provide a
/// validated [EnglishEspeakBackend] explicitly and may then pass this object as
/// [EnglishG2pEngine.fallback].
final class EnglishEspeakFallback implements EnglishFallbackBackend {
  /// Creates a fallback for [dialect] and final [phonemeVersion] behavior.
  const EnglishEspeakFallback({
    required this.backend,
    this.dialect = EnglishDialect.american,
    this.phonemeVersion = EnglishPhonemeVersion.legacy,
  });

  /// Raw eSpeak-ng provider.
  final EnglishEspeakBackend backend;

  /// eSpeak language and dialect-specific postprocessing selection.
  final EnglishDialect dialect;

  /// Whether legacy flap/glottal replacements are applied.
  final EnglishPhonemeVersion phonemeVersion;

  @override
  BackendInfo get info => BackendInfo(
    name: 'misaki-espeak-fallback',
    version: '0.9.4',
    details: <String, String>{
      'backend': backend.info.name,
      'backendVersion': backend.info.version,
      'dialect': dialect.name,
      'phonemeVersion': phonemeVersion.name,
    },
  );

  @override
  EnglishPronunciation? pronounce(MisakiToken token) {
    final String? raw;
    try {
      raw = backend.phonemize(token.text, dialect: dialect);
    } on MisakiException {
      rethrow;
    } on Exception catch (error) {
      throw BackendFailureException(
        'English eSpeak backend ${backend.info} failed to phonemize a token.',
        cause: error,
      );
    }
    if (raw == null) {
      return null;
    }
    var phonemes = _trimPythonWhitespace(raw);
    for (final (source, replacement) in _commonMappings) {
      phonemes = phonemes.replaceAll(source, replacement);
    }
    phonemes = _replaceSyllabicCombiningMark(phonemes);

    switch (dialect) {
      case EnglishDialect.british:
        phonemes = phonemes
            .replaceAll('e^ə', 'ɛː')
            .replaceAll('iə', 'ɪə')
            .replaceAll('ə^ʊ', 'Q');
      case EnglishDialect.american:
        phonemes = phonemes
            .replaceAll('o^ʊ', 'O')
            .replaceAll('ɜːɹ', 'ɜɹ')
            .replaceAll('ɜː', 'ɜɹ')
            .replaceAll('ɪə', 'iə')
            .replaceAll('ː', '');
    }
    phonemes = phonemes.replaceAll('o', 'ɔ');
    if (phonemeVersion == EnglishPhonemeVersion.legacy) {
      phonemes = phonemes.replaceAll('ɾ', 'T').replaceAll('ʔ', 't');
    }
    return EnglishPronunciation(
      phonemes: phonemes.replaceAll('^', ''),
      rating: 2,
    );
  }
}

String _replaceSyllabicCombiningMark(String input) {
  final codePoints = input.runes.toList(growable: false);
  final output = StringBuffer();
  for (var index = 0; index < codePoints.length; index++) {
    final codePoint = codePoints[index];
    if (index + 1 < codePoints.length &&
        codePoints[index + 1] == 0x329 &&
        !isPython312WhitespaceScalar(codePoint)) {
      output.write('ᵊ');
      if (codePoint != 0x329) {
        output.writeCharCode(codePoint);
      }
      index++;
    } else if (codePoint != 0x329) {
      output.writeCharCode(codePoint);
    }
  }
  return output.toString();
}

String _trimPythonWhitespace(String input) {
  final codePoints = input.runes.toList(growable: false);
  var start = 0;
  while (start < codePoints.length &&
      isPython312WhitespaceScalar(codePoints[start])) {
    start++;
  }
  var end = codePoints.length;
  while (end > start && isPython312WhitespaceScalar(codePoints[end - 1])) {
    end--;
  }
  return String.fromCharCodes(codePoints.sublist(start, end));
}

const List<(String, String)> _commonMappings = <(String, String)>[
  ('ʔˌn\u0329', 'ʔn'),
  ('ʔn\u0329', 'ʔn'),
  ('a^ɪ', 'I'),
  ('a^ʊ', 'W'),
  ('d^ʒ', 'ʤ'),
  ('e^ɪ', 'A'),
  ('t^ʃ', 'ʧ'),
  ('ɔ^ɪ', 'Y'),
  ('ə^l', 'ᵊl'),
  ('ʲo', 'jo'),
  ('ʲə', 'jə'),
  ('ʲ', ''),
  ('ɚ', 'əɹ'),
  ('r', 'ɹ'),
  ('x', 'k'),
  ('ç', 'k'),
  ('ɐ', 'ə'),
  ('ɬ', 'l'),
  ('\u0303', ''),
];
