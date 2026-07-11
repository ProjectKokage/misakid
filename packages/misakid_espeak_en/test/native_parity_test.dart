import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:misakid_espeak_en/misakid_espeak_en.dart';
import 'package:misakid_espeak_en/src/native_bindings.dart';
import 'package:misakid_espeak_en/src/resource_identity.dart';
import 'package:test/test.dart';

void main() {
  final adapterPath = Platform.environment['MISAKID_ESPEAK_EN_ADAPTER_LIBRARY'];
  final runtimePath = Platform.environment['MISAKID_ESPEAK_EN_LIBRARY'];
  final dataPath = Platform.environment['MISAKID_ESPEAK_EN_DATA'];
  final skipReason =
      adapterPath == null || runtimePath == null || dataPath == null
      ? 'Set MISAKID_ESPEAK_EN_ADAPTER_LIBRARY, '
            'MISAKID_ESPEAK_EN_LIBRARY, and MISAKID_ESPEAK_EN_DATA.'
      : false;

  group(
    'provisioned macOS arm64 eSpeak adapter',
    () {
      late EspeakEnglishBackend backend;
      late List<Map<String, Object?>> fixtures;

      setUpAll(() async {
        fixtures = await _readFixtures();
        backend = await EspeakEnglishBackend.open(
          adapterLibraryPath: adapterPath!,
          espeakLibraryPath: runtimePath!,
          dataPath: dataPath!,
        );
      });

      tearDownAll(() {
        backend.close();
        backend.close();
        expect(backend.isClosed, isTrue);
      });

      test('reports exact immutable identities', () {
        expect(backend.info.name, 'espeak-ng');
        expect(backend.info.version, '1.52.0');
        expect(backend.info.details['platform'], 'macos-arm64');
        expect(
          backend.info.details['librarySha256'],
          pinnedEspeakNgLibrarySha256,
        );
        expect(
          backend.info.details['dataTreeSha256'],
          pinnedEspeakNgDataTreeSha256,
        );
        expect(backend.info.details['dataDirectories'], '37');
        expect(backend.info.details['chunkLimit'], '65536');
      });

      test('all 58 accepted raw calls match both dialects exactly', () {
        var callCount = 0;
        for (final fixture in fixtures) {
          final dialect = fixture['mode'] == 'american-espeak-fallback'
              ? EnglishDialect.american
              : EnglishDialect.british;
          final backendInput = fixture['backendInput']! as Map<String, Object?>;
          final calls = backendInput['espeakCalls']! as List<Object?>;
          for (final rawCall in calls) {
            final call = rawCall! as Map<String, Object?>;
            expect(
              backend.phonemize(call['text']! as String, dialect: dialect),
              call['rawPhones'],
              reason: '${fixture['mode']}/${fixture['caseId']}',
            );
            callCount++;
          }
        }
        expect(callCount, 58);
      });

      test('all 40 final fallback outputs and tokens match pinned Misaki', () {
        for (final fixture in fixtures) {
          final dialect = fixture['mode'] == 'american-espeak-fallback'
              ? EnglishDialect.american
              : EnglishDialect.british;
          final options = fixture['options']! as Map<String, Object?>;
          final version = options['version'] == '2.0'
              ? EnglishPhonemeVersion.v2
              : EnglishPhonemeVersion.legacy;
          final backendInput = fixture['backendInput']! as Map<String, Object?>;
          final engine = EnglishG2pEngine(
            tokenizer: _FixtureTokenizer(backendInput),
            pronunciation: PinnedEnglishLexicon(dialect: dialect),
            fallback: EnglishEspeakFallback(
              backend: backend,
              dialect: dialect,
              phonemeVersion: version,
            ),
            phonemeVersion: version,
            unknownMarker: options['unk'] as String? ?? '❓',
            preprocessInput: options['preprocess'] as bool? ?? true,
          );
          final result = engine.convert(fixture['input']! as String);
          final reason = '${fixture['mode']}/${fixture['caseId']}';
          expect(result.phonemes, fixture['phonemes'], reason: reason);
          _expectTokens(result.tokens, fixture['tokens'], reason);
        }
      });

      test(
        'copied outputs, input bounds, and close are deterministic',
        () async {
          final first = backend.phonemize(
            'blorptastic',
            dialect: EnglishDialect.american,
          );
          backend.phonemize('snorflegloop', dialect: EnglishDialect.british);
          expect(first, 'blɔː^ɹptˈe^ɪstɪk ');
          expect(
            () => backend.phonemize(
              List<String>.filled(65537, 'a;').join(),
              dialect: EnglishDialect.american,
            ),
            throwsA(isA<BackendFailureException>()),
          );
          final bounded = await EspeakEnglishBackend.open(
            adapterLibraryPath: adapterPath!,
            espeakLibraryPath: runtimePath!,
            dataPath: dataPath!,
            maxInputBytes: 4,
            maxOutputBytes: 4,
          );
          try {
            expect(
              () =>
                  bounded.phonemize('hello', dialect: EnglishDialect.american),
              throwsA(isA<BackendFailureException>()),
            );
            expect(
              () => bounded.phonemize(
                'a\u0000b',
                dialect: EnglishDialect.american,
              ),
              throwsA(isA<BackendFailureException>()),
            );
            expect(
              () => bounded.phonemize(
                String.fromCharCode(0xD800),
                dialect: EnglishDialect.american,
              ),
              throwsA(isA<BackendFailureException>()),
            );
            expect(
              () =>
                  bounded.phonemize('!!!!!', dialect: EnglishDialect.american),
              throwsA(isA<BackendFailureException>()),
            );
            expect(
              () => bounded.phonemize('test', dialect: EnglishDialect.american),
              throwsA(isA<BackendFailureException>()),
            );
            expect(
              () => bounded.phonemize('a,a', dialect: EnglishDialect.american),
              throwsA(isA<BackendFailureException>()),
            );
          } finally {
            bounded.close();
            bounded.close();
          }
          expect(bounded.isClosed, isTrue);
          expect(
            () => bounded.phonemize('word', dialect: EnglishDialect.american),
            throwsA(isA<BackendUnavailableException>()),
          );
        },
      );

      test('rejects exact-library and data-tree tampering', () async {
        final temporary = await Directory.systemTemp.createTemp(
          'misakid-espeak-en-tamper-',
        );
        try {
          final alteredLibrary = File('${temporary.path}/libespeak-ng.dylib');
          await File(runtimePath!).copy(alteredLibrary.path);
          final libraryBytes = await alteredLibrary.readAsBytes();
          libraryBytes[libraryBytes.length ~/ 2] ^= 1;
          await alteredLibrary.writeAsBytes(libraryBytes, flush: true);
          await expectLater(
            EspeakResourceSnapshot.validate(
              libraryPath: alteredLibrary.path,
              dataPath: dataPath!,
            ),
            throwsA(isA<MalformedDataException>()),
          );

          final copiedData = Directory('${temporary.path}/espeak-ng-data');
          await _copyDirectory(Directory(dataPath), copiedData);
          final empty = Directory('${copiedData.path}/unexpected-empty');
          await empty.create();
          await expectLater(
            EspeakResourceSnapshot.validate(
              libraryPath: runtimePath,
              dataPath: copiedData.path,
            ),
            throwsA(isA<MalformedDataException>()),
          );
          final nativeLibrary = EspeakEnglishNativeLibrary.load(adapterPath!);
          expect(
            () => EspeakEnglishNativeContext.create(
              library: nativeLibrary,
              runtimeLibraryPath: runtimePath,
              dataPath: copiedData.path,
              maxInputBytes: 1024,
              maxOutputBytes: 1024,
            ),
            throwsA(isA<EspeakEnglishNativeException>()),
          );
          await empty.delete();
          await File(
            '${copiedData.path}/en_dict',
          ).writeAsBytes(const <int>[0], mode: FileMode.append);
          await expectLater(
            EspeakResourceSnapshot.validate(
              libraryPath: runtimePath,
              dataPath: copiedData.path,
            ),
            throwsA(isA<MalformedDataException>()),
          );
        } finally {
          await temporary.delete(recursive: true);
        }
      });

      test(
        'the process-global native lock supports concurrent isolates',
        () async {
          final outputs = await Future.wait(<Future<String>>[
            for (var index = 0; index < 4; index++)
              _phonemizeInIsolate(adapterPath!, runtimePath!, dataPath!, index),
          ]);
          expect(outputs, <String>[
            'blɔː^ɹptˈe^ɪstɪk ',
            'blɔːptˈe^ɪstɪk ',
            'blɔː^ɹptˈe^ɪstɪk ',
            'blɔːptˈe^ɪstɪk ',
          ]);
        },
      );

      test(
        'native artifact exports only the reviewed owned-result ABI',
        () async {
          final adapter = adapterPath!;
          final exports = await Process.run('nm', <String>['-gjU', adapter]);
          expect(exports.exitCode, 0);
          final actualExports = LineSplitter.split(
            exports.stdout as String,
          ).where((line) => line.isNotEmpty).toList()..sort();
          final expectedExports = await File(
            'native/expected_exports_macos.txt',
          ).readAsLines();
          expect(actualExports, expectedExports);

          final dependencies = await Process.run('otool', <String>[
            '-L',
            adapter,
          ]);
          expect(dependencies.exitCode, 0);
          final linked = dependencies.stdout as String;
          expect(linked, contains('/usr/lib/libSystem.B.dylib'));
          expect(linked, contains('/usr/lib/libc++.1.dylib'));
          expect(linked, isNot(contains('libespeak-ng')));
          expect(
            LineSplitter.split(linked).skip(1).join('\n'),
            isNot(contains('/private/tmp')),
          );

          final loadCommands = await Process.run('otool', <String>[
            '-l',
            adapter,
          ]);
          expect(loadCommands.exitCode, 0);
          expect(loadCommands.stdout, contains('minos 11.0'));
          final undefined = await Process.run('nm', <String>['-u', adapter]);
          expect(undefined.exitCode, 0);
          expect(
            undefined.stdout,
            isNot(matches(RegExp(r'(_exit|_abort)$', multiLine: true))),
          );
        },
      );

      test('native success and failure paths write no process stdio', () async {
        final result = await Process.run(Platform.resolvedExecutable, <String>[
          'run',
          'tool/native_silence_smoke.dart',
          adapterPath!,
          runtimePath!,
          dataPath!,
        ], workingDirectory: Directory.current.path);
        expect(result.exitCode, 0);
        expect(result.stdout, '');
        expect(result.stderr, '');
      });

      test('native ABI independently enforces ownership and input limits', () {
        _expectNativeSafety(
          adapterPath: adapterPath!,
          runtimePath: runtimePath!,
          dataPath: dataPath!,
        );
      });
    },
    tags: 'native',
    skip: skipReason,
  );
}

