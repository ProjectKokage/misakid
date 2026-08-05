import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:test/test.dart';

import '../hook/build.dart' as build_hook;

void main() {
  group('desktop native-assets tuples', () {
    test('accepts Linux x64/arm64 and Windows x64 only', () {
      expect(
        build_hook.supportsOpenJtalkNativeAssetTarget(
          OS.linux,
          Architecture.x64,
        ),
        isTrue,
      );
      expect(
        build_hook.supportsOpenJtalkNativeAssetTarget(
          OS.linux,
          Architecture.arm64,
        ),
        isTrue,
      );
      expect(
        build_hook.supportsOpenJtalkNativeAssetTarget(
          OS.windows,
          Architecture.x64,
        ),
        isTrue,
      );
      expect(
        build_hook.supportsOpenJtalkNativeAssetTarget(
          OS.windows,
          Architecture.arm64,
        ),
        isFalse,
      );
      expect(
        build_hook.supportsOpenJtalkNativeAssetTarget(
          OS.linux,
          Architecture.ia32,
        ),
        isFalse,
      );
    });

    test('rejects unsupported tuples before compiler execution', () {
      expect(
        () => build_hook.validateOpenJtalkNativeAssetTarget(
          OS.windows,
          Architecture.arm64,
        ),
        throwsA(
          isA<BuildError>().having(
            (error) => error.message,
            'message',
            allOf(contains('Windows is limited to x64'), contains('arm64')),
          ),
        ),
      );
    });

    test('requires a same-OS, same-architecture desktop host', () {
      expect(
        () => build_hook.validateOpenJtalkDesktopBuildHost(
          OS.linux,
          Architecture.x64,
          OS.linux,
          Architecture.x64,
        ),
        returnsNormally,
      );
      expect(
        () => build_hook.validateOpenJtalkDesktopBuildHost(
          OS.windows,
          Architecture.x64,
          OS.windows,
          Architecture.x64,
        ),
        returnsNormally,
      );
      expect(
        () => build_hook.validateOpenJtalkDesktopBuildHost(
          OS.windows,
          Architecture.x64,
          OS.linux,
          Architecture.x64,
        ),
        throwsA(
          isA<BuildError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('require a native windows-x64 host'),
              contains('linux-x64'),
            ),
          ),
        ),
      );
      expect(
        () => build_hook.validateOpenJtalkDesktopBuildHost(
          OS.linux,
          Architecture.arm64,
          OS.linux,
          Architecture.x64,
        ),
        throwsA(
          isA<BuildError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('require a native linux-arm64 host'),
              contains('linux-x64'),
            ),
          ),
        ),
      );
      expect(
        () => build_hook.validateOpenJtalkDesktopBuildHost(
          OS.macOS,
          Architecture.x64,
          OS.macOS,
          Architecture.arm64,
        ),
        returnsNormally,
      );
    });
  });

  group('desktop compiler policy', () {
    test('keeps MSVC and clang/GCC flags separate', () {
      final windowsC = build_hook.openJtalkFrontendCompilerFlags(
        OS.windows,
        r'C:\source\misakid_openjtalk',
      );
      final windowsCpp = build_hook.openJtalkAdapterCompilerFlags(
        OS.windows,
        r'C:\source\misakid_openjtalk',
        r'C:\source\exports_android.map',
      );
      final linuxC = build_hook.openJtalkFrontendCompilerFlags(
        OS.linux,
        '/source/misakid_openjtalk',
      );
      final linuxCpp = build_hook.openJtalkAdapterCompilerFlags(
        OS.linux,
        '/source/misakid_openjtalk',
        '/source/exports_android.map',
      );

      expect(windowsC, containsAll(<String>['/utf-8', '/Gy', '/Gw']));
      expect(windowsCpp, contains('/EHsc'));
      expect(
        windowsC.followedBy(windowsCpp),
        isNot(contains(startsWith('-f'))),
      );
      expect(linuxC, contains('-fsigned-char'));
      expect(linuxCpp, contains('-Wl,--gc-sections'));
      expect(linuxCpp, contains('-Wl,-soname,libmisakid_openjtalk.so'));
      expect(
        linuxCpp,
        contains('-Wl,--version-script=/source/exports_android.map'),
      );
      expect(linuxC.followedBy(linuxCpp), isNot(contains(startsWith('/'))));
    });

    test('requires cl.exe when Windows supplies an explicit compiler', () {
      expect(
        () => build_hook.validateOpenJtalkWindowsCompiler(
          OS.windows,
          Uri.file(
            r'C:\Program Files\Microsoft Visual Studio\cl.exe',
            windows: true,
          ),
        ),
        returnsNormally,
      );
      expect(
        () => build_hook.validateOpenJtalkWindowsCompiler(
          OS.windows,
          Uri.file(r'C:\LLVM\bin\clang.exe', windows: true),
        ),
        throwsA(
          isA<BuildError>().having(
            (error) => error.message,
            'message',
            contains('MSVC cl.exe'),
          ),
        ),
      );
      expect(
        () => build_hook.validateOpenJtalkWindowsCompiler(
          OS.linux,
          Uri.file('/usr/bin/clang'),
        ),
        returnsNormally,
      );
    });

    test('uses the platform null device', () {
      expect(build_hook.openJtalkMecabDefaultRc(OS.windows), '"NUL"');
      expect(build_hook.openJtalkMecabDefaultRc(OS.linux), '"/dev/null"');
    });
  });

  group('Windows portability boundary', () {
    test('selects Win32 facilities without Unix feature macros', () {
      final config = File('native/portable/config.h').readAsStringSync();
      final windowsBlock = config.substring(
        config.indexOf('#if defined(_WIN32)'),
        config.indexOf('#else', config.indexOf('#if defined(_WIN32)')),
      );

      expect(windowsBlock, contains('#define HAVE_WINDOWS_H 1'));
      expect(windowsBlock, contains('#define SIZEOF_LONG 4'));
      expect(windowsBlock, contains('#define SIZEOF_SIZE_T 8'));
      expect(windowsBlock, isNot(contains('#define HAVE_PTHREAD_H')));
      expect(windowsBlock, isNot(contains('#define HAVE_MMAP')));
      expect(windowsBlock, isNot(contains('#define HAVE_GCC_ATOMIC_OPS')));
      expect(windowsBlock, isNot(contains('#define HAVE_TLS_KEYWORD')));
      expect(
        windowsBlock,
        isNot(contains('#define HAVE_UNSIGNED_LONG_LONG_INT')),
      );
      expect(windowsBlock, isNot(contains('__SIZEOF_')));
    });

    test('strictly converts UTF-8 paths before Win32 file mapping', () {
      final header = File('native/src/silent_stdio.h').readAsStringSync();
      final source = File('native/src/silent_stdio.c').readAsStringSync();
      final vendoredMmap = File(
        'native/vendor/open_jtalk/mecab/src/mmap.h',
      ).readAsStringSync();

      expect(vendoredMmap, contains('::CreateFileA(filename'));
      expect(header, contains('#define NOMINMAX'));
      expect(header, contains('#undef ERROR'));
      expect(header, contains('#define strdup _strdup'));
      expect(
        header,
        contains('#define CreateFileA misakid_openjtalk_create_file_utf8'),
      );
      expect(source, contains('MB_ERR_INVALID_CHARS'));
      expect(source, contains(r'L"\\\\?\\"'));
      expect(source, contains(r'L"\\\\?\\UNC\\"'));
      expect(source, contains('path[index] = L'));
      expect(source, contains('CreateFileW(extended_filename'));
      expect(source, contains('ERROR_FILENAME_EXCED_RANGE'));
      expect(source, contains('ERROR_BAD_PATHNAME'));
    });
  });
}
