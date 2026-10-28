# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 T C(255, service): fixed version-zero service-account metadata, not nested service
## maps.
##
## Exposes ServiceMetadata, nominal account resource fields, decodeServiceMetadata and
## serviceMetadataEntry.

import ./natural as codec_natural
import ./bounded as codec_bounded
import ./composite as codec_composite
import ./work_digest as codec_work_digest
import ./state_layout as codec_state_layout
import ./state_trie as codec_state_trie
export ServiceIndex, CodeHash, Gas

const ServiceMetadataBytes* = 105 ## Version zero, code hash, supervisor pair, six E8 values and four E4 values.

type
  AccountBalance* = distinct uint64 ## Balance and gratis/deposit offset share token units, distinct from gas or storage size.
  AccountStorageBytes* = distinct uint64 ## Stored footprint octets use the full E8 domain and cannot substitute for item counts.
  AccountStorageItems* = distinct uint32 ## Stored footprint item count uses E4, independently from byte counts and service IDs.
  AccountSlot* = distinct uint32 ## Service creation/last-accumulation absolute timeslots are separate from service IDs or record ordinals.
  ServiceMetadata* = object ## Version-zero fixed metadata owns every field by value; nested maps and service identity are outside this payload.
    codeHash*: CodeHash
    balance*, supervisorBalance*, depositOffset*: AccountBalance
    supervisor*: ServiceIndex
    supervisorCreated*: AccountSlot
    minimumAccumulationGas*, minimumTransferGas*: Gas
    storageBytes*: AccountStorageBytes
    storageItems*: AccountStorageItems
    created*, lastAccumulation*: AccountSlot
    parent*: ServiceIndex
  ServiceMetadataError* {.pure.} = enum ## Default and failed results contain reasons alone, never default metadata or partial consumed progress.
    Uninitialized, None, Truncated, NonCanonical, UnsupportedVersion, LimitExceeded
  ServiceMetadataResult*[T] = object ## Only a selected complete success exposes its application payload.
    case status: ServiceMetadataError
    of None:
      completed: T # Success requires the guarded accessor, including in checked optimized builds.
    else:
      discard      # Failure cannot fabricate a usable all-zero account.
  ServiceMetadataRead* = object ## Complete prefix decode returns independent fixed fields and exact consumed extent, with no heap owner required.
    metadata*: ServiceMetadata
    consumed*: int

func error*[T](parsed: ServiceMetadataResult[T]): ServiceMetadataError =
  ## Failure reasons are read-only and never authorize metadata, encoded bytes or progress.
  parsed.status
func value*[T](parsed: ServiceMetadataResult[T]): T
    {.inline, requires: parsed.status == ServiceMetadataError.None.} =
  ## Complete fixed metadata and encoded entries require successful payload selection.
  parsed.completed

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

proc decodeServiceMetadata*(input: openArray[byte], maxBytes: ByteLimit): ServiceMetadataResult[
    ServiceMetadataRead] =
  ## Decode only canonical version-zero metadata after policy, version and complete payload checks.
  if uint64(maxBytes) < uint64(ServiceMetadataBytes):
    return ServiceMetadataResult[ServiceMetadataRead](
        status: ServiceMetadataError.LimitExceeded) # Current schema must fit caller policy before input work.
  let version = codec_natural.decode(input)
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
  let metadata = ServiceMetadata(codeHash: CodeHash(code),
    supervisor: ServiceIndex(read32(input, 33)), supervisorCreated: AccountSlot(read32(input, 37)),
    balance: AccountBalance(read64(input, 41)), supervisorBalance: AccountBalance(read64(input, 49)),
    minimumAccumulationGas: Gas(read64(input, 57)), minimumTransferGas: Gas(read64(input, 65)),
    storageBytes: AccountStorageBytes(read64(input, 73)), depositOffset: AccountBalance(read64(
        input, 81)),
    storageItems: AccountStorageItems(read32(input, 89)), created: AccountSlot(read32(input, 93)),
    lastAccumulation: AccountSlot(read32(input, 97)), parent: ServiceIndex(read32(input, 101)))
  ServiceMetadataResult[ServiceMetadataRead](status: ServiceMetadataError.None,
    completed: ServiceMetadataRead(metadata: metadata, consumed: ServiceMetadataBytes))

proc serviceMetadataEntry*(service: ServiceIndex, metadata: ServiceMetadata,
    maxBytes: ByteLimit): ServiceMetadataResult[StateEntry] =
  ## Construct C(255, service) with independent version-zero payload after fixed-size resource preflight.
  if uint64(maxBytes) < uint64(ServiceMetadataBytes):
    return ServiceMetadataResult[StateEntry](status: ServiceMetadataError.LimitExceeded) # No allocation occurs when the entire fixed schema exceeds policy.
  var entry = StateEntry(key: chapterServiceKey(StateChapter(255), service), value: newSeq[byte](ServiceMetadataBytes))
  entry.value[0] = 0 # This source type represents only the supported canonical version-zero schema.
  let code = array[32, byte](metadata.codeHash)
  for i in 0..<32: entry.value[1+i] = code[i] # Code identity is opaque and has no additional length prefix.
  for field, value in [uint32(metadata.supervisor), uint32(metadata.supervisorCreated)]:
    for i in 0..<4:
      # Supervisor identity and creation epoch bind authority to one concrete account lifetime.
      entry.value[33+field*4+i] = byte((value shr (i*8)) and 255)
  let wide = [uint64(metadata.balance), uint64(metadata.supervisorBalance), uint64(
      metadata.minimumAccumulationGas), uint64(metadata.minimumTransferGas),
    uint64(metadata.storageBytes), uint64(metadata.depositOffset)]
  for field, value in wide:
    for i in 0..<8: entry.value[41+field*8+i] = byte((value shr (i*8)) and
        255) # Preserve every E8 octet in normative order.
  let narrow = [uint32(metadata.storageItems), uint32(metadata.created), uint32(
      metadata.lastAccumulation), uint32(metadata.parent)]
  for field, value in narrow:
    for i in 0..<4: entry.value[89+field*4+i] = byte((value shr (i*8)) and
        255) # Parent service is E4, just like timeslots/items.
  ServiceMetadataResult[StateEntry](status: ServiceMetadataError.None, completed: entry)
