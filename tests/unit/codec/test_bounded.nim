# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exercise bounded byte strings and fixed-width sequences, including truncation, borrowed spans
## and atomic writes.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import std/[assertions, syncio]
import ../../../src/codec/[bounded, natural, fixed_unsigned]

# Check byte-string boundaries, exact borrowed spans, every truncation and failure atomicity.
proc checkBlob(size: int) =
  var value = newSeq[byte](size)
  # Distinct data exposes byte ordering, prefix corruption and omitted payload bytes.
  for i in 0..<size: value[i] = byte(i mod 256)
  var wire = newSeq[byte](size + 10)
  let encoded = encodeBytes(value, ByteLimit(uint64(size)), wire)
  assert encoded.error == ContainerError.None
  wire[encoded.written] = 42
  let decoded = decodeBytesBorrowed(wire.toOpenArray(0, encoded.written), ByteLimit(uint64(size)))
  assert decoded.error == ContainerError.None and decoded.length == size
  assert decoded.consumed == encoded.written
  # The returned indices refer to the exact payload in the original buffer.
  for i in 0..<size: assert wire[decoded.offset + i] == value[i]
  # All incomplete container prefixes must fail without returning a span.
  for cut in 0..<encoded.written:
    let short = decodeBytesBorrowed(wire.toOpenArray(0, cut - 1), ByteLimit(uint64(size)))
    assert short.error == ContainerError.Truncated
  var small: array[1, byte] = default(array[1, byte])
  small[0] = 77
  # Nonempty values cannot fit just a header; a failed write must preserve the sentinel.
  if size > 0:
    assert encodeBytes(value, ByteLimit(uint64(size)), small).error ==
        ContainerError.OutputTooSmall
    assert small[0] == 77
    assert decodeBytesBorrowed(wire, ByteLimit(uint64(size - 1))).error ==
        ContainerError.LimitExceeded
    assert encodeBytes(value, ByteLimit(uint64(size - 1)), small).error ==
        ContainerError.LimitExceeded

