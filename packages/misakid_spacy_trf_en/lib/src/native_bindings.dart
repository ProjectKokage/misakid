// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

/// Native ABI version required by the transformer adapter.
const int spacyTransformerNativeAbiVersion = 1;

/// Fixed native upper bound for one marked byte-BPE sequence.
const int maximumSpacyTransformerNativePieces = 4000002;

/// Fixed native upper bound for non-whitespace tokens in one document.
const int maximumSpacyTransformerNativeTokens = 1000000;

/// Exact number of F32 values in the transformer's linear tagger head.
const int spacyTransformerTaggerWeightCount = 49 * 768;

/// Exact number of F32 values in the transformer's tagger bias.
const int spacyTransformerTaggerBiasCount = 49;

const int _maximumPathBytes = 32768;
const int _maximumDiagnosticBytes = 256;

/// Immutable identity fields required from the package-owned native shim.
const Map<int, String> expectedSpacyTransformerNativeIdentities = <int, String>{
  0: '0.1.0-dev.1',
  1: '3.8.0',
  2: '2b7061c623f424486e5dddcff79276927127cee339cc6a9d26d87837c3e6074a',
  3: 'aecff2bb262b0b9aeb554af63ecaa3f02e6e87b28f6e8c2440e5ec24acd52589',
  4: 'roberta-base-12x768-stride104-window144-mean49',
  5: 'misakid-spacy-trf-en-accelerate-v1',
};

/// Bounded, input-free diagnostic returned by native transformer inference.
final class SpacyTransformerNativeException implements Exception {
  /// Creates one stable native diagnostic.
  const SpacyTransformerNativeException({
    required this.code,
    required this.stage,
    required this.message,
  });

  /// Stable native status code.
  final int code;

  /// Native pipeline stage that failed.
  final String stage;

  /// Bounded message containing no text, token, or configured path.
  final String message;

  @override
  String toString() =>
      'SpacyTransformerNativeException(code: $code, stage: $stage, '
      'message: $message)';
}

/// Failure to load, bind, or validate the package-owned native shim.
final class SpacyTransformerNativeLibraryException implements Exception {
  /// Creates one native-library compatibility failure.
  const SpacyTransformerNativeLibraryException(this.message, {this.cause});

  /// Actionable failure summary.
  final String message;

  /// Lower-level failure, when available.
  final Object? cause;

  @override
  String toString() => 'SpacyTransformerNativeLibraryException: $message';
}

final class _NativeContext extends Opaque {}

final class _NativeResult extends Opaque {}

typedef _AbiNative = Uint32 Function();
typedef _AbiDart = int Function();
typedef _IdentityDataNative = Pointer<Uint8> Function(Uint32);
typedef _IdentityDataDart = Pointer<Uint8> Function(int);
typedef _IdentitySizeNative = Size Function(Uint32);
typedef _IdentitySizeDart = int Function(int);
typedef _BufferAllocNative = Pointer<Uint8> Function(Size);
typedef _BufferAllocDart = Pointer<Uint8> Function(int);
typedef _BufferFreeNative = Void Function(Pointer<Void>);
typedef _BufferFreeDart = void Function(Pointer<Void>);
typedef _ContextCreateNative =
    Pointer<_NativeContext> Function(
      Pointer<Uint8>,
      Size,
      Pointer<Float>,
      Size,
      Pointer<Float>,
      Size,
    );
typedef _ContextCreateDart =
    Pointer<_NativeContext> Function(
      Pointer<Uint8>,
      int,
      Pointer<Float>,
      int,
      Pointer<Float>,
      int,
    );
typedef _ContextStatusNative = Uint32 Function(Pointer<_NativeContext>);
typedef _ContextStatusDart = int Function(Pointer<_NativeContext>);
typedef _ContextDataNative = Pointer<Uint8> Function(Pointer<_NativeContext>);
typedef _ContextDataDart = Pointer<Uint8> Function(Pointer<_NativeContext>);
typedef _ContextSizeNative = Size Function(Pointer<_NativeContext>);
typedef _ContextSizeDart = int Function(Pointer<_NativeContext>);
typedef _ContextDestroyNative = Void Function(Pointer<_NativeContext>);
typedef _ContextDestroyDart = void Function(Pointer<_NativeContext>);
typedef _InferNative =
    Pointer<_NativeResult> Function(
      Pointer<_NativeContext>,
      Pointer<Uint32>,
      Size,
      Pointer<Uint32>,
      Size,
    );
