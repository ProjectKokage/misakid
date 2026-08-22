// Dart adaptation of English G2P.__call__ orchestration in
// hexgrad/misaki/misaki/en.py at
// fba1236595f2d2bf21d414ba6e57d25256afada3 (Misaki 0.9.4,
// Apache-2.0).
//
// Modifications: composes immutable pure stages around explicit typed backend
// contracts. It never loads spaCy, model weights, or a built-in lexicon.

import '../../core/backend.dart';
import '../../core/constants.dart';
import '../../core/engine.dart';
import '../../core/errors.dart';
import '../../core/metadata.dart';
import '../../core/result.dart';
import '../../core/token.dart';
import 'backends.dart';
import 'context.dart';
import 'preprocess.dart';
import 'render.dart';
import 'resolve.dart';
import 'retokenize.dart';
import 'token_merge.dart';

/// English G2P orchestration with explicitly injected language backends.
///
/// A tokenizer/tagger and context-aware pronunciation provider are required.
/// The package supplies `PinnedEnglishLexicon` for pronunciation data, but no
/// real tokenizer, spaCy, eSpeak, or model fallback adapter.
final class EnglishG2pEngine implements UnknownMarkerG2pEngine {
  /// Creates an English engine using caller-supplied backends.
  EnglishG2pEngine({
    required this.tokenizer,
    required this.pronunciation,
    this.fallback,
    this.phonemeVersion = EnglishPhonemeVersion.legacy,
    this.unknownMarker = defaultUnknownMarker,
    this.preprocessInput = true,
  });

  /// Tokenizer and part-of-speech tagger used by this engine.
  final EnglishTokenizerBackend tokenizer;

  /// Context-aware pronunciation or lexicon provider.
  final EnglishPronunciationBackend pronunciation;

  /// Optional context-free fallback provider.
  final EnglishFallbackBackend? fallback;

  /// Final phoneme inventory rendering behavior.
  final EnglishPhonemeVersion phonemeVersion;

  /// Marker rendered for unresolved tokens.
  @override
  final String unknownMarker;

  /// Whether [convert] applies Misaki inline preprocessing before tokenization.
  final bool preprocessInput;

  @override
  G2pResult convert(String text) {
    final resolution = _startEnglishResolution(
      text: text,
      tokenizer: tokenizer,
      pronunciation: pronunciation,
      fallbackAvailable: fallback != null,
      unknownMarker: unknownMarker,
      preprocessInput: preprocessInput,
    );
    var request = resolution.next();
    while (request != null) {
      request = resolution.resume(_fallback(request.token));
    }
    return _renderEnglishResolution(
      resolution,
      version: phonemeVersion,
      unknownMarker: unknownMarker,
    );
  }

  EnglishPronunciation? _fallback(MisakiToken token) {
    final backend = fallback;
    if (backend == null) {
      return null;
    }
    final backendInfo = backend.info;
    try {
      final result = backend.pronounce(token);
      _validateBackendPronunciation(result, backendInfo, 'fallback');
      return result;
    } on MisakiException {
      rethrow;
    } on Exception catch (error) {
      throw BackendFailureException(
        'English fallback ${backendInfo.name} ${backendInfo.version} failed.',
        cause: error,
      );
    }
  }
}

/// English G2P orchestration with an asynchronous model/process fallback.
///
/// Tokenization, lexicon lookup, context propagation, grouping, and rendering
/// remain the same synchronous pure stages as [EnglishG2pEngine]. Only fallback
/// pronunciation is awaited, so callers never have to block an isolate on
/// model-backed work.
final class AsyncEnglishG2pEngine implements AsyncUnknownMarkerG2pEngine {
  /// Creates an English engine using caller-supplied backends.
  AsyncEnglishG2pEngine({
    required this.tokenizer,
    required this.pronunciation,
    this.fallback,
    this.phonemeVersion = EnglishPhonemeVersion.legacy,
    this.unknownMarker = defaultUnknownMarker,
    this.preprocessInput = true,
  });

  /// Tokenizer and part-of-speech tagger used by this engine.
  final EnglishTokenizerBackend tokenizer;

  /// Context-aware pronunciation or lexicon provider.
  final EnglishPronunciationBackend pronunciation;

  /// Optional asynchronous context-free fallback provider.
  final AsyncEnglishFallbackBackend? fallback;

  /// Final phoneme inventory rendering behavior.
  final EnglishPhonemeVersion phonemeVersion;

