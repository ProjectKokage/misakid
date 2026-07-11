import 'dart:convert';

import 'package:misakid/misaki.dart';
import 'package:test/test.dart';

import '../support/upstream_fixture.dart';

void main() {
  test('parses a pinned successful record and preserves null tokens', () {
    final fixture = UpstreamFixture.parse(
      jsonEncode(_record(tokens: null)),
      location: 'memory:1',
    );

    expect(fixture.caseId, 'case-1');
    expect(fixture.phonemes, 'さんびゃく');
    expect(fixture.tokens, isNull);
    expect(fixture.errorCategory, isNull);
    expect(fixture.backendInput, isNull);
    expect(fixture.options, <String, Object?>{'dictionary': 'hiragana'});
    expect(() => fixture.options['x'] = true, throwsUnsupportedError);
  });

  test('preserves an available empty token list', () {
    final fixture = UpstreamFixture.parse(
      jsonEncode(_record(tokens: <Object?>[])),
      location: 'memory:1',
    );

    expect(fixture.tokens, isNotNull);
    expect(fixture.tokens, isEmpty);
  });

  test('accepts a stable failure category only with null outputs', () {
    final record = _record(tokens: null)
      ..['phonemes'] = null
      ..['error'] = <String, Object?>{'category': 'upstreamFailure'};
    final fixture = UpstreamFixture.parse(
      jsonEncode(record),
      location: 'memory:1',
    );

    expect(fixture.errorCategory, 'upstreamFailure');
    expect(fixture.phonemes, isNull);
    expect(fixture.tokens, isNull);
  });

  test('rejects fixtures from a different upstream commit', () {
    final record = _record(tokens: null)..['upstreamCommit'] = 'main';

    expect(
      () => UpstreamFixture.parse(jsonEncode(record), location: 'memory:1'),
      throwsA(
        isA<UpstreamFixtureFormatException>().having(
          (error) => error.message,
          'message',
          contains('upstreamCommit'),
        ),
      ),
    );
  });

  test('rejects ambiguous success and failure shapes', () {
    final missingOutput = _record(tokens: null)..['phonemes'] = null;
    final failureWithOutput = _record(tokens: null)
      ..['error'] = <String, Object?>{'category': 'upstreamFailure'};

    for (final record in <Map<String, Object?>>[
      missingOutput,
      failureWithOutput,
    ]) {
      expect(
        () => UpstreamFixture.parse(jsonEncode(record), location: 'memory:1'),
        throwsA(isA<UpstreamFixtureFormatException>()),
      );
    }
  });

  test('parses and freezes typed pyopenjtalk backend input', () {
    final record = _record(tokens: <Object?>[])
      ..['mode'] = 'pyopenjtalk'
      ..['backendVersions'] = <String, Object?>{'pyopenjtalk': '0.4.1'}
      ..['backendInput'] = _backendInput();

    final fixture = UpstreamFixture.parse(
      jsonEncode(record),
      location: 'memory:1',
    );
    final input = fixture.backendInput;
    expect(input, isA<PyopenjtalkFixtureBackendInput>());
    final typedInput = input as PyopenjtalkFixtureBackendInput;
    final word = typedInput.words.single;
    expect(word.surface, 'こんにちは');
    expect(word.partOfSpeech, '感動詞');
    expect(word.partOfSpeechGroup1, '*');
    expect(word.partOfSpeechGroup2, '*');
    expect(word.partOfSpeechGroup3, '*');
    expect(word.conjugationType, '*');
    expect(word.conjugationForm, '*');
    expect(word.original, 'こんにちは');
    expect(word.reading, 'コンニチハ');
    expect(word.pronunciation, 'コンニチワ');
    expect(word.accent, 0);
    expect(word.moraSize, 5);
    expect(word.chainRule, '-1');
    expect(word.rawChainFlag, -1);
    expect(typedInput.words.clear, throwsUnsupportedError);
  });

  test('rejects incomplete or incorrectly typed pyopenjtalk words', () {
    final missingPronunciation = _backendInput();
    final missingPronunciationWords =
        missingPronunciation['words']! as List<Object?>;
    final missingPronunciationWord =
        missingPronunciationWords.single as Map<String, Object?>;
    missingPronunciationWord.remove('pron');

    final booleanAccent = _backendInput();
    final booleanAccentWords = booleanAccent['words']! as List<Object?>;
    final booleanAccentWord = booleanAccentWords.single as Map<String, Object?>;
    booleanAccentWord['acc'] = true;

    for (final backendInput in <Map<String, Object?>>[
      missingPronunciation,
      booleanAccent,
    ]) {
      final record = _record(tokens: <Object?>[])
        ..['mode'] = 'pyopenjtalk'
        ..['backendInput'] = backendInput;
      expect(
        () => UpstreamFixture.parse(jsonEncode(record), location: 'memory:1'),
        throwsA(isA<UpstreamFixtureFormatException>()),
      );
    }
  });

  test('parses and freezes typed English replay input', () {
    final record = _record(tokens: <Object?>[])
      ..['language'] = 'en'
      ..['mode'] = 'american-no-fallback'
      ..['backendInput'] = _englishBackendInput();
    final fixture = UpstreamFixture.parse(
      jsonEncode(record),
      location: 'memory:1',
    );

    final input = fixture.backendInput as EnglishFixtureBackendInput;
    expect(input.preprocess.applied, isTrue);
    expect(input.preprocess.text, 'hello');
    expect(input.preprocess.sourceWords, <String>['hello']);
    final feature = input.preprocess.features.single;
    expect(feature.sourceWordIndex, 0);
    expect(feature.value, isA<EnglishFixtureDoubleFeature>());
    expect((feature.value as EnglishFixtureDoubleFeature).value, -0.5);
    expect(input.tokens.single.text, 'hello');
    expect(input.tokens.single.metadata.stress, -0.5);
    expect(input.tokens.single.metadata.rating, 5);
    expect(input.espeakCalls, isNull);
    expect(input.modelCalls, isNull);
    expect(input.tokens.clear, throwsUnsupportedError);
  });

  test('parses and freezes typed English raw eSpeak replay calls', () {
    final backendInput = _englishBackendInput()
      ..['schemaVersion'] = EnglishFixtureBackendInput.espeakSchemaVersion
      ..['espeakCalls'] = <Object?>[
        <String, Object?>{'rawPhones': ' blˈɔːp ', 'text': 'blorp'},
        <String, Object?>{'rawPhones': null, 'text': 'silent'},
      ];
    final record = _record(tokens: <Object?>[])
      ..['language'] = 'en'
      ..['mode'] = 'american-espeak-fallback'
      ..['backendInput'] = backendInput;
    final fixture = UpstreamFixture.parse(
      jsonEncode(record),
      location: 'memory:1',
    );

    final input = fixture.backendInput as EnglishFixtureBackendInput;
    expect(input.espeakCalls, hasLength(2));
    expect(input.espeakCalls!.first.text, 'blorp');
    expect(input.espeakCalls!.first.rawPhones, ' blˈɔːp ');
    expect(input.espeakCalls!.last.rawPhones, isNull);
    expect(input.espeakCalls!.clear, throwsUnsupportedError);
    expect(input.modelCalls, isNull);
  });

  test('parses and freezes typed English BART fallback calls', () {
    final backendInput = _englishBackendInput()
      ..['schemaVersion'] = EnglishFixtureBackendInput.modelSchemaVersion
      ..['modelCalls'] = <Object?>[
        <String, Object?>{
          'generatedIds': <Object?>[2, 4, 7, 2],
          'inputIds': <Object?>[1, 5, 3, 2],
          'phonemes': 'ˈA',
          'rating': 1,
          'text': 'a😀',
        },
      ];
    final record = _record(tokens: <Object?>[])
      ..['language'] = 'en'
      ..['mode'] = 'american-model-fallback'
      ..['backendInput'] = backendInput;
    final fixture = UpstreamFixture.parse(
      jsonEncode(record),
      location: 'memory:1',
    );

    final input = fixture.backendInput as EnglishFixtureBackendInput;
    expect(input.espeakCalls, isNull);
    expect(input.modelCalls, hasLength(1));
    final call = input.modelCalls!.single;
    expect(call.text, 'a😀');
    expect(call.inputIds, <int>[1, 5, 3, 2]);
    expect(call.generatedIds, <int>[2, 4, 7, 2]);
    expect(call.phonemes, 'ˈA');
    expect(call.rating, 1);
    expect(call.inputIds.clear, throwsUnsupportedError);
    expect(call.generatedIds.clear, throwsUnsupportedError);
    expect(input.modelCalls!.clear, throwsUnsupportedError);

    for (final invalidCall in <Map<String, Object?>>[
      <String, Object?>{
        'generatedIds': <Object?>[2],
        'inputIds': <Object?>[0, 5, 2],
        'phonemes': '',
        'rating': 1,
        'text': 'a',
      },
      <String, Object?>{
        'generatedIds': <Object?>[],
        'inputIds': <Object?>[1, 5, 2],
        'phonemes': '',
        'rating': 1,
        'text': 'a',
      },
      <String, Object?>{
        'generatedIds': <Object?>[2],
        'inputIds': <Object?>[1, 5, 2],
        'phonemes': '',
        'rating': 2,
        'text': 'a',
      },
    ]) {
      final invalidBackend = _englishBackendInput()
        ..['schemaVersion'] = EnglishFixtureBackendInput.modelSchemaVersion
        ..['modelCalls'] = <Object?>[invalidCall];
      final invalidRecord = _record(tokens: <Object?>[])
        ..['language'] = 'en'
        ..['mode'] = 'american-model-fallback'
        ..['backendInput'] = invalidBackend;
      expect(
        () => UpstreamFixture.parse(
          jsonEncode(invalidRecord),
          location: 'invalid',
        ),
        throwsA(isA<UpstreamFixtureFormatException>()),
      );
    }
  });

  test('parses and freezes typed Cutlet morphology replay input', () {
    final record = _record(tokens: null)
      ..['mode'] = 'cutlet'
      ..['backendInput'] = _cutletBackendInput();
    final fixture = UpstreamFixture.parse(
      jsonEncode(record),
      location: 'memory:1',
    );

    final input = fixture.backendInput as CutletFixtureBackendInput;
    expect(input.normalizedText, '今日は さん匹');
    expect(input.words, hasLength(2));
    expect(input.words.first.surface, '今日');
    expect(input.words.first.pronunciation, 'キョウ');
    expect(input.words.first.kana, 'キョウ');
    expect(input.words.first.hiragana, 'きょう');
    expect(input.words.first.charType, 2);
    expect(input.words.first.isUnknown, isFalse);
    expect(input.words.first.joinWithNext, isTrue);
    expect(input.words.last.pronunciation, isNull);
    expect(input.words.last.kana, 'ハ');
    expect(input.words.clear, throwsUnsupportedError);
  });

  test('parses and freezes typed Korean external replay input', () {
    final record = _record(tokens: null)
      ..['language'] = 'ko'
      ..['mode'] = 'g2pkc-default'
      ..['phonemes'] = '한국어'
      ..['backendInput'] = _koreanBackendInput();
    final fixture = UpstreamFixture.parse(
      jsonEncode(record),
      location: 'memory:1',
    );

    final input = fixture.backendInput as KoreanFixtureBackendInput;
    expect(input.input, '한국어');
    expect(input.cmuLookups, hasLength(2));
    expect(input.cmuLookups.first.key, 'game');
    expect(input.cmuLookups.first.arpabet, <String>['G', 'EY1', 'M']);
    expect(input.cmuLookups.last.key, 'missing');
    expect(input.cmuLookups.last.arpabet, isNull);
    expect(input.tokens.single.surface, '한국어');
    expect(input.tokens.single.tag, 'NNG');
    expect(input.cmuLookups.clear, throwsUnsupportedError);
    expect(
      () => input.cmuLookups.first.arpabet!.add('X'),
      throwsUnsupportedError,
    );
    expect(input.tokens.clear, throwsUnsupportedError);
  });

  test('parses and freezes typed Vietnamese tokenizer replay input', () {
    final record = _record(tokens: <Object?>[])
      ..['language'] = 'vi'
      ..['mode'] = 'north-no-english-fallback'
      ..['phonemes'] = 'sin1 caw2'
      ..['backendInput'] = _vietnameseBackendInput();
    final fixture = UpstreamFixture.parse(
      jsonEncode(record),
      location: 'memory:1',
    );

    final input = fixture.backendInput as VietnameseFixtureBackendInput;
    expect(input.input, 'xin chào');
    expect(input.tokens, <String>['xin', 'chào']);
    expect(input.tokens.clear, throwsUnsupportedError);
  });

  test('rejects unknown and malformed replay schemas', () {
    final unknown = <String, Object?>{
      'kind': 'unknown.backend',
      'schemaVersion': 1,
    };
    final malformedEnglish = _englishBackendInput();
    final englishTokens = malformedEnglish['tokens']! as List<Object?>;
    final englishToken = englishTokens.single as Map<String, Object?>;
    final englishMetadata = englishToken['_']! as Map<String, Object?>;
    englishMetadata['alias'] = 'unexpected';
    final malformedKorean = _koreanBackendInput();
    final koreanTokens = malformedKorean['tokens']! as List<Object?>;
    final koreanToken = koreanTokens.single as Map<String, Object?>;
    koreanToken['tag'] = 1;
    final malformedKoreanCmu = _koreanBackendInput();
    final koreanLookups = malformedKoreanCmu['cmuLookups']! as List<Object?>;
    final koreanLookup = koreanLookups.first as Map<String, Object?>;
    koreanLookup['key'] = 'Game';
    final malformedCutlet = _cutletBackendInput();
    final cutletWords = malformedCutlet['words']! as List<Object?>;
    final cutletWord = cutletWords.last as Map<String, Object?>;
    cutletWord['joinWithNext'] = true;
    final malformedCutletReading = _cutletBackendInput();
    final readingWords = malformedCutletReading['words']! as List<Object?>;
    final readingWord = readingWords.first as Map<String, Object?>;
    readingWord['hiragana'] = '';
    final malformedCutletPronunciation = _cutletBackendInput();
    final pronunciationWords =
        malformedCutletPronunciation['words']! as List<Object?>;
    final pronunciationWord = pronunciationWords.first as Map<String, Object?>;
    pronunciationWord['pronunciation'] = 1;
    final malformedCutletGroup = _cutletBackendInput();
    final groupedWords = malformedCutletGroup['words']! as List<Object?>;
    final groupedWord = groupedWords.last as Map<String, Object?>;
    groupedWord['charType'] = 3;
    groupedWord['isUnknown'] = true;
    final malformedVietnamese = _vietnameseBackendInput();
    final vietnameseTokens = malformedVietnamese['tokens']! as List<Object?>;
    vietnameseTokens.add('');
    final mistypedVietnamese = _vietnameseBackendInput();
    final mistypedTokens = mistypedVietnamese['tokens']! as List<Object?>;
    mistypedTokens[0] = 1;

    for (final backendInput in <Map<String, Object?>>[
      unknown,
      malformedEnglish,
      malformedCutlet,
      malformedCutletGroup,
      malformedCutletPronunciation,
      malformedCutletReading,
      malformedKorean,
      malformedKoreanCmu,
      malformedVietnamese,
      mistypedVietnamese,
    ]) {
      final record = _record(tokens: <Object?>[])
        ..['backendInput'] = backendInput;
      expect(
        () => UpstreamFixture.parse(jsonEncode(record), location: 'memory:1'),
        throwsA(isA<UpstreamFixtureFormatException>()),
      );
    }
  });
}

