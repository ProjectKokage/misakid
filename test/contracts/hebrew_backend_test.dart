import 'package:misakid/misaki_he.dart';
import 'package:test/test.dart';

void main() {
  test('forwards default options and preserves null token semantics', () {
    final backend = _FakeHebrewBackend(output: 'ʃalˈom');
    final result = HebrewG2pEngine(backend: backend).convert('שָׁלוֹם');

    expect(result.phonemes, 'ʃalˈom');
    expect(result.tokens, isNull);
    expect(backend.lastText, 'שָׁלוֹם');
    expect(backend.lastPunctuation, isTrue);
    expect(backend.lastStress, isTrue);
  });

  test('forwards explicitly disabled preservation options', () {
    final backend = _FakeHebrewBackend(output: 'ʃalom');
    final engine = HebrewG2pEngine(
      backend: backend,
      options: const HebrewOptions(
        preservePunctuation: false,
        preserveStress: false,
      ),
    );

    engine.convert('שָׁלוֹם!');

    expect(backend.lastPunctuation, isFalse);
    expect(backend.lastStress, isFalse);
  });

  test('does not trim or normalize backend output', () {
    const output = ' ʃalˈom!\ne\u0301 ';
    final result = HebrewG2pEngine(
      backend: _FakeHebrewBackend(output: output),
    ).convert('שָׁלוֹם');

    expect(result.phonemes, output);
    expect(result.tokens, isNull);
  });

  test('wraps adapter exceptions with backend identity and cause', () {
    const error = FormatException('adapter failed');
    final backend = _FakeHebrewBackend(error: error);

    expect(
      () => HebrewG2pEngine(backend: backend).convert('שָׁלוֹם'),
      throwsA(
        isA<BackendFailureException>()
            .having(
              (exception) => exception.message,
              'message',
              contains('fake-mishkal 0.3.2'),
            )
            .having((exception) => exception.cause, 'cause', same(error)),
      ),
    );
  });

  test('preserves typed adapter exceptions without wrapping', () {
    const error = BackendUnavailableException('Mishkal data is unavailable.');
    final backend = _FakeHebrewBackend(error: error);

    expect(
      () => HebrewG2pEngine(backend: backend).convert('שָׁלוֹם'),
      throwsA(same(error)),
    );
  });

  test('returns a defensive inventory and rejects empty symbols', () {
    final source = <String>{'a', 'ʃ'};
    final backend = _FakeHebrewBackend(output: '', inventory: source);
    final inventory = HebrewG2pEngine(backend: backend).phonemeInventory();
    source.clear();

    expect(inventory, <String>{'a', 'ʃ'});
    expect(() => inventory.add('b'), throwsUnsupportedError);

    final malformed = _FakeHebrewBackend(output: '', inventory: <String>{''});
    expect(
      () => HebrewG2pEngine(backend: malformed).phonemeInventory(),
      throwsA(isA<MalformedDataException>()),
    );

    final empty = _FakeHebrewBackend(output: '', inventory: <String>{});
    expect(
      () => HebrewG2pEngine(backend: empty).phonemeInventory(),
      throwsA(isA<MalformedDataException>()),
    );
  });

  test('wraps inventory adapter failures and preserves typed failures', () {
    const adapterError = FormatException('bad inventory');
    final failing = _FakeHebrewBackend(
      output: '',
      inventoryError: adapterError,
    );
    expect(
      () => HebrewG2pEngine(backend: failing).phonemeInventory(),
      throwsA(
        isA<BackendFailureException>()
            .having(
              (exception) => exception.message,
              'message',
              contains('fake-mishkal 0.3.2'),
            )
            .having(
              (exception) => exception.cause,
              'cause',
              same(adapterError),
            ),
      ),
    );

    const unavailable = BackendUnavailableException('inventory unavailable');
    final typed = _FakeHebrewBackend(output: '', inventoryError: unavailable);
    expect(
      () => HebrewG2pEngine(backend: typed).phonemeInventory(),
      throwsA(same(unavailable)),
    );
  });
}

final class _FakeHebrewBackend implements HebrewPhonemizerBackend {
  _FakeHebrewBackend({
    this.output,
    this.error,
    this.inventoryError,
    this.inventory = const <String>{'a', 'ʃ'},
  });

  final String? output;
  final Exception? error;
  final Exception? inventoryError;
  final Set<String> inventory;

  String? lastText;
  bool? lastPunctuation;
  bool? lastStress;

  @override
  BackendInfo get info => BackendInfo(name: 'fake-mishkal', version: '0.3.2');

  @override
  Set<String> phonemeInventory() {
    final failure = inventoryError;
    if (failure != null) {
      throw failure;
    }
    return inventory;
  }

  @override
  String phonemize(
    String text, {
    required bool preservePunctuation,
    required bool preserveStress,
  }) {
    lastText = text;
    lastPunctuation = preservePunctuation;
    lastStress = preserveStress;
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return output!;
  }
}
