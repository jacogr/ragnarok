# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 Psi_A/I bootstrap: compact arguments and collision-checked initial public service ID.
## Exposes immutable bootstrap handles and a bound adapter deriving posterior entropy from the block stage.
## Mutable implications/checkpoints, PVM execution and state publication remain separate.

import ../codec/[natural, bounded, composite, header, state_safrole, state_layout]
import ../crypto/primitives
import ./[accumulation_service, accumulation_round, accumulation_queue, report_admission,
  block_transition, store]

type
  ## Invocation input count is not a gas amount, service identity or byte ceiling.
  AccumulationArgumentCount* = distinct uint64
  ## Local membership-lookup ceiling is distinct from the protocol's public identifier interval.
  ServiceProbeLimit* = distinct uint64
  ## Failed/default results expose no partially selected ID or argument buffer.
  AccumulationInvocationError* {.pure.} = enum
    Uninitialized, None, InvalidService, CodeUnavailable, InvalidState, MissingState,
    MalformedState, BackendFailure, LimitExceeded, InvalidIndex
  ## Copied seed metadata records exact entropy and slot, without claiming an execution outcome.
  AccumulationInvocationInfo* = object
    service*, nextService*: ServiceIndex
    slot*: HeaderSlot
    inputs*: AccumulationArgumentCount
    entropy*: StateEntropyWord
  ## Private acyclic storage retains immutable service/state/input provenance and argument bytes.
  InvocationData = ref object
    service: PreparedAccumulationService
    info: AccumulationInvocationInfo
    arguments: seq[byte]
  ## Pure bootstrap trusts the caller's explicit posterior entropy; it is not a block certificate.
  PreparedAccumulationInvocation* = object
    data: nil InvocationData
  ## Bound storage retains the genuine service certificate and its posterior-entropy projection.
  BlockInvocationData = ref object
    service: BlockAccumulationService
    projection: PreparedAccumulationInvocation
  ## Only the block adapter can bind the entropy word to the service's actual block stage.
  BlockAccumulationInvocation* = object
    data: nil BlockInvocationData
  ## Only complete selected success carries arguments, owners or a collision-checked identifier.
  AccumulationInvocationResult*[T] = object
    case status: AccumulationInvocationError
    of None:
      completed: T # Guard extraction in checked optimized builds too.
    else:
      discard      # No default success fields accompany a reason.

const
  ## GP Cminpublicindex; low indices are reserved for explicit Registrar creation.
  FirstPublicService* = 65536'u64
  ## The top 256 service IDs are excluded from automatic allocation.
  PublicServiceEnd* = 4294967040'u64
  ## Exact cyclic automatic-allocation domain; arithmetic is proved in uint64 before narrowing.
  PublicServiceCount = PublicServiceEnd-FirstPublicService

## Read failure without granting result retagging.
func error*[T](outcome: AccumulationInvocationResult[
    T]): AccumulationInvocationError = outcome.status
## Extract only selected success under supported compiler/runtime contracts.
func value*[T](outcome: AccumulationInvocationResult[T]): T {.inline,
    requires: outcome.status == AccumulationInvocationError.None.} = outcome.completed

## E(t,s,len(inputs)) uses general compact naturals, independent of header field widths.
proc accumulationArguments*(slot: HeaderSlot, service: ServiceIndex,
    count: AccumulationArgumentCount): seq[byte] =
  result = @[]
  # Three fixed scalar encodings require at most 5+5+9 octets; no count-dependent allocation occurs.
  for scalar in [uint64(uint32(slot)), uint64(uint32(service)), uint64(count)]:
    let encoded = natural.encode(JamNatural(scalar))
    for i in 0..<encoded.len: result.add(encoded.bytes[
        i]) # Concatenate exact compact bytes, without extra framing.

