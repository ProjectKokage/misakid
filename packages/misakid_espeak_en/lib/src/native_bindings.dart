// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:misakid/misaki_en.dart';

/// Native ABI version required by this adapter.
const int espeakEnglishNativeAbiVersion = 1;

const int _maximumPathBytes = 32768;
const int _maximumDecodedBytes = 64 * 1024 * 1024;

/// Exact immutable identities required from a compatible owned-result shim.
const Map<int, String> expectedEspeakEnglishNativeIdentities = <int, String>{
  0: '0.1.0-dev.1',
  1: '1.52.0',
  2: 'bb635eee1ee9c456f4a5cf06fb6cb352ecdd4d61e1951743b423ef22bb57f470',
  3: '730e20a0d06976b23b8344bac21dab6e1da447d0e16906bab6a0b54db89dd6e2',
  4: 'phonemizer-fork-3.3.2-en-preserve-stress-punctuation-tie',
  5: 'misakid-espeak-en-owned-result-v2',
};

/// Bounded, input-free diagnostic returned by the native shim.
final class EspeakEnglishNativeException implements Exception {
  /// Creates one stable native diagnostic.
  const EspeakEnglishNativeException({
    required this.code,
    required this.stage,
    required this.message,
  });

  /// Stable native status code.
  final int code;

  /// Native stage that failed.
  final String stage;

  /// Bounded diagnostic containing no input text or configured path.
  final String message;

  @override
  String toString() =>
      'EspeakEnglishNativeException(code: $code, stage: $stage, '
      'message: $message)';
}

/// Failure to load, bind, or decode the package-owned native shim.
final class EspeakEnglishNativeLibraryException implements Exception {
  /// Creates one native-library compatibility failure.
  const EspeakEnglishNativeLibraryException(this.message, {this.cause});

  /// Actionable failure summary.
  final String message;

  /// Lower-level failure, when available.
  final Object? cause;

  @override
  String toString() => 'EspeakEnglishNativeLibraryException: $message';
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
      Pointer<Uint8>,
      Size,
      Size,
      Size,
    );
