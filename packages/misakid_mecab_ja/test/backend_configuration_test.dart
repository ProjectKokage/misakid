import 'dart:ffi';
import 'dart:io';

import 'package:misakid_mecab_ja/misakid_mecab_ja.dart';
import 'package:test/test.dart';

void main() {
  final membership = _Membership();

  test('rejects relative resource paths before platform or I/O', () async {
    await expectLater(
      MecabJapaneseCutletBackend.open(
        libraryPath: 'library',
        dictionaryPath: '/dictionary',
        wordListPath: '/words',
      ),
      throwsA(isA<InvalidConfigurationException>()),
    );
    await expectLater(
      MecabJapaneseCutletBackend.openWithMembership(
        libraryPath: '/library',
        dictionaryPath: 'dictionary',
        wordMembership: membership,
      ),
      throwsA(isA<InvalidConfigurationException>()),
    );
    await expectLater(
      MecabJapaneseCutletBackend.openBundledWithMembership(
        dictionaryPath: 'dictionary',
        wordMembership: membership,
      ),
      throwsA(isA<InvalidConfigurationException>()),
    );
  });

  test('rejects invalid input limits before platform or I/O', () async {
    for (final limit in <int>[0, 64 * 1024 * 1024 + 1]) {
      await expectLater(
        MecabJapaneseCutletBackend.openWithMembership(
          libraryPath: '/library',
          dictionaryPath: '/dictionary',
          wordMembership: membership,
          maxInputBytes: limit,
        ),
        throwsA(isA<InvalidConfigurationException>()),
      );
      await expectLater(
        MecabJapaneseCutletBackend.openBundledWithMembership(
          dictionaryPath: '/dictionary',
          wordMembership: membership,
          maxInputBytes: limit,
        ),
        throwsA(isA<InvalidConfigurationException>()),
      );
    }
  });

  test('publishes the exact bundled target operating systems', () {
    expect(mecabJapaneseBundledBuildPlatforms, <String>{
      'android',
      'ios',
      'macos',
    });
    expect(
      () => mecabJapaneseBundledBuildPlatforms.add('linux'),
      throwsUnsupportedError,
    );
  });

  test('publishes only provisioned UniDic feature layouts', () {
    expect(
      MecabJapaneseUnidicFeatureLayout.values,
      <MecabJapaneseUnidicFeatureLayout>[
        MecabJapaneseUnidicFeatureLayout.fields26,
        MecabJapaneseUnidicFeatureLayout.fields29,
      ],
    );
  });

  test(
    'unsupported platform fails before reading any configured resource',
    () async {
      await expectLater(
        MecabJapaneseCutletBackend.open(
          libraryPath: '/definitely/missing/library',
          dictionaryPath: '/definitely/missing/dictionary',
          wordListPath: '/definitely/missing/words',
        ),
        throwsA(isA<BackendUnavailableException>()),
      );
      await expectLater(
        MecabJapaneseCutletBackend.openWithMembership(
          libraryPath: '/definitely/missing/library',
          dictionaryPath: '/definitely/missing/dictionary',
          wordMembership: membership,
        ),
        throwsA(isA<BackendUnavailableException>()),
      );
    },
    skip: Platform.isMacOS && Abi.current() == Abi.macosArm64
        ? 'This host is the supported native tuple.'
        : false,
  );

  test('raw record preserves nullable readings and literal star', () {
    const unknown = MecabJapaneseRawWord(
      surface: 'ABC',
      pronunciation: null,
      kana: null,
      charType: 5,
      isUnknown: true,
    );
    const symbol = MecabJapaneseRawWord(
      surface: '・',
      pronunciation: '*',
      kana: '・',
      charType: 7,
      isUnknown: false,
    );
    expect(unknown.pronunciation, isNull);
    expect(unknown.kana, isNull);
    expect(symbol.pronunciation, '*');
    expect(symbol.kana, '・');
  });
}

final class _Membership implements JapaneseCutletWordMembership {
  @override
  final BackendInfo info = BackendInfo(name: 'test', version: '1');

  @override
  bool contains(String surface) => false;
}