## Hash compact service, raw posterior entropy and compact slot; decode only the first four LE digest bytes.
proc initialAccumulationService*(service: ServiceIndex, entropy: StateEntropyWord,
    slot: HeaderSlot): AccumulationInvocationResult[ServiceIndex] =
  let id = natural.encode(JamNatural(uint64(uint32(service))))
  let time = natural.encode(JamNatural(uint64(uint32(slot))))
  var seed = default(array[42, byte])
  var cursor = 0
  for i in 0..<id.len: seed[cursor] = id.bytes[i]; inc cursor # Leading service has no E4 override.
  let word = array[32, byte](entropy)
  for i in 0..<32: seed[cursor] = word[i]; inc cursor # Entropy has fixed raw hash width.
  for i in 0..<time.len: seed[cursor] = time.bytes[i]; inc cursor # Slot remains compact in this formula.
  let digest = blake2b256(seed.toOpenArray(0, cursor-1))
  if digest.error != CryptoError.None:
    return AccumulationInvocationResult[ServiceIndex](
        status: AccumulationInvocationError.BackendFailure) # Never fabricate a candidate after provider failure.
  let bytes = array[32, byte](digest.value)
  var raw = 0'u64
  for i in 0..<4: raw = raw or (uint64(bytes[i]) shl (i*8)) # Truncation and little-endian order are explicit.
  let candidate = raw mod PublicServiceCount+FirstPublicService
  AccumulationInvocationResult[ServiceIndex](status: AccumulationInvocationError.None,
    completed: ServiceIndex(uint32(candidate)))

## GP check(i): only actual C(255,i) membership occupies an ID; bound probes include the final absence check.
proc findUnusedAccumulationService*(state: StateStoreSnapshot, start: ServiceIndex,
    limit: ServiceProbeLimit): AccumulationInvocationResult[ServiceIndex] =
  var candidate = uint64(uint32(start))
  if candidate < FirstPublicService or candidate >= PublicServiceEnd:
    return AccumulationInvocationResult[ServiceIndex](
        status: AccumulationInvocationError.InvalidIndex) # Reserved ranges cannot enter the automatic cycle.
  var examined = 0'u64
  # One full cycle is sufficient even if a caller supplies an enormous local ceiling.
  while examined < uint64(limit) and examined < PublicServiceCount:
    inc examined
    let entry = state.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(uint32(candidate))))
    if entry.error == StateStoreError.MissingKey:
      return AccumulationInvocationResult[ServiceIndex](status: AccumulationInvocationError.None,
        completed: ServiceIndex(uint32(candidate))) # First absence wins; no account allocation occurs here.
    if entry.error != StateStoreError.None:
      return AccumulationInvocationResult[ServiceIndex](
          status: AccumulationInvocationError.InvalidState) # Default maps cannot masquerade as empty account sets.
    candidate = FirstPublicService+(candidate-FirstPublicService+1) mod PublicServiceCount
  AccumulationInvocationResult[ServiceIndex](status: AccumulationInvocationError.LimitExceeded)

## Copy bootstrap metadata while preserving immutable service/state/input ownership.
proc bootstrapInfo*(plan: PreparedAccumulationInvocation): AccumulationInvocationResult[
    AccumulationInvocationInfo] =
  let data = plan.data
  if data == nil: return AccumulationInvocationResult[AccumulationInvocationInfo](
      status: AccumulationInvocationError.Uninitialized) # No default ID or entropy.
  AccumulationInvocationResult[AccumulationInvocationInfo](status: AccumulationInvocationError.None,
      completed: data.info)

## Retain the original service context independently of this bootstrap handle.
proc bootstrapService*(plan: PreparedAccumulationInvocation): AccumulationInvocationResult[
    PreparedAccumulationService] =
  let data = plan.data
  if data == nil: return AccumulationInvocationResult[PreparedAccumulationService](
      status: AccumulationInvocationError.Uninitialized) # No synthetic execution context.
  AccumulationInvocationResult[PreparedAccumulationService](
      status: AccumulationInvocationError.None, completed: data.service)

## Return independent argument bytes; caller edits cannot alter subsequent invocation setup.
proc bootstrapArguments*(plan: PreparedAccumulationInvocation): AccumulationInvocationResult[seq[byte]] =
  let data = plan.data
  if data == nil: return AccumulationInvocationResult[seq[byte]](
      status: AccumulationInvocationError.Uninitialized) # No fake empty argument tuple.
  var bytes = newSeq[byte](data.arguments.len)
  for i in 0..<bytes.len: bytes[i] = data.arguments[i] # Copy the complete validated small tuple.
  AccumulationInvocationResult[seq[byte]](status: AccumulationInvocationError.None,
      completed: bytes)

