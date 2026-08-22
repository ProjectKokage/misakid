import 'dart:async';
import 'dart:typed_data';

import 'package:misakid/misaki_en.dart';
import 'package:misakid_fonix_en/src/backend.dart';
import 'package:misakid_fonix_en/src/ctc_codec.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

void main() {
  test('runs one copied request and returns rating one', () async {
    final runner = _FakeRunner();
    final backend = await FonixEnglishG2pBackend.openWithRunner(
      profile: testProfile(),
      runner: runner,
    );

    final pending = backend.pronounce(_token('a'));
    expect(runner.inputs.single, Int64List.fromList(<int>[2]));
    runner.active!.completeWithIds(<int>[1, 0, 0, 0, 0, 0, 0, 0]);
    final result = await pending;

    expect(result.phonemes, 'p');
    expect(result.rating, 1);
    expect(backend.info.details['provider'], 'cpu');
    await backend.close();
    expect(runner.closeCalls, 1);
  });

  test('rejects concurrent calls without queuing native work', () async {
    final runner = _FakeRunner();
    final backend = await FonixEnglishG2pBackend.openWithRunner(
      profile: testProfile(),
      runner: runner,
    );
    final first = backend.pronounce(_token('a'));

    await expectLater(
      backend.pronounce(_token('b')),
      throwsA(isA<BackendFailureException>()),
    );
    expect(runner.startCalls, 1);

    runner.active!.completeWithIds(<int>[1, 0, 0, 0, 0, 0, 0, 0]);
    await first;
    await backend.close();
  });

  test('cancels, drains, recovers, and closes idempotently', () async {
    final runner = _FakeRunner();
    final backend = await FonixEnglishG2pBackend.openWithRunner(
      profile: testProfile(),
      runner: runner,
    );
    final first = backend.pronounce(_token('a'));
    final cancelledRun = runner.active!;
    final cancellation = backend.cancelActive();
    await Future<void>.delayed(Duration.zero);
    expect(cancelledRun.cancelCalls, 1);
    cancelledRun.completeError(Exception('cancelled'));

    await expectLater(first, throwsA(isA<BackendFailureException>()));
    await cancellation;

    final recovered = backend.pronounce(_token('b'));
    runner.active!.completeWithIds(<int>[2, 0, 0, 0, 0, 0, 0, 0]);
    expect((await recovered).phonemes, 'q');

    final firstClose = backend.close();
    final secondClose = backend.close();
    expect(identical(firstClose, secondClose), isTrue);
    await firstClose;
    expect(runner.closeCalls, 1);
    await expectLater(
      backend.pronounce(_token('a')),
      throwsA(isA<BackendFailureException>()),
    );
  });

  test('closes a runner whose graph names are incompatible', () async {
    final runner = _FakeRunner(inputNames: const <String>['wrong']);
    await expectLater(
      FonixEnglishG2pBackend.openWithRunner(
        profile: testProfile(),
        runner: runner,
      ),
      throwsA(isA<MalformedDataException>()),
    );
    expect(runner.closeCalls, 1);
  });
}

final class _FakeRunner implements EnglishCtcRunner {
  _FakeRunner({this.inputNames = const <String>['grapheme_ids']});

  @override
  final Iterable<String> inputNames;

  @override
  Iterable<String> get outputNames => const <String>['logits'];

  final List<Int64List> inputs = <Int64List>[];
  var startCalls = 0;
  var closeCalls = 0;
  _FakeRun? active;

  @override
  EnglishCtcRun startRun(Int64List graphemeIds) {
    startCalls++;
    inputs.add(Int64List.fromList(graphemeIds));
    final run = _FakeRun(graphemeIds.length);
    active = run;
    return run;
  }

  @override
  Future<void> close() async {
    closeCalls++;
  }
}

final class _FakeRun implements EnglishCtcRun {
  _FakeRun(this.inputLength);

  final int inputLength;
  final Completer<EnglishCtcLogits> _result = Completer<EnglishCtcLogits>();
  var cancelCalls = 0;

  @override
  Future<EnglishCtcLogits> get result => _result.future;

  @override
  Future<void> cancel() async {
    cancelCalls++;
  }

  void completeWithIds(List<int> ids) {
    final expectedSteps = inputLength * 8;
    if (ids.length != expectedSteps) {
      throw ArgumentError('Expected $expectedSteps fake CTC IDs.');
    }
    final values = Float32List(expectedSteps * 3);
    for (var step = 0; step < expectedSteps; step++) {
      values[step * 3 + ids[step]] = 1;
    }
    _result.complete(
      EnglishCtcLogits(shape: <int>[1, expectedSteps, 3], values: values),
    );
  }

  void completeError(Object error) => _result.completeError(error);
}

MisakiToken _token(String text) => MisakiToken(
  text: text,
  tag: 'NN',
  whitespace: '',
  metadata: const EnglishTokenMetadata(isHead: true),
);
