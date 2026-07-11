// Dart adaptation of VIG2P.__call__ in pinned Misaki vi.py at
// fba1236595f2d2bf21d414ba6e57d25256afada3. Viphoneme/cleaner provenance is
// recorded in THIRD_PARTY_NOTICES.md. Modifications: injected external
// boundaries, immutable typed metadata/results, and bounded typed failures.

import '../../core/engine.dart';
import '../../core/errors.dart';
import '../../core/metadata.dart';
import '../../core/python311_case.dart';
import '../../core/python312_unicode.dart';
import '../../core/result.dart';
import '../../core/token.dart';
import '../../generated/vietnamese_cleaner_tables.dart';
import 'backends.dart';
import 'cleaner.dart';
import 'options.dart';
import 'phonology.dart';
import 'subtoken.dart';

/// Pure Vietnamese pipeline with explicit tokenizer and optional English
/// fallback providers.
final class VietnameseG2pEngine implements G2pEngine {
  /// Creates an engine. A `null` [englishFallback] exactly selects the
  /// no-English-fallback path; no model or resource is discovered.
  VietnameseG2pEngine({
    required this.tokenizer,
    this.options = const VietnameseOptions(),
    this.englishFallback,
  }) : cleaner = VietnameseCleaner(options: options);

  /// Underthesea-compatible token provider.
  final VietnameseTokenizerBackend tokenizer;

  /// Immutable dialect, tone, substring, and cleaning options.
  final VietnameseOptions options;

  /// Optional English phoneme provider.
  final VietnameseEnglishFallbackBackend? englishFallback;

  /// Pure text cleaner configured with [options].
  final VietnameseCleaner cleaner;

  @override
  G2pResult convert(String text) {
    var source = options.substringTokenization
        ? text.replaceAll('_', ' ').replaceAll('-', ' ')
        : text;
    final custom = <String, String>{};
    for (final match in _inlineControl.allMatches(source).toList()) {
      final word = match.group(1)!;
      custom[stripPython311Whitespace(python311Lower(word))] = match
          .group(2)!
          .replaceAll('/', '');
      source = source.replaceAll(match.group(0)!, word);
    }

    final cleaned = cleaner.clean(source);
    final backendTokens = _tokenize(cleaned);
    final tokens = <MisakiToken>[];
    final rendered = <String>[];
    for (final rawToken in backendTokens) {
      for (final token in _splitAnalyzerToken(rawToken)) {
        if (!_isEnglishVietnameseToken(token)) {
          final phonemes = '[$token]';
          rendered.add(phonemes);
          tokens.add(
            MisakiToken(
              text: token,
              tag: '',
              whitespace: ' ',
              phonemes: phonemes,
            ),
          );
          continue;
        }

        final punctuation = _normalizePunctuation(token);
        if (punctuation != null) {
          rendered.add(punctuation);
          tokens.add(
            MisakiToken(
              text: punctuation,
              tag: '',
              whitespace: ' ',
              phonemes: punctuation,
            ),
          );
          continue;
        }

        final customPhonemes =
            custom[stripPython311Whitespace(python311Lower(token))];
        if (customPhonemes != null) {
          rendered.add(customPhonemes);
          tokens.add(
            MisakiToken(
              text: token,
              tag: '',
              whitespace: ' ',
              phonemes: customPhonemes,
            ),
          );
          continue;
        }

        final firstAttempt = convertVietnameseWord(
          python311Lower(token),
          options,
        );
        final parts = _splitWithFallback(token, firstAttempt);
        for (final part in parts) {
          final fields = part.phonemes.contains('/')
              ? part.phonemes.split('/')
              : const <String>[];
          if (fields.isNotEmpty && fields.length != 4) {
            throw BackendFailureException(
              'Vietnamese English fallback returned slash-delimited output '
              'with ${fields.length} fields; expected four or none.',
            );
          }
          final onset = fields.isEmpty ? '' : fields[0];
          final nucleus = fields.isEmpty ? '' : fields[1];
          final coda = fields.isEmpty ? '' : fields[2];
          final tone = fields.isEmpty ? '' : fields[3];
          final phonemes = fields.isEmpty
              ? part.phonemes
              : '$onset$nucleus$coda$tone';
          rendered.add(phonemes);
          tokens.add(
            MisakiToken(
              text: part.text,
              tag: '',
              whitespace: ' ',
              phonemes: phonemes,
              metadata: VietnameseTokenMetadata(
                parent: part.parent,
                onset: onset,
                nucleus: nucleus,
                coda: coda,
                tone: tone,
              ),
            ),
          );
        }
      }
    }
    return G2pResult(phonemes: rendered.join(' '), tokens: tokens);
  }

