# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 accounts code lookup and Psi_A entry gate for one prepared accumulation service.
## Exposes immutable account/input/code contexts and an admitted-parent/slot-bound initial-round adapter.
## Incoming transfer credit is retained on a private complete-map branch; no PVM execution or caller publication.

import ../codec/[bounded, composite, work_digest, state_accounts, state_layout,
  state_service_values, header, owned, c2_records]
import ../crypto/primitives
import ./[accumulation_inputs, accumulation_round, accumulation_queue, report_admission,
  block_transition, block_admission, store]

type
  ServiceCodeLimit* = distinct uint64 ## Protocol code-size eligibility is distinct from local preimage-copy/hash resource policy.
  AccumulationServiceConfig* = object ## Bound complete preimage work independently of the protocol limit on the extracted code suffix.
    codeLimit*: ServiceCodeLimit
    preimageBytes*: ByteLimit
  AccumulationCodeStatus* {.pure.} = enum ## Successful contexts distinguish absent/malformed/oversized code from a valid empty code blob.
    Missing, Malformed, Oversized, Ready
  AccumulationServiceError* {.pure.} = enum ## Failures expose no partially resolved account, code or input sequence.
    Uninitialized, None, InvalidInputs, InvalidIndex, InvalidState, MissingAccount,
    MalformedAccount, LimitExceeded, BackendFailure, CodeUnavailable, InvalidRound, BalanceOverflow
  AccumulationServiceInfo* = object ## Copied post-credit metadata preserves other account fields and exact invocation gas/input counts.
    service*: ServiceIndex
    slot*: HeaderSlot
    gas*: Gas
    transfers*, operands*, codeBytes*: int
    account*: ServiceMetadata
    code*: AccumulationCodeStatus
  ## Private acyclic storage retains the exact complete map and inputs, with an independent code suffix copy.
  ServiceData = ref object
    info: AccumulationServiceInfo
    state, prior: StateStoreSnapshot
    inputs: PreparedAccumulationInputs
    index: InvocationServiceIndex
    code: seq[byte]
  PreparedAccumulationService* = object ## Pure contexts certify only resolution against the caller's explicit state and slot.
    data: nil ServiceData
  ## Bound storage retains the original initial-round certificate separately from its immutable projection.
  BlockServiceData = ref object
    round: BlockAccumulationRound
    projection: PreparedAccumulationService
  BlockAccumulationService* = object ## Only the block adapter supplies exact admitted-parent state and authenticated candidate slot.
    data: nil BlockServiceData
  AccumulationServiceResult*[T] = object ## Only selected success carries complete retained handles, copied metadata or independent code bytes.
    case status: AccumulationServiceError
    of None:
      completed: T # Extract through the selected-success accessor only.
    else:
      discard      # Failures/defaults carry no usable success payload.

func error*[T](outcome: AccumulationServiceResult[T]): AccumulationServiceError =
  ## Inspect a reason without permitting retagging or mutable access.
  outcome.status
func value*[T](outcome: AccumulationServiceResult[T]): T {.inline,
    requires: outcome.status == AccumulationServiceError.None.} =
  ## Extract selected success under compiler and runtime contracts.
  outcome.completed

func serviceSourceMatches*(plan: PreparedAccumulationService, inputs: PreparedAccumulationInputs,
    prior: StateStoreSnapshot): bool =
  ## Prove exact input and prior-snapshot ownership without exposing replaceable handles.
  ## Defaults never match; copied handles of the genuine immutable sources remain valid.
  let data = plan.data
  if data == nil:
    return false # No default service can certify an input set or complete-map prior.
  sameAccumulationInputs(data.inputs, inputs) and sameStateSnapshot(data.prior, prior)

proc serviceInfo*(plan: PreparedAccumulationService): AccumulationServiceResult[
    AccumulationServiceInfo] =
  ## Copy complete account/gas/code-status metadata without exporting retained arrays.
  let data = plan.data
  if data == nil: return AccumulationServiceResult[AccumulationServiceInfo](
      status: AccumulationServiceError.Uninitialized) # No default account or successful empty code.
  AccumulationServiceResult[AccumulationServiceInfo](status: AccumulationServiceError.None,
    completed: data.info)

proc serviceState*(plan: PreparedAccumulationService): AccumulationServiceResult[
    StateStoreSnapshot] =
  ## Retain the post-credit complete state independently for later skip or execution-context construction.
  let data = plan.data
  if data == nil: return AccumulationServiceResult[StateStoreSnapshot](
      status: AccumulationServiceError.Uninitialized) # No substitute parent map.
  AccumulationServiceResult[StateStoreSnapshot](status: AccumulationServiceError.None,
      completed: data.state)

proc servicePriorState*(plan: PreparedAccumulationService): AccumulationServiceResult[
    StateStoreSnapshot] =
  ## Retain the exact pre-credit source separately; extracting or reusing either view never credits again.
  let data = plan.data
  if data == nil:
    # No default source can stand in for an initialized complete map.
    return AccumulationServiceResult[StateStoreSnapshot](
        status: AccumulationServiceError.Uninitialized)
  AccumulationServiceResult[StateStoreSnapshot](status: AccumulationServiceError.None,
    completed: data.prior)