final class _FixtureTokenizer implements EnglishTokenizerBackend {
  _FixtureTokenizer(Map<String, Object?> backendInput)
    : _tokens = (backendInput['tokens']! as List<Object?>)
          .map((raw) => _fixtureToken(raw! as Map<String, Object?>))
          .toList(growable: false);

  final List<MisakiToken> _tokens;

  @override
  BackendInfo get info =>
      BackendInfo(name: 'fixture-spacy-replay', version: '3.8.0');

  @override
  List<MisakiToken> tokenize(EnglishPreprocessResult input) => _tokens;
}

MisakiToken _fixtureToken(Map<String, Object?> raw) {
  final metadata = raw['_']! as Map<String, Object?>;
  return MisakiToken(
    text: raw['text']! as String,
    tag: raw['tag']! as String,
    whitespace: raw['whitespace']! as String,
    phonemes: raw['phonemes'] as String?,
    startTimeSeconds: (raw['start_ts'] as num?)?.toDouble(),
    endTimeSeconds: (raw['end_ts'] as num?)?.toDouble(),
    metadata: EnglishTokenMetadata(
      isHead: metadata['is_head']! as bool,
      alias: metadata['alias'] as String?,
      stress: (metadata['stress'] as num?)?.toDouble(),
      currency: metadata['currency'] as String?,
      numberFlags: metadata['num_flags']! as String,
      precededBySpace: metadata['prespace']! as bool,
      rating: (raw['rating'] ?? metadata['rating']) as int?,
    ),
  );
}

