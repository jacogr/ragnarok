## Owned snapshot regressions: mutation, original lifetime, detached copies, typed failures and nested records.
import ../../src/codec/[bounded, composite, work_digest, owned]
import ./ownership_checks

# Return a snapshot made from local stack storage; ARC must retain the copied bytes across this scope.
proc escaped(): OwnedFrame =
  var temporary = [2'u8, 10, 20, 99]
  let parsed = decodeOwnedBytes(temporary, ByteLimit(2))
  doAssert parsed.error == OwnershipError.None
  temporary[1] = 88
  parsed.value

let frame = escaped()
let alias = frame
let info = ownedInfo(frame)
doAssert info.error == OwnershipError.None and info.value.consumed == 3
var payload: array[2, byte]
doAssert copyOwnedBlob(frame, 0, payload).error == OwnershipError.None
doAssert payload == [10'u8, 20]
payload[0] = 55 # Mutating an extracted copy must not mutate its owner.
doAssert copyOwnedBlob(alias, 0, payload).error == OwnershipError.None
doAssert payload == [10'u8, 20]
var short = [77'u8]
doAssert copyOwnedBlob(frame, 0, short).error == OwnershipError.OutputTooSmall
doAssert short == [77'u8]
doAssert encodeOwned(frame, short).error == OwnershipError.OutputTooSmall
doAssert short == [77'u8]
doAssert ownedBlobLength(frame, -1).error == OwnershipError.InvalidIndex
doAssert ownedBlobLength(frame, 1).error == OwnershipError.InvalidIndex
doAssert copyOwnedBlob(frame, -1, short).error == OwnershipError.InvalidIndex
doAssert copyOwnedBlob(frame, 1, short).error == OwnershipError.InvalidIndex
doAssert ownedDigestInfo(frame).error == OwnershipError.WrongSchema
var absentOwner: OwnedFrame
doAssert ownedInfo(absentOwner).error == OwnershipError.InvalidOwner
doAssert ownedBlobLength(absentOwner, 0).error == OwnershipError.InvalidOwner
doAssert encodeOwned(absentOwner, short).error == OwnershipError.InvalidOwner
let absent = decodeOwnedOptional([0'u8], ByteLimit(0))
doAssert absent.error == OwnershipError.None and not ownedOptionalInfo(absent.value).value.present
doAssert copyOwnedBlob(absent.value, 0, short).error == OwnershipError.InvalidIndex
let empty = decodeOwnedOptional([1'u8, 0], ByteLimit(0))
doAssert empty.error == OwnershipError.None and ownedOptionalInfo(empty.value).value.present
doAssert ownedOptionalInfo(empty.value).value.length == 0
doAssert copyOwnedBlob(empty.value, 0, short).value == 0
let workError = decodeOwnedWork([1'u8], ByteLimit(0))
doAssert workError.error == OwnershipError.None and ownedWorkInfo(workError.value).value.kind ==
    WorkKind.OutOfGas
let limits = PreimageLimits(items: ElementLimit(2), perBlob: ByteLimit(2),
    totalBlobBytes: ByteLimit(2))
var recordsWire = [2'u8, 1, 0, 0, 0, 2, 10, 20, 2, 0, 0, 0, 0, 99]
let records = decodeOwnedPreimages(recordsWire, limits)
doAssert records.error == OwnershipError.None
recordsWire[6] = 66 # A post-validation mutation cannot affect either nested payload.
doAssert uint32(ownedService(records.value, 0).value) == 1
doAssert uint32(ownedService(records.value, 1).value) == 2
doAssert copyOwnedBlob(records.value, 0, payload).value == 2 and payload == [10'u8, 20]
doAssert copyOwnedBlob(records.value, 1, short).value == 0
doAssert ownedInfo(records.value).value.consumed == 13
# Complete digest fixtures use the normal encoder, then independently verify fixed metadata and payload snapshotting.
var digestWire: array[128, byte]
let digest = WorkDigest(service: ServiceIndex(7), accumulateGas: Gas(9),
    output: successfulWork(BlobSpan(offset: 0, length: 2)),
    refine: RefineLoad(gasUsed: Gas(10)))
let encoded = encodeDigestBorrowed(digest, [10'u8, 20], ByteLimit(2), digestWire)
doAssert encoded.error == CompositeError.None
let decoded = decodeDigestBorrowed(digestWire, ByteLimit(2))
checkOwnedDigest(digestWire, ByteLimit(2), decoded)
let ownedDigest = decodeOwnedDigest(digestWire, ByteLimit(2))
doAssert ownedDigest.error == OwnershipError.None
digestWire[78] = 99 # The owned successful blob is independent of the original digest wire.
doAssert copyOwnedBlob(ownedDigest.value, 0, payload).value == 2 and payload == [10'u8, 20]
doAssert uint32(ownedDigestInfo(ownedDigest.value).value.service) == 7
# Random malformed/truncated frames must preserve borrowed error semantics, including late nested failures.
var random = 0x4a414d'u64
var fuzz: array[96, byte]
# Exercise all five schemas over the same deterministic random corpus.
for trial in 0..<10000:
  random = random * 6364136223846793005'u64 + 1'u64
  let size = int(random mod uint64(fuzz.len + 1))
  # Vary every byte independently so discriminators, prefixes and suffix metrics are all exercised.
  for i in 0..<size:
    random = random * 6364136223846793005'u64 + 1'u64
    fuzz[i] = byte(random shr 56)
  let input = fuzz[0..<size]
  let bytes = decodeBytesBorrowed(input, ByteLimit(64))
  doAssert $decodeOwnedBytes(input, ByteLimit(64)).error == $bytes.error
  # Successful snapshots must reproduce the validated prefix and payload exactly.
  if bytes.error == ContainerError.None: checkOwnedBytes(input, ByteLimit(64), bytes)
  let optional = decodeOptionalBorrowed(input, ByteLimit(64))
  doAssert $decodeOwnedOptional(input, ByteLimit(64)).error == $optional.error
  if optional.error == CompositeError.None: checkOwnedOptional(input, ByteLimit(64),
      optional) # Present/absent parity.
  let work = decodeWorkBorrowed(input, ByteLimit(64))
  doAssert $decodeOwnedWork(input, ByteLimit(64)).error == $work.error
  if work.error == CompositeError.None: checkOwnedWork(input, ByteLimit(64), work) # All work variants.
  let full = decodeDigestBorrowed(input, ByteLimit(64))
  doAssert $decodeOwnedDigest(input, ByteLimit(64)).error == $full.error
  if full.error == CompositeError.None: checkOwnedDigest(input, ByteLimit(64), full) # Complete suffix parity.
  var output: array[2, Preimage]
  let preimages = decodePreimagesBorrowed(input, limits, output)
  doAssert $decodeOwnedPreimages(input, limits).error == $preimages.error
  if preimages.error == CompositeError.None: checkOwnedPreimages(input, limits, preimages,
      output) # Nested records.
echo "Nim ownership: immutable snapshots, retained lifetime, atomic copies and 10000 five-schema fuzz cases passed"
