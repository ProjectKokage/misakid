import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:misakid/misaki_ja.dart';
import 'package:misakid_openjtalk/misakid_openjtalk.dart';
import 'package:misakid_openjtalk/src/dictionary_identity.dart';
import 'package:misakid_openjtalk/src/native_bindings.dart';
import 'package:test/test.dart';

const _stringFields = <String>[
  'string',
  'pos',
  'pos_group1',
  'pos_group2',
  'pos_group3',
  'ctype',
  'cform',
  'orig',
  'read',
  'pron',
  'chain_rule',
];
const _integerFields = <String>['acc', 'mora_size', 'chain_flag'];

void main() {
  final libraryPath = Platform.environment['MISAKID_OPENJTALK_LIBRARY'];
  final dictionaryPath = Platform.environment['MISAKID_OPENJTALK_DICTIONARY'];
  final skipReason = libraryPath == null || dictionaryPath == null
      ? 'Set MISAKID_OPENJTALK_LIBRARY and MISAKID_OPENJTALK_DICTIONARY.'
      : false;

  group(
    'provisioned macOS arm64 adapter',
    () {
      late List<Map<String, Object?>> fixtures;
      late OpenJtalkNativeLibrary library;
      late OpenJtalkNativeFrontend rawFrontend;
      late OpenJtalkFrontendBackend backend;

      setUpAll(() async {
        fixtures = await _readFixtures();
        library = OpenJtalkNativeLibrary.load(libraryPath!);
        final dictionary = await OpenJtalkDictionarySnapshot.validate(
          dictionaryPath!,
        );
        rawFrontend = OpenJtalkNativeFrontend.create(
          library: library,
          dictionaryPath: dictionary.resolvedPath,
          maxInputBytes: defaultOpenJtalkMaxInputBytes,
        );
        backend = await OpenJtalkFrontendBackend.open(
          libraryPath: libraryPath,
          dictionaryPath: dictionaryPath,
        );
      });

      tearDownAll(() {
        rawFrontend.close();
        backend.close();
        backend.close();
        expect(backend.isClosed, isTrue);
        expect(
          () => backend.analyze('猫'),
          throwsA(isA<BackendUnavailableException>()),
        );
      });

      test('reports exact immutable identities', () {
        expect(library.identities, expectedOpenJtalkNativeIdentities);
        expect(backend.info.name, 'pyopenjtalk');
        expect(backend.info.version, '0.4.1');
        expect(backend.info.details['platform'], 'macos-arm64');
        expect(
          backend.info.details['dictionaryTreeSha256'],
          openJtalkDictionaryTreeSha256,
        );
      });

      test('all 24 cases and 155 words match every raw field', () {
        var wordCount = 0;
        for (final fixture in fixtures) {
          final caseId = _string(fixture, 'caseId');
          final actual = rawFrontend.analyzeRaw(_string(fixture, 'input'));
          final backendInput = _map(fixture['backendInput'], '$caseId backend');
          final expectedWords = _list(backendInput['words'], '$caseId words');
          expect(actual, hasLength(expectedWords.length), reason: caseId);
          wordCount += actual.length;
          for (var index = 0; index < actual.length; index++) {
            final expected = _map(expectedWords[index], '$caseId word $index');
            for (var field = 0; field < _stringFields.length; field++) {
              expect(
                actual[index].stringFields[field],
                expected[_stringFields[field]],
                reason: '$caseId word $index ${_stringFields[field]}',
              );
            }
            for (var field = 0; field < _integerFields.length; field++) {
              expect(
                actual[index].integerFields[field],
                expected[_integerFields[field]],
                reason: '$caseId word $index ${_integerFields[field]}',
              );
            }
          }
        }
        expect(fixtures, hasLength(24));
        expect(wordCount, 155);
      });

      test('all final outputs and typed tokens match the pinned oracle', () {
        final engine = JapanesePyopenjtalkEngine(backend: backend);
        for (final fixture in fixtures) {
          final caseId = _string(fixture, 'caseId');
          if (fixture['error'] != null) {
            expect(
              () => engine.convert(_string(fixture, 'input')),
              throwsA(isA<BackendFailureException>()),
              reason: caseId,
            );
            continue;
          }
          final actual = engine.convert(_string(fixture, 'input'));
          expect(actual.phonemes, fixture['phonemes'], reason: caseId);
          _expectTokens(actual.tokens, fixture['tokens'], caseId);
        }
      });

      test('copied results survive later calls and close is deterministic', () {
        final first = rawFrontend.analyzeRaw('東京。');
        final surface = first.first.surface;
        rawFrontend.analyzeRaw('大阪。');
        expect(first.first.surface, surface);

        final disposable = OpenJtalkNativeFrontend.create(
          library: library,
          dictionaryPath: dictionaryPath!,
          maxInputBytes: 3,
        );
        expect(disposable.analyzeRaw('猫'), isNotEmpty);
        expect(
          () => disposable.analyzeRaw('猫a'),
          throwsA(
            isA<OpenJtalkNativeException>().having(
              (error) => error.code,
              'code',
              2,
            ),
          ),
        );
        expect(
          () => disposable.analyzeRaw('猫\u0000犬'),
          throwsA(isA<OpenJtalkNativeException>()),
        );
        expect(
          () => disposable.analyzeRaw(String.fromCharCode(0xD800)),
          throwsA(isA<OpenJtalkNativeException>()),
        );
        disposable.close();
        disposable.close();
        expect(disposable.isClosed, isTrue);
        expect(
          () => disposable.analyzeRaw('猫'),
          throwsA(isA<OpenJtalkNativeException>()),
        );
      });

      test('native results own every field across later analysis', () {
        _expectNativeResultOwnership(
          libraryPath: libraryPath!,
          dictionaryPath: dictionaryPath!,
        );
      });

      test('rejects excessive MeCab words before NJD construction', () {
        expect(
          () => rawFrontend.analyzeRaw(List<String>.filled(70000, '。').join()),
          throwsA(
            isA<OpenJtalkNativeException>()
                .having((error) => error.code, 'code', 6)
                .having((error) => error.stage, 'stage', 'mecab-word-limit'),
          ),
        );
      });

      test(
        'the process-global native lock supports concurrent isolates',
        () async {
          final outputs = await Future.wait(<Future<String>>[
            for (var index = 0; index < 4; index++)
              _analyzeInIsolate(libraryPath!, dictionaryPath!, index),
          ]);
          expect(outputs, everyElement('東京'));
        },
      );

      test('the native ABI independently enforces input validation', () {
        _expectNativeInputStatuses(
          libraryPath: libraryPath!,
          dictionaryPath: dictionaryPath!,
        );
      });

      test(
        'native success and failure paths do not write process stdio',
        () async {
          final result =
              await Process.run(Platform.resolvedExecutable, <String>[
                'run',
                'tool/native_silence_smoke.dart',
                libraryPath!,
                dictionaryPath!,
              ], workingDirectory: Directory.current.path);
          expect(result.exitCode, 0);
          expect(result.stdout, '');
          expect(result.stderr, '');
        },
      );
    },
    tags: 'native',
    skip: skipReason,
  );
}

