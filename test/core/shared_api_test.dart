import 'package:misakid/misaki.dart';
import 'package:test/test.dart';

void main() {
  group('G2pResult', () {
    test('preserves null and empty token semantics', () {
      final unavailable = G2pResult(phonemes: '', tokens: null);
      final available = G2pResult(phonemes: '', tokens: const <MisakiToken>[]);

      expect(unavailable.tokens, isNull);
      expect(available.tokens, isNotNull);
      expect(available.tokens, isEmpty);
    });

    test('defensively freezes its token list', () {
      final source = <MisakiToken>[
        const MisakiToken(text: 'a', tag: 'X', whitespace: ''),
      ];
      final result = G2pResult(phonemes: '❓', tokens: source);
      source.clear();

      expect(result.tokens, hasLength(1));
      expect(
        () => result.tokens!.add(
          const MisakiToken(text: 'b', tag: 'X', whitespace: ''),
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('MisakiToken', () {
    test('renders null phonemes with the exact default unknown marker', () {
      const token = MisakiToken(text: '𠀋', tag: 'X', whitespace: '  ');

      expect(token.render(), '❓  ');
      expect(token.render(unknownMarker: '□'), '□  ');
    });

    test('distinguishes empty phonemes from unavailable phonemes', () {
      const token = MisakiToken(
        text: '-',
        tag: ':',
        whitespace: '\n',
        phonemes: '',
      );

      expect(token.render(), '\n');
    });
  });

  test('Japanese metadata freezes related arrays', () {
    final moras = <String>['ミ', 'サ', 'キ'];
    final accents = <int>[0, 1, 3];
    final metadata = JapaneseTokenMetadata(
      pronunciation: 'ミサキ',
      accent: 3,
      moraSize: 3,
      chainFlag: false,
      moras: moras,
      accents: accents,
      pitch: '___---^^^',
    );
    moras.clear();
    accents.clear();

    expect(metadata.moras, <String>['ミ', 'サ', 'キ']);
    expect(metadata.accents, <int>[0, 1, 3]);
    expect(() => metadata.moras.add('ー'), throwsUnsupportedError);
  });

  test('BackendInfo validates and freezes stable identity details', () {
    final source = <String, String>{'dictionary': '1.0'};
    final info = BackendInfo(name: 'backend', version: '2.0', details: source);
    source.clear();

    expect(info.toString(), 'backend 2.0');
    expect(info.details, <String, String>{'dictionary': '1.0'});
    expect(() => info.details['model'] = 'x', throwsUnsupportedError);
    expect(
      () => BackendInfo(name: '', version: '1'),
      throwsA(isA<InvalidConfigurationException>()),
    );
    expect(
      () =>
          BackendInfo(name: 'backend', version: '1', details: const {'': 'x'}),
      throwsA(isA<InvalidConfigurationException>()),
    );
    expect(
      () => BackendInfo(name: ' ', version: '1'),
      throwsA(isA<InvalidConfigurationException>()),
    );
    expect(
      () => BackendInfo(name: 'backend', version: '\t'),
      throwsA(isA<InvalidConfigurationException>()),
    );
    expect(
      () => BackendInfo(
        name: 'backend',
        version: '1',
        details: const <String, String>{'resource': '  '},
      ),
      throwsA(isA<InvalidConfigurationException>()),
    );
  });

  test('exposes the authoritative upstream identity', () {
    expect(misakiUpstreamRepository, 'hexgrad/misaki');
    expect(misakiUpstreamCommit, 'fba1236595f2d2bf21d414ba6e57d25256afada3');
    expect(misakiUpstreamVersion, '0.9.4');
    expect(defaultUnknownMarker, '❓');
  });
}
