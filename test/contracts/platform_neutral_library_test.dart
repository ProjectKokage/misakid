import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('published library stays platform-neutral and silent', () {
    const forbiddenDartLibraries = <String>{
      'ffi',
      'html',
      'indexed_db',
      'io',
      'js',
      'js_interop',
      'js_util',
      'mirrors',
      'web_audio',
      'web_gl',
    };
    final dartImport = RegExp(
      r'''^import ['"]dart:([^'"]+)['"];''',
      multiLine: true,
    );
    final files =
        Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .toList(growable: false)
          ..sort((left, right) => left.path.compareTo(right.path));

    expect(files, isNotEmpty);
    for (final file in files) {
      final source = file.readAsStringSync();
      for (final match in dartImport.allMatches(source)) {
        expect(
          forbiddenDartLibraries,
          isNot(contains(match.group(1))),
          reason: file.path,
        );
      }
      expect(
        source,
        isNot(
          matches(RegExp(r'''^import ['"]package:flutter/''', multiLine: true)),
        ),
        reason: file.path,
      );
      expect(
        source,
        isNot(matches(RegExp(r'^\s*print\(', multiLine: true))),
        reason: file.path,
      );
    }

    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(
      pubspec,
      isNot(matches(RegExp(r'^\s+sdk:\s+flutter\s*$', multiLine: true))),
    );
    expect(
      pubspec,
      isNot(matches(RegExp(r'^\s+flutter:\s*$', multiLine: true))),
    );
  });

  test('examples and benchmarks compile against public entrypoints only', () {
    for (final directoryName in <String>['example', 'benchmark']) {
      final files = Directory(directoryName)
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));
      for (final file in files) {
        expect(
          file.readAsStringSync(),
          isNot(contains('package:misakid/src/')),
          reason: file.path,
        );
      }
    }
  });
}