Future<List<Map<String, Object?>>> _readFixtures() async {
  final file = File(
    '../../test/fixtures/upstream/'
    'fba1236595f2d2bf21d414ba6e57d25256afada3/'
    'ja_pyopenjtalk.jsonl',
  );
  final rows = <Map<String, Object?>>[];
  await for (final line
      in file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    final decoded = jsonDecode(line);
    rows.add(_map(decoded, 'fixture row'));
  }
  return rows;
}

void _expectTokens(List<MisakiToken>? actual, Object? raw, String caseId) {
  final expected = _list(raw, '$caseId tokens');
  if (actual == null) fail('$caseId returned no token list');
  expect(actual, hasLength(expected.length), reason: caseId);
  for (var index = 0; index < actual.length; index++) {
    final expectedToken = _map(expected[index], '$caseId token $index');
    final token = actual[index];
    expect(token.text, expectedToken['text'], reason: caseId);
    expect(token.tag, expectedToken['tag'], reason: caseId);
    expect(token.whitespace, expectedToken['whitespace'], reason: caseId);
    expect(token.phonemes, expectedToken['phonemes'], reason: caseId);
    expect(token.startTimeSeconds, expectedToken['start_ts'], reason: caseId);
    expect(token.endTimeSeconds, expectedToken['end_ts'], reason: caseId);
    final metadata = token.metadata;
    if (metadata is! JapaneseTokenMetadata) {
      fail('$caseId token $index has no Japanese metadata');
    }
    final expectedMetadata = _map(expectedToken['_'], '$caseId metadata');
    expect(metadata.pronunciation, expectedMetadata['pron'], reason: caseId);
    expect(metadata.accent, expectedMetadata['acc'], reason: caseId);
    expect(metadata.moraSize, expectedMetadata['mora_size'], reason: caseId);
    expect(
      metadata.chainFlag,
      _fixtureBool(expectedMetadata['chain_flag']),
      reason: caseId,
    );
    expect(metadata.moras, expectedMetadata['moras'], reason: caseId);
    expect(metadata.accents, expectedMetadata['accents'], reason: caseId);
    expect(metadata.pitch, expectedMetadata['pitch'], reason: caseId);
  }
}