# Check sequences at every width, including zero-width elements, and exact output ownership.
proc checkSequence(count, stride: int) =
  var values = newSeq[FixedUnsigned](count)
  # Width-zero items must all be zero; other widths use a small recognizably changing value.
  for i in 0..<count: values[i] = FixedUnsigned(if stride == 0: 0'u64 else: uint64(i mod 256))
  var wire = newSeq[byte](count * stride + 10)
  let encoded = encodeSequence(values, ByteWidth(stride), ElementLimit(uint64(count)), wire)
  assert encoded.error == ContainerError.None
  var output = newSeq[FixedUnsigned](count + 1)
  output[count] = FixedUnsigned(999)
  wire[encoded.written] = 42
  let decoded = decodeSequence(wire.toOpenArray(0, encoded.written), ByteWidth(stride),
                               ElementLimit(uint64(count)), output)
  assert decoded.error == ContainerError.None and decoded.count == count
  assert decoded.consumed == encoded.written and uint64(output[count]) == 999
  # Only the proved output prefix may be changed; all values must match the original domain values.
  for i in 0..<count: assert uint64(output[i]) == uint64(values[i])
  # Every truncation fails before committing even the first output element.
  for cut in 0..<encoded.written:
    output[0] = FixedUnsigned(777)
    let short = decodeSequence(wire.toOpenArray(0, cut - 1), ByteWidth(stride),
                               ElementLimit(uint64(count)), output)
    assert short.error == ContainerError.Truncated
    assert uint64(output[0]) == 777

# Arbitrary-byte entry point checks both decoders, including unchanged typed output on errors.
proc fuzzBounded*(input: openArray[byte], stride: int, limit: uint64) =
  let blob = decodeBytesBorrowed(input, ByteLimit(limit))
  # A successful span must lie entirely within the input and the caller's bound.
  if blob.error == ContainerError.None:
    assert blob.offset + blob.length == blob.consumed and blob.consumed <= input.len
    assert uint64(blob.length) <= limit
    let prefix = natural.encode(JamNatural(uint64(blob.length)))
    assert prefix.len == blob.offset
    # Re-encoding the declared payload length must reproduce the exact prefix before the borrowed span.
    for i in 0..<prefix.len: assert input[i] == prefix.bytes[i]
  var output: array[8, FixedUnsigned] = default(array[8, FixedUnsigned])
  # Fill output with sentinels so every failed decode can prove that it made no partial writes.
  for item in output.mitems: item = FixedUnsigned(999)
  let decoded = decodeSequence(input, ByteWidth(stride), ElementLimit(limit), output)
  # Success must re-encode exactly the consumed frame, including canonical length and fixed-width octets.
  if decoded.error == ContainerError.None:
    var wire: array[73, byte] = default(array[73, byte])
    let encoded = encodeSequence(output.toOpenArray(0, decoded.count - 1), ByteWidth(stride),
                                 ElementLimit(limit), wire)
    assert encoded.error == ContainerError.None and encoded.written == decoded.consumed
    # Compare the entire completed container rather than just decoded element values.
    for i in 0..<decoded.consumed: assert wire[i] == input[i]
  else:
    # On any failure, output and consumption must remain unchanged.
    assert decoded.error != typeof(decoded.error).None
    for item in output: assert uint64(item) == 999

# Natural length transitions are shared by byte strings and sequences.
for size in [0, 1, 127, 128, 255, 256, 16383, 16384]: checkBlob(size)
for stride in 0..8:
  # Zero counts and the 127/128 count transition exercise both empty and multi-octet length prefixes.
  for count in [0, 1, 127, 128]: checkSequence(count, stride)
# A noncanonical zero and an excessive full-width count must fail before payload or output use.
assert decodeBytesBorrowed([128'u8, 0], ByteLimit(high(uint64))).error ==
    ContainerError.NonCanonical
let huge = natural.encode(JamNatural(high(uint64)))
var values: array[2, FixedUnsigned] = default(array[2, FixedUnsigned])
values[0] = FixedUnsigned(77)
assert decodeSequence(huge.bytes, ByteWidth(0), ElementLimit(high(uint64)), values).error ==
    ContainerError.OutputTooSmall
assert decodeSequence(huge.bytes, ByteWidth(8), ElementLimit(high(uint64)), values).error ==
    ContainerError.Truncated
assert decodeSequence(huge.bytes, ByteWidth(0), ElementLimit(2), values).error ==
    ContainerError.LimitExceeded
# Default result reasons are readable, but their payloads require success through guarded accessors.
let defaultBlob = default(BlobResult)
let defaultWrite = default(WriteResult)
let defaultSequence = default(SequenceResult)
assert defaultBlob.error == ContainerError.Uninitialized
assert defaultWrite.error == ContainerError.Uninitialized
assert defaultSequence.error == ContainerError.Uninitialized
# Wrapping arithmetic cannot turn a huge claimed count into a small valid span or output extent.
for count in [uint64(high(int)) - 1, uint64(high(int)), uint64(high(int)) + 1, high(uint64)]:
  let prefix = natural.encode(JamNatural(count))
  # Division/length comparisons reject before multiplication, host-int conversion or output writes.
  assert decodeBytesBorrowed(prefix.bytes, ByteLimit(high(uint64))).error ==
      ContainerError.Truncated
  assert decodeSequence(prefix.bytes, ByteWidth(8), ElementLimit(high(uint64)), values).error ==
      ContainerError.Truncated
  assert decodeSequence(prefix.bytes, ByteWidth(0), ElementLimit(high(uint64)), values).error ==
      ContainerError.OutputTooSmall
  assert uint64(values[0]) == 77 and uint64(values[1]) == 0
# A late bad value must not leave a header or the earlier good element in output.
var wire: array[32, byte] = default(array[32, byte])
for b in wire.mitems: b = 77
let bad = [FixedUnsigned(1), FixedUnsigned(256)]
assert encodeSequence(bad, ByteWidth(1), ElementLimit(2), wire).error ==
    ContainerError.ValueOutOfRange
for b in wire: assert b == 77
# Zero-width values are still validated and count-limited, not silently dropped.
assert encodeSequence(bad, ByteWidth(0), ElementLimit(2), wire).error ==
    ContainerError.ValueOutOfRange
assert encodeSequence([], ByteWidth(-1), ElementLimit(0), wire).error ==
    ContainerError.InvalidWidth
# Overlapping buffers are a typed error, preserving their bytes rather than corrupting borrowed input.
var alias: array[16, byte] = default(array[16, byte])
for b in alias.mitems: b = 77
assert encodeBytes(alias.toOpenArray(0, 3), ByteLimit(4), alias).error ==
    ContainerError.AliasedBuffers
for b in alias: assert b == 77
let typedBytes = cast[ptr array[16, byte]](addr values[0])
assert encodeSequence(values, ByteWidth(1), ElementLimit(2), typedBytes[]).error ==
    ContainerError.AliasedBuffers
typedBytes[][0] = 1
typedBytes[][1] = 42
assert decodeSequence(typedBytes[], ByteWidth(1), ElementLimit(2), values).error ==
    ContainerError.AliasedBuffers
# Output inside a later field must also be rejected, even when it misses the consumed prefix.
assert decodeSequence(typedBytes[], ByteWidth(1), ElementLimit(2),
                        values.toOpenArray(1, 1)).error == ContainerError.AliasedBuffers
assert uint64(values[1]) == 0
var state = 0x424f554e44'u64
# Reproducible byte/width/count cases cover malformed prefixes and both payload/storage bounds.
for iteration in 0..<10000:
  var input: array[32, byte] = default(array[32, byte])
  # Generate deterministic bytes; this generator is for coverage, not cryptography.
  for b in input.mitems:
    state = state xor (state shl 13)
    state = state xor (state shr 7)
    state = state xor (state shl 17)
    b = byte(state and 255)
  fuzzBounded(input.toOpenArray(0, iteration mod 33 - 1), iteration mod 13 - 2, uint64(
      iteration mod 12))
echo "Nim bounded: byte/sequence boundaries, atomic errors, aliasing and 10000 fuzz cases passed"
