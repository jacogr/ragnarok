# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## JAM fixed-width unsigned integers, Gray Paper v0.8.0 C.1.7. See spec/fixed-unsigned.md for
## domain, error and ownership details.
##
## Exposes FixedUnsigned and ByteWidth domains, encodeFixed/decodeFixed and checked
## value/consumption results.

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
  # The encoder alone constructs successful owned prefixes; callers cannot forge or retag them.
  FixedEncodeResult* = object
    case success: bool
    of true:
      # Copied fixed storage is private until the success precondition is satisfied.
      encodedValue: EncodedFixed
    of false:
      # Default/error alternatives carry only a reason; default remains InvalidWidth.
      failureReason: FixedError
  # The decoder alone constructs copied values with complete prefix extents.
  FixedDecodeResult* = object
    case success: bool
    of true:
      # Zero-width success still has value zero and consumes no bytes.
      decodedValue: FixedUnsigned
      byteConsumed: range[0..8]
    of false:
      # No value or cursor progress exists on failure.
      failureReason: FixedError

# Read the encoding outcome without exposing a writable discriminator.
func ok*(value: FixedEncodeResult): bool = value.success
# Read the decoding outcome; a default result remains an explicit failure.
func ok*(value: FixedDecodeResult): bool = value.success
# Return copied encoded storage only for a completed successful encoding.
func encoded*(value: FixedEncodeResult): EncodedFixed {.inline, requires: value.success.} =
  value.encodedValue
# Decode success owns its value; no default zero can escape a failed decode.
func value*(value: FixedDecodeResult): FixedUnsigned {.inline, requires: value.success.} =
  value.decodedValue
# Only a complete decode may advance the caller's prefix cursor.
func consumed*(value: FixedDecodeResult): range[0..8] {.inline, requires: value.success.} =
  value.byteConsumed
# Encoding success has no failure reason; ask for it only after selecting failure.
func error*(value: FixedEncodeResult): FixedError {.inline, requires: not value.success.} =
  value.failureReason
# Decoding success has no failure reason, even when it consumes zero bytes.
func error*(value: FixedDecodeResult): FixedError {.inline, requires: not value.success.} =
  value.failureReason

# Encode exactly width little-endian bytes without allocation or silent narrowing.
# Inline this small scalar operation so checked container loops can eliminate temporary result construction.
proc encodeFixed*(value: FixedUnsigned, width: ByteWidth): FixedEncodeResult {.inline, raises: [].} =
  let count = int(width)
  # Validate the signed width before using it as a loop bound or shift amount.
  if count < 0 or count > 8:
    return FixedEncodeResult(success: false, failureReason: FixedError.InvalidWidth)
  let x = uint64(value)
  # For widths below eight, reject all values outside N_(2^(8*count)).
  # This also restricts width zero to zero; skipping width eight avoids shifting by 64.
  if count < 8 and x >= (1'u64 shl (8 * count)):
    return FixedEncodeResult(success: false, failureReason: FixedError.ValueOutOfRange)
  var encoded = EncodedFixed(len: count)
  # Extract the least significant octet first; masking makes each byte conversion bounded.
  # The empty loop for width zero produces the specified empty representation.
  for i in 0..<count:
    encoded.bytes[i] = byte((x shr (8 * i)) and 255)
  FixedEncodeResult(success: true, encodedValue: encoded)

# Decode a borrowed prefix of exactly width bytes; trailing bytes remain with the caller.
# Inline without disabling checks; enclosing loops already prove each complete scalar input extent.
proc decodeFixed*(input: openArray[byte], width: ByteWidth): FixedDecodeResult {.inline, raises: [].} =
  let count = int(width)
  # Reject invalid widths even if the buffer is large enough; this check precedes indexing.
  if count < 0 or count > 8:
    return FixedDecodeResult(success: false, failureReason: FixedError.InvalidWidth)
  # A shorter buffer cannot contain the entire requested field; read nothing on failure.
  if input.len < count:
    return FixedDecodeResult(success: false, failureReason: FixedError.Truncated)
  var x = 0'u64
  # Place each octet at its little-endian position; the largest shift is 56 bits.
  # Width zero leaves x at zero and does not inspect input, even if trailing bytes exist.
  for i in 0..<count:
    x = x or (uint64(input[i]) shl (8 * i))
  FixedDecodeResult(success: true, decodedValue: FixedUnsigned(x), byteConsumed: count)
