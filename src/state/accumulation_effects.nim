# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 implications: immutable yields, requested provisions and exceptional checkpoints.
## Exposes prepared effect pairs, yield/checkpoint/provision mutations and retained provision extraction.
## Guest memory, gas, registers, execution verdicts and publication belong to their caller's PVM layer.

import std/assertions
import ../codec/[bounded, composite, state_outputs, state_accounts, state_layout, state_requests, state_service_values]
import ../crypto/primitives
import ./[accumulation_context, store, preimages]

type
  ## No refused/default operation exposes a partial context, fabricated hash or successful empty owner.
  AccumulationEffectError* {.pure.} = enum
    Uninitialized, None, InvalidContexts, InvalidDimension, YieldAbsent, UnknownService,
    NotRequested, AlreadyProvided, InvalidLength, InvalidState, MalformedState, LimitExceeded,
      BackendFailure, InvalidIndex
  ## A provision ordinal is neither its target service nor a byte count.
  AccumulationProvisionIndex* = distinct uint64
  ## Independent ceilings bound retained records, individual hash/copy work and aggregate payload bytes.
  AccumulationProvisionLimits* = object
    items*: ElementLimit
    perBlob*, totalBlobBytes*: ByteLimit
  ## Immutable provision backing binds the exact target to its independent raw-byte payload.
  ProvisionData = ref object
    service: ServiceIndex
    bytes: seq[byte]
  ## Retained provision owns its original bytes and target; no detached span or caller-selected buffer is accepted.
  AccumulationProvision* = object
    data: nil ProvisionData
  ## Copied fixed facts never expose the provision's mutable backing sequence.
  AccumulationProvisionInfo* = object
    service*: ServiceIndex
    bytes*: int
  ## Immutable set owner lets yield/checkpoint share provision membership without copying its sequence.
  ProvisionSetData = ref object
    values: seq[AccumulationProvision]
    bytes, largest: uint64
  ## Only a present alternative stores a commitment; absence cannot expose a default all-zero hash.
  YieldValue = object
    case present: bool
    of true:
      commitment: OutputCommitment # Zero bytes remain a present protocol value.
    of false:
      discard                      # Absence carries no commitment payload.
  ## Current implications retain initial accounts/roles/next-ID with versioned yield and provisions.
  EffectData = ref object
    initial: InitialAccumulationContext
    output: YieldValue
    provisions: ProvisionSetData
  ## Read-only acyclic context; copies retain a version independently of later effect operations.
  AccumulationEffectContext* = object
    data: nil EffectData
  ## Private pair retains exact initial provenance; neither child refers back to this owner or older pairs.
  PairData = ref object
    source: PreparedAccumulationContexts
    regular, exceptional: AccumulationEffectContext
  ## Only prepared initial contexts create a pair; mutations preserve their service/input identity.
  AccumulationEffects* = object
    data: nil PairData
  ## Copied current facts report retained provisions and the still-empty outgoing transfer sequence.
  AccumulationEffectInfo* = object
    service*, nextService*: ServiceIndex
    transfers*, provisions*: int
    hasYield*: bool
  ## Successful alternatives alone carry complete retained handles, facts or a present yield value.
  AccumulationEffectResult*[T] = object
    case status: AccumulationEffectError
    of None:
      completed: T # Contract-guarded extraction is the only public payload access.
    else:
      discard      # Refusals/defaults carry only their reason.

## Inspect success/failure without permitting retagging or mutable access.
func error*[T](outcome: AccumulationEffectResult[T]): AccumulationEffectError = outcome.status
## Extract selected success under compiler/runtime contracts, including optimized execution.
func value*[T](outcome: AccumulationEffectResult[T]): T {.inline,
    requires: outcome.status == AccumulationEffectError.None.} = outcome.completed

## Retain the exact initial context backing this version's accounts, roles, next-ID and input provenance.
proc effectInitialContext*(context: AccumulationEffectContext): AccumulationEffectResult[
    InitialAccumulationContext] =
  let data = context.data
  if data == nil:
    # A default effect cannot supply another context as a substitute source.
    return AccumulationEffectResult[InitialAccumulationContext](
        status: AccumulationEffectError.Uninitialized)
  AccumulationEffectResult[InitialAccumulationContext](status: AccumulationEffectError.None,
    completed: data.initial)