typedef _InferDart =
    Pointer<_NativeResult> Function(
      Pointer<_NativeContext>,
      Pointer<Uint32>,
      int,
      Pointer<Uint32>,
      int,
    );
typedef _ResultStatusNative = Uint32 Function(Pointer<_NativeResult>);
typedef _ResultStatusDart = int Function(Pointer<_NativeResult>);
typedef _ResultDataNative = Pointer<Uint8> Function(Pointer<_NativeResult>);
typedef _ResultDataDart = Pointer<Uint8> Function(Pointer<_NativeResult>);
typedef _ResultSizeNative = Size Function(Pointer<_NativeResult>);
typedef _ResultSizeDart = int Function(Pointer<_NativeResult>);
typedef _ResultTagsNative = Pointer<Uint16> Function(Pointer<_NativeResult>);
typedef _ResultTagsDart = Pointer<Uint16> Function(Pointer<_NativeResult>);
typedef _ResultDestroyNative = Void Function(Pointer<_NativeResult>);
typedef _ResultDestroyDart = void Function(Pointer<_NativeResult>);

/// Loaded and identity-checked native transformer ABI.
final class SpacyTransformerNativeLibrary {
  SpacyTransformerNativeLibrary._(DynamicLibrary library)
    : _abiVersion = library.lookupFunction<_AbiNative, _AbiDart>(
        'misakid_spacy_trf_en_abi_version',
      ),
      _identityData = library
          .lookupFunction<_IdentityDataNative, _IdentityDataDart>(
            'misakid_spacy_trf_en_identity_data',
          ),
      _identitySize = library
          .lookupFunction<_IdentitySizeNative, _IdentitySizeDart>(
            'misakid_spacy_trf_en_identity_size',
          ),
      _bufferAlloc = library
          .lookupFunction<_BufferAllocNative, _BufferAllocDart>(
            'misakid_spacy_trf_en_buffer_alloc',
          ),
      _bufferFree = library.lookupFunction<_BufferFreeNative, _BufferFreeDart>(
        'misakid_spacy_trf_en_buffer_free',
      ),
      _contextCreate = library
          .lookupFunction<_ContextCreateNative, _ContextCreateDart>(
            'misakid_spacy_trf_en_context_create',
          ),
      _contextStatus = library
          .lookupFunction<_ContextStatusNative, _ContextStatusDart>(
            'misakid_spacy_trf_en_context_status',
          ),
      _contextErrorStageData = library
          .lookupFunction<_ContextDataNative, _ContextDataDart>(
            'misakid_spacy_trf_en_context_error_stage_data',
          ),
      _contextErrorStageSize = library
          .lookupFunction<_ContextSizeNative, _ContextSizeDart>(
            'misakid_spacy_trf_en_context_error_stage_size',
          ),
      _contextErrorMessageData = library
          .lookupFunction<_ContextDataNative, _ContextDataDart>(
            'misakid_spacy_trf_en_context_error_message_data',
          ),
      _contextErrorMessageSize = library
          .lookupFunction<_ContextSizeNative, _ContextSizeDart>(
            'misakid_spacy_trf_en_context_error_message_size',
          ),
      _contextDestroy = library
          .lookupFunction<_ContextDestroyNative, _ContextDestroyDart>(
            'misakid_spacy_trf_en_context_destroy',
          ),
      _contextDestroyPointer = library
          .lookup<NativeFunction<_ContextDestroyNative>>(
            'misakid_spacy_trf_en_context_destroy',
          )
          .cast<NativeFunction<Void Function(Pointer<Void>)>>(),
      _infer = library.lookupFunction<_InferNative, _InferDart>(
        'misakid_spacy_trf_en_infer',
      ),
      _resultStatus = library
          .lookupFunction<_ResultStatusNative, _ResultStatusDart>(
            'misakid_spacy_trf_en_result_status',
          ),
      _resultErrorStageData = library
          .lookupFunction<_ResultDataNative, _ResultDataDart>(
            'misakid_spacy_trf_en_result_error_stage_data',
          ),
      _resultErrorStageSize = library
          .lookupFunction<_ResultSizeNative, _ResultSizeDart>(
            'misakid_spacy_trf_en_result_error_stage_size',
          ),
      _resultErrorMessageData = library
          .lookupFunction<_ResultDataNative, _ResultDataDart>(
            'misakid_spacy_trf_en_result_error_message_data',
          ),
      _resultErrorMessageSize = library
          .lookupFunction<_ResultSizeNative, _ResultSizeDart>(
            'misakid_spacy_trf_en_result_error_message_size',
          ),
      _resultTagsData = library
          .lookupFunction<_ResultTagsNative, _ResultTagsDart>(
            'misakid_spacy_trf_en_result_tags_data',
          ),
      _resultTagsSize = library
          .lookupFunction<_ResultSizeNative, _ResultSizeDart>(
            'misakid_spacy_trf_en_result_tags_size',
          ),
      _resultDestroy = library
          .lookupFunction<_ResultDestroyNative, _ResultDestroyDart>(
            'misakid_spacy_trf_en_result_destroy',
          );