  /// Marker rendered for unresolved tokens.
  @override
  final String unknownMarker;

  /// Whether [convert] applies Misaki inline preprocessing before tokenization.
  final bool preprocessInput;

  @override
  Future<G2pResult> convert(String text) async {
    final resolution = _startEnglishResolution(
      text: text,
      tokenizer: tokenizer,
      pronunciation: pronunciation,
      fallbackAvailable: fallback != null,
      unknownMarker: unknownMarker,
      preprocessInput: preprocessInput,
    );
    var request = resolution.next();
    while (request != null) {
      request = resolution.resume(await _fallback(request.token));
    }
    return _renderEnglishResolution(
      resolution,
      version: phonemeVersion,
      unknownMarker: unknownMarker,
    );
  }

  Future<EnglishPronunciation?> _fallback(MisakiToken token) async {
    final backend = fallback;
    if (backend == null) {
      return null;
    }
    final backendInfo = backend.info;
    try {
      final result = await backend.pronounce(token);
      _validateBackendPronunciation(result, backendInfo, 'fallback');
      return result;
    } on MisakiException {
      rethrow;
    } on Exception catch (error) {
      throw BackendFailureException(
        'English fallback ${backendInfo.name} ${backendInfo.version} failed.',
        cause: error,
      );
    }
  }
}

_EnglishResolution _startEnglishResolution({
  required String text,
  required EnglishTokenizerBackend tokenizer,
  required EnglishPronunciationBackend pronunciation,
  required bool fallbackAvailable,
  required String unknownMarker,
  required bool preprocessInput,
}) {
  final preprocessed = preprocessInput
      ? const EnglishInlinePreprocessor().preprocess(text)
      : EnglishPreprocessResult(
          text: text,
          sourceWords: const <String>[],
          controls: const <int, EnglishInlineControl>{},
        );
  final tokenized = _tokenizeEnglish(tokenizer, preprocessed);
  final folded = foldEnglishTokenHeads(tokenized, unknownMarker: unknownMarker);
  return _EnglishResolution(
    retokenizeEnglishTokens(folded),
    fallbackAvailable: fallbackAvailable,
    lookup: (token, context) => _lookupEnglish(pronunciation, token, context),
  );
}

G2pResult _renderEnglishResolution(
  _EnglishResolution resolution, {
  required EnglishPhonemeVersion version,
  required String unknownMarker,
}) {
  final finalTokens = <MisakiToken>[
    for (final item in resolution.items)
      switch (item) {
        EnglishRetokenizedToken(:final token) => token,
        EnglishRetokenizedGroup(:final tokens) => mergeEnglishTokens(
          tokens,
          unknownMarker: unknownMarker,
        ),
      },
  ];
  return renderEnglishTokens(
    finalTokens,
    version: version,
    unknownMarker: unknownMarker,
  );
}

List<MisakiToken> _tokenizeEnglish(
  EnglishTokenizerBackend tokenizer,
  EnglishPreprocessResult input,
) {
  final backendInfo = tokenizer.info;
  late final List<MisakiToken> result;
  try {
    result = tokenizer.tokenize(input);
  } on MisakiException {
    rethrow;
  } on Exception catch (error) {
    throw BackendFailureException(
      'English tokenizer ${backendInfo.name} ${backendInfo.version} failed.',
      cause: error,
    );
  }
  final reconstructed = StringBuffer();
  for (var index = 0; index < result.length; index++) {
    final token = result[index];
    final metadata = token.metadata;
    if (metadata is! EnglishTokenMetadata) {
      throw BackendFailureException(
        'English tokenizer ${backendInfo.name} ${backendInfo.version} '
        'returned token $index without English metadata.',
      );
    }
    if (token.text.isEmpty || token.tag.isEmpty) {
      throw BackendFailureException(
        'English tokenizer ${backendInfo.name} ${backendInfo.version} '
        'returned token $index with empty text or tag.',
      );
    }
    if (index == 0 && !metadata.isHead) {
      throw BackendFailureException(
        'English tokenizer ${backendInfo.name} ${backendInfo.version} '
        'returned a continuation as its first token.',
      );
    }
    final stress = metadata.stress;
    if (stress != null &&
        (!stress.isFinite || stress * 2 != (stress * 2).round())) {
      throw BackendFailureException(
        'English tokenizer ${backendInfo.name} ${backendInfo.version} '
        'returned token $index with non-half-step stress `$stress`.',
      );
    }
    final rating = metadata.rating;
    if (rating != null && (rating < 1 || rating > 5)) {
      throw BackendFailureException(
        'English tokenizer ${backendInfo.name} ${backendInfo.version} '
        'returned token $index with rating `$rating` outside 1..5.',
      );
    }
    reconstructed
      ..write(token.text)
      ..write(token.whitespace);
  }
  if (reconstructed.toString() != input.text) {
    throw BackendFailureException(
      'English tokenizer ${backendInfo.name} ${backendInfo.version} '
      'did not preserve the exact preprocessed text.',
    );
  }
  return List<MisakiToken>.unmodifiable(result);
}

