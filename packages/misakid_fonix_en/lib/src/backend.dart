import 'dart:async';
import 'dart:typed_data';

import 'package:fonix/fonix.dart';
import 'package:misakid/misaki_en.dart';

import 'ctc_codec.dart';
import 'model_profile.dart';

const int _workerMessageBytes = 2 * 1024 * 1024 + 64 * 1024;
const int _workerInputBytes = 4 * 1024;
const int _maximumTensorElements = 512 * 1024;

/// Narrow copied-value boundary used by the model fallback and its tests.
abstract interface class EnglishCtcRunner {
  /// Model input names.
  Iterable<String> get inputNames;

  /// Model output names.
  Iterable<String> get outputNames;

  /// Starts one bounded inference request.
  EnglishCtcRun startRun(Int64List graphemeIds);

  /// Closes the runner and its native owners.
  Future<void> close();
}

/// One cancellable CTC inference request.
abstract interface class EnglishCtcRun {
  /// Copied logits after authoritative run settlement.
  Future<EnglishCtcLogits> get result;

  /// Requests queued removal or native ONNX Runtime termination.
  Future<void> cancel();
}

/// Manifest-bound, isolate-owned Fonix English neural fallback.
final class FonixEnglishG2pBackend implements AsyncEnglishFallbackBackend {
  FonixEnglishG2pBackend._({
    required this.profile,
    required EnglishCtcRunner runner,
  }) : _runner = runner,
       _codec = EnglishCtcCodec(profile),
       info = BackendInfo(
         name: 'misakid-fonix-english-ctc',
         version: profile.version,
         details: <String, String>{
           'modelId': profile.modelId,
           'modelSha256': profile.modelSha256,
           'modelBytes': profile.modelSizeBytes.toString(),
           'architecture': 'misakid-medium-conv-bigru-ctc',
           'dialect': 'en-US',
           'provider': 'cpu',
           'maximumGraphemeCodePoints': profile.maximumGraphemeCodePoints
               .toString(),
           'slotsPerGrapheme': profile.slotsPerGrapheme.toString(),
         },
       );

  /// Opens one exact model in a dedicated Fonix worker isolate.
  ///
  /// [runtimeSource] is explicit because the consuming application owns the
  /// platform's single ONNX Runtime packaging decision.
  static Future<FonixEnglishG2pBackend> open({
    required Uint8List manifestBytes,
    required Uint8List modelBytes,
    required OrtRuntimeSource runtimeSource,
  }) async {
    final profile = FonixEnglishG2pModelProfile.parse(manifestBytes);
    profile.validateModelBytes(modelBytes);
    EnglishCtcRunner? runner;
    try {
      runner = await _FonixEnglishCtcRunner.open(
        profile: profile,
        modelBytes: modelBytes,
        runtimeSource: runtimeSource,
      );
      return await openWithRunner(profile: profile, runner: runner);
    } on MisakiException {
      if (runner != null) {
        await _closeRejectedRunner(runner);
      }
      rethrow;
    } on Exception catch (error) {
      if (runner != null) {
        await _closeRejectedRunner(runner);
      }
      throw BackendUnavailableException(
        'The Fonix English G2P session could not be opened.',
        cause: error,
      );
    }
  }

  /// Attaches a copied-value runner after validating its exact tensor names.
  ///
  /// This package-internal seam lets ordinary tests use fakes without loading
  /// ONNX Runtime or a model.
  static Future<FonixEnglishG2pBackend> openWithRunner({
    required FonixEnglishG2pModelProfile profile,
    required EnglishCtcRunner runner,
  }) async {
    if (!_hasExactNames(runner.inputNames, <String>{profile.inputName}) ||
        !_hasExactNames(runner.outputNames, <String>{profile.outputName})) {
      await _closeRejectedRunner(runner);
      throw const MalformedDataException(
        'The English G2P model has an incompatible tensor contract.',
      );
    }
    return FonixEnglishG2pBackend._(profile: profile, runner: runner);
  }

  /// Exact validated model profile.
  final FonixEnglishG2pModelProfile profile;

  final EnglishCtcRunner _runner;
  final EnglishCtcCodec _codec;

  @override
  final BackendInfo info;

  bool _closed = false;
  _ActiveEnglishCtcRun? _activeRun;
  Future<void>? _closeFuture;

  /// Whether [close] has invalidated this backend.
  bool get isClosed => _closed;

  @override
  Future<EnglishPronunciation> pronounce(MisakiToken token) async {
    if (_closed) {
      throw const BackendFailureException(
        'The Fonix English G2P backend is closed.',
      );
    }
    if (_activeRun != null) {
      throw const BackendFailureException(
        'The Fonix English G2P backend is already running.',
      );
    }

    final input = _codec.encode(token.text);
    _ActiveEnglishCtcRun? active;
    try {
      active = _ActiveEnglishCtcRun(_runner.startRun(input));
      _activeRun = active;
      final logits = await active.run.result;
      final phonemes = _codec.decode(logits, inputLength: input.length);
      return EnglishPronunciation(phonemes: phonemes, rating: 1);
    } on MisakiException {
      rethrow;
    } on Exception catch (error) {
      throw BackendFailureException(
        'Fonix English G2P inference failed.',
        cause: error,
      );
    } finally {
      if (active != null && identical(_activeRun, active)) {
        _activeRun = null;
      }
      active?.settle();
    }
  }

