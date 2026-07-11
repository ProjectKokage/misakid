// MurmurHash3 was written by Austin Appleby and placed in the public domain.
//
// This specialized uint64 path is a Dart transcription of
// `MurmurHash3_x86_128_uint64` in thinc 8.3.4's numpy backend. It intentionally
// retains uint64 overflow after every operation.

const int _uint64Mask = 0xffffffffffffffff;
const int _uint32Mask = 0xffffffff;

/// Hashes one signed-int uint64 bit pattern into Thinc's four uint32 keys.
///
/// spaCy stores lexical feature IDs as uint64 values. On the Dart VM their
/// exact bit patterns may arrive as negative [int] values; masking preserves
/// those bits before applying the pinned Thinc hash path.
List<int> murmurHash3X86_128Uint64(int value, int seed) {
  if (seed < 0 || seed > _uint32Mask) {
    throw RangeError.range(seed, 0, _uint32Mask, 'seed');
  }

  var h1 = value & _uint64Mask;
  h1 = _multiply64(h1, 0x87c37b91114253d5);
  h1 = _rotateLeft64(h1, 31);
  h1 = _multiply64(h1, 0x4cf5ad432745937f);
  h1 = (h1 ^ seed ^ 8) & _uint64Mask;

  var h2 = (seed ^ 8) & _uint64Mask;
  h1 = (h1 + h2) & _uint64Mask;
  h2 = (h2 + h1) & _uint64Mask;
  h1 = _finalMix64(h1);
  h2 = _finalMix64(h2);
  h1 = (h1 + h2) & _uint64Mask;
  h2 = (h2 + h1) & _uint64Mask;

  return List<int>.unmodifiable(<int>[
    h1 & _uint32Mask,
    (h1 >>> 32) & _uint32Mask,
    h2 & _uint32Mask,
    (h2 >>> 32) & _uint32Mask,
  ]);
}

int _multiply64(int left, int right) =>
    ((left & _uint64Mask) * (right & _uint64Mask)) & _uint64Mask;

int _rotateLeft64(int value, int count) =>
    (((value << count) & _uint64Mask) | (value >>> (64 - count))) & _uint64Mask;

int _finalMix64(int value) {
  var result = value & _uint64Mask;
  result = (result ^ (result >>> 33)) & _uint64Mask;
  result = _multiply64(result, 0xff51afd7ed558ccd);
  result = (result ^ (result >>> 33)) & _uint64Mask;
  result = _multiply64(result, 0xc4ceb9fe1a85ec53);
  return (result ^ (result >>> 33)) & _uint64Mask;
}