EnglishPronunciation? _lookupEnglish(
  EnglishPronunciationBackend pronunciation,
  MisakiToken token,
  EnglishTokenContext context,
) {
  final backendInfo = pronunciation.info;
  try {
    final result = pronunciation.lookup(token, context);
    _validateBackendPronunciation(result, backendInfo, 'pronunciation');
    return result;
  } on MisakiException {
    rethrow;
  } on Exception catch (error) {
    throw BackendFailureException(
      'English pronunciation ${backendInfo.name} ${backendInfo.version} '
      'failed.',
      cause: error,
    );
  }
}

typedef _EnglishLookup =
    EnglishPronunciation? Function(
      MisakiToken token,
      EnglishTokenContext context,
    );

final class _EnglishFallbackRequest {
  const _EnglishFallbackRequest(this.token);

  final MisakiToken token;
}

final class _EnglishResolution {
  _EnglishResolution(
    List<EnglishRetokenizedItem> input, {
    required bool fallbackAvailable,
    required _EnglishLookup lookup,
  }) : _items = List<EnglishRetokenizedItem>.of(input),
       _itemIndex = input.length - 1,
       _fallbackAvailable = fallbackAvailable,
       _lookup = lookup;

  final List<EnglishRetokenizedItem> _items;
  final bool _fallbackAvailable;
  final _EnglishLookup _lookup;
  var _context = const EnglishTokenContext();
  int _itemIndex;
  void Function(EnglishPronunciation? result)? _pendingFallback;

  List<EnglishRetokenizedItem> get items {
    if (_itemIndex >= 0 || _pendingFallback != null) {
      throw StateError('English resolution has not completed.');
    }
    return List<EnglishRetokenizedItem>.unmodifiable(_items);
  }

  _EnglishFallbackRequest? next() {
    if (_pendingFallback != null) {
      throw StateError('English resolution is waiting for fallback output.');
    }
    return _advance();
  }

  _EnglishFallbackRequest? resume(EnglishPronunciation? result) {
    final continuation = _pendingFallback;
    if (continuation == null) {
      throw StateError('English resolution has no pending fallback request.');
    }
    _pendingFallback = null;
    continuation(result);
    return _advance();
  }