## Copy current yield-presence and retained service facts, never mutable implication storage.
proc effectInfo*(context: AccumulationEffectContext): AccumulationEffectResult[
    AccumulationEffectInfo] =
  let data = context.data
  if data == nil:
    # Missing owners cannot masquerade as valid services with zero effects.
    return AccumulationEffectResult[AccumulationEffectInfo](
        status: AccumulationEffectError.Uninitialized)
  let source = data.initial.contextInfo.value
  AccumulationEffectResult[AccumulationEffectInfo](status: AccumulationEffectError.None,
    completed: AccumulationEffectInfo(service: source.service, nextService: source.nextService,
      transfers: source.transfers, provisions: data.provisions.values.len,
      hasYield: data.output.present))

## Read a present yield by value; default and absent alternatives never return a fake zero commitment.
proc effectYield*(context: AccumulationEffectContext): AccumulationEffectResult[OutputCommitment] =
  let data = context.data
  if data == nil:
    # Default contexts have no selected yield state.
    return AccumulationEffectResult[OutputCommitment](status: AccumulationEffectError.Uninitialized)
  if not data.output.present:
    # A successfully prepared context may legitimately have no yield yet.
    return AccumulationEffectResult[OutputCommitment](status: AccumulationEffectError.YieldAbsent)
  AccumulationEffectResult[OutputCommitment](status: AccumulationEffectError.None,
    completed: data.output.commitment)

## Select one exact version; invalid enum casts cannot silently alias the exceptional dimension.
proc effectContext*(effects: AccumulationEffects, dimension: AccumulationDimension):
    AccumulationEffectResult[AccumulationEffectContext] =
  if ord(dimension) < ord(AccumulationDimension.Regular) or ord(dimension) > ord(
      AccumulationDimension.Exceptional):
    # Reject unsupported dimensions before selecting any retained child.
    return AccumulationEffectResult[AccumulationEffectContext](
        status: AccumulationEffectError.InvalidDimension)
  let data = effects.data
  if data == nil:
    # Default pairs are not initialized I squared values.
    return AccumulationEffectResult[AccumulationEffectContext](
        status: AccumulationEffectError.Uninitialized)
  let selected = if dimension == AccumulationDimension.Regular: data.regular
    else: data.exceptional # Only the two validated dimensions remain.
  AccumulationEffectResult[AccumulationEffectContext](status: AccumulationEffectError.None,
    completed: selected)

## Retain original prepared provenance independently of effect versions and checkpoint lifetimes.
proc effectsSource*(effects: AccumulationEffects): AccumulationEffectResult[
    PreparedAccumulationContexts] =
  let data = effects.data
  if data == nil:
    # No default pair may grant an initialized preparation certificate.
    return AccumulationEffectResult[PreparedAccumulationContexts](
        status: AccumulationEffectError.Uninitialized)
  AccumulationEffectResult[PreparedAccumulationContexts](status: AccumulationEffectError.None,
    completed: data.source)

## Begin at the actual initial I in both dimensions; no caller-selected replacement state or yield is accepted.
proc prepareAccumulationEffects*(contexts: PreparedAccumulationContexts): AccumulationEffectResult[
    AccumulationEffects] =
  let initial = contexts.initialContext(AccumulationDimension.Regular)
  if initial.error != AccumulationContextError.None:
    # Only successfully prepared immutable contexts can authorize host state effects.
    return AccumulationEffectResult[AccumulationEffects](
        status: AccumulationEffectError.InvalidContexts)
  let current = AccumulationEffectContext(data: EffectData(initial: initial.value,
    output: YieldValue(present: false), provisions: ProvisionSetData(values: @[], bytes: 0, largest: 0)))
  AccumulationEffectResult[AccumulationEffects](status: AccumulationEffectError.None,
    completed: AccumulationEffects(data: PairData(source: contexts, regular: current,
        exceptional: current)))

