# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 accumulation provision set union and atomic posterior fnprovide application.
## Exposes immutable plans from explicit implication contexts; terminal selection and pipeline binding remain caller-owned.

import std/algorithm
import ../codec/[bounded, composite, natural, owned, header, state_trie]
import ./[accumulation_effects, preimages, store]

type
  ## A retained context ordinal is distinct from a provision's ordinal inside that context.
  AccumulationProvisionSourceIndex* = distinct uint64
  ## Actual copied/union byte observations are not caller ceilings or protocol gas amounts.
  AccumulationProvisionBytes* = distinct uint64
  ## Traversal caps charge repeated inputs too; encodedBytes separately bounds deterministic frame transport.
  AccumulationProvisionUnionLimits* = object
    contexts*: ElementLimit
    values*: PreimageLimits
    encodedBytes*: ByteLimit
  ## Default/refused plans never carry sources, rows or partially published maps.
  AccumulationProvisionError* {.pure.} = enum
    Uninitialized, None, InvalidContext, InvalidIndex, InvalidState, LimitExceeded,
    MalformedState, BackendFailure
  ## Fixed facts distinguish inspected contributions from the unique set eventually applied.
  AccumulationProvisionPlanInfo* = object
    contexts*, inputItems*, items*: int
    inputBytes*, bytes*: AccumulationProvisionBytes
  ## Private copied sort rows own their entire raw blob; no source ordinal can substitute a payload.
  UnionRow = object
    service: ServiceIndex
    bytes: seq[byte]
  ## Acyclic owner retains exact selected contexts and independently captured canonical union transport.
  ProvisionPlanData = ref object
    sources: seq[AccumulationEffectContext]
    values: PreparedPreimageValues
    info: AccumulationProvisionPlanInfo
  ## Only successful union preparation constructs a plan; mutable buffers and execution verdict flags are not accepted.
  PreparedAccumulationProvisions* = object
    data: nil ProvisionPlanData
  ## Read-only success extraction preserves the selected-result contract in optimized native builds.
  AccumulationProvisionResult*[T] = object
    case status: AccumulationProvisionError
    of None:
      completed: T # No partial owner accompanies a failed alternative.
    else:
      discard

## Inspect refusal without allowing result retagging.
func error*[T](outcome: AccumulationProvisionResult[T]): AccumulationProvisionError = outcome.status
## Extract only selected success under runtime/compiler contracts.
func value*[T](outcome: AccumulationProvisionResult[T]): T {.inline,
    requires: outcome.status == AccumulationProvisionError.None.} = outcome.completed

## Canonical set transport orders numeric services, then complete raw byte strings including proper prefixes.
func compareRow(a, b: UnionRow): int =
  if uint32(a.service) < uint32(b.service): return -1 # Service IDs are numeric, not little-endian wire strings.
  if uint32(a.service) > uint32(b.service): return 1
  for i in 0..<min(a.bytes.len, b.bytes.len):
    # Compare actual raw octets rather than lengths, framing or hash digests.
    if a.bytes[i] < b.bytes[i]: return -1
    if a.bytes[i] > b.bytes[i]: return 1
  if a.bytes.len < b.bytes.len: return -1 # Equal prefixes put the shorter value first.
  if a.bytes.len > b.bytes.len: return 1
  0

## Copy cardinalities and byte observations; retained arrays are never exposed.
proc provisionPlanInfo*(plan: PreparedAccumulationProvisions): AccumulationProvisionResult[
    AccumulationProvisionPlanInfo] =
  let data = plan.data
  if data == nil:
    return AccumulationProvisionResult[AccumulationProvisionPlanInfo](
        status: AccumulationProvisionError.Uninitialized) # Defaults are not valid empty unions.
  AccumulationProvisionResult[AccumulationProvisionPlanInfo](
      status: AccumulationProvisionError.None, completed: data.info)

