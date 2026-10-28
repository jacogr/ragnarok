# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Owned snapshot regressions: mutation, original lifetime, detached copies, typed failures and
## nested records.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

# @@Verification={"arc": "arc_release"}

import std/assertions
import std/syncio
import ../../support/testing_arc_evidence
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/work_digest as codec_work_digest
import ../../../src/codec/owned as codec_owned
import ../../support/codec_ownership_checks

# Return a snapshot made from local stack storage; ARC must retain the copied bytes across this scope.
proc escaped(): OwnedFrame =
  var temporary = [2'u8, 10, 20, 99]
  let parsed = decodeOwnedBytes(temporary, ByteLimit(2))
  assert parsed.error == OwnershipError.None
  temporary[1] = 88
  parsed.value

# Replacing the original handle must not retire a snapshot retained by another handle.
proc retainedReplacement(): OwnedFrame =
  var original = decodeOwnedBytes([byte(2), 10, 20], ByteLimit(2)).value
  let retained = original
  original = decodeOwnedBytes([byte(2), 77, 88], ByteLimit(2)).value
  var copied: array[2, byte] = default(array[2, byte])
  assert copyOwnedBlob(original, 0, copied).value == 2 and copied == [byte(77), 88]
  assert copyOwnedBlob(retained, 0, copied).value == 2 and copied == [byte(10), 20]
  retained

# Each call owns and releases its complete source, snapshot, aliases and extracted copy before returning.
proc releaseCycle(marker: byte) =
  var source = @[byte(2), marker, 20]
  let decoded = decodeOwnedBytes(source, ByteLimit(2))
  assert decoded.error == OwnershipError.None
  let alias = decoded.value
  source[1] = marker xor 255
  let optional = decodeOwnedOptional([byte(1), 2, marker, 20], ByteLimit(2))
  let work = decodeOwnedWork([byte(0), 2, marker, 20], ByteLimit(2))
  let limits = PreimageLimits(items: ElementLimit(1), perBlob: ByteLimit(2),
      totalBlobBytes: ByteLimit(2))
  let preimages = decodeOwnedPreimages([byte(1), 7, 0, 0, 0, 2, marker, 20], limits)
  var wire: array[128, byte] = default(array[128, byte])
  let value = WorkDigest(output: successfulWork(BlobSpan(offset: 0, length: 2)))
  let encoded = encodeDigestBorrowed(value, [marker, byte(20)], ByteLimit(2), wire)
  assert encoded.error == CompositeError.None
  let digest = decodeOwnedDigest(wire, ByteLimit(2))
  assert optional.error == OwnershipError.None and work.error == OwnershipError.None
  assert preimages.error == OwnershipError.None and digest.error == OwnershipError.None
  var copied = newSeq[byte](2)
  # Every schema retains independent payload bytes; all local references die before the next observation.
  for frame in [alias, optional.value, work.value, preimages.value, digest.value]:
    assert copyOwnedBlob(frame, 0, copied).value == 2 and copied[0] == marker and copied[1] == 20

# Use the public live-memory counter after allocator warmup, rather than RSS or a private runtime hook.
for i in 0..<100: releaseCycle(byte(i mod 256))
let beforeRelease = getOccupiedMem()
for i in 0..<1000: releaseCycle(byte(i mod 256))
let afterRelease = getOccupiedMem()
assert afterRelease == beforeRelease
let replaced = retainedReplacement()
var replacementCopy: array[2, byte] = default(array[2, byte])
assert copyOwnedBlob(replaced, 0, replacementCopy).value == 2 and replacementCopy == [byte(10), 20]
# An explicit generic success builder does not validate a default handle; owner APIs still reject it.
let noOwner = default(OwnedFrame)
let explicitlyWrapped = ownedSuccess(noOwner)
assert ownedInfo(explicitlyWrapped.value).error == OwnershipError.InvalidOwner
let defaultResult = default(OwnedResult[OwnedFrame])
assert defaultResult.error == OwnershipError.Uninitialized
let defaultOptionalInfo = default(OwnedOptionalInfo)
let defaultWorkInfo = default(OwnedWorkInfo)
assert not defaultOptionalInfo.present
assert defaultWorkInfo.kind == WorkKind.Success and defaultWorkInfo.length == 0
let frame = escaped()
let alias = frame
let info = ownedInfo(frame)
assert info.error == OwnershipError.None and info.value.consumed == 3
var payload: array[2, byte] = default(array[2, byte])
assert copyOwnedBlob(frame, 0, payload).error == OwnershipError.None
assert payload == [10'u8, 20]
payload[0] = 55 # Mutating an extracted copy must not mutate its owner.
assert copyOwnedBlob(alias, 0, payload).error == OwnershipError.None
assert payload == [10'u8, 20]
var short = [77'u8]
assert copyOwnedBlob(frame, 0, short).error == OwnershipError.OutputTooSmall
assert short == [77'u8]
assert encodeOwned(frame, short).error == OwnershipError.OutputTooSmall
assert short == [77'u8]
assert ownedBlobLength(frame, -1).error == OwnershipError.InvalidIndex
assert ownedBlobLength(frame, 1).error == OwnershipError.InvalidIndex
assert copyOwnedBlob(frame, -1, short).error == OwnershipError.InvalidIndex
assert copyOwnedBlob(frame, 1, short).error == OwnershipError.InvalidIndex
assert ownedDigestInfo(frame).error == OwnershipError.WrongSchema
var absentOwner: OwnedFrame = default(OwnedFrame)
assert ownedInfo(absentOwner).error == OwnershipError.InvalidOwner
assert ownedBlobLength(absentOwner, 0).error == OwnershipError.InvalidOwner
assert encodeOwned(absentOwner, short).error == OwnershipError.InvalidOwner
let absent = decodeOwnedOptional([0'u8], ByteLimit(0))
assert absent.error == OwnershipError.None and not ownedOptionalInfo(absent.value).value.present
assert copyOwnedBlob(absent.value, 0, short).error == OwnershipError.InvalidIndex
let empty = decodeOwnedOptional([1'u8, 0], ByteLimit(0))
assert empty.error == OwnershipError.None and ownedOptionalInfo(empty.value).value.present
assert ownedOptionalInfo(empty.value).value.length == 0
assert copyOwnedBlob(empty.value, 0, short).value == 0
let workError = decodeOwnedWork([1'u8], ByteLimit(0))
assert workError.error == OwnershipError.None and ownedWorkInfo(workError.value).value.kind ==
    WorkKind.OutOfGas
let limits = PreimageLimits(items: ElementLimit(2), perBlob: ByteLimit(2),
    totalBlobBytes: ByteLimit(2))
var recordsWire = [2'u8, 1, 0, 0, 0, 2, 10, 20, 2, 0, 0, 0, 0, 99]
let records = decodeOwnedPreimages(recordsWire, limits)
assert records.error == OwnershipError.None
recordsWire[6] = 66 # A post-validation mutation cannot affect either nested payload.
assert uint32(ownedService(records.value, 0).value) == 1
assert uint32(ownedService(records.value, 1).value) == 2
assert copyOwnedBlob(records.value, 0, payload).value == 2 and payload == [10'u8, 20]
assert copyOwnedBlob(records.value, 1, short).value == 0
assert ownedInfo(records.value).value.consumed == 13
# Complete digest fixtures use the normal encoder, then independently verify fixed metadata and payload snapshotting.
var digestWire: array[128, byte] = default(array[128, byte])
let digest = WorkDigest(service: ServiceIndex(7), accumulateGas: Gas(9),
    output: successfulWork(BlobSpan(offset: 0, length: 2)),
    refine: RefineLoad(gasUsed: Gas(10)))
let encoded = encodeDigestBorrowed(digest, [10'u8, 20], ByteLimit(2), digestWire)
assert encoded.error == CompositeError.None
let decoded = decodeDigestBorrowed(digestWire, ByteLimit(2))
checkOwnedDigest(digestWire, ByteLimit(2), decoded)
let ownedDigest = decodeOwnedDigest(digestWire, ByteLimit(2))
assert ownedDigest.error == OwnershipError.None
digestWire[78] = 99 # The owned successful blob is independent of the original digest wire.
assert copyOwnedBlob(ownedDigest.value, 0, payload).value == 2 and payload == [10'u8, 20]
assert uint32(ownedDigestInfo(ownedDigest.value).value.service) == 7
# Random malformed/truncated frames must preserve borrowed error semantics, including late nested failures.
var random = 0x4a414d'u64
var fuzz: array[96, byte] = default(array[96, byte])
# Exercise all five schemas over the same deterministic random corpus.
for trial in 0..<10000:
  random = random * 6364136223846793005'u64 + 1'u64
  let size = int(random mod uint64(fuzz.len + 1))
  # Vary every byte independently so discriminators, prefixes and suffix metrics are all exercised.
  for i in 0..<size:
    random = random * 6364136223846793005'u64 + 1'u64
    fuzz[i] = byte(random shr 56)
  let input = fuzz.toOpenArray(0, size - 1)
  let bytes = decodeBytesBorrowed(input, ByteLimit(64))
  assert $decodeOwnedBytes(input, ByteLimit(64)).error == $bytes.error
  # Successful snapshots must reproduce the validated prefix and payload exactly.
  if bytes.error == ContainerError.None: checkOwnedBytes(input, ByteLimit(64), bytes)
  let optional = decodeOptionalBorrowed(input, ByteLimit(64))
  assert $decodeOwnedOptional(input, ByteLimit(64)).error == $optional.error
  if optional.error == CompositeError.None: checkOwnedOptional(input, ByteLimit(64),
      optional) # Present/absent parity.
  let work = decodeWorkBorrowed(input, ByteLimit(64))
  assert $decodeOwnedWork(input, ByteLimit(64)).error == $work.error
  if work.error == CompositeError.None: checkOwnedWork(input, ByteLimit(64), work) # All work variants.
  let full = decodeDigestBorrowed(input, ByteLimit(64))
  assert $decodeOwnedDigest(input, ByteLimit(64)).error == $full.error
  if full.error == CompositeError.None: checkOwnedDigest(input, ByteLimit(64), full) # Complete suffix parity.
  var output: array[2, Preimage] = default(array[2, Preimage])
  let preimages = decodePreimagesBorrowed(input, limits, output)
  assert $decodeOwnedPreimages(input, limits).error == $preimages.error
  if preimages.error == CompositeError.None: checkOwnedPreimages(input, limits, preimages,
      output) # Nested records.
echo "Nimony ownership: immutable snapshots, retained lifetime, atomic copies and 10000 five-schema fuzz cases passed"
# Numeric evidence stays outside the platform-independent success marker.
recordArcRelease("codec_ownership", 1000, beforeRelease, afterRelease, schemas = 5)
echo "ARC_RELEASE cycles=1000 unchanged"
