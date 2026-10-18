# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exercise optional/work variants and nested preimage codecs, including explicit source
## constructors and failure boundaries.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import std/[assertions, syncio]
import ../../../src/codec/[composite, bounded]

# Explicit source constructors retain optional/work wire defaults and return copied descriptors.
proc checkSources() =
  let defaultOptional = default(OptionalBlob)
  let defaultWork = default(WorkOutput)
  assert not defaultOptional.present
  assert defaultWork.kind == WorkKind.Success and defaultWork.blob.length == 0
  let optional = presentBlob(BlobSpan(offset: 1, length: 2))
  var optionalCopy = optional.blob
  optionalCopy.offset = 0
  assert optional.blob.offset == 1 and optionalCopy.offset == 0
  let work = successfulWork(BlobSpan(offset: 1, length: 2))
  var workCopy = work.blob
  workCopy.length = 0
  assert work.blob.length == 2 and workCopy.length == 0
  var bytes: array[2, byte] = default(array[2, byte])
  assert encodeOptionalBorrowed(defaultOptional, [], ByteLimit(0), bytes).written == 1
  assert bytes[0] == 0
  assert encodeWorkBorrowed(defaultWork, [], ByteLimit(0), bytes).written == 2
  assert bytes[0] == 0 and bytes[1] == 0
  let absent = decodeOptionalBorrowed([byte(0)], ByteLimit(0))
  assert absent.error == CompositeError.None and not absent.value.present
  let emptyWork = decodeWorkBorrowed([byte(0), 0], ByteLimit(0))
  assert emptyWork.error == CompositeError.None and emptyWork.value.blob.length == 0
  let defaultWrite = default(CompositeWrite)
  let defaultRead = default(OptionalResult)
  let defaultWorkRead = default(WorkResult)
  let defaultPreimages = default(PreimageResult)
  assert defaultWrite.error == CompositeError.Uninitialized and defaultRead.error ==
      CompositeError.Uninitialized
  assert defaultWorkRead.error == CompositeError.Uninitialized and defaultPreimages.error ==
      CompositeError.Uninitialized
  assert compositeFailure(CompositeError.Truncated).error == CompositeError.Truncated
  assert compositeWritten(0).written == 0

checkSources()

# Arbitrary-byte entry point: all successful values re-encode their consumed prefix, and errors preserve records.
proc fuzzComposite*(input: openArray[byte]) =
  var wire: array[128, byte] = default(array[128, byte])
  let optional = decodeOptionalBorrowed(input, ByteLimit(64))
  if optional.error == CompositeError.None:
    # A typed optional view must reconstruct exactly its canonical prefix and nested blob.
    let encoded = encodeOptionalBorrowed(optional.value, input, ByteLimit(64), wire)
    assert encoded.error == CompositeError.None and encoded.written == optional.consumed
    for i in 0..<optional.consumed: assert wire[i] == input[i] # Compare tag, length and payload.
  let work = decodeWorkBorrowed(input, ByteLimit(64))
  if work.error == CompositeError.None:
    # Successful and payload-free error variants both preserve their precise wire representation.
    let encoded = encodeWorkBorrowed(work.value, input, ByteLimit(64), wire)
    assert encoded.error == CompositeError.None and encoded.written == work.consumed
    for i in 0..<work.consumed: assert wire[i] == input[i] # Do not include unrelated trailing bytes.
  var output: array[4, Preimage] = default(array[4, Preimage])
  for item in output.mitems: item = Preimage(service: ServiceIndex(777), blob: BlobSpan(offset: 333,
      length: 444)) # Failure sentinels.
  let limits = PreimageLimits(items: ElementLimit(4), perBlob: ByteLimit(32),
      totalBlobBytes: ByteLimit(64))
  let decoded = decodePreimagesBorrowed(input, limits, output)
  if decoded.error == CompositeError.None:
    # A decoded nested frame must round-trip from the returned input-relative descriptors.
    let encoded = encodePreimagesBorrowed(output.toOpenArray(0, decoded.count - 1), input, limits, wire)
    assert encoded.error == CompositeError.None and encoded.written == decoded.consumed
    for i in 0..<decoded.consumed: assert wire[i] == input[i] # Include all tuple fields and lengths.
  else:
    # No failing nested record may initialize even an earlier valid record.
    assert decoded.error != typeof(decoded.error).None
    # Check every descriptor field, including records beyond any valid prefix.
    for item in output: assert uint32(item.service) == 777 and item.blob.offset == 333 and
        item.blob.length == 444

