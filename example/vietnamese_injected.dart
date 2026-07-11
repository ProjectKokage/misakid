import 'package:misakid/misaki_vi.dart';

void main() {
  final result = VietnameseG2pEngine(
    tokenizer: _FixedVietnameseTokenizer(),
  ).convert('Xin chào');

  print(result.phonemes); // sin1 caw2
}

/// A fixed-record example, not a production underthesea adapter.
final class _FixedVietnameseTokenizer implements VietnameseTokenizerBackend {
  @override
  final BackendInfo info = BackendInfo(
    name: 'fixed-vietnamese-example',
    version: '1',
  );

  @override
  List<String> tokenize(String text) {
    if (text != 'xin chào') {
      throw StateError('The fixed example only contains its documented case.');
    }
    return const <String>['xin', 'chào'];
  }
}