Map<String, Object?> _map(Object? value, String location) {
  if (value is Map<String, Object?>) return value;
  throw StateError('$location is not an object');
}

List<Object?> _list(Object? value, String location) {
  if (value is List<Object?>) return value;
  throw StateError('$location is not a list');
}

String _string(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is String) return value;
  throw StateError('$key is not a string');
}

bool _fixtureBool(Object? value) {
  if (value is bool) return value;
  if (value is List<Object?> && value.isEmpty) return false;
  throw StateError('fixture value is not bool-like');
}

Future<String> _analyzeInIsolate(
  String libraryPath,
  String dictionaryPath,
  int index,
) async {
  final receivePort = ReceivePort();
  await Isolate.spawn<(SendPort, String, String, int)>(_isolateEntry, (
    receivePort.sendPort,
    libraryPath,
    dictionaryPath,
    index,
  ));
  final message = await receivePort.first;
  receivePort.close();
  if (message is List<Object?> &&
      message.length == 2 &&
      message[0] == 'ok' &&
      message[1] is String) {
    return message[1]! as String;
  }
  throw StateError('native isolate failed: $message');
}

void _isolateEntry((SendPort, String, String, int) arguments) {
  final (sendPort, libraryPath, dictionaryPath, index) = arguments;
  try {
    final library = OpenJtalkNativeLibrary.load(libraryPath);
    final frontend = OpenJtalkNativeFrontend.create(
      library: library,
      dictionaryPath: dictionaryPath,
      maxInputBytes: 1024,
    );
    try {
      sendPort.send(<Object?>[
        'ok',
        frontend.analyzeRaw('東京$index。').first.surface,
      ]);
    } finally {
      frontend.close();
    }
  } on Object catch (error) {
    sendPort.send(<Object?>['error', error.toString()]);
  }
}

final class _TestContext extends Opaque {}

final class _TestResult extends Opaque {}

typedef _TestAllocNative = Pointer<Uint8> Function(Size);
typedef _TestAllocDart = Pointer<Uint8> Function(int);
typedef _TestFreeNative = Void Function(Pointer<Void>);
typedef _TestFreeDart = void Function(Pointer<Void>);
typedef _TestCreateNative =
    Pointer<_TestContext> Function(Pointer<Uint8>, Size, Size);
typedef _TestCreateDart =
    Pointer<_TestContext> Function(Pointer<Uint8>, int, int);
typedef _TestContextStatusNative = Uint32 Function(Pointer<_TestContext>);
typedef _TestContextStatusDart = int Function(Pointer<_TestContext>);
typedef _TestContextDestroyNative = Void Function(Pointer<_TestContext>);
typedef _TestContextDestroyDart = void Function(Pointer<_TestContext>);
typedef _TestAnalyzeNative =
    Pointer<_TestResult> Function(Pointer<_TestContext>, Pointer<Uint8>, Size);
