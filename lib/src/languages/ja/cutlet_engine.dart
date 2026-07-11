// Dart adaptation of hexgrad/misaki/misaki/cutlet.py at
// fba1236595f2d2bf21d414ba6e57d25256afada3 (Misaki 0.9.4,
// Apache-2.0), itself adapted from polm/cutlet commit
// d03f11c52a7cc7ed29a17d538e9271d693cb1cd0 (MIT).
//
// Modifications: replaces fugashi and the externally supplied ja_words.txt
// grouping resource with typed injected records carrying explicit decisions.

import '../../core/backend.dart';
import '../../core/engine.dart';
import '../../core/errors.dart';
import '../../core/python312_unicode.dart';
import '../../core/result.dart';
import 'cutlet_mapping.dart';
import 'cutlet_normalizer.dart';

/// One post-normalization morphology record consumed by Cutlet rendering.
final class JapaneseCutletMorphologyWord {
  /// Creates one immutable morphology record.
  const JapaneseCutletMorphologyWord({
    required this.surface,
    required this.hiragana,
    required this.charType,
    required this.isUnknown,
    this.joinWithNext = false,
  });

  /// Exact surface after Cutlet text normalization.
  final String surface;

  /// Hiragana reading selected from pronunciation, kana, or surface fallback.
  final String hiragana;

  /// Raw fugashi/MeCab character type.
  final int charType;

  /// Whether the morphology backend marked this record unknown.
  final bool isUnknown;

  /// Whether the pinned `ja_words.txt` decision grouped the next record here.
  ///
  /// Real adapters must provide the pinned decision or a documented
  /// equivalent; the pure package does not contain `ja_words.txt`.
  final bool joinWithNext;
}

/// Explicit morphology boundary for the Cutlet-compatible Japanese mode.
abstract interface class JapaneseCutletMorphologyBackend
    implements MisakiBackend {
  /// Analyzes already [normalizedText] in exact source order.
  List<JapaneseCutletMorphologyWord> analyze(String normalizedText);
}

/// Pure Cutlet-compatible Japanese renderer with injected morphology.
///
/// The result deliberately has `tokens == null`, matching pinned Cutlet mode.
/// No fugashi, MeCab, dictionary, or `ja_words.txt` payload is bundled.
final class JapaneseCutletEngine implements G2pEngine {
  /// Creates a Cutlet renderer backed by [backend].
  const JapaneseCutletEngine({required this.backend});

  /// Explicit morphology and grouping backend.
  final JapaneseCutletMorphologyBackend backend;

  @override
  G2pResult convert(String text) {
    if (text.isEmpty) {
      return G2pResult(phonemes: '', tokens: null);
    }
    final normalized = normalizeJapaneseCutletText(text);
    final words = _analyze(normalized);
    final grouped = _group(words);
    final rendered = <_RenderedCutletToken>[];

    for (var index = 0; index < grouped.length; index++) {
      final word = grouped[index];
      final romanized = _romanizeWord(word, index);
      final token = _RenderedCutletToken(romanized);
      final previous = rendered.isEmpty ? null : rendered.last;
      // Python's `needle in haystack` is substring membership, including the
      // observable quirk that the empty string is contained in every string.
      if (_openingSurfaces.contains(word.surface) ||
          _openingRomanizations.contains(romanized)) {
        if (previous != null) {
          previous.space = true;
        }
      } else if (_closingSurfaces.contains(word.surface) ||
          _closingRomanizations.contains(romanized)) {
        if (previous != null) {
          previous.space = false;
        }
        token.space = true;
      } else if (romanized == ' ') {
        token.space = false;
      } else {
        token.space = true;
      }
      rendered.add(token);
    }

    final output = StringBuffer();
    for (final token in rendered) {
      output.write(token.surface.replaceAll('っ', ''));
      if (token.space) {
        output.write(' ');
      }
    }
    var phonemes = _collapsePythonWhitespace(
      output.toString(),
    ).replaceAll('(', '«').replaceAll(')', '»');
    phonemes = _removeSokuonSpaces(phonemes);
    return G2pResult(phonemes: phonemes, tokens: null);
  }

  List<JapaneseCutletMorphologyWord> _analyze(String normalizedText) {
    final info = backend.info;
    try {
      return List<JapaneseCutletMorphologyWord>.unmodifiable(
        backend.analyze(normalizedText),
      );
    } on MisakiException {
      rethrow;
    } on Exception catch (error) {
      throw BackendFailureException(
        'Japanese Cutlet morphology ${info.name} ${info.version} failed.',
        cause: error,
      );
    }
  }

