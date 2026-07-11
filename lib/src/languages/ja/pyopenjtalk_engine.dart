// Dart adaptation of hexgrad/misaki/misaki/ja.py at
// fba1236595f2d2bf21d414ba6e57d25256afada3 (Misaki 0.9.4).
// The pinned source and this modified Dart port are distributed under the
// Apache License 2.0. This file replaces pyopenjtalk dictionaries with typed,
// injected frontend values and validates upstream assertions at runtime.

import '../../core/constants.dart';
import '../../core/engine.dart';
import '../../core/errors.dart';
import '../../core/metadata.dart';
import '../../core/result.dart';
import '../../core/token.dart';
import 'frontend.dart';

/// Pure rendering pipeline for pyopenjtalk-style Japanese frontend words.
///
/// This engine does not load or discover pyopenjtalk. Callers must explicitly
/// inject a [JapaneseFrontendBackend] that supplies compatible word data.
final class JapanesePyopenjtalkEngine implements G2pEngine {
  /// Creates a Japanese pipeline backed by [backend].
  JapanesePyopenjtalkEngine({
    required JapaneseFrontendBackend backend,
    this.unknownMarker = defaultUnknownMarker,
  }) : _backend = backend {
    _ensureInventoryIsValid();
  }

  final JapaneseFrontendBackend _backend;

  /// Marker rendered for frontend words without phonemes.
  final String unknownMarker;

  /// Splits a frontend [pronunciation] into the pinned inventory's moras.
  ///
  /// Unsupported Unicode scalars are ignored, matching upstream. The returned
  /// list is unmodifiable.
  static List<String> pronunciationToMoras(String pronunciation) {
    _ensureInventoryIsValid();
    final moras = <String>[];
    for (final character in _scalarCharacters(pronunciation)) {
      if (!_moraToPhoneme.containsKey(character)) {
        continue;
      }
      if (moras.isNotEmpty) {
        final combined = '${moras.last}$character';
        if (_moraToPhoneme.containsKey(combined)) {
          moras[moras.length - 1] = combined;
          continue;
        }
      }
      moras.add(character);
    }
    return List<String>.unmodifiable(moras);
  }