Map<String, Object?> _record({required List<Object?>? tokens}) =>
    <String, Object?>{
      'backendVersions': <String, Object?>{},
      'caseId': 'case-1',
      'input': '300',
      'language': 'ja',
      'mode': 'ja-num2kana',
      'options': <String, Object?>{'dictionary': 'hiragana'},
      'phonemes': 'さんびゃく',
      'schemaVersion': 1,
      'tokens': tokens,
      'upstreamCommit': misakiUpstreamCommit,
      'upstreamRepository': misakiUpstreamRepository,
      'upstreamVersion': misakiUpstreamVersion,
    };

Map<String, Object?> _backendInput() => <String, Object?>{
  'kind': PyopenjtalkFixtureBackendInput.kind,
  'schemaVersion': PyopenjtalkFixtureBackendInput.schemaVersion,
  'words': <Object?>[
    <String, Object?>{
      'acc': 0,
      'cform': '*',
      'chain_flag': -1,
      'chain_rule': '-1',
      'ctype': '*',
      'mora_size': 5,
      'orig': 'こんにちは',
      'pos': '感動詞',
      'pos_group1': '*',
      'pos_group2': '*',
      'pos_group3': '*',
      'pron': 'コンニチワ',
      'read': 'コンニチハ',
      'string': 'こんにちは',
    },
  ],
};