  List<_GroupedCutletWord> _group(List<JapaneseCutletMorphologyWord> input) {
    final result = <_GroupedCutletWord>[];
    var index = 0;
    while (index < input.length) {
      final first = input[index];
      _validateWord(first, index);
      final charType = _effectiveCharType(first);
      final surface = StringBuffer(first.surface);
      final hiragana = StringBuffer(first.hiragana);
      var end = index;
      while (input[end].joinWithNext) {
        if (end + 1 >= input.length) {
          throw _invalidWord(end, 'joinWithNext cannot target past the end.');
        }
        final next = input[end + 1];
        _validateWord(next, end + 1);
        if (_effectiveCharType(next) != charType) {
          throw _invalidWord(
            end,
            'a grouped continuation must have the same effective charType.',
          );
        }
        surface.write(next.surface);
        hiragana.write(next.hiragana);
        end++;
      }
      result.add(
        _GroupedCutletWord(
          surface: surface.toString(),
          hiragana: hiragana.toString(),
          charType: charType,
        ),
      );
      index = end + 1;
    }
    return List<_GroupedCutletWord>.unmodifiable(result);
  }

  void _validateWord(JapaneseCutletMorphologyWord word, int index) {
    if (word.surface.isEmpty) {
      throw _invalidWord(index, 'surface must not be empty.');
    }
    if (word.hiragana.isEmpty) {
      throw _invalidWord(index, 'hiragana must not be empty.');
    }
    if (word.charType < 0) {
      throw _invalidWord(index, 'charType must be non-negative.');
    }
  }

  BackendFailureException _invalidWord(int index, String message) {
    final info = backend.info;
    return BackendFailureException(
      'Japanese Cutlet morphology ${info.name} ${info.version} returned '
      'invalid word $index: $message',
    );
  }

  String _romanizeWord(_GroupedCutletWord word, int index) {
    if (word.surface.runes.every(isPython312DigitScalar)) {
      throw _invalidWord(
        index,
        'surface `${word.surface}` remained numeric after normalization.',
      );
    }
    if (_isAscii(word.surface)) {
      return word.surface;
    }
    if (word.charType == 3) {
      final result = StringBuffer();
      for (final scalar in word.surface.runes) {
        final character = String.fromCharCode(scalar);
        result.write(japaneseCutletMapping(character) ?? character);
      }
      return result.toString();
    }
    if (word.charType != 6) {
      return '';
    }

    final reading = word.hiragana.runes
        .map<String>(String.fromCharCode)
        .toList(growable: false);
    final output = StringBuffer();
    for (var kanaIndex = 0; kanaIndex < reading.length; kanaIndex++) {
      output.write(
        _singleMapping(
          kanaIndex == 0 ? null : reading[kanaIndex - 1],
          reading[kanaIndex],
          kanaIndex + 1 == reading.length ? null : reading[kanaIndex + 1],
          index,
        ),
      );
    }
    return output.toString();
  }

  String _singleMapping(
    String? previous,
    String current,
    String? next,
    int wordIndex,
  ) {
    if (_iterationMarks.contains(current)) {
      if (current == 'ゝ' || current == 'ヽ') {
        return previous ?? '';
      }
      if (current == 'ゞ' || current == 'ヾ') {
        if (previous == null) {
          return '';
        }
        final voiced = _dakuten[previous];
        return voiced == null ? '' : (japaneseCutletMapping(voiced) ?? '');
      }
      return '';
    }
    if (previous != null) {
      final combined = japaneseCutletMapping('$previous$current');
      if (combined != null) {
        return combined;
      }
    }
    if (next != null && japaneseCutletMapping('$current$next') != null) {
      return '';
    }
    if (next != null && _smallKana.contains(next)) {
      if (current == 'っ') {
        return '';
      }
      final currentMapping = japaneseCutletMapping(current);
      final nextMapping = japaneseCutletMapping(next);
      if (currentMapping == null || nextMapping == null) {
        throw _invalidWord(
          wordIndex,
          'reading `$current$next` cannot apply the small-kana fallback.',
        );
      }
      return '${_dropLastScalar(currentMapping)}$nextMapping';
    }
    if (_smallKana.contains(current)) {
      return '';
    }
    if (current == 'ー') {
      return 'ː';
    }
    if (current == 'っ') {
      return 'ʔ';
    }
    if (current == 'ん') {
      final nextMapping = next == null ? null : japaneseCutletMapping(next);
      if (nextMapping != null && nextMapping.isNotEmpty) {
        final first = String.fromCharCode(nextMapping.runes.first);
        if ('mpb'.contains(first)) {
          return 'm';
        }
        if (first == 'k' || first == 'ɡ') {
          return 'ŋ';
        }
        if (nextMapping.startsWith('ɲ') ||
            nextMapping.startsWith('ʨ') ||
            nextMapping.startsWith('ʥ')) {
          return 'ɲ';
        }
        if ('ntdɾz'.contains(first)) {
          return 'n';
        }
      }
      return 'ɴ';
    }
    return japaneseCutletMapping(current) ?? '';
  }
}

