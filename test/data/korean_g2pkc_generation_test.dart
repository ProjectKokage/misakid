import 'dart:io';

import 'package:misakid/src/generated/korean_g2pkc_data.dart';
import 'package:test/test.dart';

void main() {
  test('generated Korean rule data is byte-for-byte reproducible', () async {
    final result = await Process.run(Platform.resolvedExecutable, const [
      'run',
      'tool/generators/generate_korean_g2pkc_data.dart',
      '--check',
    ]);

    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  });

  test('runtime Korean rule tables retain exact counts and sentinels', () {
    expect(koreanG2pkcIdioms, hasLength(355));
    expect(koreanG2pkcTableRules, hasLength(401));
    expect(koreanG2pkcIdioms.first, ('갇혀', '가쳐'));
    expect(koreanG2pkcTableRules.first, ('ᇂ', 'ᄒ', 'ᄒ'));
    expect(() => koreanG2pkcIdioms.add(('x', 'y')), throwsUnsupportedError);
    expect(
      () => koreanG2pkcTableRules.add(('x', 'y', 'z')),
      throwsUnsupportedError,
    );
  });
}