typedef _TestAnalyzeDart =
    Pointer<_TestResult> Function(Pointer<_TestContext>, Pointer<Uint8>, int);
typedef _TestResultStatusNative = Uint32 Function(Pointer<_TestResult>);
typedef _TestResultStatusDart = int Function(Pointer<_TestResult>);
typedef _TestWordCountNative = Size Function(Pointer<_TestResult>);
typedef _TestWordCountDart = int Function(Pointer<_TestResult>);
typedef _TestWordStringDataNative =
    Pointer<Uint8> Function(Pointer<_TestResult>, Size, Uint32);
typedef _TestWordStringDataDart =
    Pointer<Uint8> Function(Pointer<_TestResult>, int, int);
typedef _TestWordStringSizeNative =
    Size Function(Pointer<_TestResult>, Size, Uint32);
typedef _TestWordStringSizeDart = int Function(Pointer<_TestResult>, int, int);
typedef _TestWordIntegerNative =
    Int32 Function(Pointer<_TestResult>, Size, Uint32);
typedef _TestWordIntegerDart = int Function(Pointer<_TestResult>, int, int);
typedef _TestResultDestroyNative = Void Function(Pointer<_TestResult>);
typedef _TestResultDestroyDart = void Function(Pointer<_TestResult>);

void _expectNativeResultOwnership({
  required String libraryPath,
  required String dictionaryPath,
}) {
  final dynamicLibrary = DynamicLibrary.open(libraryPath);
  final allocate = dynamicLibrary
      .lookupFunction<_TestAllocNative, _TestAllocDart>(
        'misakid_openjtalk_buffer_alloc',
      );
  final free = dynamicLibrary.lookupFunction<_TestFreeNative, _TestFreeDart>(
    'misakid_openjtalk_buffer_free',
  );
  final create = dynamicLibrary
      .lookupFunction<_TestCreateNative, _TestCreateDart>(
        'misakid_openjtalk_context_create',
      );
  final contextStatus = dynamicLibrary
      .lookupFunction<_TestContextStatusNative, _TestContextStatusDart>(
        'misakid_openjtalk_context_status',
      );
  final contextDestroy = dynamicLibrary
      .lookupFunction<_TestContextDestroyNative, _TestContextDestroyDart>(
        'misakid_openjtalk_context_destroy',
      );
  final analyze = dynamicLibrary
      .lookupFunction<_TestAnalyzeNative, _TestAnalyzeDart>(
        'misakid_openjtalk_analyze',
      );
  final resultStatus = dynamicLibrary
      .lookupFunction<_TestResultStatusNative, _TestResultStatusDart>(
        'misakid_openjtalk_result_status',
      );
  final wordCount = dynamicLibrary
      .lookupFunction<_TestWordCountNative, _TestWordCountDart>(
        'misakid_openjtalk_result_word_count',
      );
  final wordStringData = dynamicLibrary
      .lookupFunction<_TestWordStringDataNative, _TestWordStringDataDart>(
        'misakid_openjtalk_result_word_string_data',
      );
  final wordStringSize = dynamicLibrary
      .lookupFunction<_TestWordStringSizeNative, _TestWordStringSizeDart>(
        'misakid_openjtalk_result_word_string_size',
      );
  final wordInteger = dynamicLibrary
      .lookupFunction<_TestWordIntegerNative, _TestWordIntegerDart>(
        'misakid_openjtalk_result_word_integer',
      );
  final resultDestroy = dynamicLibrary
      .lookupFunction<_TestResultDestroyNative, _TestResultDestroyDart>(
        'misakid_openjtalk_result_destroy',
      );

  final pathBytes = Uint8List.fromList(utf8.encode(dictionaryPath));
  final path = allocate(pathBytes.length);
  path.asTypedList(pathBytes.length).setAll(0, pathBytes);
  final context = create(path, pathBytes.length, 1024);
  free(path.cast<Void>());
  expect(context.address, isNot(0));
  expect(contextStatus(context), 0);

  Pointer<_TestResult> analyzeText(String text) {
    final bytes = Uint8List.fromList(utf8.encode(text));
    final input = allocate(bytes.length);
    input.asTypedList(bytes.length).setAll(0, bytes);
    try {
      final result = analyze(context, input, bytes.length);
      expect(result.address, isNot(0));
      expect(resultStatus(result), 0);
      return result;
    } finally {
      free(input.cast<Void>());
    }
  }

  List<List<Object>> snapshot(Pointer<_TestResult> result) => <List<Object>>[
    for (var word = 0; word < wordCount(result); word++)
      <Object>[
        for (var field = 0; field < 11; field++)
          _readNativeString(
            wordStringData(result, word, field),
            wordStringSize(result, word, field),
          ),
        for (var field = 0; field < 3; field++)
          wordInteger(result, word, field),
      ],
  ];

  try {
    final first = analyzeText('東京。');
    try {
      final before = snapshot(first);
      final second = analyzeText('大阪。');
      try {
        expect(snapshot(first), before);
      } finally {
        resultDestroy(second);
      }
    } finally {
      resultDestroy(first);
    }
  } finally {
    contextDestroy(context);
  }
}

