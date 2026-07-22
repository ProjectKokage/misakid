import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:misakid_mecab_ja/misakid_mecab_ja.dart';
import 'package:misakid_mecab_ja/src/dictionary_identity.dart';
import 'package:misakid_mecab_ja/src/native_bindings.dart';
import 'package:test/test.dart';

void main() {
  final libraryPath = Platform.environment['MISAKID_MECAB_JA_LIBRARY'];
  final dictionaryPath = Platform.environment['MISAKID_MECAB_JA_DICTIONARY'];
  final wordListPath = Platform.environment['MISAKID_MECAB_JA_WORD_LIST'];
  final fixturePath =
      Platform.environment['MISAKID_MECAB_JA_FIXTURE'] ??
      '../../test/fixtures/upstream/'
          'fba1236595f2d2bf21d414ba6e57d25256afada3/ja_cutlet.jsonl';
  final skipReason =
      libraryPath == null || dictionaryPath == null || wordListPath == null
      ? 'Set MISAKID_MECAB_JA_LIBRARY, MISAKID_MECAB_JA_DICTIONARY, and MISAKID_MECAB_JA_WORD_LIST.'
      : false;

  group(
    'provisioned macOS arm64 adapter',
    () {
      late List<Map<String, Object?>> fixtures;
      late MecabJapaneseNativeLibrary library;
      late MecabJapaneseCutletBackend backend;

      setUpAll(() async {
        fixtures = await _readFixtures(fixturePath);
        library = MecabJapaneseNativeLibrary.load(libraryPath!);
        backend = await MecabJapaneseCutletBackend.open(
          libraryPath: libraryPath,
          dictionaryPath: dictionaryPath!,
          wordListPath: wordListPath!,
          dictionaryProfile:
              MecabJapaneseDictionaryProfile.pinnedUnidicPyCwjParity,
        );
      });

      tearDownAll(() {
        backend.close();
        backend.close();
        expect(backend.isClosed, isTrue);
        expect(
          () => backend.analyzeRaw('猫'),
          throwsA(isA<BackendUnavailableException>()),
        );
      });

      test('reports every immutable identity', () {
        expect(library.identities, expectedMecabJapaneseNativeIdentities);
        expect(
          backend.dictionaryProfile,
          MecabJapaneseDictionaryProfile.pinnedUnidicPyCwjParity,
        );
        expect(
          backend.dictionaryFeatureLayout,
          MecabJapaneseUnidicFeatureLayout.fields29,
        );
        expect(backend.info.name, 'mecab-unidic-cutlet');
        expect(backend.info.version, '0.996');
        expect(
          backend.info.details['dictionaryProfile'],
          'pinned-unidic-py-cwj-parity',
        );
        expect(backend.info.details['dictionaryCorpus'], 'cwj');
        expect(backend.info.details['dictionaryDistribution'], 'unidic-py');
        expect(
          backend.info.details['dictionaryReleaseMarker'],
          pinnedUnidicPyCwjReleaseMarker,
        );
        expect(backend.info.details['platform'], 'macos-arm64');
        expect(
          backend.info.details['dictionaryTreeSha256'],
          pinnedUnidicPyCwjTreeSha256,
        );
        expect(
          backend.info.details['wordMembershipVersion'],
          'fba1236595f2d2bf21d414ba6e57d25256afada3',
        );
      });

      test('dylib declares the exact macOS 11 minimum', () async {
        final result = await Process.run('xcrun', <String>[
          'vtool',
          '-show-build',
          libraryPath!,
        ]);
        expect(result.exitCode, 0);
        expect(result.stdout, contains('minos 11.0'));
      });

      test(
        'dylib exports only the reviewed ABI and links system libraries',
        () async {
          final nm = await Process.run('nm', <String>['-gU', libraryPath!]);
          expect(nm.exitCode, 0);
          final actualExports =
              const LineSplitter()
                  .convert(nm.stdout as String)
                  .map((line) => line.trim().split(RegExp(r'\s+')).last)
                  .toList(growable: false)
                ..sort();
          final expectedExports = await File(
            'native/expected_exports_macos.txt',
          ).readAsLines();
          expect(actualExports, expectedExports);

          final otool = await Process.run('otool', <String>['-L', libraryPath]);
          expect(otool.exitCode, 0);
          final linkage = const LineSplitter()
              .convert(otool.stdout as String)
              .skip(1)
              .map((line) => line.trim().split(' ').first)
              .toList(growable: false);
          expect(linkage, <String>[
            '@rpath/libmisakid_mecab_ja.dylib',
            '/usr/lib/libc++.1.dylib',
            '/usr/lib/libSystem.B.dylib',
          ]);
        },
      );

      test('all 27 cases and 126 words match every raw field', () {
        var wordCount = 0;
        for (final fixture in fixtures) {
          final caseId = _string(fixture, 'caseId');
          final backendInput = _map(fixture['backendInput'], '$caseId backend');
          final normalized = _string(backendInput, 'normalizedText');
          final expectedWords = _list(backendInput['words'], '$caseId words');
          final actual = backend.analyzeRaw(normalized);
          expect(actual, hasLength(expectedWords.length), reason: caseId);
          wordCount += actual.length;
          for (var index = 0; index < actual.length; index++) {
            final expected = _map(expectedWords[index], '$caseId word $index');
            if (!expected.containsKey('pronunciation') ||
                !expected.containsKey('kana')) {
              fail('$caseId word $index lacks raw pronunciation/kana fields');
            }
            expect(actual[index].surface, expected['surface'], reason: caseId);
            expect(
              actual[index].pronunciation,
              expected['pronunciation'],
              reason: '$caseId word $index pronunciation',
            );
            expect(
              actual[index].kana,
              expected['kana'],
              reason: '$caseId word $index kana',
            );
            expect(
              actual[index].charType,
              expected['charType'],
              reason: '$caseId word $index charType',
            );
            expect(
              actual[index].isUnknown,
              expected['isUnknown'],
              reason: '$caseId word $index isUnknown',
            );
          }
        }
        expect(fixtures, hasLength(27));
        expect(wordCount, 126);
      });

      test('all derived readings and grouping decisions match', () {
        for (final fixture in fixtures) {
          final caseId = _string(fixture, 'caseId');
          final backendInput = _map(fixture['backendInput'], '$caseId backend');
          final expectedWords = _list(backendInput['words'], '$caseId words');
          final actual = backend.analyze(
            _string(backendInput, 'normalizedText'),
          );
          expect(actual, hasLength(expectedWords.length), reason: caseId);
          for (var index = 0; index < actual.length; index++) {
            final expected = _map(expectedWords[index], '$caseId word $index');
            expect(
              actual[index].hiragana,
              expected['hiragana'],
              reason: '$caseId word $index hiragana',
            );
            expect(
              actual[index].joinWithNext,
              expected['joinWithNext'],
              reason: '$caseId word $index joinWithNext',
            );
          }
        }
      });

      test('all final outputs and null-token contracts match', () {
        final engine = JapaneseCutletEngine(backend: backend);
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
          expect(actual.tokens, isNull, reason: caseId);
        }
      });

      test('nullable raw readings preserve Fugashi distinctions', () {
        final greeting = backend.analyzeRaw('こんにちは').single;
        expect(greeting.pronunciation, 'コンニチワ');
        expect(greeting.kana, 'コンニチハ');
        final middleDot = backend.analyzeRaw('・').single;
        expect(middleDot.pronunciation, '*');
        expect(middleDot.kana, '・');
        final unknown = backend.analyzeRaw('Misaki').single;
        expect(unknown.isUnknown, isTrue);
        expect(unknown.pronunciation, isNull);
        expect(unknown.kana, isNull);
      });

      test('result ownership, bounds, and close are deterministic', () {
        final first = backend.analyzeRaw('東京。');
        final snapshot = <Object?>[
          first.first.surface,
          first.first.pronunciation,
          first.first.kana,
          first.first.charType,
          first.first.isUnknown,
        ];
        backend.analyzeRaw('大阪。');
        expect(<Object?>[
          first.first.surface,
          first.first.pronunciation,
          first.first.kana,
          first.first.charType,
          first.first.isUnknown,
        ], snapshot);

        final raw = MecabJapaneseNativeAnalyzer.create(
          library: library,
          dictionaryPath: dictionaryPath!,
          maxInputBytes: 3,
        );
        expect(raw.featureFieldCount, 29);
        expect(raw.analyzeRaw('猫'), isNotEmpty);
        expect(
          () => raw.analyzeRaw('猫a'),
          throwsA(
            isA<MecabJapaneseNativeException>().having(
              (error) => error.code,
              'code',
              2,
            ),
          ),
        );
        expect(
          () => raw.analyzeRaw('猫\u0000犬'),
          throwsA(isA<MecabJapaneseNativeException>()),
        );
        expect(
          () => raw.analyzeRaw(String.fromCharCode(0xD800)),
          throwsA(isA<MecabJapaneseNativeException>()),
        );
        raw.close();
        raw.close();
        expect(raw.isClosed, isTrue);
        expect(
          () => raw.analyzeRaw('猫'),
          throwsA(isA<MecabJapaneseNativeException>()),
        );
      });

      test('native result ownership and validation statuses are exact', () {
        _expectNativeAbiOwnershipAndStatuses(
          libraryPath: libraryPath!,
          dictionaryPath: dictionaryPath!,
        );
      });

      test('process-global native lock supports concurrent isolates', () async {
        final outputs = await Future.wait(<Future<String>>[
          for (var index = 0; index < 4; index++)
            _analyzeInIsolate(libraryPath!, dictionaryPath!, index),
        ]);
        expect(outputs, everyElement('東京'));
      });

      test(
        'success and native failures write no process stdio',
        () async {
          final temporary = await Directory.systemTemp.createTemp(
            'misakid-mecab-ja-silence-',
          );
          try {
            final executable = '${temporary.path}/native_silence_smoke';
            final compile = await Process.run('xcrun', <String>[
              'clang++',
              '-std=c++17',
              '-Wall',
              '-Wextra',
              '-Werror',
              '-I',
              'native/include',
              'tool/native_silence_smoke.cpp',
              '-o',
              executable,
            ], workingDirectory: Directory.current.path);
            expect(
              compile.exitCode,
              0,
              reason: '${compile.stdout}${compile.stderr}',
            );
            final result = await Process.run(executable, <String>[
              libraryPath!,
              dictionaryPath!,
            ]);
            expect(result.exitCode, 0);
            expect(result.stdout, '');
            expect(result.stderr, '');
          } finally {
            await temporary.delete(recursive: true);
          }
        },
        timeout: const Timeout(Duration(seconds: 30)),
      );
    },
    tags: 'native',
    skip: skipReason,
  );

  group(
    'provisioned bundled native-asset adapter',
    () {
      late List<Map<String, Object?>> fixtures;
      late MecabJapaneseCutletBackend backend;

      setUpAll(() async {
        fixtures = await _readFixtures(fixturePath);
        final wordListBytes = await File(wordListPath!).readAsBytes();
        backend = await MecabJapaneseCutletBackend.openBundled(
          dictionaryPath: dictionaryPath!,
          wordListBytes: wordListBytes,
          dictionaryProfile:
              MecabJapaneseDictionaryProfile.pinnedUnidicPyCwjParity,
        );
        wordListBytes.fillRange(0, wordListBytes.length, 0);
      });

      tearDownAll(() => backend.close());

      test('reports the portable build and exact resource identities', () {
        expect(
          backend.dictionaryProfile,
          MecabJapaneseDictionaryProfile.pinnedUnidicPyCwjParity,
        );
        expect(
          backend.dictionaryFeatureLayout,
          MecabJapaneseUnidicFeatureLayout.fields29,
        );
        expect(
          backend.info.details['platform'],
          'native-assets-${Abi.current()}',
        );
        expect(
          backend.info.details['nativeBuildProfile'],
          'misakid-mecab-ja-build-v4-portable',
        );
        expect(
          backend.info.details['dictionaryTreeSha256'],
          pinnedUnidicPyCwjTreeSha256,
        );
        expect(
          backend.info.details['wordMembershipVersion'],
          'fba1236595f2d2bf21d414ba6e57d25256afada3',
        );
      });

      test(
        'compatible profile does not infer CWJ from its release marker',
        () async {
          final wordListBytes = await File(wordListPath!).readAsBytes();
          final compatible = await MecabJapaneseCutletBackend.openBundled(
            dictionaryPath: dictionaryPath!,
            wordListBytes: wordListBytes,
          );
          wordListBytes.fillRange(0, wordListBytes.length, 0);
          try {
            expect(
              compatible.dictionaryProfile,
              MecabJapaneseDictionaryProfile.compatible,
            );
            expect(
              compatible.dictionaryFeatureLayout,
              MecabJapaneseUnidicFeatureLayout.fields29,
            );
            expect(compatible.info.details['dictionaryCorpus'], 'unknown');
            expect(
              compatible.info.details['dictionaryDistribution'],
              'unknown',
            );
            expect(compatible.info.details['dictionaryIdentity'], 'unverified');
            expect(
              compatible.info.details,
              isNot(contains('dictionaryReleaseMarker')),
            );
            expect(
              compatible.info.details,
              isNot(contains('dictionaryTreeSha256')),
            );
          } finally {
            compatible.close();
          }
        },
      );

      test('all raw words and Cutlet grouping match the pinned oracle', () {
        var wordCount = 0;
        for (final fixture in fixtures) {
          final caseId = _string(fixture, 'caseId');
          final backendInput = _map(fixture['backendInput'], '$caseId backend');
          final expectedWords = _list(backendInput['words'], '$caseId words');
          final normalized = _string(backendInput, 'normalizedText');
          final raw = backend.analyzeRaw(normalized);
          final grouped = backend.analyze(normalized);
          expect(raw, hasLength(expectedWords.length), reason: caseId);
          expect(grouped, hasLength(expectedWords.length), reason: caseId);
          wordCount += raw.length;
          for (var index = 0; index < raw.length; index++) {
            final expected = _map(expectedWords[index], '$caseId word $index');
            expect(raw[index].surface, expected['surface'], reason: caseId);
            expect(
              raw[index].pronunciation,
              expected['pronunciation'],
              reason: '$caseId word $index pronunciation',
            );
            expect(
              raw[index].kana,
              expected['kana'],
              reason: '$caseId word $index kana',
            );
            expect(
              raw[index].charType,
              expected['charType'],
              reason: '$caseId word $index charType',
            );
            expect(
              raw[index].isUnknown,
              expected['isUnknown'],
              reason: '$caseId word $index isUnknown',
            );
            expect(
              grouped[index].hiragana,
              expected['hiragana'],
              reason: '$caseId word $index hiragana',
            );
            expect(
              grouped[index].joinWithNext,
              expected['joinWithNext'],
              reason: '$caseId word $index joinWithNext',
            );
          }
        }
        expect(fixtures, hasLength(27));
        expect(wordCount, 126);
      });

      test('all final phonemes and null-token contracts match', () {
        final engine = JapaneseCutletEngine(backend: backend);
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
          expect(actual.tokens, isNull, reason: caseId);
        }
      });

      test(
        'bundled analyzer lifecycle, bounds, and isolates are safe',
        () async {
          final analyzer = MecabJapaneseNativeAnalyzer.create(
            library: MecabJapaneseNativeLibrary.loadBundled(),
            dictionaryPath: dictionaryPath!,
            maxInputBytes: 3,
          );
          expect(analyzer.featureFieldCount, 29);
          expect(analyzer.analyzeRaw('猫'), isNotEmpty);
          expect(
            () => analyzer.analyzeRaw('猫a'),
            throwsA(
              isA<MecabJapaneseNativeException>().having(
                (error) => error.code,
                'code',
                2,
              ),
            ),
          );
          analyzer.close();
          analyzer.close();
          expect(analyzer.isClosed, isTrue);

          final outputs = await Future.wait(<Future<String>>[
            for (var index = 0; index < 4; index++)
              _analyzeBundledInIsolate(dictionaryPath, index),
          ]);
          expect(outputs, everyElement('東京'));
        },
      );
    },
    tags: 'native',
    skip: dictionaryPath == null || wordListPath == null
        ? 'Set MISAKID_MECAB_JA_DICTIONARY and MISAKID_MECAB_JA_WORD_LIST.'
        : false,
  );
}

