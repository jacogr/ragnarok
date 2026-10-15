## JAM fixed-width unsigned integers, Gray Paper v0.7.1 C.1.7.
## See spec/fixed-unsigned.md for domain, error and ownership details.
type
  # An unsigned wire value, distinct from both ordinary uint64 and general JAM naturals.
  FixedUnsigned* = distinct uint64
  # A requested byte count, validated by both APIs before use; supported counts are 0..8.
  ByteWidth* = distinct int
  # Complete output storage belongs to the caller; only the first len bytes are emitted.
  EncodedFixed* = object
    bytes*: array[8, byte]
    len*: range[0..8]
  # Errors distinguish an unsupported width, a value that will not fit, and missing input bytes.
  FixedError* {.pure.} = enum
    InvalidWidth, ValueOutOfRange, Truncated
  # Success carries owned encoded storage; failure exposes only its typed reason.
  FixedEncodeResult* = object
    case ok*: bool
    of true:
      # Callers may read the encoded prefix only after checking ok.
      encoded*: EncodedFixed
    of false:
      error*: FixedError
  # Success carries a value and prefix length; failure cannot expose a decoded value.
  FixedDecodeResult* = object
    case ok*: bool
    of true:
      # Zero-width success has value zero and consumes no bytes.
      value*: FixedUnsigned
      consumed*: range[0..8]
    of false:
      # No caller cursor is advanced on an error.
      error*: FixedError

# Encode exactly width little-endian bytes without allocation or silent narrowing.
# Inline this small scalar operation so checked container loops can eliminate temporary result construction.
proc encodeFixed*(value: FixedUnsigned, width: ByteWidth): FixedEncodeResult {.inline, raises: [].} =
  let count = int(width)
  # Validate the signed width before using it as a loop bound or shift amount.
  if count < 0 or count > 8:
    return FixedEncodeResult(ok: false, error: FixedError.InvalidWidth)
  let x = uint64(value)
  # For widths below eight, reject all values outside N_(2^(8*count)).
  # This also restricts width zero to zero; skipping width eight avoids shifting by 64.
  if count < 8 and x >= (1'u64 shl (8 * count)):
    return FixedEncodeResult(ok: false, error: FixedError.ValueOutOfRange)
  var encoded = EncodedFixed(len: count)
  # Extract the least significant octet first; masking makes each byte conversion bounded.
  # The empty loop for width zero produces the specified empty representation.
  for i in 0..<count:
    encoded.bytes[i] = byte((x shr (8 * i)) and 255)
  FixedEncodeResult(ok: true, encoded: encoded)

# Decode a borrowed prefix of exactly width bytes; trailing bytes remain with the caller.
# Inline without disabling checks; enclosing loops already prove each complete scalar input extent.
proc decodeFixed*(input: openArray[byte], width: ByteWidth): FixedDecodeResult {.inline, raises: [].} =
  let count = int(width)
  # Reject invalid widths even if the buffer is large enough; this check precedes indexing.
  if count < 0 or count > 8:
    return FixedDecodeResult(ok: false, error: FixedError.InvalidWidth)
  # A shorter buffer cannot contain the entire requested field; read nothing on failure.
  if input.len < count:
    return FixedDecodeResult(ok: false, error: FixedError.Truncated)
  var x = 0'u64
  # Place each octet at its little-endian position; the largest shift is 56 bits.
  # Width zero leaves x at zero and does not inspect input, even if trailing bytes exist.
  for i in 0..<count:
    x = x or (uint64(input[i]) shl (8 * i))
  FixedDecodeResult(ok: true, value: FixedUnsigned(x), consumed: count)