  /// Converts [text] with the injected frontend.
  ///
  /// As in the pinned pyopenjtalk-style mode, [G2pResult.phonemes] contains the
  /// rendered phoneme text followed immediately by its equal-scalar-length
  /// pitch trace.
  @override
  G2pResult convert(String text) {
    final words = _analyze(text);
    final tokens = <_WorkingJapaneseToken>[];
    var lastAccentState = 0;
    int? phraseAccent;
    var phraseMoraCount = 0;

    for (var wordIndex = 0; wordIndex < words.length; wordIndex++) {
      final word = words[wordIndex];
      if (word.moraSize < 0) {
        throw _invalidWord(
          wordIndex,
          'moraSize must be non-negative, got ${word.moraSize}.',
        );
      }
      if (word.accent < 0) {
        throw _invalidWord(
          wordIndex,
          'accent must be non-negative, got ${word.accent}.',
        );
      }

      var moras = const <String>[];
      if (word.moraSize > 0) {
        moras = pronunciationToMoras(word.pronunciation);
        final leadingLongVowelAdjustment =
            moras.isNotEmpty && moras.first == 'ー' ? 1 : 0;
        if (moras.length != word.moraSize &&
            moras.length + leadingLongVowelAdjustment != word.moraSize) {
          throw _invalidWord(
            wordIndex,
            'pronunciation `${word.pronunciation}` produced ${moras.length} '
            'moras, but moraSize is ${word.moraSize}.',
          );
        }
      }

      final chainFlag =
          word.moraSize > 0 &&
          tokens.isNotEmpty &&
          tokens.last.moraSize > 0 &&
          (word.chainFlag || moras.first == 'ー');
      if (!chainFlag) {
        phraseAccent = null;
        phraseMoraCount = 0;
      }
      phraseAccent ??= word.accent;

      final accents = <int>[];
      for (var moraIndex = 0; moraIndex < moras.length; moraIndex++) {
        phraseMoraCount++;
        final accentState = switch (phraseAccent) {
          0 => phraseMoraCount == 1 ? 0 : (lastAccentState == 0 ? 1 : 2),
          final int accent when accent == phraseMoraCount => 3,
          final int accent
              when 1 < phraseMoraCount && phraseMoraCount < accent =>
            lastAccentState == 0 ? 1 : 2,
          _ => 0,
        };
        accents.add(accentState);
        lastAccentState = accentState;
      }

      final surface = _punctuationMap[word.surface] ?? word.surface;
      var whitespace = '';
      String? phonemes;
      String? pitch;
      if (moras.isNotEmpty) {
        final phonemeBuffer = StringBuffer();
        final pitchBuffer = StringBuffer();
        for (var moraIndex = 0; moraIndex < moras.length; moraIndex++) {
          final phoneme = _moraToPhoneme[moras[moraIndex]];
          if (phoneme == null) {
            throw MalformedDataException(
              'Japanese mora table has no phoneme for `${moras[moraIndex]}`.',
            );
          }
          phonemeBuffer.write(phoneme);
          final pitchSymbol = switch (accents[moraIndex]) {
            0 => '_',
            3 => '^',
            _ => '-',
          };
          _writeRepeated(pitchBuffer, pitchSymbol, _scalarLength(phoneme));
        }
        phonemes = phonemeBuffer.toString();
        pitch = pitchBuffer.toString();
      } else if (_isPunctuation(surface)) {
        phonemes = surface;
        final finalCharacter = _lastScalar(surface);
        if (_punctuationStops.contains(finalCharacter)) {
          whitespace = ' ';
          if (tokens.isNotEmpty) {
            tokens.last.whitespace = '';
          }
        } else if (_punctuationStarts.contains(finalCharacter) &&
            tokens.isNotEmpty &&
            tokens.last.whitespace.isEmpty) {
          tokens.last.whitespace = ' ';
        }
      }

      final mergesIntoPrevious =
          (tokens.isNotEmpty && phonemes == null && surface == '・') ||
          _isNonEmptyWhitespace(surface);
      if (mergesIntoPrevious) {
        if (tokens.isEmpty) {
          throw _invalidWord(
            wordIndex,
            'leading whitespace cannot attach to a preceding token.',
          );
        }
        tokens.last.whitespace = ' ';
        continue;
      }

      tokens.add(
        _WorkingJapaneseToken(
          text: surface,
          tag: word.partOfSpeech,
          whitespace: whitespace,
          phonemes: phonemes,
          pronunciation: word.pronunciation,
          accent: word.accent,
          moraSize: word.moraSize,
          chainFlag: chainFlag,
          moras: moras,
          accents: accents,
          pitch: pitch,
        ),
      );
    }

    return _render(tokens);
  }

  List<JapaneseFrontendWord> _analyze(String text) {
    final backendInfo = _backend.info;
    try {
      return _backend.analyze(text);
    } on MisakiException {
      rethrow;
    } on Exception catch (error) {
      throw BackendFailureException(
        'Japanese frontend ${backendInfo.name} ${backendInfo.version} failed.',
        cause: error,
      );
    }
  }

  BackendFailureException _invalidWord(int index, String message) {
    final backendInfo = _backend.info;
    return BackendFailureException(
      'Japanese frontend ${backendInfo.name} ${backendInfo.version} returned '
      'invalid word $index: $message',
    );
  }

