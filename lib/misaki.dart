/// Shared, platform-neutral APIs for the Misaki Dart port.
///
/// Language engines are exposed from their own entrypoints, such as
/// `package:misakid/misaki_ja.dart`, so applications only import the APIs they
/// use.
library;

export 'src/core/backend.dart';
export 'src/core/constants.dart';
export 'src/core/engine.dart';
export 'src/core/errors.dart';
export 'src/core/kokoro_frontend.dart';
export 'src/core/metadata.dart';
export 'src/core/result.dart';
export 'src/core/strict_json.dart';
export 'src/core/token.dart';