void _expectTokens(List<MisakiToken>? actual, Object? raw, String reason) {
  final expected = raw! as List<Object?>;
  expect(actual, isNotNull, reason: reason);
  expect(actual, hasLength(expected.length), reason: reason);
  for (var index = 0; index < expected.length; index++) {
    final expectedToken = expected[index]! as Map<String, Object?>;
    final expectedMetadata = expectedToken['_']! as Map<String, Object?>;
    final token = actual![index];
    final metadata = token.metadata! as EnglishTokenMetadata;
    final tokenReason = '$reason token $index';
    expect(token.text, expectedToken['text'], reason: tokenReason);
    expect(token.tag, expectedToken['tag'], reason: tokenReason);
    expect(token.whitespace, expectedToken['whitespace'], reason: tokenReason);
    expect(token.phonemes, expectedToken['phonemes'], reason: tokenReason);
    expect(
      token.startTimeSeconds,
      expectedToken['start_ts'],
      reason: tokenReason,
    );
    expect(token.endTimeSeconds, expectedToken['end_ts'], reason: tokenReason);
    expect(metadata.isHead, expectedMetadata['is_head'], reason: tokenReason);
    expect(metadata.alias, expectedMetadata['alias'], reason: tokenReason);
    expect(metadata.stress, expectedMetadata['stress'], reason: tokenReason);
    expect(
      metadata.currency,
      expectedMetadata['currency'],
      reason: tokenReason,
    );
    expect(
      metadata.numberFlags,
      expectedMetadata['num_flags'],
      reason: tokenReason,
    );
    expect(
      metadata.precededBySpace,
      expectedMetadata['prespace'],
      reason: tokenReason,
    );
    expect(
      metadata.rating,
      expectedToken['rating'] ?? expectedMetadata['rating'],
      reason: tokenReason,
    );
  }
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    final relative = entity.path.substring(source.path.length + 1);
    final target = '${destination.path}/$relative';
    if (entity is Directory) {
      await Directory(target).create(recursive: true);
    } else if (entity is File) {
      await File(target).parent.create(recursive: true);
      await entity.copy(target);
    } else {
      throw StateError('unexpected source resource entry: ${entity.path}');
    }
  }
}