  G2pResult _render(List<_WorkingJapaneseToken> tokens) {
    final result = StringBuffer();
    final pitch = StringBuffer();
    String? lastResultScalar;

    for (final token in tokens) {
      if (token.phonemes == null) {
        final rendered = '$unknownMarker${token.whitespace}';
        result.write(rendered);
        _writeRepeated(pitch, 'j', _scalarLength(rendered));
        if (rendered.isNotEmpty) {
          lastResultScalar = _lastScalar(rendered);
        }
        continue;
      }

      if (token.moraSize > 0 &&
          !token.chainFlag &&
          lastResultScalar != null &&
          _phonemeTails.contains(lastResultScalar) &&
          token.moras.first != 'ン') {
        result.write(' ');
        pitch.write('j');
        lastResultScalar = ' ';
      }

      final rendered = '${token.phonemes}${token.whitespace}';
      result.write(rendered);
      if (token.pitch == null) {
        _writeRepeated(pitch, 'j', _scalarLength(token.phonemes!));
      } else {
        pitch.write(token.pitch);
      }
      _writeRepeated(pitch, 'j', _scalarLength(token.whitespace));
      if (rendered.isNotEmpty) {
        lastResultScalar = _lastScalar(rendered);
      }
    }

    var resultText = result.toString();
    var pitchText = pitch.toString();
    if (tokens.isNotEmpty &&
        tokens.last.whitespace.isNotEmpty &&
        resultText.endsWith(tokens.last.whitespace)) {
      resultText = _dropLastScalars(
        resultText,
        _scalarLength(tokens.last.whitespace),
      );
      pitchText = _takeScalars(pitchText, _scalarLength(resultText));
    }

    return G2pResult(
      phonemes: '$resultText$pitchText',
      tokens: <MisakiToken>[for (final token in tokens) token.freeze()],
    );
  }
}

final class _WorkingJapaneseToken {
  _WorkingJapaneseToken({
    required this.text,
    required this.tag,
    required this.whitespace,
    required this.phonemes,
    required this.pronunciation,
    required this.accent,
    required this.moraSize,
    required this.chainFlag,
    required this.moras,
    required this.accents,
    required this.pitch,
  });

  final String text;
  final String tag;
  String whitespace;
  final String? phonemes;
  final String pronunciation;
  final int accent;
  final int moraSize;
  final bool chainFlag;
  final List<String> moras;
  final List<int> accents;
  final String? pitch;

  MisakiToken freeze() => MisakiToken(
    text: text,
    tag: tag,
    whitespace: whitespace,
    phonemes: phonemes,
    metadata: JapaneseTokenMetadata(
      pronunciation: pronunciation,
      accent: accent,
      moraSize: moraSize,
      chainFlag: chainFlag,
      moras: moras,
      accents: accents,
      pitch: pitch,
    ),
  );
}