  /// Loads required symbols and validates every immutable shim identity.
  static SpacyTransformerNativeLibrary load(String path) {
    try {
      final bindings = SpacyTransformerNativeLibrary._(
        DynamicLibrary.open(path),
      );
      bindings._validateIdentity();
      return bindings;
    } on SpacyTransformerNativeLibraryException {
      rethrow;
    } on Object catch (error) {
      throw SpacyTransformerNativeLibraryException(
        'The configured library is not a compatible Misakid transformer adapter.',
        cause: error,
      );
    }
  }

  final _AbiDart _abiVersion;
  final _IdentityDataDart _identityData;
  final _IdentitySizeDart _identitySize;
  final _BufferAllocDart _bufferAlloc;
  final _BufferFreeDart _bufferFree;
  final _ContextCreateDart _contextCreate;
  final _ContextStatusDart _contextStatus;
  final _ContextDataDart _contextErrorStageData;
  final _ContextSizeDart _contextErrorStageSize;
  final _ContextDataDart _contextErrorMessageData;
  final _ContextSizeDart _contextErrorMessageSize;
  final _ContextDestroyDart _contextDestroy;
  final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
  _contextDestroyPointer;
  final _InferDart _infer;
  final _ResultStatusDart _resultStatus;
  final _ResultDataDart _resultErrorStageData;
  final _ResultSizeDart _resultErrorStageSize;
  final _ResultDataDart _resultErrorMessageData;
  final _ResultSizeDart _resultErrorMessageSize;
  final _ResultTagsDart _resultTagsData;
  final _ResultSizeDart _resultTagsSize;
  final _ResultDestroyDart _resultDestroy;

  /// Exact native identity values after successful validation.
  late final Map<int, String> identities =
      Map<int, String>.unmodifiable(<int, String>{
        for (final field in expectedSpacyTransformerNativeIdentities.keys)
          field: _decode(
            _identityData(field),
            _identitySize(field),
            'native identity',
          ),
      });

  void _validateIdentity() {
    if (_abiVersion() != spacyTransformerNativeAbiVersion) {
      throw const SpacyTransformerNativeLibraryException(
        'The transformer adapter ABI version is incompatible.',
      );
    }
    for (final expected in expectedSpacyTransformerNativeIdentities.entries) {
      if (identities[expected.key] != expected.value) {
        throw const SpacyTransformerNativeLibraryException(
          'The transformer adapter source or resource identity is incompatible.',
        );
      }
    }
  }
}

/// One reusable native transformer context with deterministic ownership.
final class SpacyTransformerNativeContext implements Finalizable {
  SpacyTransformerNativeContext._({
    required SpacyTransformerNativeLibrary library,
    required Pointer<_NativeContext> context,
  }) : _library = library,
       _context = context,
       _finalizer = NativeFinalizer(library._contextDestroyPointer) {
    _finalizer.attach(this, context.cast<Void>(), detach: this);
  }

