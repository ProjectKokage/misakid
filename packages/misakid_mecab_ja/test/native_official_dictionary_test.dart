import 'dart:ffi';
import 'dart:io';

import 'package:misakid_mecab_ja/misakid_mecab_ja.dart';
import 'package:test/test.dart';

void main() {
  _defineOfficialDictionaryTests(
    label: 'official UniDic CWJ 2023.02',
    environmentName: 'MISAKID_MECAB_JA_CWJ_202302_DICTIONARY',
  );
  _defineOfficialDictionaryTests(
    label: 'official UniDic CSJ 2023.02',
    environmentName: 'MISAKID_MECAB_JA_CSJ_202302_DICTIONARY',
  );
}

void _defineOfficialDictionaryTests({
  required String label,
  required String environmentName,
}) {
  final dictionaryPath = Platform.environment[environmentName];
  final skipReason = dictionaryPath == null
      ? 'Set $environmentName to the extracted official dictionary directory.'
      : !_isSupportedHost
      ? 'The bundled native asset supports Android, iOS, and macOS.'
      : false;

  group(
    label,
    () {
      late MecabJapaneseCutletBackend backend;

      setUpAll(() async {
        backend = await MecabJapaneseCutletBackend.openBundledWithMembership(
          dictionaryPath: dictionaryPath!,
          wordMembership: _EmptyMembership(),
        );
      });

      tearDownAll(() => backend.close());

      test('reports layout compatibility without inferring identity', () {
        expect(
          backend.dictionaryProfile,
          MecabJapaneseDictionaryProfile.compatible,
        );
        expect(
          backend.dictionaryFeatureLayout,
          MecabJapaneseUnidicFeatureLayout.fields29,
        );
        expect(backend.info.version, '0.996');
        expect(backend.info.details['dictionaryProfile'], 'compatible');
        expect(backend.info.details['dictionaryCorpus'], 'unknown');
        expect(backend.info.details['dictionaryDistribution'], 'unknown');
        expect(backend.info.details['dictionaryIdentity'], 'unverified');
        expect(backend.info.details['dictionaryFeatureFieldCount'], '29');
        expect(
          backend.info.details['dictionaryFeatureLayoutSupport'],
          'unidic-features-26-29-v1',
        );
        expect(
          backend.info.details,
          isNot(contains('dictionaryReleaseMarker')),
        );
        expect(backend.info.details, isNot(contains('dictionaryTreeSha256')));

        final words = backend.analyzeRaw('講師');
        expect(words, hasLength(1));
        expect(words.single.surface, '講師');
        expect(words.single.isUnknown, isFalse);
        expect(words.single.pronunciation, 'コーシ');
        expect(words.single.kana, 'コウシ');
      });

      test('does not satisfy the pinned modified-CWJ identity', () async {
        await expectLater(
          MecabJapaneseCutletBackend.openBundledWithMembership(
            dictionaryPath: dictionaryPath!,
            wordMembership: _EmptyMembership(),
            dictionaryProfile:
                MecabJapaneseDictionaryProfile.pinnedUnidicPyCwjParity,
          ),
          throwsA(isA<MalformedDataException>()),
        );
      });
    },
    tags: 'native',
    skip: skipReason,
  );
}

final class _EmptyMembership implements JapaneseCutletWordMembership {
  @override
  final BackendInfo info = BackendInfo(
    name: 'empty-test-membership',
    version: '1',
  );

  @override
  bool contains(String surface) => false;
}

bool get _isSupportedHost {
  final abi = Abi.current();
  return (Platform.isAndroid &&
          (abi == Abi.androidArm ||
              abi == Abi.androidArm64 ||
              abi == Abi.androidX64)) ||
      (Platform.isIOS && (abi == Abi.iosArm64 || abi == Abi.iosX64)) ||
      (Platform.isMacOS && (abi == Abi.macosArm64 || abi == Abi.macosX64));
}