const Map<String, String> _moraToPhoneme = <String, String>{
  'ァ': 'a',
  'ア': 'a',
  'ィ': 'i',
  'イ': 'i',
  'ゥ': 'u',
  'ウ': 'u',
  'ェ': 'e',
  'エ': 'e',
  'ォ': 'o',
  'オ': 'o',
  'カ': 'ka',
  'ガ': 'ga',
  'キ': 'ki',
  'ギ': 'gi',
  'ク': 'ku',
  'グ': 'gu',
  'ケ': 'ke',
  'ゲ': 'ge',
  'コ': 'ko',
  'ゴ': 'go',
  'サ': 'sa',
  'ザ': 'za',
  'シ': 'ɕi',
  'ジ': 'ʥi',
  'ス': 'su',
  'ズ': 'zu',
  'セ': 'se',
  'ゼ': 'ze',
  'ソ': 'so',
  'ゾ': 'zo',
  'タ': 'ta',
  'ダ': 'da',
  'チ': 'ʨi',
  'ヂ': 'ʥi',
  'ツ': 'ʦu',
  'ヅ': 'zu',
  'テ': 'te',
  'デ': 'de',
  'ト': 'to',
  'ド': 'do',
  'ナ': 'na',
  'ニ': 'ni',
  'ヌ': 'nu',
  'ネ': 'ne',
  'ノ': 'no',
  'ハ': 'ha',
  'バ': 'ba',
  'パ': 'pa',
  'ヒ': 'hi',
  'ビ': 'bi',
  'ピ': 'pi',
  'フ': 'fu',
  'ブ': 'bu',
  'プ': 'pu',
  'ヘ': 'he',
  'ベ': 'be',
  'ペ': 'pe',
  'ホ': 'ho',
  'ボ': 'bo',
  'ポ': 'po',
  'マ': 'ma',
  'ミ': 'mi',
  'ム': 'mu',
  'メ': 'me',
  'モ': 'mo',
  'ャ': 'ja',
  'ヤ': 'ja',
  'ュ': 'ju',
  'ユ': 'ju',
  'ョ': 'jo',
  'ヨ': 'jo',
  'ラ': 'ra',
  'リ': 'ri',
  'ル': 'ru',
  'レ': 're',
  'ロ': 'ro',
  'ヮ': 'wa',
  'ワ': 'wa',
  'ヰ': 'i',
  'ヱ': 'e',
  'ヲ': 'o',
  'ヴ': 'vu',
  'ヵ': 'ka',
  'ヶ': 'ke',
  'ヷ': 'va',
  'ヸ': 'vi',
  'ヹ': 've',
  'ヺ': 'vo',
  'イェ': 'je',
  'ウィ': 'wi',
  'ウゥ': 'wu',
  'ウェ': 'we',
  'ウォ': 'wo',
  'キィ': 'ᶄi',
  'キェ': 'ᶄe',
  'キャ': 'ᶄa',
  'キュ': 'ᶄu',
  'キョ': 'ᶄo',
  'ギィ': 'ᶃi',
  'ギェ': 'ᶃe',
  'ギャ': 'ᶃa',
  'ギュ': 'ᶃu',
  'ギョ': 'ᶃo',
  'クァ': 'Ka',
  'クィ': 'Ki',
  'クゥ': 'Ku',
  'クェ': 'Ke',
  'クォ': 'Ko',
  'クヮ': 'Ka',
  'グァ': 'Ga',
  'グィ': 'Gi',
  'グゥ': 'Gu',
  'グェ': 'Ge',
  'グォ': 'Go',
  'グヮ': 'Ga',
  'シェ': 'ɕe',
  'シャ': 'ɕa',
  'シュ': 'ɕu',
  'ショ': 'ɕo',
  'ジェ': 'ʥe',
  'ジャ': 'ʥa',
  'ジュ': 'ʥu',
  'ジョ': 'ʥo',
  'スィ': 'si',
  'ズィ': 'zi',
  'チェ': 'ʨe',
  'チャ': 'ʨa',
  'チュ': 'ʨu',
  'チョ': 'ʨo',
  'ヂェ': 'ʥe',
  'ヂャ': 'ʥa',
  'ヂュ': 'ʥu',
  'ヂョ': 'ʥo',
  'ツァ': 'ʦa',
  'ツィ': 'ʦi',
  'ツェ': 'ʦe',
  'ツォ': 'ʦo',
  'ティ': 'ti',
  'テェ': 'ƫe',
  'テャ': 'ƫa',
  'テュ': 'ƫu',
  'テョ': 'ƫo',
  'ディ': 'di',
  'デェ': 'ᶁe',
  'デャ': 'ᶁa',
  'デュ': 'ᶁu',
  'デョ': 'ᶁo',
  'トゥ': 'tu',
  'ドゥ': 'du',
  'ニィ': 'ɲi',
  'ニェ': 'ɲe',
  'ニャ': 'ɲa',
  'ニュ': 'ɲu',
  'ニョ': 'ɲo',
  'ヒィ': 'çi',
  'ヒェ': 'çe',
  'ヒャ': 'ça',
  'ヒュ': 'çu',
  'ヒョ': 'ço',
  'ビィ': 'ᶀi',
  'ビェ': 'ᶀe',
  'ビャ': 'ᶀa',
  'ビュ': 'ᶀu',
  'ビョ': 'ᶀo',
  'ピィ': 'ᶈi',
  'ピェ': 'ᶈe',
  'ピャ': 'ᶈa',
  'ピュ': 'ᶈu',
  'ピョ': 'ᶈo',
  'ファ': 'fa',
  'フィ': 'fi',
  'フェ': 'fe',
  'フォ': 'fo',
  'ミィ': 'ᶆi',
  'ミェ': 'ᶆe',
  'ミャ': 'ᶆa',
  'ミュ': 'ᶆu',
  'ミョ': 'ᶆo',
  'リィ': 'ᶉi',
  'リェ': 'ᶉe',
  'リャ': 'ᶉa',
  'リュ': 'ᶉu',
  'リョ': 'ᶉo',
  'ヴァ': 'va',
  'ヴィ': 'vi',
  'ヴェ': 've',
  'ヴォ': 'vo',
  'ヴャ': 'ᶀa',
  'ヴュ': 'ᶀu',
  'ヴョ': 'ᶀo',
  'ッ': 'ʔ',
  'ン': 'ɴ',
  'ー': 'ː',
};

