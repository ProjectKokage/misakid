import 'package:misakid_spacy_trf_en/src/native_bindings.dart';
import 'package:test/test.dart';

void main() {
  test('pins the complete native ABI and resource identity', () {
    expect(spacyTransformerNativeAbiVersion, 1);
    expect(spacyTransformerTaggerWeightCount, 49 * 768);
    expect(spacyTransformerTaggerBiasCount, 49);
    expect(maximumSpacyTransformerNativePieces, 4000002);
    expect(maximumSpacyTransformerNativeTokens, 1000000);
    expect(expectedSpacyTransformerNativeIdentities, <int, String>{
      0: '0.1.0-dev.1',
      1: '3.8.0',
      2: '2b7061c623f424486e5dddcff79276927127cee339cc6a9d26d87837c3e6074a',
      3: 'aecff2bb262b0b9aeb554af63ecaa3f02e6e87b28f6e8c2440e5ec24acd52589',
      4: 'roberta-base-12x768-stride104-window144-mean49',
      5: 'misakid-spacy-trf-en-accelerate-v1',
    });
  });

  test('missing or incompatible native libraries fail explicitly', () {
    expect(
      () => SpacyTransformerNativeLibrary.load(
        '/definitely/missing/libmisakid_spacy_trf_en.dylib',
      ),
      throwsA(isA<SpacyTransformerNativeLibraryException>()),
    );
  });
}