proc serviceInputAt*(plan: PreparedAccumulationService,
    index: InvocationInputIndex): AccumulationServiceResult[InvocationInput] =
  ## Extract one input only from this context's original service group; no second service selector is accepted.
  let data = plan.data
  if data == nil: return AccumulationServiceResult[InvocationInput](
      status: AccumulationServiceError.Uninitialized) # No fabricated input.
  let input = data.inputs.invocationInputAt(data.index, index)
  if input.error != AccumulationInputError.None:
    return AccumulationServiceResult[InvocationInput](
        status: AccumulationServiceError.InvalidIndex) # Bound ordinal before access.
  AccumulationServiceResult[InvocationInput](status: AccumulationServiceError.None,
      completed: input.value)

proc serviceCode*(plan: PreparedAccumulationService): AccumulationServiceResult[seq[byte]] =
  ## Copy only eligible code, preserving immutable owner storage; Ready with zero bytes is valid here.
  let data = plan.data
  if data == nil: return AccumulationServiceResult[seq[byte]](
      status: AccumulationServiceError.Uninitialized) # A default owner is not an unavailable-code success.
  if data.info.code != AccumulationCodeStatus.Ready:
    return AccumulationServiceResult[seq[byte]](status: AccumulationServiceError.CodeUnavailable) # Never expose a fake empty program.
  var bytes = newSeq[byte](data.code.len)
  for i in 0..<bytes.len: bytes[i] = data.code[i] # Caller mutations cannot alter later extraction.
  AccumulationServiceResult[seq[byte]](status: AccumulationServiceError.None, completed: bytes)

proc prepareAccumulationService*(inputs: PreparedAccumulationInputs, index: InvocationServiceIndex,
    state: StateStoreSnapshot, slot: HeaderSlot,
    config: AccumulationServiceConfig): AccumulationServiceResult[PreparedAccumulationService] =
  ## Resolve one service from explicit state/slot and prepared inputs; missing accounts are a preparation refusal,
  ## not a fabricated Psi_A outcome. No invocation-time minimum-gas or balance filter is added by this layer.
  ## The account's code preimage is E(length(metadata)) || metadata || code, with no outer code length.
  ## Refuse without exposing an earlier metadata record or partially copied code.
  template fail(reason: AccumulationServiceError) =
    return AccumulationServiceResult[PreparedAccumulationService](status: reason)
  let selected = inputs.invocationServiceAt(index)
  if selected.error != AccumulationInputError.None:
    if selected.error == AccumulationInputError.InvalidIndex:
      fail(AccumulationServiceError.InvalidIndex) # Nominal service ordinal must fit before state work.
    fail(AccumulationServiceError.InvalidInputs) # Default inputs are not a valid empty invocation.
  let source = selected.value
  let found = state.lookup(chapterServiceKey(StateChapter(255), source.service))
  if found.error == StateStoreError.MissingKey:
    fail(AccumulationServiceError.MissingAccount) # Do not invent account fields or an execution result.
  if found.error != StateStoreError.None:
    fail(AccumulationServiceError.InvalidState) # Default maps cannot satisfy account binding.
  if found.value.byteLength != ServiceMetadataBytes:
    fail(AccumulationServiceError.MalformedAccount) # Exact fixed metadata extent precedes copying.
  let account = decodeServiceMetadata(found.value.bytes, ByteLimit(ServiceMetadataBytes))
  if account.error != ServiceMetadataError.None:
    fail(AccumulationServiceError.MalformedAccount) # No unsupported version or malformed metadata fallback.
  var metadata = account.value.metadata
  let originalBalance = uint64(metadata.balance)
  let originalSupervisorBalance = uint64(metadata.supervisorBalance)
  var balance = originalBalance
  var supervisorBalance = originalSupervisorBalance
  # Filtered source order is retained; each canonical flag chooses one independent unsigned balance.
  for i in 0..<source.transfers:
    let input = inputs.invocationInputAt(index, InvocationInputIndex(uint64(i))).value
    let transfer = input.transfer
    let amount = uint64(transfer.amount)
    if transfer.destinationSupervisor:
      if amount > high(uint64)-supervisorBalance:
        fail(AccumulationServiceError.BalanceOverflow) # Supervised credit cannot wrap into liquid balance.
      supervisorBalance += amount
    else:
      if amount > high(uint64)-balance:
        fail(AccumulationServiceError.BalanceOverflow) # Liquid credit remains in its own full uint64 domain.
      balance += amount
  metadata.balance = AccountBalance(balance)
  metadata.supervisorBalance = AccountBalance(supervisorBalance)
  let key = servicePreimageKey(source.service, ServicePreimageHash(array[32, byte](
      metadata.codeHash)), ByteLimit(32))
  if key.error != ServiceValueError.None:
    fail(AccumulationServiceError.BackendFailure) # Hash failure cannot become missing code.
  let preimage = state.lookup(key.value)
  var status = AccumulationCodeStatus.Missing
  var code: seq[byte] = @[]
  var codeBytes = 0
  if preimage.error == StateStoreError.None:
    if uint64(preimage.value.byteLength) > uint64(config.preimageBytes):
      fail(AccumulationServiceError.LimitExceeded) # Bound complete copy/hash work, including metadata, first.
    let raw = preimage.value.bytes
    let hash = blake2b256(raw)
    if hash.error != CryptoError.None:
      fail(AccumulationServiceError.BackendFailure) # A rejected backend must not fabricate code eligibility.
    if array[32, byte](hash.value) != array[32, byte](metadata.codeHash):
      fail(AccumulationServiceError.InvalidState) # Enforce the preimage/hash invariant without treating corruption as absence.
    let envelope = decodeBytesBorrowed(raw, ByteLimit(raw.len))
    if envelope.error != ContainerError.None:
      status = AccumulationCodeStatus.Malformed # Accounts definition maps an invalid two-blob envelope to absent code.
    else:
      let start = envelope.consumed
      codeBytes = raw.len-start
      if uint64(codeBytes) > uint64(config.codeLimit):
        status = AccumulationCodeStatus.Oversized # Protocol size gate concerns code, not preceding metadata.
      else:
        status = AccumulationCodeStatus.Ready # PVM program validity is checked later, including empty programs.
        code = newSeq[byte](codeBytes)
        for i in 0..<code.len: code[i] = raw[start+i] # Copy only proved suffix bytes, retaining no detached span.
  elif preimage.error != StateStoreError.MissingKey:
    fail(AccumulationServiceError.InvalidState) # Only actual absence becomes Missing code.
  else:
    discard # Present account with no code preimage is an ordinary non-executing Psi_A gate.
  var credited = state
  if balance != originalBalance or supervisorBalance != originalSupervisorBalance:
    # Fork the entire retained map with inherited ceilings; never reconstruct a partial account-only root.
    var working = state.forkStateStore.value
    let entry = serviceMetadataEntry(source.service, metadata, ByteLimit(
        ServiceMetadataBytes)).value
    let applied = working.apply([StateWrite(key: entry.key, kind: StateWriteKind.Put,
        value: entry.value)])
    if applied.error == StateStoreError.BackendFailure:
      fail(AccumulationServiceError.BackendFailure) # Late Merklization failure exposes no credited owner.
    if applied.error != StateStoreError.None:
      fail(AccumulationServiceError.LimitExceeded) # Inherited write/trie budgets apply to the complete branch.
    credited = applied.value
  AccumulationServiceResult[PreparedAccumulationService](status: AccumulationServiceError.None,
    completed: PreparedAccumulationService(data: ServiceData(state: credited, prior: state,
      inputs: inputs,
      index: index,
      code: code, info: AccumulationServiceInfo(service: source.service, slot: slot,
        gas: source.gas,
        transfers: source.transfers, operands: source.operands, account: metadata, code: status,
        codeBytes: codeBytes))))

