# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Psi_A's absent-account branch retains exact prior state and zero effects before incoming credit or code lookup.
## Pure and initial block-bound certificates never fabricate resolved services or executed outcomes.
import ../../codec/[composite, header]
import ../../codec/state/[accounts as state_accounts, layout as state_layout]
import ../../codec/work/digest as work_digest
import ./[inputs as accumulation_inputs, round as accumulation_round, queue as accumulation_queue]
import ../report/admission as report_admission
import "../block/transition" as block_transition
import "../block/admission" as block_admission
import ../store

type
  AccumulationAbsentError* {.pure.} = enum ## Default/refused alternatives carry reasons alone.
    Uninitialized, None, InvalidInputs, InvalidIndex, InvalidState, AccountPresent, InvalidRound
  AccumulationAbsentInfo* = object ## Fixed copied observations distinguish offered input budget from actual zero execution.
    service*: ServiceIndex
    slot*: HeaderSlot
    offeredGas*, gasUsed*: Gas
    incomingTransfers*, operands*: int
    modifiedAccounts*, transfers*, provisions*: int
    hasYield*: bool
  AbsentData = ref object # Acyclic immutable source handles retain no borrowed buffers or synthetic service metadata.
    inputs: PreparedAccumulationInputs
    index: InvocationServiceIndex
    state: StateStoreSnapshot
    info: AccumulationAbsentInfo
  AbsentAccumulation* = object ## Only actual absence in this exact common source constructs a complete no-execution proof.
    data: nil AbsentData
  BlockAbsentData = ref object # Genuine block authority remains separate from the explicit-input pure projection.
    round: BlockAccumulationRound
    projection: AbsentAccumulation
  BlockAbsentAccumulation* = object ## Only the bound adapter supplies the admitted parent and authenticated slot.
    data: nil BlockAbsentData
  AccumulationAbsentResult*[T] = object ## Only selected success exposes retained immutable state or proof owners.
    case status: AccumulationAbsentError
    of None:
      completed: T # No public writable tag or inactive success storage.
    else:
      discard      # Failure carries no fabricated empty effects.

func error*[T](outcome: AccumulationAbsentResult[T]): AccumulationAbsentError =
  ## Inspect the reason without granting retagging.
  outcome.status

func value*[T](outcome: AccumulationAbsentResult[T]): T {.inline,
    requires: outcome.status == AccumulationAbsentError.None.} =
  ## Extract only complete success under optimized checked contracts.
  outcome.completed

proc finishAbsentAccumulation*(inputs: PreparedAccumulationInputs, index: InvocationServiceIndex,
    state: StateStoreSnapshot, slot: HeaderSlot): AccumulationAbsentResult[AbsentAccumulation] =
  ## Certify the first Psi_A branch before any amount arithmetic, code/preimage lookup, hashing or guest bootstrap.
  template fail(reason: AccumulationAbsentError) =
    return AccumulationAbsentResult[AbsentAccumulation](status: reason)
  let selected = inputs.invocationServiceAt(index)
  if selected.error == AccumulationInputError.InvalidIndex:
    fail(AccumulationAbsentError.InvalidIndex) # Preserve full-width ordinal refusal before state work.
  if selected.error != AccumulationInputError.None:
    fail(AccumulationAbsentError.InvalidInputs) # A default owner is not a prepared empty invocation group.
  let found = state.lookup(chapterServiceKey(StateChapter(255), selected.value.service))
  if found.error == StateStoreError.None:
    fail(AccumulationAbsentError.AccountPresent) # Present malformed records also require ordinary service validation; never claim they are absent.
  if found.error != StateStoreError.MissingKey:
    fail(AccumulationAbsentError.InvalidState) # Default/invalid maps cannot prove account absence.
  let source = selected.value
  AccumulationAbsentResult[AbsentAccumulation](status: AccumulationAbsentError.None,
    completed: AbsentAccumulation(data: AbsentData(inputs: inputs, index: index, state: state,
      info: AccumulationAbsentInfo(service: source.service, slot: slot, offeredGas: source.gas,
        gasUsed: Gas(0), incomingTransfers: source.transfers, operands: source.operands,
        modifiedAccounts: 0, transfers: 0, provisions: 0, hasYield: false))))

