// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

@DefaultAsset('package:misakid_openjtalk/misakid_openjtalk')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

/// Native ABI version required by this Dart adapter.
const int openJtalkNativeAbiVersion = 1;

const int _maximumDictionaryPathBytes = 32768;

/// Exact immutable identities required from a compatible native library.
const Map<int, String> expectedOpenJtalkNativeIdentities = <int, String>{
  0: '0.1.0-dev.1',
  1: '0.4.1',
  2: '1.11',
  3: 'dea0f240fad8dc8b9ea1984920a4d64a48227a40c2924a3c545eaeca50357857',
  4: 'd5ada46f7fc2b52c1c79c273eb9668ff6ad7ab276a8db9d8be119ef93440f0dc',
  5: 'misakid-openjtalk-safety-v1',
  6: '8b26c37228c9e9b92333e612e1144c958f2788d219e46c8652f698a089be1ccc',
};

/// Bounded, input-free diagnostic returned by the native frontend.
final class OpenJtalkNativeException implements Exception {
  /// Creates a native diagnostic.
  const OpenJtalkNativeException({
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
      'OpenJtalkNativeException(code: $code, stage: $stage, message: $message)';
}

/// Failure to load, bind, or decode the configured native library.
final class OpenJtalkNativeLibraryException implements Exception {
  /// Creates a native-library compatibility failure.
  const OpenJtalkNativeLibraryException(this.message, {this.cause});

  /// Actionable failure summary.
  final String message;

  /// Lower-level failure, when one exists.
  final Object? cause;

  @override
  String toString() => 'OpenJtalkNativeLibraryException: $message';
}

/// Immutable copy of all 14 fields in one Open JTalk frontend word.
final class OpenJtalkRawWord {
  /// Creates one validated raw frontend word.
  OpenJtalkRawWord({
    required List<String> stringFields,
    required List<int> integerFields,
  }) : stringFields = List<String>.unmodifiable(stringFields),
       integerFields = List<int>.unmodifiable(integerFields);

  /// Eleven string fields in the native ABI's stable enum order.
  final List<String> stringFields;

  /// Accent, mora-size, and raw-chain fields in stable enum order.
  final List<int> integerFields;

  /// Raw `string` surface field.
  String get surface => stringFields[0];

  /// Raw `pos` field.
  String get partOfSpeech => stringFields[1];

  /// Raw `pron` field.
  String get pronunciation => stringFields[9];

  /// Raw `acc` field.
  int get accent => integerFields[0];

  /// Raw `mora_size` field.
  int get moraSize => integerFields[1];

  /// Raw integer `chain_flag` field.
  int get rawChainFlag => integerFields[2];
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
typedef _WordCountNative = Size Function(Pointer<_NativeResult>);
typedef _WordCountDart = int Function(Pointer<_NativeResult>);
typedef _WordStringDataNative =
    Pointer<Uint8> Function(Pointer<_NativeResult>, Size, Uint32);
typedef _WordStringDataDart =
    Pointer<Uint8> Function(Pointer<_NativeResult>, int, int);
typedef _WordStringSizeNative =
    Size Function(Pointer<_NativeResult>, Size, Uint32);
typedef _WordStringSizeDart = int Function(Pointer<_NativeResult>, int, int);
typedef _WordIntegerNative =
    Int32 Function(Pointer<_NativeResult>, Size, Uint32);
typedef _WordIntegerDart = int Function(Pointer<_NativeResult>, int, int);
typedef _ResultDestroyNative = Void Function(Pointer<_NativeResult>);
typedef _ResultDestroyDart = void Function(Pointer<_NativeResult>);

@Native<_AbiNative>(symbol: 'misakid_openjtalk_abi_version')
external int _bundledAbiVersion();

@Native<_IdentityDataNative>(symbol: 'misakid_openjtalk_identity_data')
external Pointer<Uint8> _bundledIdentityData(int field);

@Native<_IdentitySizeNative>(symbol: 'misakid_openjtalk_identity_size')
external int _bundledIdentitySize(int field);

@Native<_BufferAllocNative>(symbol: 'misakid_openjtalk_buffer_alloc')
external Pointer<Uint8> _bundledBufferAlloc(int size);

@Native<_BufferFreeNative>(symbol: 'misakid_openjtalk_buffer_free')
external void _bundledBufferFree(Pointer<Void> buffer);

@Native<_ContextCreateNative>(symbol: 'misakid_openjtalk_context_create')
external Pointer<_NativeContext> _bundledContextCreate(
  Pointer<Uint8> dictionaryPath,
  int dictionaryPathSize,
  int maxInputBytes,
);

@Native<_ContextStatusNative>(symbol: 'misakid_openjtalk_context_status')
external int _bundledContextStatus(Pointer<_NativeContext> context);

@Native<_ContextDataNative>(
  symbol: 'misakid_openjtalk_context_error_stage_data',
)
external Pointer<Uint8> _bundledContextErrorStageData(
  Pointer<_NativeContext> context,
);

@Native<_ContextSizeNative>(
  symbol: 'misakid_openjtalk_context_error_stage_size',
)
external int _bundledContextErrorStageSize(Pointer<_NativeContext> context);

@Native<_ContextDataNative>(
  symbol: 'misakid_openjtalk_context_error_message_data',
)
external Pointer<Uint8> _bundledContextErrorMessageData(
  Pointer<_NativeContext> context,
);

@Native<_ContextSizeNative>(
  symbol: 'misakid_openjtalk_context_error_message_size',
)
external int _bundledContextErrorMessageSize(Pointer<_NativeContext> context);

@Native<_ContextDestroyNative>(symbol: 'misakid_openjtalk_context_destroy')
external void _bundledContextDestroy(Pointer<_NativeContext> context);

@Native<_AnalyzeNative>(symbol: 'misakid_openjtalk_analyze')
external Pointer<_NativeResult> _bundledAnalyze(
  Pointer<_NativeContext> context,
  Pointer<Uint8> utf8,
  int utf8Size,
);

@Native<_ResultStatusNative>(symbol: 'misakid_openjtalk_result_status')
external int _bundledResultStatus(Pointer<_NativeResult> result);

@Native<_ResultDataNative>(symbol: 'misakid_openjtalk_result_error_stage_data')
external Pointer<Uint8> _bundledResultErrorStageData(
  Pointer<_NativeResult> result,
);

@Native<_ResultSizeNative>(symbol: 'misakid_openjtalk_result_error_stage_size')
external int _bundledResultErrorStageSize(Pointer<_NativeResult> result);

@Native<_ResultDataNative>(
  symbol: 'misakid_openjtalk_result_error_message_data',
)
external Pointer<Uint8> _bundledResultErrorMessageData(
  Pointer<_NativeResult> result,
);

@Native<_ResultSizeNative>(
  symbol: 'misakid_openjtalk_result_error_message_size',
)
external int _bundledResultErrorMessageSize(Pointer<_NativeResult> result);

@Native<_WordCountNative>(symbol: 'misakid_openjtalk_result_word_count')
external int _bundledResultWordCount(Pointer<_NativeResult> result);

@Native<_WordStringDataNative>(
  symbol: 'misakid_openjtalk_result_word_string_data',
)
external Pointer<Uint8> _bundledResultWordStringData(
  Pointer<_NativeResult> result,
  int wordIndex,
  int field,
);

@Native<_WordStringSizeNative>(
  symbol: 'misakid_openjtalk_result_word_string_size',
)
external int _bundledResultWordStringSize(
  Pointer<_NativeResult> result,
  int wordIndex,
  int field,
);

@Native<_WordIntegerNative>(symbol: 'misakid_openjtalk_result_word_integer')
external int _bundledResultWordInteger(
  Pointer<_NativeResult> result,
  int wordIndex,
  int field,
);

@Native<_ResultDestroyNative>(symbol: 'misakid_openjtalk_result_destroy')
external void _bundledResultDestroy(Pointer<_NativeResult> result);

/// Loaded and identity-checked native ABI bindings.
final class OpenJtalkNativeLibrary {
  OpenJtalkNativeLibrary._(DynamicLibrary library)
    : _abiVersion = library.lookupFunction<_AbiNative, _AbiDart>(
        'misakid_openjtalk_abi_version',
      ),
      _identityData = library
          .lookupFunction<_IdentityDataNative, _IdentityDataDart>(
            'misakid_openjtalk_identity_data',
          ),
      _identitySize = library
          .lookupFunction<_IdentitySizeNative, _IdentitySizeDart>(
            'misakid_openjtalk_identity_size',
          ),
      _bufferAlloc = library
          .lookupFunction<_BufferAllocNative, _BufferAllocDart>(
            'misakid_openjtalk_buffer_alloc',
          ),
      _bufferFree = library.lookupFunction<_BufferFreeNative, _BufferFreeDart>(
        'misakid_openjtalk_buffer_free',
      ),
      _contextCreate = library
          .lookupFunction<_ContextCreateNative, _ContextCreateDart>(
            'misakid_openjtalk_context_create',
          ),
      _contextStatus = library
          .lookupFunction<_ContextStatusNative, _ContextStatusDart>(
            'misakid_openjtalk_context_status',
          ),
      _contextErrorStageData = library
          .lookupFunction<_ContextDataNative, _ContextDataDart>(
            'misakid_openjtalk_context_error_stage_data',
          ),
      _contextErrorStageSize = library
          .lookupFunction<_ContextSizeNative, _ContextSizeDart>(
            'misakid_openjtalk_context_error_stage_size',
          ),
      _contextErrorMessageData = library
          .lookupFunction<_ContextDataNative, _ContextDataDart>(
            'misakid_openjtalk_context_error_message_data',
          ),
      _contextErrorMessageSize = library
          .lookupFunction<_ContextSizeNative, _ContextSizeDart>(
            'misakid_openjtalk_context_error_message_size',
          ),
      _contextDestroy = library
          .lookupFunction<_ContextDestroyNative, _ContextDestroyDart>(
            'misakid_openjtalk_context_destroy',
          ),
      _contextDestroyPointer = library
          .lookup<NativeFunction<_ContextDestroyNative>>(
            'misakid_openjtalk_context_destroy',
          )
          .cast<NativeFunction<Void Function(Pointer<Void>)>>(),
      _analyze = library.lookupFunction<_AnalyzeNative, _AnalyzeDart>(
        'misakid_openjtalk_analyze',
      ),
      _resultStatus = library
          .lookupFunction<_ResultStatusNative, _ResultStatusDart>(
            'misakid_openjtalk_result_status',
          ),
      _resultErrorStageData = library
          .lookupFunction<_ResultDataNative, _ResultDataDart>(
            'misakid_openjtalk_result_error_stage_data',
          ),
      _resultErrorStageSize = library
          .lookupFunction<_ResultSizeNative, _ResultSizeDart>(
            'misakid_openjtalk_result_error_stage_size',
          ),
      _resultErrorMessageData = library
          .lookupFunction<_ResultDataNative, _ResultDataDart>(
            'misakid_openjtalk_result_error_message_data',
          ),
      _resultErrorMessageSize = library
          .lookupFunction<_ResultSizeNative, _ResultSizeDart>(
            'misakid_openjtalk_result_error_message_size',
          ),
      _resultWordCount = library
          .lookupFunction<_WordCountNative, _WordCountDart>(
            'misakid_openjtalk_result_word_count',
          ),
      _resultWordStringData = library
          .lookupFunction<_WordStringDataNative, _WordStringDataDart>(
            'misakid_openjtalk_result_word_string_data',
          ),
      _resultWordStringSize = library
          .lookupFunction<_WordStringSizeNative, _WordStringSizeDart>(
            'misakid_openjtalk_result_word_string_size',
          ),
      _resultWordInteger = library
          .lookupFunction<_WordIntegerNative, _WordIntegerDart>(
            'misakid_openjtalk_result_word_integer',
          ),
      _resultDestroy = library
          .lookupFunction<_ResultDestroyNative, _ResultDestroyDart>(
            'misakid_openjtalk_result_destroy',
          );

  OpenJtalkNativeLibrary._bundled()
    : _abiVersion = _bundledAbiVersion,
      _identityData = _bundledIdentityData,
      _identitySize = _bundledIdentitySize,
      _bufferAlloc = _bundledBufferAlloc,
      _bufferFree = _bundledBufferFree,
      _contextCreate = _bundledContextCreate,
      _contextStatus = _bundledContextStatus,
      _contextErrorStageData = _bundledContextErrorStageData,
      _contextErrorStageSize = _bundledContextErrorStageSize,
      _contextErrorMessageData = _bundledContextErrorMessageData,
      _contextErrorMessageSize = _bundledContextErrorMessageSize,
      _contextDestroy = _bundledContextDestroy,
      _contextDestroyPointer =
          Native.addressOf<NativeFunction<_ContextDestroyNative>>(
            _bundledContextDestroy,
          ).cast<NativeFunction<Void Function(Pointer<Void>)>>(),
      _analyze = _bundledAnalyze,
      _resultStatus = _bundledResultStatus,
      _resultErrorStageData = _bundledResultErrorStageData,
      _resultErrorStageSize = _bundledResultErrorStageSize,
      _resultErrorMessageData = _bundledResultErrorMessageData,
      _resultErrorMessageSize = _bundledResultErrorMessageSize,
      _resultWordCount = _bundledResultWordCount,
      _resultWordStringData = _bundledResultWordStringData,
      _resultWordStringSize = _bundledResultWordStringSize,
      _resultWordInteger = _bundledResultWordInteger,
      _resultDestroy = _bundledResultDestroy;

  /// Loads all required symbols and verifies immutable ABI/source identities.
  static OpenJtalkNativeLibrary load(String path) {
    try {
      final bindings = OpenJtalkNativeLibrary._(DynamicLibrary.open(path));
      bindings._validateIdentity();
      return bindings;
    } on OpenJtalkNativeLibraryException {
      rethrow;
    } on Object catch (error) {
      throw OpenJtalkNativeLibraryException(
        'The configured library could not be loaded as a compatible '
        'misakid Open JTalk adapter.',
        cause: error,
      );
    }
  }

  /// Loads the package's build-hook native asset and verifies its identities.
  static OpenJtalkNativeLibrary loadBundled() {
    try {
      final bindings = OpenJtalkNativeLibrary._bundled();
      bindings._validateIdentity();
      return bindings;
    } on OpenJtalkNativeLibraryException {
      rethrow;
    } on Object catch (error) {
      throw OpenJtalkNativeLibraryException(
        'The bundled native asset could not be loaded as a compatible '
        'misakid Open JTalk adapter.',
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
  final _WordCountDart _resultWordCount;
  final _WordStringDataDart _resultWordStringData;
  final _WordStringSizeDart _resultWordStringSize;
  final _WordIntegerDart _resultWordInteger;
  final _ResultDestroyDart _resultDestroy;

  /// Native identity values after exact validation.
  late final Map<int, String> identities =
      Map<int, String>.unmodifiable(<int, String>{
        for (final field in expectedOpenJtalkNativeIdentities.keys)
          field: _decode(
            _identityData(field),
            _identitySize(field),
            'native identity',
          ),
      });

  void _validateIdentity() {
    final actualAbi = _abiVersion();
    if (actualAbi != openJtalkNativeAbiVersion) {
      throw OpenJtalkNativeLibraryException(
        'Open JTalk ABI mismatch: expected $openJtalkNativeAbiVersion, '
        'got $actualAbi.',
      );
    }
    for (final expected in expectedOpenJtalkNativeIdentities.entries) {
      if (identities[expected.key] != expected.value) {
        throw const OpenJtalkNativeLibraryException(
          'The Open JTalk native source or resource identity is incompatible.',
        );
      }
    }
  }
}

/// One reusable native frontend context with deterministic ownership.
final class OpenJtalkNativeFrontend implements Finalizable {
  OpenJtalkNativeFrontend._({
    required OpenJtalkNativeLibrary library,
    required Pointer<_NativeContext> context,
    required this.maxInputBytes,
  }) : _library = library,
       _context = context,
       _finalizer = NativeFinalizer(library._contextDestroyPointer) {
    _finalizer.attach(this, context.cast<Void>(), detach: this);
  }

  /// Creates a context after its library and dictionary have been validated.
  static OpenJtalkNativeFrontend create({
    required OpenJtalkNativeLibrary library,
    required String dictionaryPath,
    required int maxInputBytes,
  }) {
    final pathBytes = _encodeValidUtf8(
      dictionaryPath,
      rejectNul: true,
      maxBytes: _maximumDictionaryPathBytes,
      tooLarge: const OpenJtalkNativeException(
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
      throw const OpenJtalkNativeException(
        code: 8,
        stage: 'initialize',
        message: 'Native context allocation failed.',
      );
    }
    final status = library._contextStatus(context);
    if (status != 0) {
      try {
        throw OpenJtalkNativeException(
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
    return OpenJtalkNativeFrontend._(
      library: library,
      context: context,
      maxInputBytes: maxInputBytes,
    );
  }

  final OpenJtalkNativeLibrary _library;
  final NativeFinalizer _finalizer;

  /// Maximum UTF-8 input bytes configured on both Dart and native sides.
  final int maxInputBytes;
  Pointer<_NativeContext>? _context;

  /// Whether the native context has been released.
  bool get isClosed => _context == null;

  /// Returns owned copies of all raw Open JTalk word fields.
  List<OpenJtalkRawWord> analyzeRaw(String text) {
    final context = _context;
    if (context == null) {
      throw const OpenJtalkNativeException(
        code: 1,
        stage: 'lifecycle',
        message: 'The Open JTalk native frontend is closed.',
      );
    }
    final bytes = _encodeValidUtf8(
      text,
      rejectNul: true,
      maxBytes: maxInputBytes,
      tooLarge: OpenJtalkNativeException(
        code: 2,
        stage: 'input',
        message:
            'Input exceeds the configured $maxInputBytes-byte frontend limit.',
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
      throw const OpenJtalkNativeException(
        code: 8,
        stage: 'analysis',
        message: 'Native result allocation failed.',
      );
    }
    try {
      final status = _library._resultStatus(result);
      if (status != 0) {
        throw OpenJtalkNativeException(
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
      final words = <OpenJtalkRawWord>[];
      final count = _library._resultWordCount(result);
      for (var wordIndex = 0; wordIndex < count; wordIndex++) {
        final strings = <String>[
          for (var field = 0; field < 11; field++)
            _decode(
              _library._resultWordStringData(result, wordIndex, field),
              _library._resultWordStringSize(result, wordIndex, field),
              'word $wordIndex string field $field',
            ),
        ];
        final integers = <int>[
          for (var field = 0; field < 3; field++)
            _library._resultWordInteger(result, wordIndex, field),
        ];
        words.add(
          OpenJtalkRawWord(stringFields: strings, integerFields: integers),
        );
      }
      return List<OpenJtalkRawWord>.unmodifiable(words);
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
  OpenJtalkNativeException? tooLarge,
}) {
  final codeUnits = value.codeUnits;
  var byteLength = 0;
  for (var index = 0; index < codeUnits.length; index++) {
    final unit = codeUnits[index];
    if (rejectNul && unit == 0) {
      throw const OpenJtalkNativeException(
        code: 1,
        stage: 'input',
        message: 'NUL scalars are unsupported by the Open JTalk C frontend.',
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
        throw const OpenJtalkNativeException(
          code: 3,
          stage: 'input',
          message: 'Input contains an unpaired UTF-16 surrogate.',
        );
      }
      byteLength += 4;
      index++;
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      throw const OpenJtalkNativeException(
        code: 3,
        stage: 'input',
        message: 'Input contains an unpaired UTF-16 surrogate.',
      );
    } else {
      byteLength += 3;
    }
    if (maxBytes != null && byteLength > maxBytes) {
      throw tooLarge ??
          const OpenJtalkNativeException(
            code: 2,
            stage: 'input',
            message: 'Input exceeds the configured frontend byte limit.',
          );
    }
  }

  return utf8.encode(value);
}

Pointer<Uint8> _copyToNative(OpenJtalkNativeLibrary library, Uint8List bytes) {
  final pointer = library._bufferAlloc(bytes.length);
  if (pointer.address == 0) {
    throw const OpenJtalkNativeException(
      code: 8,
      stage: 'allocation',
      message: 'Native buffer allocation failed.',
    );
  }
  if (bytes.isNotEmpty) pointer.asTypedList(bytes.length).setAll(0, bytes);
  return pointer;
}

String _decode(Pointer<Uint8> pointer, int size, String location) {
  if (size < 0 || size > 1024 * 1024) {
    throw OpenJtalkNativeLibraryException(
      'Invalid UTF-8 byte length returned for $location.',
    );
  }
  if (size == 0) return '';
  if (pointer.address == 0) {
    throw OpenJtalkNativeLibraryException(
      'Null UTF-8 data returned for $location.',
    );
  }
  try {
    return utf8.decode(pointer.asTypedList(size), allowMalformed: false);
  } on FormatException catch (error) {
    throw OpenJtalkNativeLibraryException(
      'Malformed UTF-8 returned for $location.',
      cause: error,
    );
  }
}