proc serviceBlockRound*(plan: BlockAccumulationService): AccumulationServiceResult[
    BlockAccumulationRound] =
  ## Retain the original bound initial round independently of the extracted service context.
  let data = plan.data
  if data == nil: return AccumulationServiceResult[BlockAccumulationRound](
      status: AccumulationServiceError.Uninitialized) # No forged round certificate.
  AccumulationServiceResult[BlockAccumulationRound](status: AccumulationServiceError.None,
      completed: data.round)

proc serviceProjection*(plan: BlockAccumulationService): AccumulationServiceResult[
    PreparedAccumulationService] =
  ## Retain a pure context while preserving the separately held admitted-block provenance.
  let data = plan.data
  if data == nil: return AccumulationServiceResult[PreparedAccumulationService](
      status: AccumulationServiceError.Uninitialized) # No default success projection.
  AccumulationServiceResult[PreparedAccumulationService](status: AccumulationServiceError.None,
    completed: data.projection)

proc prepareBlockAccumulationService*(round: BlockAccumulationRound, index: InvocationServiceIndex,
    config: AccumulationServiceConfig): AccumulationServiceResult[BlockAccumulationService] =
  ## Supply exact admitted-parent accounts and the authenticated candidate slot for one initial-round service.
  ## Publish neither a bound owner nor pure projection after any parent/lookup refusal.
  template fail(reason: AccumulationServiceError) =
    return AccumulationServiceResult[BlockAccumulationService](status: reason)
  let bound = round.roundBlockQueue
  if bound.error != AccumulationRoundError.None:
    fail(AccumulationServiceError.InvalidRound) # Only the genuine initial-round adapter certifies this source.
  let stage = bound.value.accumulationAdmission.value.reportBlockStage.value.value
  let parent = stage.admitted.admittedState
  let slot = headerInfo(stage.admitted.admittedHeader).value.unsigned.slot
  let projected = prepareAccumulationService(round.roundProjection.value.roundInputs.value,
    index, parent, slot, config)
  if projected.error != AccumulationServiceError.None:
    fail(projected.error) # No earlier account or code escapes a failed bound preparation.
  AccumulationServiceResult[BlockAccumulationService](status: AccumulationServiceError.None,
    completed: BlockAccumulationService(data: BlockServiceData(round: round,
        projection: projected.value)))