typedef _ContextCreateDart =
    Pointer<_NativeContext> Function(
      Pointer<Uint8>,
      int,
      Pointer<Uint8>,
      int,
      int,
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
typedef _PhonemizeNative =
    Pointer<_NativeResult> Function(
      Pointer<_NativeContext>,
      Pointer<Uint8>,
      Size,
      Uint32,
    );
typedef _PhonemizeDart =
    Pointer<_NativeResult> Function(
      Pointer<_NativeContext>,
      Pointer<Uint8>,
      int,
      int,
    );
typedef _ResultStatusNative = Uint32 Function(Pointer<_NativeResult>);
typedef _ResultStatusDart = int Function(Pointer<_NativeResult>);
typedef _ResultDataNative = Pointer<Uint8> Function(Pointer<_NativeResult>);
typedef _ResultDataDart = Pointer<Uint8> Function(Pointer<_NativeResult>);
typedef _ResultSizeNative = Size Function(Pointer<_NativeResult>);
typedef _ResultSizeDart = int Function(Pointer<_NativeResult>);
typedef _ResultDestroyNative = Void Function(Pointer<_NativeResult>);
typedef _ResultDestroyDart = void Function(Pointer<_NativeResult>);

/// Loaded and identity-checked package-owned native ABI.
final class EspeakEnglishNativeLibrary {
  EspeakEnglishNativeLibrary._(DynamicLibrary library)
    : _abiVersion = library.lookupFunction<_AbiNative, _AbiDart>(
        'misakid_espeak_en_abi_version',
      ),
      _identityData = library
          .lookupFunction<_IdentityDataNative, _IdentityDataDart>(
            'misakid_espeak_en_identity_data',
          ),
      _identitySize = library
          .lookupFunction<_IdentitySizeNative, _IdentitySizeDart>(
            'misakid_espeak_en_identity_size',
          ),
      _bufferAlloc = library
          .lookupFunction<_BufferAllocNative, _BufferAllocDart>(
            'misakid_espeak_en_buffer_alloc',
          ),
      _bufferFree = library.lookupFunction<_BufferFreeNative, _BufferFreeDart>(
        'misakid_espeak_en_buffer_free',
      ),
      _contextCreate = library
          .lookupFunction<_ContextCreateNative, _ContextCreateDart>(
            'misakid_espeak_en_context_create',
          ),
      _contextStatus = library
          .lookupFunction<_ContextStatusNative, _ContextStatusDart>(
            'misakid_espeak_en_context_status',
          ),
      _contextErrorStageData = library
          .lookupFunction<_ContextDataNative, _ContextDataDart>(
            'misakid_espeak_en_context_error_stage_data',
          ),
      _contextErrorStageSize = library
          .lookupFunction<_ContextSizeNative, _ContextSizeDart>(
            'misakid_espeak_en_context_error_stage_size',
          ),
      _contextErrorMessageData = library
          .lookupFunction<_ContextDataNative, _ContextDataDart>(
            'misakid_espeak_en_context_error_message_data',
          ),
      _contextErrorMessageSize = library
          .lookupFunction<_ContextSizeNative, _ContextSizeDart>(
            'misakid_espeak_en_context_error_message_size',
          ),
      _contextDestroy = library
          .lookupFunction<_ContextDestroyNative, _ContextDestroyDart>(
            'misakid_espeak_en_context_destroy',
          ),
      _contextDestroyPointer = library
          .lookup<NativeFunction<_ContextDestroyNative>>(
            'misakid_espeak_en_context_destroy',
          )
          .cast<NativeFunction<Void Function(Pointer<Void>)>>(),
      _phonemize = library.lookupFunction<_PhonemizeNative, _PhonemizeDart>(
        'misakid_espeak_en_phonemize',
      ),
      _resultStatus = library
          .lookupFunction<_ResultStatusNative, _ResultStatusDart>(
            'misakid_espeak_en_result_status',
          ),
      _resultErrorStageData = library
          .lookupFunction<_ResultDataNative, _ResultDataDart>(
            'misakid_espeak_en_result_error_stage_data',
          ),
      _resultErrorStageSize = library
          .lookupFunction<_ResultSizeNative, _ResultSizeDart>(
            'misakid_espeak_en_result_error_stage_size',
          ),
      _resultErrorMessageData = library
          .lookupFunction<_ResultDataNative, _ResultDataDart>(
            'misakid_espeak_en_result_error_message_data',
          ),
      _resultErrorMessageSize = library
          .lookupFunction<_ResultSizeNative, _ResultSizeDart>(
            'misakid_espeak_en_result_error_message_size',
          ),
      _resultOutputData = library
          .lookupFunction<_ResultDataNative, _ResultDataDart>(
            'misakid_espeak_en_result_output_data',
          ),
      _resultOutputSize = library
          .lookupFunction<_ResultSizeNative, _ResultSizeDart>(
            'misakid_espeak_en_result_output_size',
          ),
      _resultDestroy = library
          .lookupFunction<_ResultDestroyNative, _ResultDestroyDart>(
            'misakid_espeak_en_result_destroy',
          );

  /// Loads required symbols and validates immutable shim identities.
  static EspeakEnglishNativeLibrary load(String path) {
    try {
      final bindings = EspeakEnglishNativeLibrary._(DynamicLibrary.open(path));
      bindings._validateIdentity();
      return bindings;
    } on EspeakEnglishNativeLibraryException {
      rethrow;
    } on Object catch (error) {
      throw EspeakEnglishNativeLibraryException(
        'The configured library is not a compatible misakid eSpeak adapter.',
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
  final _PhonemizeDart _phonemize;
  final _ResultStatusDart _resultStatus;
  final _ResultDataDart _resultErrorStageData;
  final _ResultSizeDart _resultErrorStageSize;
  final _ResultDataDart _resultErrorMessageData;
  final _ResultSizeDart _resultErrorMessageSize;
  final _ResultDataDart _resultOutputData;
  final _ResultSizeDart _resultOutputSize;
  final _ResultDestroyDart _resultDestroy;

  /// Native identity values after exact validation.
  late final Map<int, String> identities =
      Map<int, String>.unmodifiable(<int, String>{
        for (final field in expectedEspeakEnglishNativeIdentities.keys)
          field: _decode(
            _identityData(field),
            _identitySize(field),
            'native identity',
          ),
      });

  void _validateIdentity() {
    if (_abiVersion() != espeakEnglishNativeAbiVersion) {
      throw const EspeakEnglishNativeLibraryException(
        'The eSpeak adapter ABI version is incompatible.',
      );
    }
    for (final expected in expectedEspeakEnglishNativeIdentities.entries) {
      if (identities[expected.key] != expected.value) {
        throw const EspeakEnglishNativeLibraryException(
          'The eSpeak adapter source or resource identity is incompatible.',
        );
      }
    }
  }
}

/// Reusable native eSpeak context with deterministic ownership.
final class EspeakEnglishNativeContext implements Finalizable {
  EspeakEnglishNativeContext._({
    required EspeakEnglishNativeLibrary library,
    required Pointer<_NativeContext> context,
    required this.maxInputBytes,
    required this.maxOutputBytes,
  }) : _library = library,
       _context = context,
       _finalizer = NativeFinalizer(library._contextDestroyPointer) {
    _finalizer.attach(this, context.cast<Void>(), detach: this);
  }

  /// Initializes the exact caller-supplied runtime and data paths.
  static EspeakEnglishNativeContext create({
    required EspeakEnglishNativeLibrary library,
    required String runtimeLibraryPath,
    required String dataPath,
    required int maxInputBytes,
    required int maxOutputBytes,
  }) {
    final runtimeBytes = _encodeValidUtf8(
      runtimeLibraryPath,
      rejectNul: true,
      maxBytes: _maximumPathBytes,
    );
    final dataBytes = _encodeValidUtf8(
      dataPath,
      rejectNul: true,
      maxBytes: _maximumPathBytes,
    );
    Pointer<Uint8>? runtimeBuffer;
    Pointer<Uint8>? dataBuffer;
    Pointer<_NativeContext> context;
    try {
      // Both copies sit inside the try, so a failed second allocation still
      // frees the first buffer.
      runtimeBuffer = _copyToNative(library, runtimeBytes);
      dataBuffer = _copyToNative(library, dataBytes);
      context = library._contextCreate(
        runtimeBuffer,
        runtimeBytes.length,
        dataBuffer,
        dataBytes.length,
        maxInputBytes,
        maxOutputBytes,
      );
    } finally {
      if (runtimeBuffer != null) {
        library._bufferFree(runtimeBuffer.cast<Void>());
      }
      if (dataBuffer != null) {
        library._bufferFree(dataBuffer.cast<Void>());
      }
    }
    if (context.address == 0) {
      throw const EspeakEnglishNativeException(
        code: 11,
        stage: 'initialize',
        message: 'Native context allocation failed.',
      );
    }
    final status = library._contextStatus(context);
    if (status != 0) {
      try {
        throw EspeakEnglishNativeException(
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
      } finally {
        library._contextDestroy(context);
      }
    }
    return EspeakEnglishNativeContext._(
      library: library,
      context: context,
      maxInputBytes: maxInputBytes,
      maxOutputBytes: maxOutputBytes,
    );
  }

  final EspeakEnglishNativeLibrary _library;
  final NativeFinalizer _finalizer;

  /// Configured maximum input size in UTF-8 bytes.
  final int maxInputBytes;

  /// Configured maximum native result size in UTF-8 bytes.
  final int maxOutputBytes;

  Pointer<_NativeContext>? _context;

  /// Whether [close] released this context.
  bool get isClosed => _context == null;

  /// Enforces the configured limit and C-ABI text contract on one public call.
  void validateInput(String text) {
    _encodeValidUtf8(text, rejectNul: true, maxBytes: maxInputBytes);
  }

  /// Enforces the configured aggregate copied-output limit.
  void validateOutput(String text) {
    if (utf8.encode(text).length > maxOutputBytes) {
      throw const EspeakEnglishNativeException(
        code: 10,
        stage: 'result-copy',
        message: 'The formatted eSpeak output exceeded the configured limit.',
      );
    }
  }

  /// Returns the direct eSpeak IPA/tie output before phonemizer formatting.
  String phonemizeChunk(String text, EnglishDialect dialect) {
    final context = _context;
    if (context == null) {
      throw const EspeakEnglishNativeException(
        code: 1,
        stage: 'lifecycle',
        message: 'The native eSpeak context is closed.',
      );
    }
    final bytes = _encodeValidUtf8(
      text,
      rejectNul: true,
      maxBytes: maxInputBytes,
    );
    final input = _copyToNative(_library, bytes);
    Pointer<_NativeResult> result;
    try {
      result = _library._phonemize(
        context,
        input,
        bytes.length,
        dialect == EnglishDialect.american ? 0 : 1,
      );
    } finally {
      _library._bufferFree(input.cast<Void>());
    }
    if (result.address == 0) {
      throw const EspeakEnglishNativeException(
        code: 11,
        stage: 'conversion',
        message: 'Native result allocation failed.',
      );
    }
    try {
      final status = _library._resultStatus(result);
      if (status != 0) {
        throw EspeakEnglishNativeException(
          code: status,
          stage: _decode(
            _library._resultErrorStageData(result),
            _library._resultErrorStageSize(result),
            'result error stage',
          ),
          message: _decode(
            _library._resultErrorMessageData(result),
            _library._resultErrorMessageSize(result),
            'result error message',
          ),
        );
      }
      final size = _library._resultOutputSize(result);
      if (size > maxOutputBytes) {
        throw const EspeakEnglishNativeLibraryException(
          'The native eSpeak output exceeds the configured Dart limit.',
        );
      }
      return _decode(
        _library._resultOutputData(result),
        size,
        'eSpeak output',
        maxBytes: maxOutputBytes,
      );
    } finally {
      _library._resultDestroy(result);
    }
  }

  /// Releases the native context. Repeated calls are safe.
  void close() {
    final context = _context;
    if (context == null) return;
    _context = null;
    _finalizer.detach(this);
    _library._contextDestroy(context);
  }
}

Uint8List _encodeValidUtf8(
  String value, {
  required bool rejectNul,
  required int maxBytes,
}) {
  final units = value.codeUnits;
  var byteLength = 0;
  for (var index = 0; index < units.length; index++) {
    final unit = units[index];
    if (rejectNul && unit == 0) {
      throw const EspeakEnglishNativeException(
        code: 3,
        stage: 'input',
        message: 'NUL scalars are unsupported by the eSpeak C API.',
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
        throw const EspeakEnglishNativeException(
          code: 3,
          stage: 'input',
          message: 'Input contains an unpaired UTF-16 surrogate.',
        );
      }
      byteLength += 4;
      index++;
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      throw const EspeakEnglishNativeException(
        code: 3,
        stage: 'input',
        message: 'Input contains an unpaired UTF-16 surrogate.',
      );
    } else {
      byteLength += 3;
    }
    if (byteLength > maxBytes) {
      throw EspeakEnglishNativeException(
        code: 2,
        stage: 'input',
        message: 'Input exceeds the configured $maxBytes-byte limit.',
      );
    }
  }
  return utf8.encode(value);
}

Pointer<Uint8> _copyToNative(
  EspeakEnglishNativeLibrary library,
  Uint8List bytes,
) {
  final pointer = library._bufferAlloc(bytes.length);
  if (pointer.address == 0) {
    throw const EspeakEnglishNativeException(
      code: 11,
      stage: 'allocation',
      message: 'Native buffer allocation failed.',
    );
  }
  if (bytes.isNotEmpty) pointer.asTypedList(bytes.length).setAll(0, bytes);
  return pointer;
}

String _decode(
  Pointer<Uint8> pointer,
  int size,
  String location, {
  int maxBytes = _maximumDecodedBytes,
}) {
  if (size < 0 || size > maxBytes) {
    throw EspeakEnglishNativeLibraryException(
      'Invalid byte length returned for $location.',
    );
  }
  if (size == 0) return '';
  if (pointer.address == 0) {
    throw EspeakEnglishNativeLibraryException(
      'Null UTF-8 data returned for $location.',
    );
  }
  try {
    return utf8.decode(pointer.asTypedList(size), allowMalformed: false);
  } on FormatException catch (error) {
    throw EspeakEnglishNativeLibraryException(
      'Malformed UTF-8 returned for $location.',
      cause: error,
    );
  }
}
