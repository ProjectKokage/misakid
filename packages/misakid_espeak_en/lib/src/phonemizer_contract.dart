// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0
//
// Clean-room formatting for the observable phonemizer-fork 3.3.2 option tuple
// used by pinned Misaki. No phonemizer source or table is included.

import 'package:misakid/misaki_en.dart';

import 'native_bindings.dart';

/// Maximum punctuation chunks and native eSpeak clauses in one public call.
///
/// Exceeding either independently enforced boundary is an intentional safety
/// failure surfaced by the public backend as [BackendFailureException].
const int maximumEspeakEnglishChunksPerCall = 65536;

/// Direct native-chunk callback used by the clean-room formatting stage.
typedef EspeakEnglishChunkPhonemizer =
    String Function(String text, EnglishDialect dialect);

/// Replays the exact single-string phonemizer option contract used by Misaki.
String? phonemizeEnglishLikePinnedPhonemizer({
  required String text,
  required EnglishDialect dialect,
  required EspeakEnglishChunkPhonemizer phonemizeChunk,
}) {
  final preserved = _preservePunctuation(text);
  if (preserved.chunks.length > maximumEspeakEnglishChunksPerCall) {
    throw const EspeakEnglishNativeLibraryException(
      'English punctuation preservation exceeded the 65,536-chunk limit.',
    );
  }
  final converted = <String>[
    for (final chunk in preserved.chunks)
      _postprocessNativeLine(phonemizeChunk(chunk, dialect)),
  ];
  final restored = _restorePunctuation(converted, preserved.marks);
  if (restored.isEmpty) return null;
  if (restored.length != 1) {
    throw const EspeakEnglishNativeLibraryException(
      'Single-string phonemization returned multiple utterances.',
    );
  }
  return restored.single;
}

final class _PreservedPunctuation {
  const _PreservedPunctuation({required this.chunks, required this.marks});

  final List<String> chunks;
  final List<_PunctuationMark> marks;
}

enum _MarkPosition { beginning, end, intermediate, alone }

final class _PunctuationMark {
  const _PunctuationMark({
    required this.lineIndex,
    required this.text,
    required this.position,
  });

  final int lineIndex;
  final String text;
  final _MarkPosition position;
}

final class _ScalarSpan {
  const _ScalarSpan(this.start, this.end);

  final int start;
  final int end;
}

_PreservedPunctuation _preservePunctuation(String input) {
  final scalars = input.runes.toList(growable: false);
  final spans = <_ScalarSpan>[];
  var index = 0;
  while (index < scalars.length) {
    if (!_isPunctuation(scalars[index]) &&
        !_isPythonWhitespace(scalars[index])) {
      index++;
      continue;
    }
    final start = index;
    var containsPunctuation = false;
    while (index < scalars.length &&
        (_isPunctuation(scalars[index]) ||
            _isPythonWhitespace(scalars[index]))) {
      containsPunctuation |= _isPunctuation(scalars[index]);
      index++;
    }
    if (containsPunctuation) spans.add(_ScalarSpan(start, index));
  }
  if (spans.isEmpty) {
    return _PreservedPunctuation(
      chunks: input.isEmpty ? const <String>[] : <String>[input],
      marks: const <_PunctuationMark>[],
    );
  }
  if (spans.length == 1 &&
      spans.single.start == 0 &&
      spans.single.end == scalars.length) {
    return _PreservedPunctuation(
      chunks: const <String>[],
      marks: <_PunctuationMark>[
        _PunctuationMark(
          lineIndex: 0,
          text: input,
          position: _MarkPosition.alone,
        ),
      ],
    );
  }

  final chunks = <String>[];
  final marks = <_PunctuationMark>[];
  var cursor = 0;
  for (var spanIndex = 0; spanIndex < spans.length; spanIndex++) {
    final span = spans[spanIndex];
    final chunk = String.fromCharCodes(scalars.sublist(cursor, span.start));
    chunks.add(chunk);
    var position = _MarkPosition.intermediate;
    if (spanIndex == 0 && span.start == 0) {
      position = _MarkPosition.beginning;
    } else if (spanIndex == spans.length - 1 && span.end == scalars.length) {
      position = _MarkPosition.end;
    }
    marks.add(
      _PunctuationMark(
        lineIndex: 0,
        text: String.fromCharCodes(scalars.sublist(span.start, span.end)),
        position: position,
      ),
    );
    cursor = span.end;
  }
  chunks.add(String.fromCharCodes(scalars.sublist(cursor)));
  return _PreservedPunctuation(
    chunks: List<String>.unmodifiable(
      chunks.where((chunk) => chunk.isNotEmpty),
    ),
    marks: List<_PunctuationMark>.unmodifiable(marks),
  );
}

