import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:misakid_mecab_ko/misakid_mecab_ko.dart';
import 'package:misakid_mecab_ko/src/dictionary_identity.dart';
import 'package:misakid_mecab_ko/src/native_bindings.dart';
import 'package:test/test.dart';

void main() {
  final libraryPath = Platform.environment['MISAKID_MECAB_KO_LIBRARY'];
  final dictionaryPath = Platform.environment['MISAKID_MECAB_KO_DICTIONARY'];
  final cmuDictionaryPath = Platform.environment['MISAKID_MECAB_KO_CMUDICT'];
  final skipReason =
      libraryPath == null || dictionaryPath == null || cmuDictionaryPath == null
      ? 'Set MISAKID_MECAB_KO_LIBRARY, MISAKID_MECAB_KO_DICTIONARY, '
            'and MISAKID_MECAB_KO_CMUDICT.'
      : false;

  group(
    'provisioned macOS arm64 adapter',
    () {
      late List<Map<String, Object?>> fixtures;
      late MecabKoNativeLibrary library;
      late MecabKoMorphologyBackend morphology;
      late CmuDictionaryPronunciationProvider cmu;

      setUpAll(() async {
        fixtures = await _readFixtures();
        library = MecabKoNativeLibrary.load(libraryPath!);
        morphology = await MecabKoMorphologyBackend.open(
          libraryPath: libraryPath,
          dictionaryPath: dictionaryPath!,
        );
        cmu = await CmuDictionaryPronunciationProvider.open(cmuDictionaryPath!);
      });

      tearDownAll(() {
        morphology.close();
        morphology.close();
        expect(morphology.isClosed, isTrue);
        expect(
          () => morphology.pos('안녕'),
          throwsA(isA<BackendUnavailableException>()),
        );
      });

      test('reports exact immutable identities', () {
        expect(library.identities, expectedMecabKoNativeIdentities);
        expect(morphology.info.name, 'python-mecab-ko');
        expect(morphology.info.version, '1.3.7');
        expect(morphology.info.details['platform'], 'macos-arm64');
        expect(
          morphology.info.details['dictionaryTreeSha256'],
          mecabKoDictionaryTreeSha256,
        );
        expect(cmu.info.name, 'cmudict');
        expect(cmu.info.version, '0.7a');
      });

      test('all 34 morphology streams and 293 tokens match the oracle', () {
        var tokenCount = 0;
        for (final fixture in fixtures) {
          final caseId = _string(fixture, 'caseId');
          final backendInput = _map(
            fixture['backendInput'],
            '$caseId backendInput',
          );
          final expectedTokens = _list(
            backendInput['tokens'],
            '$caseId tokens',
          );
          final actual = morphology.pos(_string(backendInput, 'input'));
          expect(actual, hasLength(expectedTokens.length), reason: caseId);
          tokenCount += actual.length;
          for (var index = 0; index < actual.length; index++) {
            final expected = _map(
              expectedTokens[index],
              '$caseId token $index',
            );
            expect(actual[index].surface, expected['surface'], reason: caseId);
            expect(actual[index].tag, expected['tag'], reason: caseId);
          }
        }
        expect(fixtures, hasLength(34));
        expect(tokenCount, 293);
      });

      test('all 23 captured CMUdict lookups match', () {
        var lookupCount = 0;
        var hitCount = 0;
        for (final fixture in fixtures) {
          final caseId = _string(fixture, 'caseId');
          final backendInput = _map(
            fixture['backendInput'],
            '$caseId backendInput',
          );
          for (final rawLookup in _list(
            backendInput['cmuLookups'],
            '$caseId cmuLookups',
          )) {
            final lookup = _map(rawLookup, '$caseId CMU lookup');
            final actual = cmu.lookup(_string(lookup, 'key'));
            final rawArpabet = lookup['arpabet'];
            if (rawArpabet == null) {
              expect(actual, isNull, reason: caseId);
            } else {
              final expected = _list(rawArpabet, '$caseId arpabet')
                  .map((phone) => _objectString(phone, '$caseId phone'))
                  .toList(growable: false);
              expect(actual?.arpabet, expected, reason: caseId);
              hitCount++;
            }
            lookupCount++;
          }
        }
        expect(lookupCount, 23);
        expect(hitCount, 22);
      });

      test('all 33 outputs and the pinned failure match original Misaki', () {
        final engine = KoreanG2pkcEngine(
          morphology: morphology,
          cmuPronunciations: cmu,
        );
        var successCount = 0;
        for (final fixture in fixtures) {
          final caseId = _string(fixture, 'caseId');
          final input = _string(fixture, 'input');
          if (fixture['error'] != null) {
            expect(
              () => engine.convert(input),
              throwsA(isA<InvalidConfigurationException>()),
              reason: caseId,
            );
            continue;
          }
          final actual = engine.convert(input);
          expect(actual.phonemes, fixture['phonemes'], reason: caseId);
          expect(actual.tokens, isNull, reason: caseId);
          successCount++;
        }
        expect(successCount, 33);
      });

      test('copied results survive later calls and close is deterministic', () {
        final snapshot = morphology.pos('한국어를 읽는다.');
        final firstSurface = snapshot.first.surface;
        morphology.pos('안녕하세요.');
        expect(snapshot.first.surface, firstSurface);

        final disposable = MecabKoNativeAnalyzer.create(
          library: library,
          dictionaryPath: dictionaryPath!,
          maxInputBytes: 3,
        );
        expect(disposable.analyzeRaw('한'), isNotEmpty);
        expect(
          () => disposable.analyzeRaw('한a'),
          throwsA(
            isA<MecabKoNativeException>().having(
              (error) => error.code,
              'code',
              2,
            ),
          ),
        );
        expect(
          () => disposable.analyzeRaw('한\u0000글'),
          throwsA(isA<MecabKoNativeException>()),
        );
        expect(
          () => disposable.analyzeRaw(String.fromCharCode(0xD800)),
          throwsA(isA<MecabKoNativeException>()),
        );
        disposable.close();
        disposable.close();
        expect(disposable.isClosed, isTrue);
        expect(
          () => disposable.analyzeRaw('한'),
          throwsA(isA<MecabKoNativeException>()),
        );
      });

      test('native result storage is owned across later analysis', () {
        final abi = _RawMecabKoAbi(DynamicLibrary.open(libraryPath!));
        final context = abi.createContext(dictionaryPath!);
        Pointer<_RawResult>? first;
        Pointer<_RawResult>? second;
        try {
          first = abi.analyze(context, utf8.encode('한국어'));
          expect(abi.resultStatus(first), 0);
          expect(abi.resultTokenCount(first), greaterThan(0));
          final expected = abi.readTokenField(first, 0, 0);

          second = abi.analyze(context, utf8.encode('안녕하세요.'));
          expect(abi.resultStatus(second), 0);
          expect(abi.readTokenField(first, 0, 0), expected);
          expect(expected, '한국어');
        } finally {
          if (second != null) abi.resultDestroy(second);
          if (first != null) abi.resultDestroy(first);
          abi.contextDestroy(context);
        }
      });

      test('native ABI independently rejects malformed bytes and NUL', () {
        final abi = _RawMecabKoAbi(DynamicLibrary.open(libraryPath!));
        final context = abi.createContext(dictionaryPath!, maxInputBytes: 3);
        try {
          final cases = <({List<int> bytes, int status})>[
            (bytes: <int>[0xC0, 0xAF], status: 3),
            (bytes: <int>[0x61, 0x00, 0x62], status: 1),
            (bytes: <int>[0x61, 0x62, 0x63, 0x64], status: 2),
          ];
          for (final invalid in cases) {
            final result = abi.analyze(context, invalid.bytes);
            try {
              expect(abi.resultStatus(result), invalid.status);
            } finally {
              abi.resultDestroy(result);
            }
          }
        } finally {
          abi.contextDestroy(context);
        }
      });

      test(
        'the process-global native lock supports concurrent isolates',
        () async {
          final outputs = await Future.wait(<Future<String>>[
            for (var index = 0; index < 4; index++)
              _analyzeInIsolate(libraryPath!, dictionaryPath!),
          ]);
          expect(outputs, everyElement('한국어'));
        },
      );

      test(
        'native success and failure paths do not write process stdio',
        () async {
          final result = await Process.run(
            Platform.resolvedExecutable,
            <String>[
              'run',
              'tool/native_silence_smoke.dart',
              libraryPath!,
              dictionaryPath!,
            ],
            workingDirectory: Directory.current.path,
          );
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

Future<String> _analyzeInIsolate(String libraryPath, String dictionaryPath) =>
    Isolate.run(() {
      final library = MecabKoNativeLibrary.load(libraryPath);
      final analyzer = MecabKoNativeAnalyzer.create(
        library: library,
        dictionaryPath: dictionaryPath,
        maxInputBytes: defaultMecabKoMaxInputBytes,
      );
      try {
        return analyzer.analyzeRaw('한국어').map((token) => token.surface).join();
      } finally {
        analyzer.close();
      }
    });

Future<List<Map<String, Object?>>> _readFixtures() async {
  final file = File(
    '../../test/fixtures/upstream/'
    'fba1236595f2d2bf21d414ba6e57d25256afada3/'
    'ko_g2pkc_default.jsonl',
  );
  final rows = <Map<String, Object?>>[];
  await for (final line
      in file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    rows.add(_map(jsonDecode(line), 'fixture row'));
  }
  return rows;
}

Map<String, Object?> _map(Object? value, String location) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$location must be an object.');
  }
  return value;
}

List<Object?> _list(Object? value, String location) {
  if (value is! List<Object?>) {
    throw FormatException('$location must be a list.');
  }
  return value;
}

String _string(Map<String, Object?> value, String key) =>
    _objectString(value[key], key);

String _objectString(Object? value, String location) {
  if (value is! String) {
    throw FormatException('$location must be a string.');
  }
  return value;
}

final class _RawContext extends Opaque {}

final class _RawResult extends Opaque {}

typedef _RawBufferAllocNative = Pointer<Uint8> Function(Size);
typedef _RawBufferAllocDart = Pointer<Uint8> Function(int);
typedef _RawBufferFreeNative = Void Function(Pointer<Void>);
typedef _RawBufferFreeDart = void Function(Pointer<Void>);
typedef _RawContextCreateNative =
    Pointer<_RawContext> Function(Pointer<Uint8>, Size, Size);
typedef _RawContextCreateDart =
    Pointer<_RawContext> Function(Pointer<Uint8>, int, int);
typedef _RawContextStatusNative = Uint32 Function(Pointer<_RawContext>);
typedef _RawContextStatusDart = int Function(Pointer<_RawContext>);
typedef _RawContextDestroyNative = Void Function(Pointer<_RawContext>);
typedef _RawContextDestroyDart = void Function(Pointer<_RawContext>);
typedef _RawAnalyzeNative =
    Pointer<_RawResult> Function(Pointer<_RawContext>, Pointer<Uint8>, Size);
typedef _RawAnalyzeDart =
    Pointer<_RawResult> Function(Pointer<_RawContext>, Pointer<Uint8>, int);
typedef _RawResultStatusNative = Uint32 Function(Pointer<_RawResult>);
typedef _RawResultStatusDart = int Function(Pointer<_RawResult>);
typedef _RawResultCountNative = Size Function(Pointer<_RawResult>);
typedef _RawResultCountDart = int Function(Pointer<_RawResult>);
typedef _RawResultDataNative =
    Pointer<Uint8> Function(Pointer<_RawResult>, Size, Uint32);
typedef _RawResultDataDart =
    Pointer<Uint8> Function(Pointer<_RawResult>, int, int);
typedef _RawResultSizeNative = Size Function(Pointer<_RawResult>, Size, Uint32);
typedef _RawResultSizeDart = int Function(Pointer<_RawResult>, int, int);
typedef _RawResultDestroyNative = Void Function(Pointer<_RawResult>);
typedef _RawResultDestroyDart = void Function(Pointer<_RawResult>);

final class _RawMecabKoAbi {
  _RawMecabKoAbi(DynamicLibrary library)
    : bufferAlloc = library
          .lookupFunction<_RawBufferAllocNative, _RawBufferAllocDart>(
            'misakid_mecab_ko_buffer_alloc',
          ),
      bufferFree = library
          .lookupFunction<_RawBufferFreeNative, _RawBufferFreeDart>(
            'misakid_mecab_ko_buffer_free',
          ),
      contextCreate = library
          .lookupFunction<_RawContextCreateNative, _RawContextCreateDart>(
            'misakid_mecab_ko_context_create',
          ),
      contextStatus = library
          .lookupFunction<_RawContextStatusNative, _RawContextStatusDart>(
            'misakid_mecab_ko_context_status',
          ),
      contextDestroy = library
          .lookupFunction<_RawContextDestroyNative, _RawContextDestroyDart>(
            'misakid_mecab_ko_context_destroy',
          ),
      analyzeRaw = library.lookupFunction<_RawAnalyzeNative, _RawAnalyzeDart>(
        'misakid_mecab_ko_analyze',
      ),
      resultStatus = library
          .lookupFunction<_RawResultStatusNative, _RawResultStatusDart>(
            'misakid_mecab_ko_result_status',
          ),
      resultTokenCount = library
          .lookupFunction<_RawResultCountNative, _RawResultCountDart>(
            'misakid_mecab_ko_result_token_count',
          ),
      resultTokenData = library
          .lookupFunction<_RawResultDataNative, _RawResultDataDart>(
            'misakid_mecab_ko_result_token_string_data',
          ),
      resultTokenSize = library
          .lookupFunction<_RawResultSizeNative, _RawResultSizeDart>(
            'misakid_mecab_ko_result_token_string_size',
          ),
      resultDestroy = library
          .lookupFunction<_RawResultDestroyNative, _RawResultDestroyDart>(
            'misakid_mecab_ko_result_destroy',
          );

  final _RawBufferAllocDart bufferAlloc;
  final _RawBufferFreeDart bufferFree;
  final _RawContextCreateDart contextCreate;
  final _RawContextStatusDart contextStatus;
  final _RawContextDestroyDart contextDestroy;
  final _RawAnalyzeDart analyzeRaw;
  final _RawResultStatusDart resultStatus;
  final _RawResultCountDart resultTokenCount;
  final _RawResultDataDart resultTokenData;
  final _RawResultSizeDart resultTokenSize;
  final _RawResultDestroyDart resultDestroy;

  Pointer<_RawContext> createContext(
    String dictionaryPath, {
    int maxInputBytes = defaultMecabKoMaxInputBytes,
  }) {
    final path = _copy(utf8.encode(dictionaryPath));
    try {
      final context = contextCreate(
        path,
        utf8.encode(dictionaryPath).length,
        maxInputBytes,
      );
      expect(context.address, isNot(0));
      expect(contextStatus(context), 0);
      return context;
    } finally {
      bufferFree(path.cast<Void>());
    }
  }

  Pointer<_RawResult> analyze(Pointer<_RawContext> context, List<int> bytes) {
    final input = _copy(bytes);
    try {
      final result = analyzeRaw(context, input, bytes.length);
      expect(result.address, isNot(0));
      return result;
    } finally {
      bufferFree(input.cast<Void>());
    }
  }

  String readTokenField(Pointer<_RawResult> result, int index, int field) {
    final size = resultTokenSize(result, index, field);
    final data = resultTokenData(result, index, field);
    if (size == 0) return '';
    expect(data.address, isNot(0));
    return utf8.decode(data.asTypedList(size), allowMalformed: false);
  }

  Pointer<Uint8> _copy(List<int> bytes) {
    final result = bufferAlloc(bytes.length);
    expect(result.address, isNot(0));
    if (bytes.isNotEmpty) {
      result.asTypedList(bytes.length).setAll(0, Uint8List.fromList(bytes));
    }
    return result;
  }
}