  _EnglishFallbackRequest? _advance() {
    while (_itemIndex >= 0) {
      final itemIndex = _itemIndex;
      final item = _items[itemIndex];
      switch (item) {
        case EnglishRetokenizedToken(:var token):
          if (token.phonemes == null) {
            final found = _lookup(token, _context);
            if (found != null) {
              token = _applyPronunciation(token, found);
            }
          }
          if (token.phonemes == null && _fallbackAvailable) {
            final unresolved = token;
            _pendingFallback = (found) {
              final resolved = found == null
                  ? unresolved
                  : _applyPronunciation(unresolved, found);
              _context = updateEnglishTokenContext(
                _context,
                resolved.phonemes,
                resolved,
              );
              _items[itemIndex] = EnglishRetokenizedToken(resolved);
              _itemIndex = itemIndex - 1;
            };
            return _EnglishFallbackRequest(unresolved);
          }
          _context = updateEnglishTokenContext(_context, token.phonemes, token);
          _items[itemIndex] = EnglishRetokenizedToken(token);
          _itemIndex = itemIndex - 1;

        case EnglishRetokenizedGroup(:final tokens):
          final group = List<MisakiToken>.of(tokens);
          var left = 0;
          var right = group.length;
          var shouldFallback = false;
          while (left < right) {
            MisakiToken? merged;
            final slice = group.sublist(left, right);
            if (!slice.any(_hasExplicitResolution)) {
              merged = mergeEnglishTokens(slice);
            }
            final found = merged == null ? null : _lookup(merged, _context);
            if (found != null) {
              group[left] = _applyPronunciation(group[left], found);
              for (var index = left + 1; index < right; index++) {
                // Pinned upstream writes the quality to a transient top-level
                // Python attribute here, not to token metadata. The group is
                // merged before it is returned, so only the empty phonemes
                // are observable from these continuation tokens.
                group[index] = _withPhonemes(group[index], '');
              }
              _context = updateEnglishTokenContext(
                _context,
                found.phonemes,
                merged!,
              );
              right = left;
              left = 0;
            } else if (left + 1 < right) {
              left++;
            } else {
              right--;
              final token = group[right];
              if (token.phonemes == null) {
                if (_isSubtokenJunk(token.text)) {
                  group[right] = _applyPronunciation(
                    token,
                    const EnglishPronunciation(phonemes: '', rating: 3),
                  );
                } else if (_fallbackAvailable) {
                  shouldFallback = true;
                  break;
                }
              }
              left = 0;
            }
          }

          if (shouldFallback) {
            final merged = mergeEnglishTokens(group);
            _pendingFallback = (found) {
              group[0] = _withFallbackResult(group[0], found);
              for (var index = 1; index < group.length; index++) {
                group[index] = _withFallbackResult(
                  group[index],
                  EnglishPronunciation(phonemes: '', rating: found?.rating),
                );
              }
              _items[itemIndex] = EnglishRetokenizedGroup(group);
              _itemIndex = itemIndex - 1;
            };
            return _EnglishFallbackRequest(merged);
          }

          final resolved = resolveEnglishTokens(group);
          group
            ..clear()
            ..addAll(resolved);
          _items[itemIndex] = EnglishRetokenizedGroup(group);
          _itemIndex = itemIndex - 1;
      }
    }
    return null;
  }
}

void _validateBackendPronunciation(
  EnglishPronunciation? pronunciation,
  BackendInfo backendInfo,
  String role,
) {
  final rating = pronunciation?.rating;
  if (rating != null && (rating < 1 || rating > 5)) {
    throw BackendFailureException(
      'English $role ${backendInfo.name} ${backendInfo.version} returned '
      'a rating `$rating` outside 1..5.',
    );
  }
}

bool _hasExplicitResolution(MisakiToken token) {
  final metadata = _metadata(token);
  return metadata.alias != null || token.phonemes != null;
}

bool _isSubtokenJunk(String text) => text.runes.every(
  (codePoint) => _subtokenJunk.contains(String.fromCharCode(codePoint)),
);

MisakiToken _applyPronunciation(
  MisakiToken token,
  EnglishPronunciation pronunciation,
) => _copyResolvedToken(
  token,
  phonemes: pronunciation.phonemes,
  rating: pronunciation.rating,
);

MisakiToken _withFallbackResult(
  MisakiToken token,
  EnglishPronunciation? pronunciation,
) => _copyResolvedToken(
  token,
  phonemes: pronunciation?.phonemes,
  rating: pronunciation?.rating,
);

MisakiToken _withPhonemes(MisakiToken token, String phonemes) {
  final metadata = _metadata(token);
  return _copyResolvedToken(token, phonemes: phonemes, rating: metadata.rating);
}

MisakiToken _copyResolvedToken(
  MisakiToken token, {
  required String? phonemes,
  required int? rating,
}) {
  final metadata = _metadata(token);
  return MisakiToken(
    text: token.text,
    tag: token.tag,
    whitespace: token.whitespace,
    phonemes: phonemes,
    startTimeSeconds: token.startTimeSeconds,
    endTimeSeconds: token.endTimeSeconds,
    metadata: EnglishTokenMetadata(
      isHead: metadata.isHead,
      alias: metadata.alias,
      stress: metadata.stress,
      currency: metadata.currency,
      numberFlags: metadata.numberFlags,
      precededBySpace: metadata.precededBySpace,
      rating: rating,
    ),
  );
}

EnglishTokenMetadata _metadata(MisakiToken token) {
  final metadata = token.metadata;
  if (metadata is! EnglishTokenMetadata) {
    throw MalformedDataException(
      'English orchestration received ${metadata.runtimeType} metadata.',
    );
  }
  return metadata;
}

const Set<String> _subtokenJunk = <String>{
  "'",
  ',',
  '-',
  '.',
  '_',
  '‘',
  '’',
  '/',
};