String _postprocessNativeLine(String input) {
  var line = _stripPythonWhitespace(input)
      .replaceAll('\n', ' ')
      .replaceAll('  ', ' ')
      .replaceAll(RegExp('_+'), '_')
      .replaceAll('_ ', ' ');
  if (line.isEmpty) return '';
  final output = StringBuffer();
  for (final rawWord in line.split(' ')) {
    final word = _stripPythonWhitespace(rawWord).replaceAll('\u0361', '^');
    output
      ..write(word)
      ..write(' ');
  }
  return output.toString();
}

List<String> _restorePunctuation(
  List<String> converted,
  List<_PunctuationMark> originalMarks,
) {
  final text = List<String>.of(converted);
  final marks = List<_PunctuationMark>.of(originalMarks);
  final output = <String>[];
  var position = 0;
  while (text.isNotEmpty || marks.isNotEmpty) {
    if (marks.isEmpty) {
      for (var line in text) {
        if (!line.endsWith(' ')) line = '$line ';
        output.add(line);
      }
      text.clear();
      continue;
    }
    if (text.isEmpty) {
      output.add(marks.map((mark) => mark.text).join());
      marks.clear();
      continue;
    }

    final current = marks.first;
    if (current.lineIndex != position) {
      output.add(text.removeAt(0));
      position++;
      continue;
    }
    marks.removeAt(0);
    final mark = current.text;
    if (text.first.endsWith(' ')) {
      text[0] = text.first.substring(0, text.first.length - 1);
    }
    switch (current.position) {
      case _MarkPosition.beginning:
        text[0] = '$mark${text[0]}';
      case _MarkPosition.end:
        output.add('${text.removeAt(0)}$mark${mark.endsWith(' ') ? '' : ' '}');
        position++;
      case _MarkPosition.alone:
        output.add('$mark${mark.endsWith(' ') ? '' : ' '}');
        position++;
      case _MarkPosition.intermediate:
        if (text.length == 1) {
          text[0] = '${text[0]}$mark';
        } else {
          final first = text.removeAt(0);
          text[0] = '$first$mark${text[0]}';
        }
    }
  }
  return List<String>.unmodifiable(output);
}

String _stripPythonWhitespace(String input) {
  final scalars = input.runes.toList(growable: false);
  var start = 0;
  while (start < scalars.length && _isPythonWhitespace(scalars[start])) {
    start++;
  }
  var end = scalars.length;
  while (end > start && _isPythonWhitespace(scalars[end - 1])) {
    end--;
  }
  return String.fromCharCodes(scalars.sublist(start, end));
}

bool _isPunctuation(int scalar) => _punctuation.contains(scalar);

bool _isPythonWhitespace(int scalar) =>
    (scalar >= 0x0009 && scalar <= 0x000D) ||
    (scalar >= 0x001C && scalar <= 0x0020) ||
    scalar == 0x0085 ||
    scalar == 0x00A0 ||
    scalar == 0x1680 ||
    (scalar >= 0x2000 && scalar <= 0x200A) ||
    scalar == 0x2028 ||
    scalar == 0x2029 ||
    scalar == 0x202F ||
    scalar == 0x205F ||
    scalar == 0x3000;

final Set<int> _punctuation = Set<int>.unmodifiable(
  ';:,.!?¡¿—…"«»“”(){}[]'.runes,
);