  /// Cancels and drains the active run, if any.
  Future<void> cancelActive() async {
    final closing = _closeFuture;
    if (closing != null) {
      await closing;
      return;
    }
    if (_closed) {
      return;
    }
    final active = _activeRun;
    if (active == null) {
      return;
    }

    Object? cancellationError;
    try {
      await active.requestCancellation();
    } on Object catch (error) {
      cancellationError = error;
    }
    await active.settled;
    if (cancellationError != null) {
      throw BackendFailureException(
        'The active Fonix English G2P run could not be cancelled safely.',
        cause: cancellationError,
      );
    }
  }

  /// Invalidates ownership, drains active work, and closes native resources.
  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) {
      return existing;
    }
    _closed = true;
    final closing = _closeAfterActiveRun();
    _closeFuture = closing;
    return closing;
  }

  Future<void> _closeAfterActiveRun() async {
    final active = _activeRun;
    Object? firstError;
    if (active != null) {
      try {
        await active.requestCancellation();
      } on Object catch (error) {
        firstError = error;
      }
      await active.settled;
    }
    try {
      await _runner.close();
    } on Object catch (error) {
      firstError ??= error;
    }
    if (firstError != null) {
      throw BackendFailureException(
        'The Fonix English G2P session could not be closed safely.',
        cause: firstError,
      );
    }
  }
}

final class _ActiveEnglishCtcRun {
  _ActiveEnglishCtcRun(this.run);

  final EnglishCtcRun run;
  final Completer<void> _settled = Completer<void>();
  Future<void>? _cancellation;

  Future<void> get settled => _settled.future;

  Future<void> requestCancellation() => _cancellation ??= run.cancel();

  void settle() {
    if (!_settled.isCompleted) {
      _settled.complete();
    }
  }
}

final class _FonixEnglishCtcRunner implements EnglishCtcRunner {
  _FonixEnglishCtcRunner._(this._session, this._profile);

  final OrtIsolateSession _session;
  final FonixEnglishG2pModelProfile _profile;

  static Future<_FonixEnglishCtcRunner> open({
    required FonixEnglishG2pModelProfile profile,
    required Uint8List modelBytes,
    required OrtRuntimeSource runtimeSource,
  }) async {
    final limits = OrtResourceLimits(
      maxModelBytes: 32 * 1024 * 1024,
      maxTensorBytes: _workerMessageBytes,
      maxTensorElements: _maximumTensorElements,
      maxRank: 3,
      maxDimension: 1024,
      maxProviders: 1,
      maxProviderOptions: 1,
      maxConfigEntries: 1,
      maxDiagnosticsBytes: 128 * 1024,
      maxTypeDepth: 2,
      maxTypeNodes: 16,
    );
    final session = await OrtIsolateSession.spawn(
      model: OrtModelSource.bytes(
        modelBytes,
        modelId: '${profile.modelId}@${profile.version}',
        limits: limits,
      ),
      runtimeSource: runtimeSource,
      options: OrtSessionOptions(
        providers: <OrtExecutionProvider>[OrtExecutionProvider.cpu()],
        fallbackPolicy: OrtFallbackPolicy.allow,
        sessionLogId: 'misakid-english-g2p',
        limits: limits,
      ),
      maxPendingRuns: 1,
      maxMessageBytes: _workerMessageBytes,
      maxOutstandingInputBytes: _workerInputBytes,
    );
    return _FonixEnglishCtcRunner._(session, profile);
  }

  @override
  Iterable<String> get inputNames => _session.inputNames;

  @override
  Iterable<String> get outputNames => _session.outputNames;

  @override
  EnglishCtcRun startRun(Int64List graphemeIds) {
    final run = _session.startRun(
      inputs: <String, OrtIsolateValue>{
        _profile.inputName: OrtIsolateTensor.fromInt64List(
          values: graphemeIds,
          shape: <int>[1, graphemeIds.length],
        ),
      },
      outputNames: <String>[_profile.outputName],
    );
    return _FonixEnglishCtcRun(run, _profile.outputName);
  }

  @override
  Future<void> close() => _session.close();
}

final class _FonixEnglishCtcRun implements EnglishCtcRun {
  _FonixEnglishCtcRun(this._run, String outputName)
    : result = _copyResult(_run.result, outputName);

  final OrtIsolateRun _run;

  @override
  final Future<EnglishCtcLogits> result;

  @override
  Future<void> cancel() async {
    await _run.cancelWithDisposition();
  }

  static Future<EnglishCtcLogits> _copyResult(
    Future<OrtIsolateRunResult> pending,
    String outputName,
  ) async {
    final result = await pending;
    if (!_hasExactNames(result.outputs.keys, <String>{outputName})) {
      throw const BackendFailureException(
        'English neural G2P returned an incompatible output set.',
      );
    }
    final value = result.outputs[outputName];
    if (value is! OrtIsolateTensor ||
        value.elementType != OrtTensorElementType.float32) {
      throw const BackendFailureException(
        'English neural G2P returned a non-float32 logits tensor.',
      );
    }
    return EnglishCtcLogits(
      shape: value.shape.dimensions,
      values: value.copyFloat32Data(),
    );
  }
}

bool _hasExactNames(Iterable<String> actual, Set<String> expected) {
  final actualSet = actual.toSet();
  return actualSet.length == expected.length && actualSet.containsAll(expected);
}

Future<void> _closeRejectedRunner(EnglishCtcRunner runner) async {
  try {
    await runner.close();
  } on Object catch (error) {
    throw BackendFailureException(
      'The rejected English G2P session could not be closed safely.',
      cause: error,
    );
  }
}