final class _GroupedCutletWord {
  const _GroupedCutletWord({
    required this.surface,
    required this.hiragana,
    required this.charType,
  });

  final String surface;
  final String hiragana;
  final int charType;
}

final class _RenderedCutletToken {
  _RenderedCutletToken(this.surface);

  final String surface;
  bool space = false;
}

int _effectiveCharType(JapaneseCutletMorphologyWord word) =>
    word.charType == 7 || !word.isUnknown ? 6 : word.charType;

bool _isAscii(String value) => value.codeUnits.every((unit) => unit < 0x80);

String _dropLastScalar(String value) {
  final scalars = value.runes.toList(growable: false);
  return String.fromCharCodes(scalars.take(scalars.length - 1));
}

String _collapsePythonWhitespace(String value) {
  final output = StringBuffer();
  var hasOutput = false;
  var pendingSpace = false;
  for (final scalar in value.runes) {
    if (_isPythonWhitespace(scalar)) {
      pendingSpace = hasOutput;
      continue;
    }
    if (pendingSpace) {
      output.write(' ');
      pendingSpace = false;
    }
    output.writeCharCode(scalar);
    hasOutput = true;
  }
  return output.toString();
}

String _removeSokuonSpaces(String value) {
  final scalars = value.runes.toList(growable: false);
  final output = <int>[];
  for (var index = 0; index < scalars.length; index++) {
    final scalar = scalars[index];
    if (scalar != 0x20) {
      output.add(scalar);
      continue;
    }
    final previous = output.isEmpty ? null : output.last;
    final next = index + 1 == scalars.length ? null : scalars[index + 1];
    if (next == _sokuon &&
        (previous == null || !_sokuonSpaceBefore.contains(previous))) {
      continue;
    }
    if (previous == _sokuon &&
        (next == null || !_sokuonSpaceAfter.contains(next))) {
      continue;
    }
    output.add(scalar);
  }
  return String.fromCharCodes(output);
}

bool _isPythonWhitespace(int scalar) =>
    (scalar >= 0x09 && scalar <= 0x0d) ||
    (scalar >= 0x1c && scalar <= 0x20) ||
    scalar == 0x85 ||
    scalar == 0xa0 ||
    scalar == 0x1680 ||
    (scalar >= 0x2000 && scalar <= 0x200a) ||
    scalar == 0x2028 ||
    scalar == 0x2029 ||
    scalar == 0x202f ||
    scalar == 0x205f ||
    scalar == 0x3000;

const Set<String> _smallKana = <String>{'ゃ', 'ゅ', 'ょ', 'ぁ', 'ぃ', 'ぅ', 'ぇ', 'ぉ'};
const Set<String> _iterationMarks = <String>{'〃', '々', 'ゝ', 'ゞ', 'ヽ'};
const String _openingSurfaces = '「『«';
const String _openingRomanizations = '([';
const String _closingSurfaces = '」』»';
const String _closingRomanizations = ']).,?!:';

const Map<String, String> _dakuten = <String, String>{
  'か': 'が',
  'き': 'ぎ',
  'く': 'ぐ',
  'け': 'げ',
  'こ': 'ご',
  'さ': 'ざ',
  'し': 'じ',
  'す': 'ず',
  'せ': 'ぜ',
  'そ': 'ぞ',
  'た': 'だ',
  'ち': 'ぢ',
  'つ': 'づ',
  'て': 'で',
  'と': 'ど',
  'は': 'ば',
  'ひ': 'び',
  'ふ': 'ぶ',
  'へ': 'べ',
  'ほ': 'ぼ',
};

const int _sokuon = 0x294;
const Set<int> _sokuonSpaceBefore = <int>{
  0x21,
  0x22,
  0x2c,
  0x2e,
  0x3a,
  0x3b,
  0x3f,
  0xbb,
  0x2014,
  0x2026,
  0x201d,
};
const Set<int> _sokuonSpaceAfter = <int>{0x22, 0xab, 0x201c};
