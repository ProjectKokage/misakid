import 'dart:math';
import 'dart:typed_data';

import 'package:misakid_spacy_trf_en/misakid_spacy_trf_en.dart';
import 'package:test/test.dart';

void main() {
  group('GPT-2 byte mapping and ranked merges', () {
    test('matches the curated-tokenizers empty-processor vector', () {
      final processor = _processor();

      expect(processor.encodeAsPieces("they'll visit Köln"), <String>[
        't',
        'h',
        'e',
        'y',
        "'",
        'l',
        'l',
        'Ġ',
        'v',
        'i',
        's',
        'i',
        't',
        'Ġ',
        'K',
        'Ã',
        '¶',
        'l',
        'n',
      ]);
    });

    test('chooses the lowest rank before position', () {
      final processor = _processor(
        merges: const <SpacyTransformerByteBpeMerge>[
          SpacyTransformerByteBpeMerge('b', 'c'),
          SpacyTransformerByteBpeMerge('a', 'b'),
        ],
      );

      expect(processor.encodeAsPieces('abc'), <String>['a', 'bc']);
    });

    test('repeats ranked merges and merges all chosen occurrences', () {
      final processor = _processor(
        merges: const <SpacyTransformerByteBpeMerge>[
          SpacyTransformerByteBpeMerge('a', 'b'),
          SpacyTransformerByteBpeMerge('ab', 'c'),
        ],
      );

      expect(processor.encodeAsPieces('abc'), <String>['abc']);
      expect(processor.encodeAsPieces('abab'), <String>['ab', 'ab']);
    });

    test('preserves exact batch semantics for adversarial merge ranks', () {
      expect(
        _processor(
          merges: const <SpacyTransformerByteBpeMerge>[
            SpacyTransformerByteBpeMerge('a', 'a'),
          ],
        ).encodeAsPieces('aaaaa'),
        <String>['aa', 'aa', 'a'],
      );
      final overlapping = _processor(
        merges: const <SpacyTransformerByteBpeMerge>[
          SpacyTransformerByteBpeMerge('aa', 'a'),
          SpacyTransformerByteBpeMerge('a', 'a'),
        ],
      );
      expect(overlapping.encodeAsPieces('aaaa'), <String>['aa', 'aa']);
      expect(overlapping.encodeAsPieces('aaaaa'), <String>['aa', 'aaa']);
      expect(
        _processor(
          merges: const <SpacyTransformerByteBpeMerge>[
            SpacyTransformerByteBpeMerge('ab', 'a'),
            SpacyTransformerByteBpeMerge('a', 'b'),
          ],
        ).encodeAsPieces('abab'),
        <String>['ab', 'ab'],
      );
      expect(
        _processor(
          merges: const <SpacyTransformerByteBpeMerge>[
            SpacyTransformerByteBpeMerge('a', 'bc'),
            SpacyTransformerByteBpeMerge('b', 'c'),
          ],
        ).encodeAsPieces('abc'),
        <String>['abc'],
      );
      expect(
        _processor(
          merges: const <SpacyTransformerByteBpeMerge>[
            SpacyTransformerByteBpeMerge('a', 'b'),
            SpacyTransformerByteBpeMerge('ab', 'ab'),
          ],
        ).encodeAsPieces('abab'),
        <String>['abab'],
      );
      expect(
        _processor(
          merges: const <SpacyTransformerByteBpeMerge>[
            SpacyTransformerByteBpeMerge('b', 'c'),
            SpacyTransformerByteBpeMerge('a', 'bc'),
            SpacyTransformerByteBpeMerge('bc', 'd'),
            SpacyTransformerByteBpeMerge('abc', 'd'),
          ],
        ).encodeAsPieces('abcd'),
        <String>['abcd'],
      );
    });

    test('matches the upstream scan algorithm on seeded synthetic tables', () {
      const symbols = <String>[
        'a',
        'b',
        'aa',
        'ab',
        'ba',
        'bb',
        'aaa',
        'aab',
        'aba',
        'abb',
        'baa',
        'bab',
        'bba',
        'bbb',
      ];
      final availablePairs = <SpacyTransformerByteBpeMerge>[
        for (final left in symbols)
          for (final right in symbols)
            if (left.length + right.length <= 5)
              SpacyTransformerByteBpeMerge(left, right),
      ];
      final random = Random(0xB17EB0E);
      for (var tableIndex = 0; tableIndex < 24; tableIndex++) {
        availablePairs.shuffle(random);
        final merges = availablePairs.take(12).toList(growable: false);
        final processor = _processor(merges: merges);
        for (var length = 1; length <= 7; length++) {
          for (var bits = 0; bits < 1 << length; bits++) {
            final input = String.fromCharCodes(<int>[
              for (var index = length - 1; index >= 0; index--)
                bits & (1 << index) == 0 ? 0x61 : 0x62,
            ]);
            expect(
              processor.encodeAsPieces(input),
              _referenceApplyMerges(input, merges),
              reason: 'table $tableIndex, input `$input`',
            );
          }
        }
      }
    });

    test('does not rescan a long unmergeable tail for every prefix merge', () {
      final merges = <SpacyTransformerByteBpeMerge>[];
      var prefix = 'a';
      for (var index = 0; index < 512; index++) {
        merges.add(SpacyTransformerByteBpeMerge(prefix, 'b'));
        prefix = '${prefix}b';
      }
      final tail = List<String>.filled(100000, 'c').join();
      final pieces = _processor(merges: merges).encodeAsPieces('$prefix$tail');

      expect(pieces, hasLength(tail.length + 1));
      expect(pieces.first, prefix);
      expect(pieces.last, 'c');
    }, timeout: const Timeout(Duration(seconds: 10)));
  });

  group('regex 2024.11.6 split semantics', () {
    test('contractions retain alternation priority and token boundaries', () {
      final processor = _processor(
        merges: const <SpacyTransformerByteBpeMerge>[
          SpacyTransformerByteBpeMerge('y', "'"),
          SpacyTransformerByteBpeMerge('Ġ', "'"),
          SpacyTransformerByteBpeMerge("Ġ'", 's'),
        ],
      );

      expect(processor.encodeAsPieces("they'll"), <String>[
        't',
        'h',
        'e',
        'y',
        "'",
        'l',
        'l',
      ]);
      expect(processor.encodeAsPieces(" 's"), <String>["Ġ'", 's']);
    });

    test('implements trailing-whitespace negative-lookahead behavior', () {
      final processor = _processor(
        merges: const <SpacyTransformerByteBpeMerge>[
          SpacyTransformerByteBpeMerge('Ġ', 'Ġ'),
        ],
      );

      expect(processor.encodeAsPieces('  '), <String>['ĠĠ']);
      expect(processor.encodeAsPieces('  a'), <String>['Ġ', 'Ġ', 'a']);
      expect(processor.encodeAsPieces('\t a'), <String>['ĉ', 'Ġ', 'a']);
    });

    test('does not merge across letter and number alternatives', () {
      final processor = _processor(
        merges: const <SpacyTransformerByteBpeMerge>[
          SpacyTransformerByteBpeMerge('a', '1'),
        ],
      );

      expect(processor.encodeAsPieces('a1'), <String>['a', '1']);
    });

    test('uses Unicode 16 Letter and Number additions', () {
      final letterProcessor = _processor(
        merges: const <SpacyTransformerByteBpeMerge>[
          SpacyTransformerByteBpeMerge('á', '²'),
          SpacyTransformerByteBpeMerge('á²', 'ī'),
          SpacyTransformerByteBpeMerge('á²ī', 'A'),
        ],
      );
      final numberProcessor = _processor(
        merges: const <SpacyTransformerByteBpeMerge>[
          SpacyTransformerByteBpeMerge('ð', 'Ĳ'),
          SpacyTransformerByteBpeMerge('ðĲ', 'µ'),
          SpacyTransformerByteBpeMerge('ðĲµ', 'Ģ'),
          SpacyTransformerByteBpeMerge('ðĲµĢ', '1'),
        ],
      );

      expect(letterProcessor.encodeAsPieces('\u{1C89}A'), <String>['á²īA']);
      expect(numberProcessor.encodeAsPieces('\u{10D40}1'), <String>['ðĲµĢ1']);
    });

    test('does not treat U+001C as regex White_Space', () {
      final processor = _processor(
        merges: const <SpacyTransformerByteBpeMerge>[
          SpacyTransformerByteBpeMerge('Ĝ', '!'),
        ],
      );

      expect(processor.encodeAsPieces('\u001C!'), <String>['Ĝ!']);
    });
  });

  group('token sequence assembly', () {
    late SpacyTransformerByteBpe processor;

    setUp(() {
      processor = _processor(
        vocabulary: const <String, int>{
          '<s>': 0,
          '<pad>': 1,
          '</s>': 2,
          '<unk>': 3,
          'a': 4,
          'Ġ': 5,
          'b': 6,
          'c': 7,
        },
      );
    });

    test('filters whitespace and uses the previous retained whitespace', () {
      final sequence = processor.encodeTokens(<SpacyTransformerInputToken>[
        SpacyTransformerInputToken(text: 'a', whitespace: ' ', isSpace: false),
        SpacyTransformerInputToken(text: ' ', whitespace: '', isSpace: true),
        SpacyTransformerInputToken(text: 'b', whitespace: '', isSpace: false),
        SpacyTransformerInputToken(text: 'c', whitespace: '', isSpace: false),
      ]);

      expect(sequence.pieceIds, <int>[0, 4, 5, 6, 7, 2]);
      expect(sequence.tokenPieceLengths, <int>[1, 2, 1]);
      expect(sequence.sourceTokenIndices, <int>[0, 2, 3]);
      expect(sequence.raggedLengths, <int>[1, 1, 2, 1, 1]);
      expect(() => sequence.pieceIds.add(99), throwsA(isA<UnsupportedError>()));
    });

    test('all-whitespace input still produces BOS and EOS', () {
      final sequence = processor.encodeTokens(<SpacyTransformerInputToken>[
        SpacyTransformerInputToken(text: ' ', whitespace: '', isSpace: true),
      ]);

      expect(sequence.pieceIds, <int>[0, 2]);
      expect(sequence.tokenPieceLengths, isEmpty);
      expect(sequence.sourceTokenIndices, isEmpty);
      expect(sequence.raggedLengths, <int>[1, 1]);
    });

    test('enforces the aggregate marked-piece limit during assembly', () {
      final tokens = <SpacyTransformerInputToken>[
        SpacyTransformerInputToken(text: 'a', whitespace: ' ', isSpace: false),
        SpacyTransformerInputToken(text: 'b', whitespace: '', isSpace: false),
        SpacyTransformerInputToken(text: 'c', whitespace: '', isSpace: false),
      ];

      expect(processor.encodeTokens(tokens, maxPieces: 6).pieceIds, <int>[
        0,
        4,
        5,
        6,
        7,
        2,
      ]);
      expect(
        () => processor.encodeTokens(tokens, maxPieces: 5),
        throwsA(isA<BackendFailureException>()),
      );
      expect(
        processor.encodeTokens(<SpacyTransformerInputToken>[
          SpacyTransformerInputToken(text: ' ', whitespace: '', isSpace: true),
        ], maxPieces: 2).pieceIds,
        <int>[0, 2],
      );
      expect(
        () => processor.encodeTokens(<SpacyTransformerInputToken>[
          SpacyTransformerInputToken(text: 'a', whitespace: '', isSpace: false),
        ], maxPieces: 2),
        throwsA(isA<BackendFailureException>()),
      );
      expect(
        () => processor.encodeTokens(tokens, maxPieces: 1),
        throwsRangeError,
      );
      expect(
        () => processor.encodeTokens(tokens, maxPieces: 1 << 30),
        throwsRangeError,
      );
    });
  });

  group('bounded failures', () {
    test('checks payload length and SHA-256 before decoding', () {
      expect(
        () => SpacyTransformerByteBpe.decodePinnedPayload(Uint8List(1)),
        throwsA(isA<MalformedDataException>()),
      );
      expect(
        () => SpacyTransformerByteBpe.decodePinnedPayload(
          Uint8List(spacyTransformerByteBpePayloadByteLength),
        ),
        throwsA(isA<MalformedDataException>()),
      );
    });

    test('rejects invalid explicit tables', () {
      expect(
        () => _processor(vocabulary: const <String, int>{'a': 0, 'b': 0}),
        throwsA(isA<MalformedDataException>()),
      );
      expect(
        () => _processor(
          merges: const <SpacyTransformerByteBpeMerge>[
            SpacyTransformerByteBpeMerge('a', 'b'),
            SpacyTransformerByteBpeMerge('a', 'b'),
          ],
        ),
        throwsA(isA<MalformedDataException>()),
      );
    });

    test('rejects missing pieces and special IDs explicitly', () {
      final processor = _processor(vocabulary: const <String, int>{});
      expect(
        () => processor.encodeAsIds('a'),
        throwsA(isA<BackendFailureException>()),
      );
      expect(
        () => processor.encodeTokens(<SpacyTransformerInputToken>[
          SpacyTransformerInputToken(text: 'a', whitespace: '', isSpace: false),
        ]),
        throwsA(isA<BackendFailureException>()),
      );
    });

    test('rejects unpaired UTF-16 surrogates', () {
      final processor = _processor();

      expect(
        () => processor.encodeAsPieces(String.fromCharCode(0xD800)),
        throwsA(isA<BackendFailureException>()),
      );
      expect(
        () => processor.encodeAsPieces(String.fromCharCode(0xDC00)),
        throwsA(isA<BackendFailureException>()),
      );
    });

    test('validates the minimal spaCy token contract', () {
      expect(
        () => SpacyTransformerInputToken(
          text: 'a',
          whitespace: '\t',
          isSpace: false,
        ),
        throwsArgumentError,
      );
      expect(
        () => SpacyTransformerInputToken(
          text: '',
          whitespace: '',
          isSpace: false,
        ),
        throwsArgumentError,
      );
    });

    test('rejects long output from its byte lower bound', () {
      final processor = _processor(
        vocabulary: const <String, int>{'<s>': 0, '</s>': 1, '<unk>': 2},
      );
      final input = List<String>.filled(500000, 'a').join();

      expect(
        () => processor.encodeTokens(<SpacyTransformerInputToken>[
          SpacyTransformerInputToken(
            text: input,
            whitespace: '',
            isSpace: false,
          ),
        ], maxPieces: 64),
        throwsA(isA<BackendFailureException>()),
      );
    });
  });
}