proc absentInfo*(outcome: AbsentAccumulation): AccumulationAbsentResult[AccumulationAbsentInfo] =
  ## Copy exact input observations and actual zero/empty effects without inventing an account/code status.
  let data = outcome.data
  if data == nil: return AccumulationAbsentResult[AccumulationAbsentInfo](
      status: AccumulationAbsentError.Uninitialized) # No default zero-execution success.
  AccumulationAbsentResult[AccumulationAbsentInfo](status: AccumulationAbsentError.None,
      completed: data.info)

proc absentInputs*(outcome: AbsentAccumulation): AccumulationAbsentResult[
    PreparedAccumulationInputs] =
  ## Retain exact prepared input ownership rather than equal-content substitution.
  let data = outcome.data
  if data == nil: return AccumulationAbsentResult[PreparedAccumulationInputs](
      status: AccumulationAbsentError.Uninitialized) # No fabricated input source.
  AccumulationAbsentResult[PreparedAccumulationInputs](status: AccumulationAbsentError.None,
      completed: data.inputs)

proc absentIndex*(outcome: AbsentAccumulation): AccumulationAbsentResult[InvocationServiceIndex] =
  ## Copy the nominal ordinal bound to this certificate's own input owner.
  let data = outcome.data
  if data == nil: return AccumulationAbsentResult[InvocationServiceIndex](
      status: AccumulationAbsentError.Uninitialized) # No detached default ordinal.
  AccumulationAbsentResult[InvocationServiceIndex](status: AccumulationAbsentError.None,
      completed: data.index)

proc absentState*(outcome: AbsentAccumulation): AccumulationAbsentResult[StateStoreSnapshot] =
  ## Retain the exact unchanged complete input state; no incoming pool is credited by this branch.
  let data = outcome.data
  if data == nil: return AccumulationAbsentResult[StateStoreSnapshot](
      status: AccumulationAbsentError.Uninitialized) # No default root or missing-account map.
  AccumulationAbsentResult[StateStoreSnapshot](status: AccumulationAbsentError.None,
      completed: data.state)

proc finishBlockAbsentAccumulation*(round: BlockAccumulationRound,
    index: InvocationServiceIndex): AccumulationAbsentResult[BlockAbsentAccumulation] =
  ## Derive source state and slot from genuine admitted block authority, never caller replacements.
  template fail(reason: AccumulationAbsentError) =
    return AccumulationAbsentResult[BlockAbsentAccumulation](status: reason)
  let bound = round.roundBlockQueue
  if bound.error != AccumulationRoundError.None:
    fail(AccumulationAbsentError.InvalidRound) # No pure/default owner can grant block authority.
  let stage = bound.value.accumulationAdmission.value.reportBlockStage.value.value
  let parent = stage.admitted.admittedState
  let slot = headerInfo(stage.admitted.admittedHeader).value.unsigned.slot
  let projected = finishAbsentAccumulation(round.roundProjection.value.roundInputs.value, index,
      parent, slot)
  if projected.error != AccumulationAbsentError.None: fail(
      projected.error) # No earlier pure success escapes failed bound preparation.
  AccumulationAbsentResult[BlockAbsentAccumulation](status: AccumulationAbsentError.None,
    completed: BlockAbsentAccumulation(data: BlockAbsentData(round: round,
        projection: projected.value)))

proc absentBlockRound*(outcome: BlockAbsentAccumulation): AccumulationAbsentResult[
    BlockAccumulationRound] =
  ## Retain the genuine admitted initial round behind this no-execution proof.
  let data = outcome.data
  if data == nil: return AccumulationAbsentResult[BlockAccumulationRound](
      status: AccumulationAbsentError.Uninitialized) # No fabricated block provenance.
  AccumulationAbsentResult[BlockAccumulationRound](status: AccumulationAbsentError.None,
      completed: data.round)

proc absentProjection*(outcome: BlockAbsentAccumulation): AccumulationAbsentResult[
    AbsentAccumulation] =
  ## Retain the pure zero-effect outcome while its block authority remains independently available.
  let data = outcome.data
  if data == nil: return AccumulationAbsentResult[AbsentAccumulation](
      status: AccumulationAbsentError.Uninitialized) # No default projection.
  AccumulationAbsentResult[AbsentAccumulation](status: AccumulationAbsentError.None,
      completed: data.projection)