  List<String> _tokenize(String text) {
    final info = tokenizer.info;
    late final List<String> tokens;
    try {
      tokens = tokenizer.tokenize(text);
    } on MisakiException {
      rethrow;
    } on Exception catch (error) {
      throw BackendFailureException(
        'Vietnamese tokenizer ${info.name} ${info.version} failed.',
        cause: error,
      );
    }
    for (var index = 0; index < tokens.length; index++) {
      if (tokens[index].isEmpty) {
        throw BackendFailureException(
          'Vietnamese tokenizer ${info.name} ${info.version} returned an '
          'empty token at index $index.',
        );
      }
    }
    return List<String>.unmodifiable(tokens);
  }

  List<VietnamesePronouncedPart> _splitWithFallback(
    String token,
    String firstAttempt,
  ) {
    final fallback = englishFallback;
    if (fallback == null) {
      return splitVietnameseToken(token, firstAttempt, options);
    }
    try {
      return splitVietnameseToken(
        token,
        firstAttempt,
        options,
        englishFallback: fallback,
      );
    } on MisakiException {
      rethrow;
    } on Exception catch (error) {
      final info = fallback.info;
      throw BackendFailureException(
        'Vietnamese English fallback ${info.name} ${info.version} failed for '
        '`${python311Lower(token)}`.',
        cause: error,
      );
    }
  }
}

List<String> _splitAnalyzerToken(String token) =>
    _pythonWhitespaceSplit(token.replaceAll('.', ' . ').replaceAll(',', ' , '));

List<String> _pythonWhitespaceSplit(String input) {
  final result = <String>[];
  final current = StringBuffer();
  for (final scalar in input.runes) {
    if (isPython312WhitespaceScalar(scalar)) {
      if (current.isNotEmpty) {
        result.add(current.toString());
        current.clear();
      }
    } else {
      current.writeCharCode(scalar);
    }
  }
  if (current.isNotEmpty) {
    result.add(current.toString());
  }
  return result;
}

bool _isEnglishVietnameseToken(String token) {
  if (token.isEmpty) {
    return false;
  }
  for (final scalar in token.runes) {
    if ((scalar >= 0x21 && scalar <= 0x7e) ||
        scalar == 0x201c ||
        scalar == 0x201d ||
        scalar == 0x2013 ||
        vietnameseCharacterSet.contains(String.fromCharCode(scalar))) {
      continue;
    }
    return false;
  }
  return true;
}

String? _normalizePunctuation(String token) {
  if (const <String>{'.', ',', ';', ':', '!', '?', ')'}.contains(token) ||
      const <String>{'}', ']'}.contains(token)) {
    return const <String>{'}', ']'}.contains(token) ? ')' : token;
  }
  if (const <String>{'(', '{', '['}.contains(token)) {
    return '(';
  }
  if (const <String>{'"', "'", '–', '“', '”'}.contains(token)) {
    return const <String>{'“', '”'}.contains(token) ? '"' : token;
  }
  return null;
}

final RegExp _inlineControl = RegExp(r'\[([^\]]+)\]\(([^\)]*)\)');