List<String> _referenceApplyMerges(
  String input,
  List<SpacyTransformerByteBpeMerge> merges,
) {
  final ranks = <(String, String), int>{
    for (var rank = 0; rank < merges.length; rank++)
      (merges[rank].left, merges[rank].right): rank,
  };
  var pieces = input.split('');
  while (pieces.length > 1) {
    (String, String)? selected;
    var selectedRank = merges.length;
    for (var index = 0; index + 1 < pieces.length; index++) {
      final pair = (pieces[index], pieces[index + 1]);
      final rank = ranks[pair];
      if (rank != null && rank < selectedRank) {
        selected = pair;
        selectedRank = rank;
      }
    }
    if (selected == null) {
      return pieces;
    }
    final next = <String>[];
    var index = 0;
    while (index < pieces.length) {
      if (index + 1 < pieces.length &&
          pieces[index] == selected.$1 &&
          pieces[index + 1] == selected.$2) {
        next.add('${pieces[index]}${pieces[index + 1]}');
        index += 2;
      } else {
        next.add(pieces[index]);
        index++;
      }
    }
    pieces = next;
  }
  return pieces;
}

SpacyTransformerByteBpe _processor({
  Map<String, int> vocabulary = const <String, int>{},
  List<SpacyTransformerByteBpeMerge> merges =
      const <SpacyTransformerByteBpeMerge>[],
}) =>
    SpacyTransformerByteBpe.fromTables(vocabulary: vocabulary, merges: merges);