Map<String, Object?> _englishBackendInput() => <String, Object?>{
  'kind': EnglishFixtureBackendInput.kind,
  'preprocess': <String, Object?>{
    'applied': true,
    'features': <Object?>[
      <String, Object?>{'sourceWordIndex': 0, 'value': -0.5},
    ],
    'sourceWords': <Object?>['hello'],
    'text': 'hello',
  },
  'schemaVersion': EnglishFixtureBackendInput.schemaVersion,
  'tokens': <Object?>[
    <String, Object?>{
      '_': <String, Object?>{
        'is_head': true,
        'num_flags': '',
        'prespace': false,
        'rating': 5,
        'stress': -0.5,
      },
      'end_ts': null,
      'phonemes': 'həlˈO',
      'start_ts': null,
      'tag': 'UH',
      'text': 'hello',
      'whitespace': '',
    },
  ],
};

Map<String, Object?> _cutletBackendInput() => <String, Object?>{
  'kind': CutletFixtureBackendInput.kind,
  'normalizedText': '今日は さん匹',
  'schemaVersion': CutletFixtureBackendInput.schemaVersion,
  'words': <Object?>[
    <String, Object?>{
      'charType': 2,
      'hiragana': 'きょう',
      'isUnknown': false,
      'joinWithNext': true,
      'kana': 'キョウ',
      'pronunciation': 'キョウ',
      'surface': '今日',
    },
    <String, Object?>{
      'charType': 2,
      'hiragana': 'は',
      'isUnknown': false,
      'joinWithNext': false,
      'kana': 'ハ',
      'pronunciation': null,
      'surface': 'は',
    },
  ],
};

Map<String, Object?> _koreanBackendInput() => <String, Object?>{
  'cmuLookups': <Object?>[
    <String, Object?>{
      'arpabet': <Object?>['G', 'EY1', 'M'],
      'key': 'game',
    },
    <String, Object?>{'arpabet': null, 'key': 'missing'},
  ],
  'input': '한국어',
  'kind': KoreanFixtureBackendInput.kind,
  'schemaVersion': KoreanFixtureBackendInput.schemaVersion,
  'tokens': <Object?>[
    <String, Object?>{'surface': '한국어', 'tag': 'NNG'},
  ],
};

Map<String, Object?> _vietnameseBackendInput() => <String, Object?>{
  'input': 'xin chào',
  'kind': VietnameseFixtureBackendInput.kind,
  'schemaVersion': VietnameseFixtureBackendInput.schemaVersion,
  'tokens': <Object?>['xin', 'chào'],
};
