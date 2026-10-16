## JAM general natural-number codec. See spec/codec.md for the pinned definition.
## Allocation-free; input is borrowed only during decode and output is a value.
type
  # A protocol natural, kept separate from ordinary integers to require an explicit conversion.
  JamNatural* = distinct uint64
  # Owns the encoded bytes; only the first len bytes are part of the wire representation.
  EncodedNatural* = object
    bytes*: array[9, byte]
    len*: range[1..9]
  # Reasons why the supplied bytes do not contain a complete, canonical natural.
  DecodeError* = enum
    truncated, nonCanonical
  # A tagged result: callers must check ok before accessing the success or error fields.
  DecodeResult* = object
    case ok*: bool
    of true:
      # Success exposes the value and the exact prefix size for the next field.
      value*: JamNatural
      consumed*: range[1..9]
    of false:
      # Failure exposes only the reason, preventing access to a nonexistent decoded value.
      error*: DecodeError

# Encode a natural into its shortest JAM representation, using at most nine bytes.
proc encode*(value: JamNatural): EncodedNatural {.raises: [].} =
  result = EncodedNatural(len: 1)
  let x = uint64(value)
  var tail: range[0..8] = 0
  # Find the payload size: each extra byte contributes eight bits but uses one more header bit.
  # This raises the value limit by seven bits per step; stop at eight to keep shifts below 64.
  while tail < 8 and x >= (1'u64 shl (7 * (tail + 1))):
    inc tail
  result.len = tail + 1
  # Values at or above 2^56 use the ff marker followed by the full eight-byte value.
  if tail == 8:
    result.bytes[0] = 255
  else:
    # Compact forms reserve leading bits for the size and retain the high value bits in the header.
    let prefix = 256'u64 - (1'u64 shl (8 - tail))
    result.bytes[0] = byte(prefix + (x shr (8 * tail)))
  # Write the low bytes first; masking keeps each narrowing conversion within byte range.
  for i in 0..<tail:
    result.bytes[i + 1] = byte((x shr (8 * i)) and 255)

# Read one natural from the start of a borrowed buffer without allocating or advancing caller state.
proc decode*(input: openArray[byte]): DecodeResult {.raises: [].} =
  ## Decode one canonical value from the front; trailing bytes belong to caller.
  ## Failure has no consumed count. No input-derived allocation or host-int cast.
  # A header is required even for zero; an empty buffer cannot contain a value.
  if input.len == 0:
    return DecodeResult(ok: false, error: truncated)
  var tail: range[0..8] = 0
  var mask = 128
  # Each leading one announces another payload byte; a zero terminates the header prefix.
  # The all-ones ff header announces eight bytes.
  while tail < 8 and (int(input[0]) and mask) != 0:
    inc tail
    mask = mask shr 1
  # Check the entire announced representation before indexing any payload byte.
  if input.len < tail + 1:
    return DecodeResult(ok: false, error: truncated)
  var x = 0'u64
  # For compact forms, place the remaining header bits above the little-endian payload.
  # The ff marker carries no value bits, so the eight-byte form skips this step.
  if tail < 8:
    x = uint64(int(input[0]) and (mask - 1)) shl (8 * tail)
  # Merge each payload byte into its position; the largest shift is 56 bits.
  for i in 0..<tail:
    x = x or (uint64(input[i + 1]) shl (8 * i))
  if tail > 0 and x < (1'u64 shl (7 * tail)):
    return DecodeResult(ok: false, error: nonCanonical)
  DecodeResult(ok: true, value: JamNatural(x), consumed: tail + 1)
