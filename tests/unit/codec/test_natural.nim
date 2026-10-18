# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exercise JAM natural-number boundaries, canonical encodings, round trips and every truncated
## prefix.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import std/[assertions, syncio]
import ../../../src/codec/natural

# Verify a value round-trips, rejects every incomplete encoding, and leaves trailing bytes unread.
proc check(x: uint64) =
  let encoded = encode(JamNatural(x))
  let decoded = decode(encoded.bytes.toOpenArray(0, encoded.len - 1))
  assert decoded.ok and uint64(decoded.value) == x
  assert decoded.consumed == encoded.len
  # Remove bytes from every possible cut point, including the header, to verify truncation errors.
  for size in 0..<encoded.len:
    let short = decode(encoded.bytes.toOpenArray(0, size - 1))
    assert not short.ok and short.error == truncated
  var padded = newSeq[byte](encoded.len + 1)
  # Copy just the encoded prefix so the appended sentinel acts as an unrelated next field.
  for i in 0..<encoded.len: padded[i] = encoded.bytes[i]
  padded[padded.len - 1] = 42
  let prefix = decode(padded)
  assert prefix.ok and prefix.consumed == encoded.len

# A default natural result stays failed with its original readable reason, never a valid zero.
let defaultResult = default(DecodeResult)
assert not defaultResult.ok and defaultResult.error == truncated
# Exhaust the first 65,536 values, covering all one- and two-byte forms and part of the next size.
for x in 0'u64..65535'u64: check(x)
# Probe both sides of every binary boundary, including all changes in encoded length.
for bits in 1..63:
  let pivot = 1'u64 shl bits
  check(pivot - 1)
  check(pivot)
  check(pivot + 1)
check(high(uint64))
# Exercise every possible header with zero payload bytes and enough storage to avoid truncation.
for first in 0..255:
  var bytes: array[9, byte] = default(array[9, byte])
  bytes[0] = byte(first)
  let decoded = decode(bytes)
  # These headers contain no value bits; with a zero payload they are overlong encodings of zero.
  if first in [128, 192, 224, 240, 248, 252, 254, 255]:
    assert not decoded.ok and decoded.error == nonCanonical
  else:
    # Other headers contain enough value bits to be canonical; verify the bytes remain unchanged.
    assert decoded.ok
    let encoded = encode(decoded.value)
    # For an accepted header, re-encoding must reproduce its consumed bytes exactly.
    for i in 0..<encoded.len: assert encoded.bytes[i] == bytes[i]

# Deterministic fuzz entry point, usable by external harnesses too.
# Check the canonical-prefix invariant for any supplied byte sequence; invalid inputs may return errors.
proc fuzzOne*(input: openArray[byte]) =
  let decoded = decode(input)
  # Only accepted inputs have a value to re-encode; errors are valid outcomes for arbitrary bytes.
  if decoded.ok:
    let encoded = encode(decoded.value)
    assert encoded.len == decoded.consumed
    # Compare every consumed byte, rather than only checking that the decoded number round-trips.
    for i in 0..<encoded.len: assert encoded.bytes[i] == input[i]

var state = 0x123456789abcdef'u64
# Use a fixed seed and vary lengths from zero through twelve so failures are reproducible.
for iteration in 0..<10000:
  var bytes: array[12, byte] = default(array[12, byte])
  # Generate each byte with xorshift; this is deterministic test data, not cryptographic randomness.
  for i in 0..<bytes.len:
    state = state xor (state shl 13)
    state = state xor (state shr 7)
    state = state xor (state shl 17)
    bytes[i] = byte(state and 255)
  fuzzOne(bytes.toOpenArray(0, iteration mod 13 - 1))
echo "Nim natural: boundaries, truncations, canonicality and 10000 fuzz cases passed"
