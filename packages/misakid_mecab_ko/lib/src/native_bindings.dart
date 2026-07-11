// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

/// Native ABI version required by this Dart adapter.
const int mecabKoNativeAbiVersion = 1;

const int _maximumDictionaryPathBytes = 32768;
const int _maximumReturnedFieldBytes = 1024 * 1024;
const int _maximumReturnedTokens = 65536;

/// Exact immutable identities required from a compatible native library.
const Map<int, String> expectedMecabKoNativeIdentities = <int, String>{
  0: '0.1.0-dev.1',
  1: '0.996/ko-0.9.2',
  2: '9b870a921e8d80fa11eec1066d21c0960916fa617e77a8c83758223dfe28827f',
  3: 'd0e0f696fc33c2183307d4eb87ec3b17845f90b81bf843bd0981e574ee3c38cb',
  4: 'misakid-mecab-ko-safety-v1',
  5: 'd851fab8708745442ac3a2d970851dbd0ef598e786a363f406847461d77a6f51',
};

/// Bounded, input-free diagnostic returned by the native analyzer.
final class MecabKoNativeException implements Exception {
  /// Creates a native diagnostic.
  const MecabKoNativeException({
    required this.code,
    required this.stage,
    required this.message,
  });

  /// Stable native status code.
  final int code;

  /// Pipeline stage that failed.
  final String stage;

  /// Bounded diagnostic without user input or configured paths.
  final String message;

  @override
  String toString() =>
      'MecabKoNativeException(code: $code, stage: $stage, message: $message)';
}

/// Failure to load, bind, or decode the configured native library.
final class MecabKoNativeLibraryException implements Exception {
  /// Creates a native-library compatibility failure.
  const MecabKoNativeLibraryException(this.message, {this.cause});

  /// Actionable failure summary.
  final String message;

  /// Lower-level failure, when one exists.
  final Object? cause;

  @override
  String toString() => 'MecabKoNativeLibraryException: $message';
}

/// Immutable owned copy of one `(surface, POS tag)` result.
final class MecabKoRawToken {
  /// Creates a raw morphology token.
  const MecabKoRawToken({required this.surface, required this.tag});

  /// Exact token surface.
  final String surface;