/// Ordered mora mappings exposed only from this internal library for QA.
Iterable<MapEntry<String, String>> get japanesePyopenjtalkMoraEntries =>
    _moraToPhoneme.entries;

const Set<String> _vowels = <String>{'a', 'e', 'i', 'o', 'u'};

const Set<String> _consonants = <String>{
  'b',
  'd',
  'f',
  'g',
  'G',
  'h',
  'j',
  'k',
  'K',
  'm',
  'n',
  'p',
  'r',
  's',
  't',
  'v',
  'w',
  'z',
  'ç',
  'ƫ',
  'ɕ',
  'ɲ',
  'ʥ',
  'ʦ',
  'ʨ',
  'ᶀ',
  'ᶁ',
  'ᶃ',
  'ᶄ',
  'ᶆ',
  'ᶈ',
  'ᶉ',
};

const Set<String> _specialMoras = <String>{'ッ', 'ン', 'ー'};
const Set<String> _phonemeTails = <String>{
  'a',
  'e',
  'i',
  'o',
  'u',
  'ʔ',
  'ɴ',
  'ː',
};

const Map<String, String> _punctuationMap = <String, String>{
  '«': '“',
  '»': '”',
  '、': ',',
  '。': '.',
  '〈': '“',
  '〉': '”',
  '《': '“',
  '》': '”',
  '「': '“',
  '」': '”',
  '『': '“',
  '』': '”',
  '【': '“',
  '】': '”',
  '！': '!',
  '（': '(',
  '）': ')',
  '：': ':',
  '；': ';',
  '？': '?',
};

const Set<String> _punctuationValues = <String>{
  '!',
  '"',
  '(',
  ')',
  ',',
  '.',
  ':',
  ';',
  '?',
  '—',
  '“',
  '”',
  '…',
};
const Set<String> _punctuationStarts = <String>{'(', '“'};
const Set<String> _punctuationStops = <String>{
  '!',
  ')',
  ',',
  '.',
  ':',
  ';',
  '?',
  '”',
};

final bool _inventoryIsValid = _validateInventory();

void _ensureInventoryIsValid() {
  if (!_inventoryIsValid) {
    throw const MalformedDataException('Japanese mora inventory is invalid.');
  }
}