## Retain one of the caller's exact selected context owners without accepting replacement buffers.
proc provisionSourceAt*(plan: PreparedAccumulationProvisions,
    index: AccumulationProvisionSourceIndex):
    AccumulationProvisionResult[AccumulationEffectContext] =
  let data = plan.data
  if data == nil:
    return AccumulationProvisionResult[AccumulationEffectContext](
        status: AccumulationProvisionError.Uninitialized) # No default owner grants provenance.
  if uint64(index) >= uint64(data.sources.len):
    return AccumulationProvisionResult[AccumulationEffectContext](
        status: AccumulationProvisionError.InvalidIndex) # Prove the complete ordinal before narrowing.
  AccumulationProvisionResult[AccumulationEffectContext](status: AccumulationProvisionError.None,
    completed: data.sources[int(uint64(index))])

## Plan only the set union of explicitly supplied contexts; this is not certification of terminal context selection.
proc prepareAccumulationProvisions*(sources: openArray[AccumulationEffectContext],
    limits: AccumulationProvisionUnionLimits): AccumulationProvisionResult[
        PreparedAccumulationProvisions] =
  ## Refuse before publishing any captured input or intermediate sorted value.
  template fail(reason: AccumulationProvisionError) =
    return AccumulationProvisionResult[PreparedAccumulationProvisions](status: reason)
  if uint64(sources.len) > uint64(limits.contexts) or sources.len > high(int) div sizeof(AccumulationEffectContext):
    fail(AccumulationProvisionError.LimitExceeded) # Bound retained source handles independently from contribution rows.
  var count = 0'u64
  var copied = 0'u64
  # Preflight every owner/count/blob extent before copying payloads or allocating sorting descriptors.
  for source in sources:
    let info = source.effectInfo
    if info.error != AccumulationEffectError.None:
      fail(AccumulationProvisionError.InvalidContext) # Default contexts cannot be interpreted as empty contributions.
    if uint64(info.value.provisions) > uint64(limits.values.items)-count:
      fail(AccumulationProvisionError.LimitExceeded) # Duplicates still consume inspected-item work.
    count += uint64(info.value.provisions)
    for index in 0..<info.value.provisions:
      let provision = source.effectProvisionAt(AccumulationProvisionIndex(uint64(index))).value
      let size = uint64(provision.provisionInfo.value.bytes)
      if size > uint64(limits.values.perBlob) or size > uint64(limits.values.totalBlobBytes)-copied:
        fail(AccumulationProvisionError.LimitExceeded) # Charge actual attempted copy work, not just unique retained bytes.
      copied += size
  if count > uint64(high(int) div (2*sizeof(UnionRow)+sizeof(int))) or copied > uint64(high(int)):
    fail(AccumulationProvisionError.LimitExceeded) # Bound sort scratch/index/native extents before allocation and narrowing.
  var rows = newSeq[UnionRow](int(count))
  var cursor = 0
  # Each accepted input contributes an independent byte copy; caller release or later effects cannot change sorting.
  for source in sources:
    for index in 0..<source.effectInfo.value.provisions:
      let provision = source.effectProvisionAt(AccumulationProvisionIndex(uint64(index))).value
      rows[cursor] = UnionRow(service: provision.provisionInfo.value.service,
          bytes: provision.copyProvisionBytes.value)
      inc cursor
  rows.sort(compareRow)
  var unique: seq[int] = @[]
  var unionBytes = 0'u64
  # Keep indices into private sorted rows, avoiding another payload copy while deduplicating the exact pair.
  for index in 0..<rows.len:
    if index == 0 or compareRow(rows[index-1], rows[index]) != 0:
      unique.add(index)
      unionBytes += uint64(rows[index].bytes.len) # A unique subset cannot exceed the preflighted aggregate copy bytes.
  let prefix = encode(JamNatural(uint64(unique.len)))
  var encodedSize = uint64(prefix.len)
  if encodedSize > uint64(limits.encodedBytes):
    fail(AccumulationProvisionError.LimitExceeded) # Even an empty set needs its canonical count byte.
  # Prove the exact encoded extent, including all service/length framing, before allocating its capture buffer.
  for index in unique:
    let length = encode(JamNatural(uint64(rows[index].bytes.len)))
    let size = 4'u64+uint64(length.len)+uint64(rows[index].bytes.len)
    if size > uint64(limits.encodedBytes)-encodedSize:
      fail(AccumulationProvisionError.LimitExceeded) # Subtract before aggregate addition under wrapping arithmetic.
    encodedSize += size
  if encodedSize > uint64(high(int)):
    fail(AccumulationProvisionError.LimitExceeded) # Native byte-buffer allocation must fit before narrowing.
  var wire = newSeq[byte](int(encodedSize))
  cursor = 0
  for i in 0..<prefix.len:
    # Encode the canonical unique-item count.
    wire[cursor] = prefix.bytes[i]
    inc cursor
  for index in unique:
    let row = rows[index]
    for offset in 0..<4:
      # E4 numeric service transport.
      wire[cursor] = byte((uint32(row.service) shr (8*offset)) and 255)
      inc cursor
    let length = encode(JamNatural(uint64(row.bytes.len)))
    for i in 0..<length.len:
      # Canonical blob-length framing.
      wire[cursor] = length.bytes[i]
      inc cursor
    for octet in row.bytes:
      # Only the exact raw blob participates in the union.
      wire[cursor] = octet
      inc cursor
  let captured = decodeOwnedPreimages(wire, limits.values)
  if captured.error != OwnershipError.None:
    fail(AccumulationProvisionError.InvalidState) # Privately encoded transport must still pass the maintained immutable capture boundary.
  let prepared = prepareProvidedPreimages(captured.value, limits.values)
  if prepared.error == PreimageTransitionError.BackendFailure:
    fail(AccumulationProvisionError.BackendFailure) # Capture immutable content/namespace identities once before exposing the union.
  if prepared.error == PreimageTransitionError.LimitExceeded:
    fail(AccumulationProvisionError.LimitExceeded) # The canonical value preparation independently enforces its work/copy ceilings.
  if prepared.error != PreimageTransitionError.None:
    fail(AccumulationProvisionError.InvalidState) # Private canonical transport cannot substitute a refused value certificate.
  var retained = newSeq[AccumulationEffectContext](sources.len)
  for index, source in sources: retained[index] = source # Share only immutable provenance owners.
  AccumulationProvisionResult[PreparedAccumulationProvisions](
    status: AccumulationProvisionError.None,
    completed: PreparedAccumulationProvisions(data: ProvisionPlanData(sources: retained,
      values: prepared.value, info: AccumulationProvisionPlanInfo(
        contexts: sources.len, inputItems: int(count), items: unique.len,
        inputBytes: AccumulationProvisionBytes(copied), bytes: AccumulationProvisionBytes(unionBytes)))))