## Prepare an eligible service's initial seed and arguments without reserving IDs or mutating state.
proc prepareAccumulationInvocation*(service: PreparedAccumulationService, entropy: StateEntropyWord,
    limit: ServiceProbeLimit): AccumulationInvocationResult[PreparedAccumulationInvocation] =
  ## Refuse atomically, exposing neither a raw candidate nor partial arguments.
  template fail(reason: AccumulationInvocationError) =
    return AccumulationInvocationResult[PreparedAccumulationInvocation](status: reason)
  let info = service.serviceInfo
  if info.error != AccumulationServiceError.None:
    fail(AccumulationInvocationError.InvalidService) # Default handles cannot authorize invocation.
  if info.value.code != AccumulationCodeStatus.Ready:
    fail(AccumulationInvocationError.CodeUnavailable) # This bootstrap is only for the invoking Psi_A alternative.
  let fields = info.value
  let count = AccumulationArgumentCount(uint64(fields.operands)) # Service contexts explicitly exclude transfers.
  let first = initialAccumulationService(fields.service, entropy, fields.slot)
  if first.error != AccumulationInvocationError.None: fail(first.error) # Preserve backend refusal before lookup.
  let unused = findUnusedAccumulationService(service.serviceState.value, first.value, limit)
  if unused.error != AccumulationInvocationError.None: fail(
      unused.error) # Local exhaustion never chooses a different policy.
  AccumulationInvocationResult[PreparedAccumulationInvocation](
    status: AccumulationInvocationError.None,
    completed: PreparedAccumulationInvocation(data: InvocationData(service: service,
      info: AccumulationInvocationInfo(service: fields.service, nextService: unused.value,
        slot: fields.slot, inputs: count, entropy: entropy),
      arguments: accumulationArguments(fields.slot, fields.service, count))))

## Retain the actual bound source so later context construction cannot replace its parent or stage.
proc bootstrapBlockService*(plan: BlockAccumulationInvocation): AccumulationInvocationResult[
    BlockAccumulationService] =
  let data = plan.data
  if data == nil: return AccumulationInvocationResult[BlockAccumulationService](
      status: AccumulationInvocationError.Uninitialized) # No forged service certificate.
  AccumulationInvocationResult[BlockAccumulationService](status: AccumulationInvocationError.None,
      completed: data.service)

## Extract the immutable pure bootstrap view from a genuine block-bound preparation.
proc bootstrapProjection*(plan: BlockAccumulationInvocation): AccumulationInvocationResult[
    PreparedAccumulationInvocation] =
  let data = plan.data
  if data == nil: return AccumulationInvocationResult[PreparedAccumulationInvocation](
      status: AccumulationInvocationError.Uninitialized) # No fabricated successful view.
  AccumulationInvocationResult[PreparedAccumulationInvocation](
      status: AccumulationInvocationError.None, completed: data.projection)

## Decode exact posterior C(6) from this service's completed block stage; parent entropy is never substituted.
proc prepareBlockAccumulationInvocation*(service: BlockAccumulationService,
    limit: ServiceProbeLimit): AccumulationInvocationResult[BlockAccumulationInvocation] =
  ## Preserve refusal without constructing a partially bound bootstrap owner.
  template fail(reason: AccumulationInvocationError) =
    return AccumulationInvocationResult[BlockAccumulationInvocation](status: reason)
  let round = service.serviceBlockRound
  if round.error != AccumulationServiceError.None:
    fail(AccumulationInvocationError.InvalidService) # Only genuine bound services expose their stage.
  let stage = round.value.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value
  let found = stage.snapshot.lookup(chapterKey(StateChapter(6)))
  if found.error == StateStoreError.MissingKey: fail(
      AccumulationInvocationError.MissingState) # No zero entropy fallback.
  if found.error != StateStoreError.None: fail(AccumulationInvocationError.InvalidState) # No default posterior state.
  if found.value.byteLength != 128: fail(AccumulationInvocationError.MalformedState) # Exact fixed chapter size precedes copying.
  let decoded = decodeStateEntropy(found.value.bytes)
  if decoded.error != StateComponentError.None: fail(
      AccumulationInvocationError.MalformedState) # No malformed entropy acceptance.
  let prepared = prepareAccumulationInvocation(service.serviceProjection.value, decoded.value.value[
      0], limit)
  if prepared.error != AccumulationInvocationError.None: fail(
      prepared.error) # No complete owner after a refused seed or probe.
  AccumulationInvocationResult[BlockAccumulationInvocation](
    status: AccumulationInvocationError.None,
    completed: BlockAccumulationInvocation(data: BlockInvocationData(service: service,
        projection: prepared.value)))
