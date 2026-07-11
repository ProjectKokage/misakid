import 'package:misakid_bart_en/misakid_bart_en.dart';
import 'package:test/test.dart';

void main() {
  test('requires explicit printable identity labels and exact digests', () {
    BartEnglishResourceIdentity valid() => BartEnglishResourceIdentity(
      name: 'reviewed',
      version: '1',
      configSizeBytes: 1,
      configSha256: '0' * 64,
      weightsSizeBytes: 1,
      weightsSha256: '1' * 64,
    );

    expect(valid().name, 'reviewed');
    expect(
      BartEnglishResourceIdentity(
        name: 'reviewed-😀',
        version: '1',
        configSizeBytes: 1,
        configSha256: '0' * 64,
        weightsSizeBytes: 1,
        weightsSha256: '1' * 64,
      ).name,
      'reviewed-😀',
    );
    for (final invalid in <BartEnglishResourceIdentity Function()>[
      () => BartEnglishResourceIdentity(
        name: '',
        version: '1',
        configSizeBytes: 1,
        configSha256: '0' * 64,
        weightsSizeBytes: 1,
        weightsSha256: '1' * 64,
      ),
      () => BartEnglishResourceIdentity(
        name: 'x',
        version: '1',
        configSizeBytes: 0,
        configSha256: '0' * 64,
        weightsSizeBytes: 1,
        weightsSha256: '1' * 64,
      ),
      () => BartEnglishResourceIdentity(
        name: 'x',
        version: '1',
        configSizeBytes: 1,
        configSha256: 'A' * 64,
        weightsSizeBytes: 1,
        weightsSha256: '1' * 64,
      ),
    ]) {
      expect(invalid, throwsA(isA<InvalidConfigurationException>()));
    }
  });
}