String _readNativeString(Pointer<Uint8> data, int size) {
  if (size == 0) return '';
  expect(data.address, isNot(0));
  return utf8.decode(data.asTypedList(size));
}

void _expectNativeInputStatuses({
  required String libraryPath,
  required String dictionaryPath,
}) {
  final dynamicLibrary = DynamicLibrary.open(libraryPath);
  final allocate = dynamicLibrary
      .lookupFunction<_TestAllocNative, _TestAllocDart>(
        'misakid_openjtalk_buffer_alloc',
      );
  final free = dynamicLibrary.lookupFunction<_TestFreeNative, _TestFreeDart>(
    'misakid_openjtalk_buffer_free',
  );
  final create = dynamicLibrary
      .lookupFunction<_TestCreateNative, _TestCreateDart>(
        'misakid_openjtalk_context_create',
      );
  final contextStatus = dynamicLibrary
      .lookupFunction<_TestContextStatusNative, _TestContextStatusDart>(
        'misakid_openjtalk_context_status',
      );
  final contextDestroy = dynamicLibrary
      .lookupFunction<_TestContextDestroyNative, _TestContextDestroyDart>(
        'misakid_openjtalk_context_destroy',
      );
  final analyze = dynamicLibrary
      .lookupFunction<_TestAnalyzeNative, _TestAnalyzeDart>(
        'misakid_openjtalk_analyze',
      );
  final resultStatus = dynamicLibrary
      .lookupFunction<_TestResultStatusNative, _TestResultStatusDart>(
        'misakid_openjtalk_result_status',
      );
  final resultDestroy = dynamicLibrary
      .lookupFunction<_TestResultDestroyNative, _TestResultDestroyDart>(
        'misakid_openjtalk_result_destroy',
      );

  final pathBytes = Uint8List.fromList(utf8.encode(dictionaryPath));
  final path = allocate(pathBytes.length);
  path.asTypedList(pathBytes.length).setAll(0, pathBytes);
  final context = create(path, pathBytes.length, 3);
  free(path.cast<Void>());
  expect(context.address, isNot(0));
  expect(contextStatus(context), 0);
  try {
    for (final testCase in <(Uint8List, int)>[
      (Uint8List.fromList(<int>[0xE7, 0x8C, 0xAB, 0x61]), 2),
      (Uint8List.fromList(<int>[0xC0]), 3),
      (Uint8List.fromList(<int>[0]), 1),
    ]) {
      final (bytes, expectedStatus) = testCase;
      final input = allocate(bytes.length);
      input.asTypedList(bytes.length).setAll(0, bytes);
      final result = analyze(context, input, bytes.length);
      free(input.cast<Void>());
      expect(result.address, isNot(0));
      try {
        expect(resultStatus(result), expectedStatus);
      } finally {
        resultDestroy(result);
      }
    }
  } finally {
    contextDestroy(context);
  }
}
