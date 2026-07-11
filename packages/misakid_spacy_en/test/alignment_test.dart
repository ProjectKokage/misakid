import 'package:misakid_spacy_en/src/alignment.dart';
import 'package:test/test.dart';

void main() {
  test('matches spaCy 3.8.4 flattened y2x alignment quirks', () {
    expect(
      flattenedSpacyY2xAlignment(
        const <String>['Hello', 'world'],
        const <String>['Hello', '\t', 'world'],
      ),
      <int>[0, 1],
    );
    expect(
      flattenedSpacyY2xAlignment(
        const <String>['foo bar'],
        const <String>['foo', ' ', 'bar'],
      ),
      <int>[0, 0, 0],
    );
    expect(
      flattenedSpacyY2xAlignment(
        const <String>['a', 'bee', 'silent', 'word'],
        const <String>['abee', 'silentword'],
      ),
      <int>[0, 1, 2, 3],
    );
  });

  test('uses exact CPython 3.12 lower expansion and Final_Sigma', () {
    expect(
      flattenedSpacyY2xAlignment(const <String>['ΟΣ'], const <String>['ος']),
      <int>[0],
    );
    expect(
      flattenedSpacyY2xAlignment(
        const <String>['ΟΣ', 'A'],
        const <String>['οσa'],
      ),
      <int>[0, 1],
    );
    expect(
      flattenedSpacyY2xAlignment(
        const <String>['İ'],
        const <String>['i\u0307'],
      ),
      <int>[0],
    );
  });

  test('rejects text changes beyond whitespace and capitalization', () {
    expect(
      () => flattenedSpacyY2xAlignment(
        const <String>['café'],
        const <String>['cafe'],
      ),
      throwsFormatException,
    );
  });
}
