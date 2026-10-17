import std/[assertions, syncio]
import ../../../src/codec/fixed_unsigned

# Default primitive results preserve InvalidWidth; valid width-zero operations remain successes.
let defaultEncoding = default(FixedEncodeResult)
let defaultDecoding = default(FixedDecodeResult)
assert not defaultEncoding.ok and defaultEncoding.error == FixedError.InvalidWidth
assert not defaultDecoding.ok and defaultDecoding.error == FixedError.InvalidWidth
# Check the value, exact byte count, all shorter prefixes and preservation of the next field.
proc checkFixed(x: uint64, count: int) =
  let encoded = encodeFixed(FixedUnsigned(x), ByteWidth(count))
  assert encoded.ok and encoded.encoded.len == count
  let bytes = encoded.encoded.bytes
  let decoded = decodeFixed(bytes.toOpenArray(0, count - 1), ByteWidth(count))
  assert decoded.ok and uint64(decoded.value) == x and decoded.consumed == count
  # Every shorter prefix must fail; a zero-width field has no incomplete representation.
  for size in 0..<count:
    let short = decodeFixed(bytes.toOpenArray(0, size - 1), ByteWidth(count))
    assert not short.ok and short.error == FixedError.Truncated
  var padded: array[9, byte] = default(array[9, byte])
  # Preserve just the field bytes before adding an unrelated next-field sentinel.
  for i in 0..<count:
    padded[i] = bytes[i]
  padded[count] = 42
  let prefix = decodeFixed(padded.toOpenArray(0, count), ByteWidth(count))
  assert prefix.ok and prefix.consumed == count and uint64(prefix.value) == x

# Expose arbitrary bytes and widths to the decoder and verify its prefix/error invariants.
proc fuzzFixed*(input: openArray[byte], width: ByteWidth) =
  let decoded = decodeFixed(input, width)
  let count = int(width)
  # Unsupported widths must be reported before any buffer-length error.
  if count < 0 or count > 8:
    assert not decoded.ok and decoded.error == FixedError.InvalidWidth
  elif input.len < count:
    # A valid width with insufficient input must fail rather than reading beyond the slice.
    assert not decoded.ok and decoded.error == FixedError.Truncated
  else:
    # Every complete fixed-width pattern is valid, including zero high octets.
    assert decoded.ok and decoded.consumed == count
    let encoded = encodeFixed(decoded.value, width)
    assert encoded.ok and encoded.encoded.len == count
    # Re-encoding must preserve exactly the consumed prefix, not trailing bytes.
    for i in 0..<count:
      assert encoded.encoded.bytes[i] == input[i]

# Exhaust the full one-byte and two-byte value domains.
for x in 0'u64..255'u64:
  checkFixed(x, 1)
for x in 0'u64..65535'u64:
  checkFixed(x, 2)
# Exercise every supported width, including empty output and the uint64 maximum.
for count in 0..8:
  let maximum = if count == 8: high(uint64) else: (1'u64 shl (8 * count)) - 1
  checkFixed(0, count)
  checkFixed(maximum, count)
  checkFixed(maximum div 2, count)
  # Widths below eight have a representable first value that must be rejected for not fitting.
  if count < 8:
    let overflow = encodeFixed(FixedUnsigned(maximum + 1), ByteWidth(count))
    assert not overflow.ok and overflow.error == FixedError.ValueOutOfRange
  # Probe every internal bit boundary rather than only the outer width boundary.
  for bits in 1..<8 * count:
    let pivot = 1'u64 shl bits
    checkFixed(pivot - 1, count)
    checkFixed(pivot, count)
    checkFixed(pivot + 1, count)
# Signed width extremes must be rejected before a shift or an array access.
for count in [low(int), -1, 9, high(int)]:
  let encoded = encodeFixed(FixedUnsigned(0), ByteWidth(count))
  assert not encoded.ok and encoded.error == FixedError.InvalidWidth
  fuzzFixed([], ByteWidth(count))
var state = 0x4a414d'u64
# Deterministic fuzzing varies both buffer length and width, including invalid widths.
for iteration in 0..<10000:
  var bytes: array[12, byte] = default(array[12, byte])
  # Generate each byte with xorshift so any failure can be replayed from the same seed.
  for i in 0..<bytes.len:
    state = state xor (state shl 13)
    state = state xor (state shr 7)
    state = state xor (state shl 17)
    bytes[i] = byte(state and 255)
  fuzzFixed(bytes.toOpenArray(0, iteration mod 13 - 1), ByteWidth(iteration mod 13 - 2))
echo "Nim fixed unsigned: widths, overflow, truncations and 10000 fuzz cases passed"
