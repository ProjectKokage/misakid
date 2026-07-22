import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:misakid_mecab_ja/misakid_mecab_ja.dart';
import 'package:test/test.dart';

const _unidicLiteRuntimeManifest = <String, ({int size, String sha256})>{
  'char.bin': (
    size: 262496,
    sha256: 'dd31396563d8924645b80fd3c9aa7b13ca089d7748f25553a1d6bc3f9b511ae8',
  ),
  'dicrc': (
    size: 1444,
    sha256: 'fcd17f35752de1417859a15e2e1f043d666da03f36dc632e8c0ed46887883a59',
  ),
  'matrix.bin': (
    size: 71544726,
    sha256: '88fb99efe1075d9b8b40e01bb2751e4095f1612618f2490af776eb5ed39190a9',
  ),
  'sys.dic': (
    size: 187680870,
    sha256: '122c4c91f026bf4b65bbe2dfd8b9f8eeb6ab56d8eb2a7287a68bca75708ba513',
  ),
  'unk.dic': (
    size: 5475,
    sha256: 'e3b92803feeb6c2712c796b905317ec192a59729d2c1e92b2728d454169541c4',
  ),
};

void main() {
  final dictionaryPath =
      Platform.environment['MISAKID_MECAB_JA_COMPATIBLE_DICTIONARY'];

  test(
    'default profile accepts the unidic-lite 26-field layout',
    () async {
      for (final entry in _unidicLiteRuntimeManifest.entries) {
        final file = File(
          '$dictionaryPath${Platform.pathSeparator}${entry.key}',
        );
        expect(await file.length(), entry.value.size, reason: entry.key);
        expect(
          (await sha256.bind(file.openRead()).first).toString(),
          entry.value.sha256,
          reason: entry.key,
        );
      }
      final backend =
          await MecabJapaneseCutletBackend.openBundledWithMembership(
            dictionaryPath: dictionaryPath!,
            wordMembership: _EmptyMembership(),
          );
      try {
        expect(
          backend.dictionaryProfile,
          MecabJapaneseDictionaryProfile.compatible,
        );
        expect(
          backend.dictionaryFeatureLayout,
          MecabJapaneseUnidicFeatureLayout.fields26,
        );
        expect(backend.info.version, '0.996');
        expect(backend.info.details['dictionaryProfile'], 'compatible');
        expect(backend.info.details['dictionaryCorpus'], 'unknown');
        expect(backend.info.details['dictionaryDistribution'], 'unknown');
        expect(backend.info.details['dictionaryIdentity'], 'unverified');
        expect(backend.info.details['dictionaryFeatureFieldCount'], '26');
        expect(
          backend.info.details,
          isNot(contains('dictionaryReleaseMarker')),
        );
        expect(backend.info.details, isNot(contains('dictionaryTreeSha256')));
        expect(
          backend.info.details['dictionaryFeatureLayoutSupport'],
          'unidic-features-26-29-v1',
        );

        final words = backend.analyzeRaw('日本');
        expect(words, hasLength(1));
        expect(words.single.surface, '日本');
        expect(words.single.pronunciation, 'ニッポン');
        expect(words.single.kana, 'ニッポン');

        final unknown = backend.analyzeRaw('𠮷');
        expect(unknown, hasLength(1));
        expect(unknown.single.isUnknown, isTrue);
        expect(unknown.single.pronunciation, isNull);
        expect(unknown.single.kana, isNull);
      } finally {
        backend.close();
      }
    },
    tags: 'native',
    skip: dictionaryPath == null
        ? 'Set MISAKID_MECAB_JA_COMPATIBLE_DICTIONARY to the tested unidic-lite 2.1.2 directory.'
        : !_isSupportedHost
        ? 'The bundled native asset supports Android, iOS, and macOS.'
        : false,
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
