import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

const _manifestSha256 =
    'aecff2bb262b0b9aeb554af63ecaa3f02e6e87b28f6e8c2440e5ec24acd52589';

void main() {
  test(
    'canonical manifest and generated C++ table have one exact identity',
    () {
      final manifestFile = File('tool/native_tensor_manifest.json');
      final manifestBytes = manifestFile.readAsBytesSync();
      expect(sha256.convert(manifestBytes).toString(), _manifestSha256);

      final manifest =
          jsonDecode(utf8.decode(manifestBytes)) as Map<String, Object?>;
      expect(manifest['schemaVersion'], 1);
      final transformer = manifest['transformer']! as Map<String, Object?>;
      expect(transformer['tensorCount'], 149);
      expect((transformer['tensors']! as List<Object?>), hasLength(149));

      final header = File(
        'native/src/generated_tensor_manifest.h',
      ).readAsStringSync();
      expect(header, contains(_manifestSha256));
      expect(header, contains('std::array<TensorRecord, 149>'));
      expect(
        RegExp(r'\{"curated_encoder\.').allMatches(header),
        hasLength(149),
      );
    },
  );

  test(
    'generator check is deterministic and does not rewrite artifacts',
    () async {
      final header = File('native/src/generated_tensor_manifest.h');
      final before = header.readAsBytesSync();
      final result = await Process.run(
        Platform.resolvedExecutable,
        <String>['tool/generate_native_tensor_manifest.dart', '--check'],
        workingDirectory: Directory.current.absolute.path,
      );

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(
        '${result.stdout}',
        contains('verified 149 native tensor records'),
      );
      expect(header.readAsBytesSync(), before);
    },
  );

  test('native production sources have no Python or Torch runtime hook', () {
    for (final path in <String>[
      'native/CMakeLists.txt',
      'native/include/misakid_spacy_trf_en.h',
      'native/src/misakid_spacy_trf_en.cpp',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        isNot(
          matches(RegExp(r'python|pytorch|libtorch', caseSensitive: false)),
        ),
      );
      expect(source, isNot(contains('dlopen')));
    }
  });
}