  /// Opens the exact model and copies the caller-validated tagger arrays.
  static SpacyTransformerNativeContext create({
    required SpacyTransformerNativeLibrary library,
    required String transformerModelPath,
    required Float32List taggerWeights,
    required Float32List taggerBiases,
  }) {
    if (taggerWeights.length != spacyTransformerTaggerWeightCount ||
        taggerBiases.length != spacyTransformerTaggerBiasCount ||
        taggerWeights.any((value) => !value.isFinite) ||
        taggerBiases.any((value) => !value.isFinite)) {
      throw const SpacyTransformerNativeException(
        code: 1,
        stage: 'initialize',
        message: 'The transformer tagger arrays are invalid.',
      );
    }
    final pathBytes = _encodeValidUtf8(
      transformerModelPath,
      maxBytes: _maximumPathBytes,
    );
    final path = _copyBytesToNative(library, pathBytes);
    Pointer<Float>? weights;
    Pointer<Float>? biases;
    Pointer<_NativeContext> context;
    try {
      weights = _copyFloat32ToNative(library, taggerWeights);
      biases = _copyFloat32ToNative(library, taggerBiases);
      context = library._contextCreate(
        path,
        pathBytes.length,
        weights,
        taggerWeights.length,
        biases,
        taggerBiases.length,
      );
    } finally {
      library._bufferFree(path.cast<Void>());
      if (weights != null) library._bufferFree(weights.cast<Void>());
      if (biases != null) library._bufferFree(biases.cast<Void>());
    }
    if (context.address == 0) {
      throw const SpacyTransformerNativeException(
        code: 7,
        stage: 'initialize',
        message: 'Native transformer context allocation failed.',
      );
    }
    final status = library._contextStatus(context);
    if (status != 0) {
      try {
        throw _contextError(library, context, status);
      } finally {
        library._contextDestroy(context);
      }
    }
    return SpacyTransformerNativeContext._(library: library, context: context);
  }

  final SpacyTransformerNativeLibrary _library;
  final NativeFinalizer _finalizer;
  Pointer<_NativeContext>? _context;

  /// Whether [close] released this context.
  bool get isClosed => _context == null;

  /// Runs one non-whitespace byte-BPE sequence and returns tag-label indices.
  Uint16List infer({
    required Uint32List pieceIds,
    required Uint32List tokenPieceLengths,
  }) {
    final context = _context;
    if (context == null) {
      throw const SpacyTransformerNativeException(
        code: 1,
        stage: 'lifecycle',
        message: 'The native transformer context is closed.',
      );
    }
    if (pieceIds.length > maximumSpacyTransformerNativePieces ||
        tokenPieceLengths.length > maximumSpacyTransformerNativeTokens) {
      throw const SpacyTransformerNativeException(
        code: 2,
        stage: 'input',
        message: 'Native transformer input exceeds its fixed limits.',
      );
    }
    final pieces = _copyUint32ToNative(_library, pieceIds);
    Pointer<Uint32>? lengths;
    Pointer<_NativeResult> result;
    try {
      lengths = _copyUint32ToNative(_library, tokenPieceLengths);
      result = _library._infer(
        context,
        pieces,
        pieceIds.length,
        lengths,
        tokenPieceLengths.length,
      );
    } finally {
      _library._bufferFree(pieces.cast<Void>());
      if (lengths != null) _library._bufferFree(lengths.cast<Void>());
    }
    if (result.address == 0) {
      throw const SpacyTransformerNativeException(
        code: 7,
        stage: 'inference',
        message: 'Native transformer result allocation failed.',
      );
    }
    try {
      final status = _library._resultStatus(result);
      if (status != 0) throw _resultError(_library, result, status);
      final size = _library._resultTagsSize(result);
      if (size != tokenPieceLengths.length) {
        throw const SpacyTransformerNativeLibraryException(
          'The native transformer returned an invalid tag count.',
        );
      }
      if (size == 0) return Uint16List(0);
      final data = _library._resultTagsData(result);
      if (data.address == 0) {
        throw const SpacyTransformerNativeLibraryException(
          'The native transformer returned null tag data.',
        );
      }
      final tags = Uint16List.fromList(data.asTypedList(size));
      if (tags.any((tag) => tag >= 49)) {
        throw const SpacyTransformerNativeLibraryException(
          'The native transformer returned an invalid tag index.',
        );
      }
      return tags;
    } finally {
      _library._resultDestroy(result);
    }
  }

  /// Releases this context. Repeated calls are safe.
  void close() {
    final context = _context;
    if (context == null) return;
    _context = null;
    _finalizer.detach(this);
    _library._contextDestroy(context);
  }
}

