import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:misakid_spacy_trf_en/misakid_spacy_trf_en.dart';
import 'package:misakid_spacy_trf_en/src/native_bindings.dart';
import 'package:misakid_spacy_trf_en/src/resource_identity.dart';
import 'package:misakid_spacy_trf_en/src/tagger_head.dart';
import 'package:test/test.dart';

void main() {
  final modelDirectory =
      Platform.environment['MISAKID_SPACY_TRF_EN_MODEL_DIR'] ??
      Platform.environment['MISAKI_SPACY_TRF_EN_MODEL_DIR'];
  final nativeLibraryPath =
      Platform.environment['MISAKID_SPACY_TRF_EN_LIBRARY'];
  final skipReason = modelDirectory == null || nativeLibraryPath == null
      ? 'Set MISAKID_SPACY_TRF_EN_MODEL_DIR and '
            'MISAKID_SPACY_TRF_EN_LIBRARY.'
      : false;

  group(
    'provisioned native transformer',
    () {
      late Directory packageRoot;
      late SpacyTransformerNativeLibrary library;
      late SpacyTransformerNativeContext lowLevelContext;
      late NativeSpacyTransformerEnglishTokenizerBackend backend;

      setUpAll(() async {
        final packageLibrary = await Isolate.resolvePackageUri(
          Uri.parse('package:misakid_spacy_trf_en/misakid_spacy_trf_en.dart'),
        );
        if (packageLibrary == null) {
          throw StateError('Could not resolve the package root.');
        }
        packageRoot = File.fromUri(packageLibrary).parent.parent;

        library = SpacyTransformerNativeLibrary.load(nativeLibraryPath!);
        final resources = await SpacyTransformerResourceSnapshot.validate(
          modelDirectory!,
        );
        final head = SpacyTransformerTaggerHead.decode(
          resources.taggerModelBytes,
        );
        lowLevelContext = SpacyTransformerNativeContext.create(
          library: library,
          transformerModelPath: resources.transformerModelPath,
          taggerWeights: head.copyWeights(),
          taggerBiases: head.copyBiases(),
        );
        backend = await NativeSpacyTransformerEnglishTokenizerBackend.open(
          modelDirectoryPath: modelDirectory,
          nativeLibraryPath: nativeLibraryPath,
        );
      });

      tearDownAll(() {
        lowLevelContext.close();
        backend.close();
      });

      test(
        'exports only the reviewed ABI and links no model runtime',
        () async {
          expect(library.identities, expectedSpacyTransformerNativeIdentities);

          final expectedExports = File(
            '${packageRoot.path}/native/expected_exports_macos.txt',
          ).readAsLinesSync();
          final nm = await Process.run('nm', <String>[
            '-gjU',
            nativeLibraryPath!,
          ]);
          expect(nm.exitCode, 0, reason: '${nm.stdout}${nm.stderr}');
          final actualExports = ('${nm.stdout}').trim().split('\n');
          expect(actualExports, expectedExports);

          final dependencies = await Process.run('otool', <String>[
            '-L',
            nativeLibraryPath,
          ]);
          expect(
            dependencies.exitCode,
            0,
            reason: '${dependencies.stdout}${dependencies.stderr}',
          );
          final linked = '${dependencies.stdout}';
          expect(linked, contains('Accelerate.framework'));
          expect(
            linked,
            isNot(matches(RegExp(r'python|torch', caseSensitive: false))),
          );
        },
      );

      test('matches all 38 pinned transformer tag fixtures exactly', () async {
        final fixture = File(
          '${packageRoot.parent.parent.path}/test/fixtures/upstream/'
          'fba1236595f2d2bf21d414ba6e57d25256afada3/'
          'en_american_trf_no_fallback.jsonl',
        );
        final records = await fixture.readAsLines();
        expect(records, hasLength(38));
        const preprocessor = EnglishInlinePreprocessor();

        for (final line in records) {
          final record = jsonDecode(line) as Map<String, Object?>;
          final caseId = record['caseId']! as String;
          final input = preprocessor.preprocess(record['input']! as String);
          final backendInput = record['backendInput']! as Map<String, Object?>;
          final expectedPreprocess =
              backendInput['preprocess']! as Map<String, Object?>;
          expect(input.text, expectedPreprocess['text'], reason: caseId);

          final expectedTokens = backendInput['tokens']! as List<Object?>;
          final actualTokens = backend.tokenize(input);
          expect(
            actualTokens,
            hasLength(expectedTokens.length),
            reason: caseId,
          );
          for (var index = 0; index < expectedTokens.length; index++) {
            final expected = expectedTokens[index]! as Map<String, Object?>;
            final actual = actualTokens[index];
            expect(
              actual.text,
              expected['text'],
              reason: '$caseId token $index',
            );
            expect(actual.tag, expected['tag'], reason: '$caseId token $index');
            expect(
              actual.whitespace,
              expected['whitespace'],
              reason: '$caseId token $index',
            );
          }
        }
      });

      test('owns results and rejects malformed native inputs safely', () {
        expect(
          lowLevelContext.infer(
            pieceIds: Uint32List.fromList(<int>[0, 2]),
            tokenPieceLengths: Uint32List(0),
          ),
          isEmpty,
        );

        for (final input in <({List<int> ids, List<int> lengths})>[
          (ids: <int>[1, 2], lengths: <int>[]),
          (ids: <int>[0, 50265, 2], lengths: <int>[1]),
          (ids: <int>[0, 31414, 232, 2], lengths: <int>[1]),
          (ids: <int>[0, 31414, 2], lengths: <int>[0xffffffff]),
        ]) {
          expect(
            () => lowLevelContext.infer(
              pieceIds: Uint32List.fromList(input.ids),
              tokenPieceLengths: Uint32List.fromList(input.lengths),
            ),
            throwsA(
              isA<SpacyTransformerNativeException>()
                  .having((error) => error.code, 'code', 1)
                  .having((error) => error.stage, 'stage', 'input'),
            ),
          );
        }

        lowLevelContext.close();
        expect(
          () => lowLevelContext.infer(
            pieceIds: Uint32List.fromList(<int>[0, 2]),
            tokenPieceLengths: Uint32List(0),
          ),
          throwsA(
            isA<SpacyTransformerNativeException>().having(
              (error) => error.stage,
              'stage',
              'lifecycle',
            ),
          ),
        );
      });
    },
    tags: 'provisioned',
    skip: skipReason,
  );
}
