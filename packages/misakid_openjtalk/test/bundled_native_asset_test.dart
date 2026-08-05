import 'dart:ffi';
import 'dart:io';

import 'package:misakid_openjtalk/src/native_bindings.dart';
import 'package:test/test.dart';

void main() {
  test(
    'bundled native asset exports the exact reviewed ABI identity',
    () {
      final library = OpenJtalkNativeLibrary.loadBundled();
      expect(library.identities, expectedOpenJtalkNativeIdentities);
    },
    skip: _isSupportedHost
        ? false
        : 'The build-hook native asset does not support this host ABI.',
  );
}

bool get _isSupportedHost {
  final abi = Abi.current();
  return (Platform.isAndroid &&
          (abi == Abi.androidArm ||
              abi == Abi.androidArm64 ||
              abi == Abi.androidX64)) ||
      (Platform.isIOS && (abi == Abi.iosArm64 || abi == Abi.iosX64)) ||
      (Platform.isMacOS && (abi == Abi.macosArm64 || abi == Abi.macosX64)) ||
      (Platform.isLinux && (abi == Abi.linuxArm64 || abi == Abi.linuxX64)) ||
      (Platform.isWindows && abi == Abi.windowsX64);
}
