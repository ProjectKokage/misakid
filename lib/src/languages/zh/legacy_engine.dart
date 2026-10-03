// Dart adaptation of the legacy ZHG2P pipeline in hexgrad/misaki/misaki/zh.py
// at fba1236595f2d2bf21d414ba6e57d25256afada3 (Misaki 0.9.4,
// Apache-2.0).
//
// Modifications: replace cn2an, jieba, and pypinyin with one explicit backend
// contract; split Basic CJK runs by Unicode scalar value; and surface adapter
// and adapter-data failures through typed package exceptions.

import '../../core/backend.dart';
import '../../core/engine.dart';
import '../../core/errors.dart';
import '../../core/python_whitespace.dart';
import '../../core/result.dart';
import 'legacy_helpers.dart';
import 'transcription.dart';

/// External capabilities required by the pinned legacy Chinese pipeline.
///
/// An implementation must provide behavior equivalent to `cn2an.transform`
/// in `an2cn` mode, `jieba.lcut` with `cut_all=False`, and
/// `pypinyin.lazy_pinyin` with `Style.TONE3` and
/// `neutral_tone_with_five=True`. The core does not bundle their data. The
/// contract is platform-neutral; concrete adapters must validate package and
/// dictionary availability before use. The sibling `misakid_chinese` package
/// implements it in pure Dart over explicit pinned resources.
abstract interface class ChineseLegacyBackend implements MisakiBackend {
  /// Performs cn2an-equivalent `an2cn` normalization over the complete input.
  String normalizeNumbers(String text);

  /// Segments one non-empty U+4E00-U+9FFF run in jieba word order.
  ///
  /// Returned words must be non-empty and concatenate back to [text].
  List<String> segmentChinese(String text);

  /// Returns tone-3 Pinyin syllables for one segmented word, in source order.
  ///
  /// Exactly one non-empty syllable is required per Unicode scalar in [word].
  List<String> tone3Pinyin(String word);
}

/// Pinned legacy/default Chinese G2P pipeline.
///
/// The pure Dart stages cover punctuation mapping, Basic CJK run handling,
/// Pinyin-to-IPA transcription, legacy retone symbols, and exact mixed-script
/// rendering. Callers must explicitly supply a [ChineseLegacyBackend]; the
/// core remains data-free while optional `misakid_chinese` supplies a
/// validated pure-Dart implementation.
///
/// The pinned legacy mode cannot provide token details, so every successful
/// result has `tokens == null`. Malformed provider records and ordinary
/// adapter exceptions surface as [BackendFailureException]; typed
/// [MisakiException] values are preserved.
final class ChineseLegacyG2pEngine implements G2pEngine {
  /// Creates an engine using the explicitly configured [backend].
  const ChineseLegacyG2pEngine({required this.backend});

  /// Backend supplying normalization, segmentation, and tone-3 Pinyin.
  final ChineseLegacyBackend backend;

  @override
  G2pResult convert(String text) {
    if (_isPythonWhitespaceOnly(text)) {
      return G2pResult(phonemes: '', tokens: null);
    }

    final normalized = _callBackend(
      'cn2an-equivalent number normalization',
      () => backend.normalizeNumbers(text),
    );
    final mapped = mapLegacyChinesePunctuation(normalized);
    if (mapped.isEmpty) {
      throw BackendFailureException(
        'Chinese legacy backend ${backend.info} normalized non-whitespace '
        'input to empty text.',
      );
    }

    return G2pResult(
      phonemes: _convertMappedText(mapped).replaceAll('\u032f', ''),
      tokens: null,
    );
  }

  String _convertMappedText(String text) {
    final scalars = text.runes.iterator;
    if (!scalars.moveNext()) {
      throw const MalformedDataException(
        'Legacy Chinese punctuation mapping unexpectedly produced empty text.',
      );
    }

    var chineseRun = _isBasicCjk(scalars.current);
    var run = StringBuffer()..writeCharCode(scalars.current);
    final result = StringBuffer();

    while (scalars.moveNext()) {
      final scalar = scalars.current;
      if (_isBasicCjk(scalar) == chineseRun) {
        run.writeCharCode(scalar);
        continue;
      }

      _writeRun(result, run.toString(), chineseRun);
      run = StringBuffer()..writeCharCode(scalar);
      chineseRun = !chineseRun;
    }
    _writeRun(result, run.toString(), chineseRun);
    return result.toString();
  }

  void _writeRun(StringBuffer result, String run, bool isChinese) {
    if (!isChinese) {
      result.write(run);
      return;
    }

    final words = _callBackend(
      'jieba-equivalent segmentation',
      () => backend.segmentChinese(run),
    );
    if (words.isEmpty ||
        words.any((word) => word.isEmpty) ||
        words.join() != run) {
      throw BackendFailureException(
        'Chinese legacy backend ${backend.info} returned segmentation that '
        'does not preserve the non-empty input run.',
      );
    }
    for (var wordIndex = 0; wordIndex < words.length; wordIndex++) {
      if (wordIndex > 0) {
        result.write(' ');
      }
      final word = words[wordIndex];
      final pinyins = _callBackend(
        'tone-3 Pinyin conversion',
        () => backend.tone3Pinyin(word),
      );
      if (pinyins.length != word.runes.length ||
          pinyins.any((pinyin) => pinyin.isEmpty)) {
        throw BackendFailureException(
          'Chinese legacy backend ${backend.info} returned malformed tone-3 '
          'Pinyin for `$word`; expected one non-empty syllable per Unicode '
          'scalar.',
        );
      }
      for (final pinyin in pinyins) {
        final List<PinyinIpaVariant> variants;
        try {
          variants = pinyinToIpa(pinyin);
        } on FormatException catch (error) {
          throw BackendFailureException(
            'Chinese legacy backend ${backend.info} returned invalid tone-3 '
            'Pinyin for a segmented word.',
            cause: error,
          );
        }
        for (final phoneme in variants.first.phonemes) {
          result.write(retoneLegacyChinese(phoneme));
        }
      }
    }
  }

  T _callBackend<T>(String operation, T Function() call) {
    try {
      return call();
    } on MisakiException {
      rethrow;
    } on Exception catch (error) {
      throw BackendFailureException(
        'Chinese legacy backend ${backend.info} failed during $operation.',
        cause: error,
      );
    }
  }
}

bool _isBasicCjk(int scalar) => scalar >= 0x4e00 && scalar <= 0x9fff;

bool _isPythonWhitespaceOnly(String text) =>
    text.runes.every(isPythonWhitespace);
