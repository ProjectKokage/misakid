import 'package:misakid/src/languages/vi/options.dart';
import 'package:misakid/src/languages/vi/phonology.dart';
import 'package:test/test.dart';

void main() {
  test('transcribes pinned onset, glide, nucleus, coda, and tone tables', () {
    const options = VietnameseOptions();
    expect(convertVietnameseWord('bạn', options), 'b/a/n/6');
    expect(convertVietnameseWord('quy', options), 'kw/i//1');
    expect(convertVietnameseWord('gi', options), 'z/i//1');
    expect(convertVietnameseWord('nghiêng', options), 'ŋ/iə/ŋ/1');
    expect(convertVietnameseWord('khuya', options), 'xw/ʷiə//1');
    expect(convertVietnameseWord('yêu', options), '/iə/w/1');
    expect(convertVietnameseWord('rượu', options), 'ʐ/ɯə/w/6');
    expect(convertVietnameseWord('xyz', options), '[xyz]');
  });

  test('preserves dialect-specific fronting and southern monophthongs', () {
    expect(
      convertVietnameseWord(
        'anh',
        const VietnameseOptions(dialect: VietnameseDialect.north),
      ),
      '/ɛ/ɲ/1',
    );
    expect(
      convertVietnameseWord(
        'anh',
        const VietnameseOptions(dialect: VietnameseDialect.central),
      ),
      '/a/ɲ/1',
    );
    expect(
      convertVietnameseWord(
        'một',
        const VietnameseOptions(dialect: VietnameseDialect.north),
      ),
      'm/o/t/6',
    );
    expect(
      convertVietnameseWord(
        'một',
        const VietnameseOptions(dialect: VietnameseDialect.south),
      ),
      'm/o/k͡p/6',
    );
  });

  test('preserves glottal field placement and Cao closed-tone suffixes', () {
    expect(
      convertVietnameseWord('an', const VietnameseOptions(glottal: true)),
      'ʔa//n/1',
    );
    expect(
      convertVietnameseWord(
        'học',
        const VietnameseOptions(toneType: VietnameseToneType.cao),
      ),
      'h/ɔ/k͡p/6b',
    );
  });

  test('applies northern palatal codas only when selected', () {
    expect(convertVietnameseWord('méc', const VietnameseOptions()), 'm/ɛ/k/5');
    expect(
      convertVietnameseWord('méc', const VietnameseOptions(palatals: true)),
      'm/ɛ/c/5',
    );
    expect(
      convertVietnameseWord(
        'méc',
        const VietnameseOptions(
          dialect: VietnameseDialect.central,
          palatals: true,
        ),
      ),
      'm/ɛ/k/5',
    );
  });

  test('parses longest symbols and marks unknown scalars', () {
    expect(
      parseVietnamesePhonemes('ban1 xyz*', delimiter: '|'),
      "|b|a|n|1| |x|'|z|",
    );
  });
}