bool _validateInventory() {
  if (_moraToPhoneme.length != 193) {
    throw MalformedDataException(
      'Japanese mora inventory has ${_moraToPhoneme.length} entries; expected 193.',
    );
  }
  for (var codePoint = 12449; codePoint < 12449 + 90; codePoint++) {
    final character = String.fromCharCode(codePoint);
    if (character != 'ッ' &&
        character != 'ン' &&
        !_moraToPhoneme.containsKey(character)) {
      throw MalformedDataException(
        'Japanese mora inventory is missing U+${codePoint.toRadixString(16)}.',
      );
    }
  }

  for (final entry in _moraToPhoneme.entries) {
    final keyLength = _scalarLength(entry.key);
    if (keyLength != 1 && keyLength != 2) {
      throw MalformedDataException(
        'Japanese mora `${entry.key}` must contain one or two Unicode scalars.',
      );
    }
    if (keyLength == 2) {
      for (final component in _scalarCharacters(entry.key)) {
        if (!_moraToPhoneme.containsKey(component)) {
          throw MalformedDataException(
            'Japanese mora `${entry.key}` contains unsupported `$component`.',
          );
        }
      }
    }
    if (_specialMoras.contains(entry.key)) {
      continue;
    }

    final phonemeLength = _scalarLength(entry.value);
    if (phonemeLength != 1 && phonemeLength != 2) {
      throw MalformedDataException(
        'Japanese phoneme `${entry.value}` must contain one or two Unicode scalars.',
      );
    }
    final phonemeCharacters = _scalarCharacters(entry.value);
    if (!_vowels.contains(phonemeCharacters.last) ||
        (phonemeLength == 2 &&
            !_consonants.contains(phonemeCharacters.first))) {
      throw MalformedDataException(
        'Japanese phoneme `${entry.value}` violates the pinned inventory.',
      );
    }
  }

  final actualTails = <String>{
    for (final phoneme in _moraToPhoneme.values) _lastScalar(phoneme),
  };
  if (actualTails.length != _phonemeTails.length ||
      !_phonemeTails.every(actualTails.contains)) {
    throw const MalformedDataException(
      'Japanese phoneme tail inventory does not match the pinned source.',
    );
  }
  if (_punctuationValues.length != 13 ||
      _punctuationStarts.length != 2 ||
      _punctuationStops.length != 8 ||
      _punctuationMap.entries.any(
        (entry) =>
            _scalarLength(entry.key) != 1 || _scalarLength(entry.value) != 1,
      )) {
    throw const MalformedDataException(
      'Japanese punctuation inventory does not match the pinned source.',
    );
  }
  return true;
}

bool _isPunctuation(String surface) {
  final characters = _scalarCharacters(surface);
  return characters.isNotEmpty && characters.every(_punctuationValues.contains);
}

bool _isNonEmptyWhitespace(String surface) =>
    surface.isNotEmpty && surface.runes.every(_isPythonWhitespace);

// CPython str.isspace/strip uses bidirectional WS/B/S characters, Unicode Zs,
// and the four historic ASCII information separators U+001C..U+001F.
bool _isPythonWhitespace(int codePoint) =>
    (codePoint >= 0x09 && codePoint <= 0x0d) ||
    (codePoint >= 0x1c && codePoint <= 0x20) ||
    codePoint == 0x85 ||
    codePoint == 0xa0 ||
    codePoint == 0x1680 ||
    (codePoint >= 0x2000 && codePoint <= 0x200a) ||
    codePoint == 0x2028 ||
    codePoint == 0x2029 ||
    codePoint == 0x202f ||
    codePoint == 0x205f ||
    codePoint == 0x3000;

List<String> _scalarCharacters(String value) =>
    value.runes.map<String>(String.fromCharCode).toList(growable: false);

int _scalarLength(String value) => value.runes.length;

String _lastScalar(String value) => String.fromCharCode(value.runes.last);

String _dropLastScalars(String value, int count) {
  final keep = _scalarLength(value) - count;
  return _takeScalars(value, keep);
}

String _takeScalars(String value, int count) =>
    String.fromCharCodes(value.runes.take(count));

void _writeRepeated(StringBuffer buffer, String value, int count) {
  for (var index = 0; index < count; index++) {
    buffer.write(value);
  }
}