## Apply only the state part of a validated yield call: replace regular yield, preserving the checkpoint.
## The host dispatcher must first charge gas/read guest memory; failures there must not call this operation.
proc recordAccumulationYield*(effects: AccumulationEffects, commitment: OutputCommitment):
    AccumulationEffectResult[AccumulationEffects] =
  let data = effects.data
  if data == nil:
    # Refuse before constructing a partially initialized regular context.
    return AccumulationEffectResult[AccumulationEffects](
        status: AccumulationEffectError.Uninitialized)
  let previous = data.regular.data
  assert previous != nil # Private construction preserves initialized children for every published pair.
  let current = AccumulationEffectContext(data: EffectData(initial: previous.initial,
    output: YieldValue(present: true, commitment: commitment), provisions: previous.provisions))
  AccumulationEffectResult[AccumulationEffects](status: AccumulationEffectError.None,
    completed: AccumulationEffects(data: PairData(source: data.source, regular: current,
      exceptional: data.exceptional)))

## Apply only checkpoint's implication assignment Y'=X; later regular changes cannot alter the retained snapshot.
## Guest gas/r7 handling is outside this state-only operation; no implicit checkpoint occurs on yield.
proc checkpointAccumulationEffects*(effects: AccumulationEffects): AccumulationEffectResult[
    AccumulationEffects] =
  let data = effects.data
  if data == nil:
    # A checkpoint cannot turn an uninitialized pair into successful empty implications.
    return AccumulationEffectResult[AccumulationEffects](
        status: AccumulationEffectError.Uninitialized)
  AccumulationEffectResult[AccumulationEffects](status: AccumulationEffectError.None,
    completed: AccumulationEffects(data: PairData(source: data.source, regular: data.regular,
      exceptional: data.regular)))

## Retain one provision only after checking its ordinal against this exact immutable context.
proc effectProvisionAt*(context: AccumulationEffectContext, index: AccumulationProvisionIndex):
    AccumulationEffectResult[AccumulationProvision] =
  let data = context.data
  if data == nil:
    # Default contexts contain no validated provision sequence.
    return AccumulationEffectResult[AccumulationProvision](
        status: AccumulationEffectError.Uninitialized)
  if uint64(index) >= uint64(data.provisions.values.len):
    # Prove the full-width ordinal before narrowing or accessing the retained sequence.
    return AccumulationEffectResult[AccumulationProvision](
        status: AccumulationEffectError.InvalidIndex)
  AccumulationEffectResult[AccumulationProvision](status: AccumulationEffectError.None,
    completed: data.provisions.values[int(uint64(index))])

## Copy the exact target and length from one owner-bound provision; default handles are not empty blobs.
proc provisionInfo*(provision: AccumulationProvision): AccumulationEffectResult[
    AccumulationProvisionInfo] =
  let data = provision.data
  if data == nil:
    # A default provision cannot fabricate target zero or a valid zero-byte payload.
    return AccumulationEffectResult[AccumulationProvisionInfo](
        status: AccumulationEffectError.Uninitialized)
  AccumulationEffectResult[AccumulationProvisionInfo](status: AccumulationEffectError.None,
    completed: AccumulationProvisionInfo(service: data.service, bytes: data.bytes.len))

## Return independent bytes from the retained provision; caller mutations never affect later extraction/checkpoints.
proc copyProvisionBytes*(provision: AccumulationProvision): AccumulationEffectResult[seq[byte]] =
  let data = provision.data
  if data == nil:
    # Empty successful payloads require an actual validated owner.
    return AccumulationEffectResult[seq[byte]](status: AccumulationEffectError.Uninitialized)
  var bytes = newSeq[byte](data.bytes.len)
  # Exact retained length was bounded before construction; copy without exporting shared mutable storage.
  for i, octet in data.bytes: bytes[i] = octet
  AccumulationEffectResult[seq[byte]](status: AccumulationEffectError.None, completed: bytes)