Future<String> _phonemizeInIsolate(
  String adapterPath,
  String runtimePath,
  String dataPath,
  int index,
) async {
  final receivePort = ReceivePort();
  await Isolate.spawn<(SendPort, String, String, String, int)>(_isolateEntry, (
    receivePort.sendPort,
    adapterPath,
    runtimePath,
    dataPath,
    index,
  ));
  final response = await receivePort.first;
  receivePort.close();
  if (response is List<Object?> &&
      response.length == 2 &&
      response.first == 'ok') {
    return response[1]! as String;
  }
  throw StateError('native isolate failed: $response');
}

void _isolateEntry((SendPort, String, String, String, int) arguments) async {
  final (sendPort, adapterPath, runtimePath, dataPath, index) = arguments;
  try {
    final backend = await EspeakEnglishBackend.open(
      adapterLibraryPath: adapterPath,
      espeakLibraryPath: runtimePath,
      dataPath: dataPath,
    );
    try {
      sendPort.send(<Object?>[
        'ok',
        backend.phonemize(
          'blorptastic',
          dialect: index.isEven
              ? EnglishDialect.american
              : EnglishDialect.british,
        ),
      ]);
    } finally {
      backend.close();
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
    Pointer<_TestContext> Function(
      Pointer<Uint8>,
      Size,
      Pointer<Uint8>,
      Size,
      Size,
      Size,
    );
typedef _TestCreateDart =
    Pointer<_TestContext> Function(
      Pointer<Uint8>,
      int,
      Pointer<Uint8>,
      int,
      int,
      int,
    );
typedef _TestContextStatusNative = Uint32 Function(Pointer<_TestContext>);
typedef _TestContextStatusDart = int Function(Pointer<_TestContext>);
typedef _TestContextDestroyNative = Void Function(Pointer<_TestContext>);
typedef _TestContextDestroyDart = void Function(Pointer<_TestContext>);
typedef _TestPhonemizeNative =
    Pointer<_TestResult> Function(
      Pointer<_TestContext>,
      Pointer<Uint8>,
      Size,
      Uint32,
    );
typedef _TestPhonemizeDart =
    Pointer<_TestResult> Function(
      Pointer<_TestContext>,
      Pointer<Uint8>,
      int,
      int,
    );
typedef _TestResultStatusNative = Uint32 Function(Pointer<_TestResult>);
typedef _TestResultStatusDart = int Function(Pointer<_TestResult>);
typedef _TestResultDataNative = Pointer<Uint8> Function(Pointer<_TestResult>);
typedef _TestResultDataDart = Pointer<Uint8> Function(Pointer<_TestResult>);
typedef _TestResultSizeNative = Size Function(Pointer<_TestResult>);
typedef _TestResultSizeDart = int Function(Pointer<_TestResult>);
typedef _TestResultDestroyNative = Void Function(Pointer<_TestResult>);
typedef _TestResultDestroyDart = void Function(Pointer<_TestResult>);

void _expectNativeSafety({
  required String adapterPath,
  required String runtimePath,
  required String dataPath,
}) {
  final library = DynamicLibrary.open(adapterPath);
  final allocate = library.lookupFunction<_TestAllocNative, _TestAllocDart>(
    'misakid_espeak_en_buffer_alloc',
  );
  final free = library.lookupFunction<_TestFreeNative, _TestFreeDart>(
    'misakid_espeak_en_buffer_free',
  );
  final create = library.lookupFunction<_TestCreateNative, _TestCreateDart>(
    'misakid_espeak_en_context_create',
  );
  final contextStatus = library
      .lookupFunction<_TestContextStatusNative, _TestContextStatusDart>(
        'misakid_espeak_en_context_status',
      );
  final contextDestroy = library
      .lookupFunction<_TestContextDestroyNative, _TestContextDestroyDart>(
        'misakid_espeak_en_context_destroy',
      );
  final phonemize = library
      .lookupFunction<_TestPhonemizeNative, _TestPhonemizeDart>(
        'misakid_espeak_en_phonemize',
      );
  final resultStatus = library
      .lookupFunction<_TestResultStatusNative, _TestResultStatusDart>(
        'misakid_espeak_en_result_status',
      );
  final resultData = library
      .lookupFunction<_TestResultDataNative, _TestResultDataDart>(
        'misakid_espeak_en_result_output_data',
      );
  final resultSize = library
      .lookupFunction<_TestResultSizeNative, _TestResultSizeDart>(
        'misakid_espeak_en_result_output_size',
      );
  final resultDestroy = library
      .lookupFunction<_TestResultDestroyNative, _TestResultDestroyDart>(
        'misakid_espeak_en_result_destroy',
      );

  Pointer<Uint8> copy(List<int> bytes) {
    final pointer = allocate(bytes.length);
    expect(pointer.address, isNot(0));
    if (bytes.isNotEmpty) pointer.asTypedList(bytes.length).setAll(0, bytes);
    return pointer;
  }

  final runtimeBytes = Uint8List.fromList(utf8.encode(runtimePath));
  final dataBytes = Uint8List.fromList(utf8.encode(dataPath));
  final runtime = copy(runtimeBytes);
  final data = copy(dataBytes);
  final context = create(
    runtime,
    runtimeBytes.length,
    data,
    dataBytes.length,
    32,
    1024,
  );
  free(runtime.cast<Void>());
  free(data.cast<Void>());
  expect(context.address, isNot(0));
  expect(contextStatus(context), 0);

  Pointer<_TestResult> call(List<int> bytes, int dialect) {
    final input = copy(bytes);
    try {
      final result = phonemize(context, input, bytes.length, dialect);
      expect(result.address, isNot(0));
      return result;
    } finally {
      free(input.cast<Void>());
    }
  }

  try {
    for (final probe in <(List<int>, int, int)>[
      (<int>[0x61, 0], 0, 3),
      (<int>[0xC0], 0, 3),
      (List<int>.filled(33, 0x61), 0, 2),
      (<int>[0x61], 2, 1),
    ]) {
      final result = call(probe.$1, probe.$2);
      try {
        expect(resultStatus(result), probe.$3);
      } finally {
        resultDestroy(result);
      }
    }

    final first = call(utf8.encode('blorptastic'), 0);
    try {
      expect(resultStatus(first), 0);
      final firstBytes = List<int>.of(
        resultData(first).asTypedList(resultSize(first)),
      );
      final second = call(utf8.encode('snorflegloop'), 1);
      try {
        expect(resultStatus(second), 0);
        expect(resultData(first).asTypedList(resultSize(first)), firstBytes);
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

Future<List<Map<String, Object?>>> _readFixtures() async {
  final directory = Directory(
    '../../test/fixtures/upstream/'
    'fba1236595f2d2bf21d414ba6e57d25256afada3',
  );
  final rows = <Map<String, Object?>>[];
  for (final name in <String>[
    'en_american_espeak_fallback.jsonl',
    'en_british_espeak_fallback.jsonl',
  ]) {
    await for (final line in File(
      '${directory.path}/$name',
    ).openRead().transform(utf8.decoder).transform(const LineSplitter())) {
      rows.add(jsonDecode(line) as Map<String, Object?>);
    }
  }
  return rows;
}