## Apply fnprovide to the explicit posterior complete map and slot; no terminal/PVM provenance is invented here.
proc integrateAccumulationProvisions*(state: var StateStore, plan: PreparedAccumulationProvisions,
    slot: HeaderSlot): AccumulationProvisionResult[StateStoreSnapshot] =
  let data = plan.data
  if data == nil:
    return AccumulationProvisionResult[StateStoreSnapshot](
        status: AccumulationProvisionError.Uninitialized) # No default plan may authorize state publication.
  let applied = integrateProvidedPreimages(state, data.values, slot)
  case applied.error
  of PreimageTransitionError.None:
    AccumulationProvisionResult[StateStoreSnapshot](status: AccumulationProvisionError.None,
        completed: applied.value)
  of PreimageTransitionError.BackendFailure:
    AccumulationProvisionResult[StateStoreSnapshot](
        status: AccumulationProvisionError.BackendFailure) # Backend refusal cannot publish a partial root.
  of PreimageTransitionError.MalformedState:
    AccumulationProvisionResult[StateStoreSnapshot](
        status: AccumulationProvisionError.MalformedState) # Invalid present posterior histories are not ordinary cancellation.
  of PreimageTransitionError.LimitExceeded:
    AccumulationProvisionResult[StateStoreSnapshot](
        status: AccumulationProvisionError.LimitExceeded) # Inherited store and preparation ceilings remain local refusals.
  else:
    AccumulationProvisionResult[StateStoreSnapshot](
        status: AccumulationProvisionError.InvalidState) # Default/malformed complete-map contracts cannot fabricate success.