SpacyTransformerNativeException _contextError(
  SpacyTransformerNativeLibrary library,
  Pointer<_NativeContext> context,
  int status,
) => SpacyTransformerNativeException(
  code: status,
  stage: _decode(
    library._contextErrorStageData(context),
    library._contextErrorStageSize(context),
    'context error stage',
  ),
  message: _decode(
    library._contextErrorMessageData(context),
    library._contextErrorMessageSize(context),
    'context error message',
  ),
);

SpacyTransformerNativeException _resultError(
  SpacyTransformerNativeLibrary library,
  Pointer<_NativeResult> result,
  int status,
) => SpacyTransformerNativeException(
  code: status,
  stage: _decode(
    library._resultErrorStageData(result),
    library._resultErrorStageSize(result),
    'result error stage',
  ),
  message: _decode(
    library._resultErrorMessageData(result),
    library._resultErrorMessageSize(result),
    'result error message',
  ),
);

Uint8List _encodeValidUtf8(String value, {required int maxBytes}) {
  final units = value.codeUnits;
  var byteLength = 0;
  for (var index = 0; index < units.length; index++) {
    final unit = units[index];
    if (unit == 0) {
      throw const SpacyTransformerNativeException(
        code: 3,
        stage: 'model-path',
        message: 'The transformer model path contains NUL.',
      );
    }
    if (unit <= 0x7F) {
      byteLength++;
    } else if (unit <= 0x7FF) {
      byteLength += 2;
    } else if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (index + 1 >= units.length ||
          units[index + 1] < 0xDC00 ||
          units[index + 1] > 0xDFFF) {
        throw const SpacyTransformerNativeException(
          code: 3,
          stage: 'model-path',
          message: 'The transformer model path contains invalid UTF-16.',
        );
      }
      byteLength += 4;
      index++;
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      throw const SpacyTransformerNativeException(
        code: 3,
        stage: 'model-path',
        message: 'The transformer model path contains invalid UTF-16.',
      );
    } else {
      byteLength += 3;
    }
    if (byteLength > maxBytes) {
      throw const SpacyTransformerNativeException(
        code: 2,
        stage: 'model-path',
        message: 'The transformer model path exceeds its native limit.',
      );
    }
  }
  return Uint8List.fromList(utf8.encode(value));
}

Pointer<Uint8> _copyBytesToNative(
  SpacyTransformerNativeLibrary library,
  Uint8List bytes,
) {
  final pointer = library._bufferAlloc(bytes.length);
  if (pointer.address == 0) _allocationFailed();
  if (bytes.isNotEmpty) pointer.asTypedList(bytes.length).setAll(0, bytes);
  return pointer;
}

Pointer<Float> _copyFloat32ToNative(
  SpacyTransformerNativeLibrary library,
  Float32List values,
) {
  final bytes = Uint8List.sublistView(values);
  final pointer = library._bufferAlloc(bytes.length);
  if (pointer.address == 0) _allocationFailed();
  if (bytes.isNotEmpty) pointer.asTypedList(bytes.length).setAll(0, bytes);
  return pointer.cast<Float>();
}

Pointer<Uint32> _copyUint32ToNative(
  SpacyTransformerNativeLibrary library,
  Uint32List values,
) {
  final bytes = Uint8List.sublistView(values);
  final pointer = library._bufferAlloc(bytes.length);
  if (pointer.address == 0) _allocationFailed();
  if (bytes.isNotEmpty) pointer.asTypedList(bytes.length).setAll(0, bytes);
  return pointer.cast<Uint32>();
}

Never _allocationFailed() => throw const SpacyTransformerNativeException(
  code: 7,
  stage: 'allocation',
  message: 'Native transformer input allocation failed.',
);

String _decode(Pointer<Uint8> pointer, int size, String location) {
  if (size < 0 || size > _maximumDiagnosticBytes) {
    throw SpacyTransformerNativeLibraryException(
      'Invalid byte length returned for $location.',
    );
  }
  if (size == 0) return '';
  if (pointer.address == 0) {
    throw SpacyTransformerNativeLibraryException(
      'Null UTF-8 data returned for $location.',
    );
  }
  try {
    return utf8.decode(pointer.asTypedList(size), allowMalformed: false);
  } on FormatException catch (error) {
    throw SpacyTransformerNativeLibraryException(
      'Malformed UTF-8 returned for $location.',
      cause: error,
    );
  }
}