  /// Exact first MeCab feature field.
  final String tag;
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
    Pointer<_NativeContext> Function(Pointer<Uint8>, Size, Size);
typedef _ContextCreateDart =
    Pointer<_NativeContext> Function(Pointer<Uint8>, int, int);
typedef _ContextStatusNative = Uint32 Function(Pointer<_NativeContext>);
typedef _ContextStatusDart = int Function(Pointer<_NativeContext>);
typedef _ContextDataNative = Pointer<Uint8> Function(Pointer<_NativeContext>);
typedef _ContextDataDart = Pointer<Uint8> Function(Pointer<_NativeContext>);
typedef _ContextSizeNative = Size Function(Pointer<_NativeContext>);
typedef _ContextSizeDart = int Function(Pointer<_NativeContext>);
typedef _ContextDestroyNative = Void Function(Pointer<_NativeContext>);
typedef _ContextDestroyDart = void Function(Pointer<_NativeContext>);
typedef _AnalyzeNative =
    Pointer<_NativeResult> Function(
      Pointer<_NativeContext>,
      Pointer<Uint8>,
      Size,
    );
typedef _AnalyzeDart =
    Pointer<_NativeResult> Function(
      Pointer<_NativeContext>,
      Pointer<Uint8>,
      int,
    );
typedef _ResultStatusNative = Uint32 Function(Pointer<_NativeResult>);
typedef _ResultStatusDart = int Function(Pointer<_NativeResult>);
typedef _ResultDataNative = Pointer<Uint8> Function(Pointer<_NativeResult>);
typedef _ResultDataDart = Pointer<Uint8> Function(Pointer<_NativeResult>);
typedef _ResultSizeNative = Size Function(Pointer<_NativeResult>);
typedef _ResultSizeDart = int Function(Pointer<_NativeResult>);
typedef _TokenCountNative = Size Function(Pointer<_NativeResult>);
typedef _TokenCountDart = int Function(Pointer<_NativeResult>);
typedef _TokenStringDataNative =
    Pointer<Uint8> Function(Pointer<_NativeResult>, Size, Uint32);
typedef _TokenStringDataDart =
    Pointer<Uint8> Function(Pointer<_NativeResult>, int, int);
typedef _TokenStringSizeNative =
    Size Function(Pointer<_NativeResult>, Size, Uint32);
typedef _TokenStringSizeDart = int Function(Pointer<_NativeResult>, int, int);
typedef _ResultDestroyNative = Void Function(Pointer<_NativeResult>);
typedef _ResultDestroyDart = void Function(Pointer<_NativeResult>);

/// Loaded and identity-checked native ABI bindings.
final class MecabKoNativeLibrary {
  MecabKoNativeLibrary._(DynamicLibrary library)
    : _abiVersion = library.lookupFunction<_AbiNative, _AbiDart>(
        'misakid_mecab_ko_abi_version',
      ),
      _identityData = library
          .lookupFunction<_IdentityDataNative, _IdentityDataDart>(
            'misakid_mecab_ko_identity_data',
          ),
      _identitySize = library
          .lookupFunction<_IdentitySizeNative, _IdentitySizeDart>(
            'misakid_mecab_ko_identity_size',
          ),
      _bufferAlloc = library
          .lookupFunction<_BufferAllocNative, _BufferAllocDart>(
            'misakid_mecab_ko_buffer_alloc',
          ),
      _bufferFree = library.lookupFunction<_BufferFreeNative, _BufferFreeDart>(
        'misakid_mecab_ko_buffer_free',
      ),
      _contextCreate = library
          .lookupFunction<_ContextCreateNative, _ContextCreateDart>(
            'misakid_mecab_ko_context_create',
          ),
      _contextStatus = library
          .lookupFunction<_ContextStatusNative, _ContextStatusDart>(
            'misakid_mecab_ko_context_status',
          ),
      _contextErrorStageData = library
          .lookupFunction<_ContextDataNative, _ContextDataDart>(
            'misakid_mecab_ko_context_error_stage_data',
          ),
      _contextErrorStageSize = library
          .lookupFunction<_ContextSizeNative, _ContextSizeDart>(
            'misakid_mecab_ko_context_error_stage_size',
          ),
      _contextErrorMessageData = library
          .lookupFunction<_ContextDataNative, _ContextDataDart>(
            'misakid_mecab_ko_context_error_message_data',
          ),
      _contextErrorMessageSize = library
          .lookupFunction<_ContextSizeNative, _ContextSizeDart>(
            'misakid_mecab_ko_context_error_message_size',
          ),
      _contextDestroy = library
          .lookupFunction<_ContextDestroyNative, _ContextDestroyDart>(
            'misakid_mecab_ko_context_destroy',
          ),
      _contextDestroyPointer = library
          .lookup<NativeFunction<_ContextDestroyNative>>(
            'misakid_mecab_ko_context_destroy',
          )
          .cast<NativeFunction<Void Function(Pointer<Void>)>>(),
      _analyze = library.lookupFunction<_AnalyzeNative, _AnalyzeDart>(
        'misakid_mecab_ko_analyze',
      ),
      _resultStatus = library
          .lookupFunction<_ResultStatusNative, _ResultStatusDart>(
            'misakid_mecab_ko_result_status',
          ),
      _resultErrorStageData = library
          .lookupFunction<_ResultDataNative, _ResultDataDart>(
            'misakid_mecab_ko_result_error_stage_data',
          ),
      _resultErrorStageSize = library
          .lookupFunction<_ResultSizeNative, _ResultSizeDart>(
            'misakid_mecab_ko_result_error_stage_size',
          ),
      _resultErrorMessageData = library
          .lookupFunction<_ResultDataNative, _ResultDataDart>(
            'misakid_mecab_ko_result_error_message_data',
          ),
      _resultErrorMessageSize = library
          .lookupFunction<_ResultSizeNative, _ResultSizeDart>(
            'misakid_mecab_ko_result_error_message_size',
          ),
      _resultTokenCount = library
          .lookupFunction<_TokenCountNative, _TokenCountDart>(
            'misakid_mecab_ko_result_token_count',
          ),
      _resultTokenStringData = library
          .lookupFunction<_TokenStringDataNative, _TokenStringDataDart>(
            'misakid_mecab_ko_result_token_string_data',
          ),
      _resultTokenStringSize = library
          .lookupFunction<_TokenStringSizeNative, _TokenStringSizeDart>(
            'misakid_mecab_ko_result_token_string_size',
          ),
      _resultDestroy = library
          .lookupFunction<_ResultDestroyNative, _ResultDestroyDart>(
            'misakid_mecab_ko_result_destroy',
          );