Future<List<Map<String, Object?>>> _readFixtures(String path) async {
  final rows = <Map<String, Object?>>[];
  await for (final line in File(
    path,
  ).openRead().transform(utf8.decoder).transform(const LineSplitter())) {
    rows.add(_map(jsonDecode(line), 'fixture row'));
  }
  return rows;
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

Future<String> _analyzeBundledInIsolate(
  String dictionaryPath,
  int index,
) async {
  final receivePort = ReceivePort();
  await Isolate.spawn<(SendPort, String, int)>(_bundledIsolateEntry, (
    receivePort.sendPort,
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
  throw StateError('bundled native isolate failed: $message');
}

void _isolateEntry((SendPort, String, String, int) arguments) {
  final (sendPort, libraryPath, dictionaryPath, index) = arguments;
  try {
    final library = MecabJapaneseNativeLibrary.load(libraryPath);
    final analyzer = MecabJapaneseNativeAnalyzer.create(
      library: library,
      dictionaryPath: dictionaryPath,
      maxInputBytes: 1024,
    );
    try {
      sendPort.send(<Object?>[
        'ok',
        analyzer.analyzeRaw('東京$index。').first.surface,
      ]);
    } finally {
      analyzer.close();
    }
  } on Object catch (error) {
    sendPort.send(<Object?>['error', error.toString()]);
  }
}

void _bundledIsolateEntry((SendPort, String, int) arguments) {
  final (sendPort, dictionaryPath, index) = arguments;
  try {
    final analyzer = MecabJapaneseNativeAnalyzer.create(
      library: MecabJapaneseNativeLibrary.loadBundled(),
      dictionaryPath: dictionaryPath,
      maxInputBytes: 1024,
    );
    try {
      sendPort.send(<Object?>[
        'ok',
        analyzer.analyzeRaw('東京$index。').first.surface,
      ]);
    } finally {
      analyzer.close();
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

void _expectNativeAbiOwnershipAndStatuses({
  required String libraryPath,
  required String dictionaryPath,
}) {
  final library = DynamicLibrary.open(libraryPath);
  final allocate = library.lookupFunction<_TestAllocNative, _TestAllocDart>(
    'misakid_mecab_ja_buffer_alloc',
  );
  final free = library.lookupFunction<_TestFreeNative, _TestFreeDart>(
    'misakid_mecab_ja_buffer_free',
  );
  final create = library.lookupFunction<_TestCreateNative, _TestCreateDart>(
    'misakid_mecab_ja_context_create',
  );
  final contextStatus = library
      .lookupFunction<_TestContextStatusNative, _TestContextStatusDart>(
        'misakid_mecab_ja_context_status',
      );
  final destroyContext = library
      .lookupFunction<_TestContextDestroyNative, _TestContextDestroyDart>(
        'misakid_mecab_ja_context_destroy',
      );
  final analyze = library.lookupFunction<_TestAnalyzeNative, _TestAnalyzeDart>(
    'misakid_mecab_ja_analyze',
  );
  final resultStatus = library
      .lookupFunction<_TestResultStatusNative, _TestResultStatusDart>(
        'misakid_mecab_ja_result_status',
      );
  final wordCount = library
      .lookupFunction<_TestWordCountNative, _TestWordCountDart>(
        'misakid_mecab_ja_result_word_count',
      );
  final stringData = library
      .lookupFunction<_TestWordStringDataNative, _TestWordStringDataDart>(
        'misakid_mecab_ja_result_word_string_data',
      );
  final stringSize = library
      .lookupFunction<_TestWordStringSizeNative, _TestWordStringSizeDart>(
        'misakid_mecab_ja_result_word_string_size',
      );
  final integer = library
      .lookupFunction<_TestWordIntegerNative, _TestWordIntegerDart>(
        'misakid_mecab_ja_result_word_integer',
      );
  final destroyResult = library
      .lookupFunction<_TestResultDestroyNative, _TestResultDestroyDart>(
        'misakid_mecab_ja_result_destroy',
      );

  Pointer<Uint8> copy(List<int> bytes) {
    final pointer = allocate(bytes.length);
    expect(pointer.address, isNot(0));
    pointer.asTypedList(bytes.length).setAll(0, bytes);
    return pointer;
  }

  final pathBytes = utf8.encode(dictionaryPath);
  final path = copy(pathBytes);
  final context = create(path, pathBytes.length, 3);
  free(path.cast<Void>());
  expect(context.address, isNot(0));
  expect(contextStatus(context), 0);

  Pointer<_TestResult> analyzeBytes(List<int> bytes) {
    final input = copy(bytes);
    try {
      final result = analyze(context, input, bytes.length);
      expect(result.address, isNot(0));
      return result;
    } finally {
      free(input.cast<Void>());
    }
  }

  List<List<Object>> snapshot(Pointer<_TestResult> result) => <List<Object>>[
    for (var word = 0; word < wordCount(result); word++)
      <Object>[
        for (var field = 0; field < 3; field++)
          _readNativeString(
            stringData(result, word, field),
            stringSize(result, word, field),
          ),
        for (var field = 0; field < 4; field++) integer(result, word, field),
      ],
  ];

  try {
    final first = analyzeBytes(utf8.encode('猫'));
    try {
      expect(resultStatus(first), 0);
      final before = snapshot(first);
      final second = analyzeBytes(utf8.encode('犬'));
      try {
        expect(resultStatus(second), 0);
        expect(snapshot(first), before);
      } finally {
        destroyResult(second);
      }
    } finally {
      destroyResult(first);
    }

    for (final invalid in <(List<int>, int)>[
      (<int>[0xC0], 3),
      (<int>[0x61, 0x00, 0x62], 1),
      (<int>[0xE7, 0x8C, 0xAB, 0x61], 2),
    ]) {
      final result = analyzeBytes(invalid.$1);
      try {
        expect(resultStatus(result), invalid.$2);
      } finally {
        destroyResult(result);
      }
    }
  } finally {
    destroyContext(context);
  }
}

String _readNativeString(Pointer<Uint8> data, int size) {
  if (size == 0) return '';
  expect(data.address, isNot(0));
  return utf8.decode(data.asTypedList(size), allowMalformed: false);
}
