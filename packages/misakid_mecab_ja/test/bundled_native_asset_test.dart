import 'dart:ffi';
import 'dart:io';

import 'package:misakid_mecab_ja/src/native_bindings.dart';
import 'package:test/test.dart';

void main() {
  test(
    'bundled native asset exports the exact reviewed ABI identity',
    () {
      final library = MecabJapaneseNativeLibrary.loadBundled();
      expect(library.identities, expectedMecabJapaneseNativeIdentities);
    },
    skip: _isSupportedHost
        ? false
        : 'The build-hook native asset supports Android, iOS, and macOS.',
  );
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