  /// Loads every required symbol and verifies immutable source identities.
  static MecabKoNativeLibrary load(String path) {
    try {
      final bindings = MecabKoNativeLibrary._(DynamicLibrary.open(path));
      bindings._validateIdentity();
      return bindings;
    } on MecabKoNativeLibraryException {
      rethrow;
    } on Object catch (error) {
      throw MecabKoNativeLibraryException(
        'The configured library could not be loaded as a compatible '
        'misakid MeCab-ko adapter.',
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
  final _AnalyzeDart _analyze;
  final _ResultStatusDart _resultStatus;
  final _ResultDataDart _resultErrorStageData;
  final _ResultSizeDart _resultErrorStageSize;
  final _ResultDataDart _resultErrorMessageData;
  final _ResultSizeDart _resultErrorMessageSize;
  final _TokenCountDart _resultTokenCount;
  final _TokenStringDataDart _resultTokenStringData;
  final _TokenStringSizeDart _resultTokenStringSize;
  final _ResultDestroyDart _resultDestroy;

  /// Native identity values after exact validation.
  late final Map<int, String> identities =
      Map<int, String>.unmodifiable(<int, String>{
        for (final field in expectedMecabKoNativeIdentities.keys)
          field: _decode(
            _identityData(field),
            _identitySize(field),
            'native identity',
          ),
      });

  void _validateIdentity() {
    final actualAbi = _abiVersion();
    if (actualAbi != mecabKoNativeAbiVersion) {
      throw MecabKoNativeLibraryException(
        'MeCab-ko ABI mismatch: expected $mecabKoNativeAbiVersion, '
        'got $actualAbi.',
      );
    }
    for (final expected in expectedMecabKoNativeIdentities.entries) {
      if (identities[expected.key] != expected.value) {
        throw const MecabKoNativeLibraryException(
          'The MeCab-ko native source or resource identity is incompatible.',
        );
      }
    }
  }
}

/// One reusable native analyzer context with deterministic ownership.
final class MecabKoNativeAnalyzer implements Finalizable {
  MecabKoNativeAnalyzer._({
    required MecabKoNativeLibrary library,
    required Pointer<_NativeContext> context,
    required this.maxInputBytes,
  }) : _library = library,
       _context = context,
       _finalizer = NativeFinalizer(library._contextDestroyPointer) {
    _finalizer.attach(this, context.cast<Void>(), detach: this);
  }

  /// Creates a context after its library and dictionary have been validated.
  static MecabKoNativeAnalyzer create({
    required MecabKoNativeLibrary library,
    required String dictionaryPath,
    required int maxInputBytes,
  }) {
    final pathBytes = _encodeValidUtf8(
      dictionaryPath,
      rejectNul: true,
      maxBytes: _maximumDictionaryPathBytes,
      tooLarge: const MecabKoNativeException(
        code: 1,
        stage: 'configuration',
        message: 'The dictionary path exceeds the native path limit.',
      ),
    );
    final pathBuffer = _copyToNative(library, pathBytes);
    Pointer<_NativeContext> context;
    try {
      context = library._contextCreate(
        pathBuffer,
        pathBytes.length,
        maxInputBytes,
      );
    } finally {
      library._bufferFree(pathBuffer.cast<Void>());
    }
    if (context.address == 0) {
      throw const MecabKoNativeException(
        code: 8,
        stage: 'initialize',
        message: 'Native context allocation failed.',
      );
    }
    final status = library._contextStatus(context);
    if (status != 0) {
      try {
        throw MecabKoNativeException(
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
    return MecabKoNativeAnalyzer._(
      library: library,
      context: context,
      maxInputBytes: maxInputBytes,
    );
  }

  final MecabKoNativeLibrary _library;
  final NativeFinalizer _finalizer;

  /// Maximum UTF-8 input bytes configured on Dart and native sides.
  final int maxInputBytes;
  Pointer<_NativeContext>? _context;

  /// Whether [close] has released the native analyzer.
  bool get isClosed => _context == null;

  /// Returns owned copies of all MeCab surface/tag pairs.
  List<MecabKoRawToken> analyzeRaw(String text) {
    final context = _context;
    if (context == null) {
      throw const MecabKoNativeException(
        code: 1,
        stage: 'lifecycle',
        message: 'The MeCab-ko native analyzer is closed.',
      );
    }
    final bytes = _encodeValidUtf8(
      text,
      rejectNul: true,
      maxBytes: maxInputBytes,
      tooLarge: MecabKoNativeException(
        code: 2,
        stage: 'input',
        message:
            'Input exceeds the configured $maxInputBytes-byte analyzer limit.',
      ),
    );
    final input = _copyToNative(_library, bytes);
    Pointer<_NativeResult> result;
    try {
      result = _library._analyze(context, input, bytes.length);
    } finally {
      _library._bufferFree(input.cast<Void>());
    }
    if (result.address == 0) {
      throw const MecabKoNativeException(
        code: 8,
        stage: 'analysis',
        message: 'Native result allocation failed.',
      );
    }
    try {
      final status = _library._resultStatus(result);
      if (status != 0) {
        throw MecabKoNativeException(
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
      final count = _library._resultTokenCount(result);
      if (count < 0 || count > _maximumReturnedTokens) {
        throw const MecabKoNativeLibraryException(
          'The native adapter returned an invalid token count.',
        );
      }
      return List<MecabKoRawToken>.unmodifiable(<MecabKoRawToken>[
        for (var index = 0; index < count; index++)
          MecabKoRawToken(
            surface: _decode(
              _library._resultTokenStringData(result, index, 0),
              _library._resultTokenStringSize(result, index, 0),
              'token $index surface',
            ),
            tag: _decode(
              _library._resultTokenStringData(result, index, 1),
              _library._resultTokenStringSize(result, index, 1),
              'token $index tag',
            ),
          ),
      ]);
    } finally {
      _library._resultDestroy(result);
    }
  }

  /// Releases the native context. Calling this repeatedly is safe.
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
  int? maxBytes,
  MecabKoNativeException? tooLarge,
}) {
  final codeUnits = value.codeUnits;
  var byteLength = 0;
  for (var index = 0; index < codeUnits.length; index++) {
    final unit = codeUnits[index];
    if (rejectNul && unit == 0) {
      throw const MecabKoNativeException(
        code: 1,
        stage: 'input',
        message: 'NUL scalars are unsupported by the MeCab-ko C boundary.',
      );
    }
    if (unit <= 0x7F) {
      byteLength++;
    } else if (unit <= 0x7FF) {
      byteLength += 2;
    } else if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (index + 1 >= codeUnits.length ||
          codeUnits[index + 1] < 0xDC00 ||
          codeUnits[index + 1] > 0xDFFF) {
        throw const MecabKoNativeException(
          code: 3,
          stage: 'input',
          message: 'Input contains an unpaired UTF-16 surrogate.',
        );
      }
      byteLength += 4;
      index++;
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      throw const MecabKoNativeException(
        code: 3,
        stage: 'input',
        message: 'Input contains an unpaired UTF-16 surrogate.',
      );
    } else {
      byteLength += 3;
    }
    if (maxBytes != null && byteLength > maxBytes) {
      throw tooLarge ??
          const MecabKoNativeException(
            code: 2,
            stage: 'input',
            message: 'Input exceeds the configured analyzer byte limit.',
          );
    }
  }
  return utf8.encode(value);
}

Pointer<Uint8> _copyToNative(MecabKoNativeLibrary library, Uint8List bytes) {
  final pointer = library._bufferAlloc(bytes.length);
  if (pointer.address == 0) {
    throw const MecabKoNativeException(
      code: 8,
      stage: 'allocation',
      message: 'Native buffer allocation failed.',
    );
  }
  if (bytes.isNotEmpty) pointer.asTypedList(bytes.length).setAll(0, bytes);
  return pointer;
}

String _decode(Pointer<Uint8> pointer, int size, String location) {
  if (size < 0 || size > _maximumReturnedFieldBytes) {
    throw MecabKoNativeLibraryException(
      'Invalid UTF-8 byte length returned for $location.',
    );
  }
  if (size == 0) return '';
  if (pointer.address == 0) {
    throw MecabKoNativeLibraryException(
      'Null UTF-8 data returned for $location.',
    );
  }
  try {
    return utf8.decode(pointer.asTypedList(size), allowMalformed: false);
  } on FormatException catch (error) {
    throw MecabKoNativeLibraryException(
      'Malformed UTF-8 returned for $location.',
      cause: error,
    );
  }
}