var pool = [1'u8, 2, 3]
var wire: array[64, byte] = default(array[64, byte])
let limits = PreimageLimits(items: ElementLimit(2), perBlob: ByteLimit(3),
    totalBlobBytes: ByteLimit(3))
let records = [Preimage(service: ServiceIndex(7), blob: BlobSpan(offset: 0, length: 3)),
               Preimage(service: ServiceIndex(high(uint32)), blob: BlobSpan(offset: 3, length: 0))]
let encoded = encodePreimagesBorrowed(records, pool, limits, wire)
assert encoded.error == CompositeError.None and encoded.written == 14
var output: array[2, Preimage] = default(array[2, Preimage])
let decoded = decodePreimagesBorrowed(wire.toOpenArray(0, 13), limits, output)
assert decoded.error == CompositeError.None and decoded.count == 2 and decoded.consumed == 14
assert uint32(output[0].service) == 7 and uint32(output[1].service) == high(uint32)
assert output[0].blob.offset == 6 and output[0].blob.length == 3 and output[1].blob.length == 0
# Every truncated prefix, especially the last record, leaves the entire record destination unchanged.
for cut in 0..<14:
  for item in output.mitems: item.service = ServiceIndex(999) # Refill sentinels before each failing decode.
  let short = decodePreimagesBorrowed(wire.toOpenArray(0, cut - 1), limits, output)
  assert short.error == CompositeError.Truncated
  # Every service sentinel must survive truncation, not only the final record.
  for item in output: assert uint32(item.service) == 999
# Aggregate policy can reject a later record without leaving the earlier one in output.
let tighter = PreimageLimits(items: ElementLimit(2), perBlob: ByteLimit(3),
    totalBlobBytes: ByteLimit(2))
assert decodePreimagesBorrowed(wire, tighter, output).error == CompositeError.LimitExceeded
for b in wire.mitems: b = 77 # Encoder failure must preserve every byte.
let bad = [records[0], Preimage(service: ServiceIndex(8), blob: BlobSpan(offset: high(int), length: 1))]
assert encodePreimagesBorrowed(bad, pool, limits, wire).error == CompositeError.InvalidSpan
# Scan the whole destination rather than just the rejected prefix.
for b in wire: assert b == 77
# Every exact work-error tag is payload-free; trailing data is not interpreted as a blob.
for tag in 1..6:
  let value = failedWork(WorkKind(tag))
  assert encodeWorkBorrowed(value, pool, ByteLimit(0), wire).written == 1
  assert decodeWorkBorrowed(wire, ByteLimit(0)).consumed == 1
# Invalid discriminators and overlong canonical-zero attempts have different typed failures.
assert decodeWorkBorrowed([7'u8], ByteLimit(0)).error == CompositeError.InvalidTag
assert decodeOptionalBorrowed([2'u8], ByteLimit(0)).error == CompositeError.InvalidTag
assert decodeOptionalBorrowed([128'u8, 0], ByteLimit(0)).error == CompositeError.NonCanonical
# Invalid source spans never reach indexing or endpoint addition.
for span in [BlobSpan(offset: -1, length: 0), BlobSpan(offset: 0, length: -1), BlobSpan(
    offset: high(int), length: high(int))]:
  assert encodeOptionalBorrowed(presentBlob(span), pool, ByteLimit(high(
      uint64)), wire).error == CompositeError.InvalidSpan
# Typed destination aliasing includes output inside a trailing field, not only the current record bytes.
let raw = cast[ptr array[sizeof(Preimage) * 2, byte]](addr output[0])
for b in raw[].mitems: b = 0 # Create a valid one-record wire frame in overlapping caller storage.
raw[][0] = 1
let snapshot = output
assert decodePreimagesBorrowed(raw[], limits, output.toOpenArray(1, 1)).error ==
    CompositeError.AliasedBuffers
assert output[1].blob.offset == snapshot[1].blob.offset
var state = 0x434f4d504f'u64
# Reproducible arbitrary data combines both variants and nested lengths with all truncation positions.
for iteration in 0..<10000:
  var input: array[64, byte] = default(array[64, byte])
  for b in input.mitems:
    # Deterministic xorshift supplies coverage bytes, not cryptographic randomness.
    state = state xor (state shl 13)
    state = state xor (state shr 7)
    state = state xor (state shl 17)
    b = byte(state and 255)
  fuzzComposite(input.toOpenArray(0, iteration mod 65 - 1))
echo "Nim composite: nested atomic failures, exact variants, aliasing and 10000 fuzz cases passed"

# Encoder overlap checks protect the pool and the typed descriptors during the entire commit.
let poolBefore = pool
let present = presentBlob(BlobSpan(offset: 0, length: 0))
assert encodeOptionalBorrowed(present, pool, ByteLimit(0), pool).error ==
    CompositeError.AliasedBuffers
assert pool == poolBefore
var descriptors = records
let descriptorBytes = cast[ptr array[sizeof(descriptors), byte]](addr descriptors[0])
let descriptorsBefore = descriptors
assert encodePreimagesBorrowed(descriptors, pool, limits, descriptorBytes[]).error ==
    CompositeError.AliasedBuffers
# Compare nominal service values explicitly while checking both span coordinates.
for i in 0..<descriptors.len:
  assert uint32(descriptors[i].service) == uint32(descriptorsBefore[i].service)
  assert descriptors[i].blob == descriptorsBefore[i].blob
