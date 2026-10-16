## GP 0.8.0 T C(255, service): fixed version-zero service-account metadata, not nested service maps.
import ./[natural, bounded, composite, work_digest, state_layout, state_trie]
export ServiceIndex, CodeHash, Gas

const ServiceMetadataBytes* = 89 ## Version zero, code hash, five E8 values and four E4 values.

type
  ## Balance and gratis/deposit offset share token units, distinct from gas or storage size.
  AccountBalance* = distinct uint64
  ## Stored footprint octets use the full E8 domain and cannot substitute for item counts.
  AccountStorageBytes* = distinct uint64
  ## Stored footprint item count uses E4, independently from byte counts and service IDs.
  AccountStorageItems* = distinct uint32
  ## Service creation/last-accumulation absolute timeslots are separate from service IDs or record ordinals.
  AccountSlot* = distinct uint32
  ## Version-zero fixed metadata owns every field by value; nested maps and service identity are outside this payload.
  ServiceMetadata* = object
    codeHash*: CodeHash
    balance*, depositOffset*: AccountBalance
    minimumAccumulationGas*, minimumTransferGas*: Gas
    storageBytes*: AccountStorageBytes
    storageItems*: AccountStorageItems
    created*, lastAccumulation*: AccountSlot
    parent*: ServiceIndex
  ## Default and failed results contain reasons alone, never default metadata or partial consumed progress.
  ServiceMetadataError* {.pure.} = enum
    Uninitialized, None, Truncated, NonCanonical, UnsupportedVersion, LimitExceeded
  ## Only a selected complete success exposes its application payload.
  ServiceMetadataResult*[T] = object
    case status: ServiceMetadataError
    of None:
      completed: T # Success requires the guarded accessor, including in checked optimized builds.
    else:
      discard      # Failure cannot fabricate a usable all-zero account.
  ## Complete prefix decode returns independent fixed fields and exact consumed extent, with no heap owner required.
  ServiceMetadataRead* = object
    metadata*: ServiceMetadata
    consumed*: int

## Failure reasons are read-only and never authorize metadata, encoded bytes or progress.
func error*[T](parsed: ServiceMetadataResult[T]): ServiceMetadataError = parsed.status
## Complete fixed metadata and encoded entries require successful payload selection.
func value*[T](parsed: ServiceMetadataResult[T]): T
    {.inline, requires: parsed.status == ServiceMetadataError.None.} = parsed.completed

## Copy one proved E8 field using explicit little-endian shifts without alignment or host-endian assumptions.
proc read64(input: openArray[byte], offset: int): uint64 =
  result = 0
  for i in 0..<8: result = result or (uint64(input[offset+i]) shl (
      i*8)) # Full payload presence precedes every field read.

## Copy one proved E4 field without exposing borrowed coordinates or silently narrowing larger integers.
proc read32(input: openArray[byte], offset: int): uint32 =
  result = 0
  for i in 0..<4: result = result or (uint32(input[offset+i]) shl (
      i*8)) # The schema fixes this scalar at four bytes.

## Decode only canonical version-zero metadata after policy, version and complete payload checks.
proc decodeServiceMetadata*(input: openArray[byte], maxBytes: ByteLimit): ServiceMetadataResult[
    ServiceMetadataRead] =
  if uint64(maxBytes) < uint64(ServiceMetadataBytes):
    return ServiceMetadataResult[ServiceMetadataRead](
        status: ServiceMetadataError.LimitExceeded) # Current schema must fit caller policy before input work.
  let version = natural.decode(input)
  if not version.ok:
    if version.error == DecodeError.truncated:
      return ServiceMetadataResult[ServiceMetadataRead](
          status: ServiceMetadataError.Truncated) # Missing discriminator bytes are not a zero version.
    else:
      return ServiceMetadataResult[ServiceMetadataRead](
          status: ServiceMetadataError.NonCanonical) # Overlong zero is not another supported representation.
  if uint64(version.value) != 0:
    return ServiceMetadataResult[ServiceMetadataRead](
        status: ServiceMetadataError.UnsupportedVersion) # Do not interpret an unknown schema as version zero.
  if input.len < ServiceMetadataBytes:
    return ServiceMetadataResult[ServiceMetadataRead](
        status: ServiceMetadataError.Truncated) # Require even the final parent-service byte before copying any fields.
  var code = default(array[32, byte])
  for i in 0..<32: code[i] = input[1+i] # Canonical version zero occupies exactly one byte.
  let metadata = ServiceMetadata(codeHash: CodeHash(code), balance: AccountBalance(read64(input, 33)),
    minimumAccumulationGas: Gas(read64(input, 41)), minimumTransferGas: Gas(read64(input, 49)),
    storageBytes: AccountStorageBytes(read64(input, 57)), depositOffset: AccountBalance(read64(
        input, 65)),
    storageItems: AccountStorageItems(read32(input, 73)), created: AccountSlot(read32(input, 77)),
    lastAccumulation: AccountSlot(read32(input, 81)), parent: ServiceIndex(read32(input, 85)))
  ServiceMetadataResult[ServiceMetadataRead](status: ServiceMetadataError.None,
    completed: ServiceMetadataRead(metadata: metadata, consumed: ServiceMetadataBytes))

## Construct C(255, service) with independent version-zero payload after fixed-size resource preflight.
proc serviceMetadataEntry*(service: ServiceIndex, metadata: ServiceMetadata,
    maxBytes: ByteLimit): ServiceMetadataResult[StateEntry] =
  if uint64(maxBytes) < uint64(ServiceMetadataBytes):
    return ServiceMetadataResult[StateEntry](status: ServiceMetadataError.LimitExceeded) # No allocation occurs when the entire fixed schema exceeds policy.
  var entry = StateEntry(key: chapterServiceKey(StateChapter(255), service), value: newSeq[byte](ServiceMetadataBytes))
  entry.value[0] = 0 # This source type represents only the supported canonical version-zero schema.
  let code = array[32, byte](metadata.codeHash)
  for i in 0..<32: entry.value[1+i] = code[i] # Code identity is opaque and has no additional length prefix.
  let wide = [uint64(metadata.balance), uint64(metadata.minimumAccumulationGas), uint64(
      metadata.minimumTransferGas),
    uint64(metadata.storageBytes), uint64(metadata.depositOffset)]
  for field, value in wide:
    for i in 0..<8: entry.value[33+field*8+i] = byte((value shr (i*8)) and
        255) # Preserve every E8 octet in normative order.
  let narrow = [uint32(metadata.storageItems), uint32(metadata.created), uint32(
      metadata.lastAccumulation), uint32(metadata.parent)]
  for field, value in narrow:
    for i in 0..<4: entry.value[73+field*4+i] = byte((value shr (i*8)) and
        255) # Parent service is E4, just like timeslots/items.
  ServiceMetadataResult[StateEntry](status: ServiceMetadataError.None, completed: entry)