## Retain a requested target/blob pair in regular implications only, with WHO/HUH-style protocol refusals.
## Stable bytes are borrowed during the call; accepted bytes are independently owned. Guest gas/memory checks precede this API.
proc recordAccumulationProvision*(effects: AccumulationEffects, service: ServiceIndex,
    bytes: openArray[byte], limits: AccumulationProvisionLimits): AccumulationEffectResult[
        AccumulationEffects] =
  ## All refusals preserve the caller's pair and expose no partially captured provision.
  template fail(reason: AccumulationEffectError) =
    return AccumulationEffectResult[AccumulationEffects](status: reason)
  let data = effects.data
  if data == nil:
    fail(AccumulationEffectError.Uninitialized) # No default pair authorizes account lookup or retained bytes.
  let previous = data.regular.data
  assert previous != nil # Only private constructors publish initialized children.
  let size = uint64(bytes.len)
  if size > uint64(high(uint32)):
    fail(AccumulationEffectError.InvalidLength) # Keep the pinned request-length domain without namespace restrictions.
  if size > uint64(limits.perBlob) or previous.provisions.largest > uint64(limits.perBlob) or
      previous.provisions.bytes > uint64(limits.totalBlobBytes) or
      uint64(previous.provisions.values.len) > uint64(limits.items):
    fail(AccumulationEffectError.LimitExceeded) # Bound hash/scan work and validate retained-prefix policy before new work.
  let state = previous.initial.contextAccounts.value
  let account = state.lookup(chapterServiceKey(StateChapter(255), service))
  if account.error == StateStoreError.MissingKey:
    fail(AccumulationEffectError.UnknownService) # Orphan request records do not create a target account.
  if account.error != StateStoreError.None:
    fail(AccumulationEffectError.InvalidState) # Default/corrupt backing cannot fabricate WHO or HUH.
  let digest = blake2b256(bytes)
  if digest.error != CryptoError.None:
    fail(AccumulationEffectError.BackendFailure) # No failed hash becomes an unrequested verdict.
  let requested = preimageRequested(state, service, ServicePreimageHash(array[32, byte](
      digest.value)),
    RequestLength(uint32(size)))
  if requested.error == PreimageTransitionError.BackendFailure:
    fail(AccumulationEffectError.BackendFailure) # Preserve canonical namespace failures separately.
  if requested.error == PreimageTransitionError.MalformedState:
    fail(AccumulationEffectError.MalformedState) # Never normalize malformed account/history bytes into ordinary HUH.
  if requested.error != PreimageTransitionError.None:
    fail(AccumulationEffectError.InvalidState) # Only a complete canonical query can authorize provision capture.
  if not requested.value:
    fail(AccumulationEffectError.NotRequested) # Only the exact outstanding (hash,length) request is eligible.
  # Equality is target plus complete raw bytes, not hash-only equality or an unrelated owner's coordinates.
  for provision in previous.provisions.values:
    let retained = provision.data
    assert retained != nil # Published provision sequences contain initialized owners only.
    if uint32(retained.service) == uint32(service) and retained.bytes == bytes:
      fail(AccumulationEffectError.AlreadyProvided) # Duplicate refusal requires no additional record capacity.
  if uint64(previous.provisions.values.len) >= uint64(limits.items) or
      previous.provisions.values.len >= high(int) div sizeof(AccumulationProvision) or
      size > uint64(limits.totalBlobBytes)-previous.provisions.bytes:
    fail(AccumulationEffectError.LimitExceeded) # Prove count/native extent and aggregate addition before allocation.
  var owned = newSeq[byte](bytes.len)
  # Borrowed caller bytes become immutable private storage before any successful pair is published.
  for i, octet in bytes: owned[i] = octet
  var provisions = newSeq[AccumulationProvision](previous.provisions.values.len+1)
  # Share only immutable prior provision owners; no new version links back to its parent effect pair.
  for i, provision in previous.provisions.values: provisions[i] = provision
  provisions[previous.provisions.values.len] = AccumulationProvision(data: ProvisionData(
      service: service, bytes: owned))
  let current = AccumulationEffectContext(data: EffectData(initial: previous.initial,
    output: previous.output, provisions: ProvisionSetData(values: provisions,
      bytes: previous.provisions.bytes+size,
      largest: max(previous.provisions.largest, size))))
  AccumulationEffectResult[AccumulationEffects](status: AccumulationEffectError.None,
    completed: AccumulationEffects(data: PairData(source: data.source, regular: current,
      exceptional: data.exceptional)))
