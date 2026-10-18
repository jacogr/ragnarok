# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 accseq/finalstateaccumulation: initial gas-bounded prefix and invocation preparation.
## Exposes pure and admitted-parent-bound immutable plans; never executes or publishes state.

import ../codec/[bounded, work_digest, report_owned, state_privileges, state_layout]
import ./[accumulation_queue, accumulation_operands, accumulation_inputs, report_admission,
  block_transition, block_admission, store]

type
  ## Explicit chain gas parameters and independent ceilings for parent decoding and projections.
  ## Gas parameters are configuration, not values authenticated by a block's state root.
  AccumulationRoundConfig* = object
    reportGas*, blockGas*: Gas
    privileges*: PrivilegeConfig
    operands*: AccumulationOperandConfig
    inputs*: AccumulationInputConfig
  ## Refusals contain neither a selected prefix nor partially prepared service inputs.
  AccumulationRoundError* {.pure.} = enum
    Uninitialized, None, InvalidConfig, InvalidQueue, InvalidPrivileges, MissingState,
    LimitExceeded, GasOverflow, InvalidOperands, InvalidInputs
  ## Declared reservation is distinct from actual execution usage; dispatch follows accseq's n > 0.
  AccumulationRoundInfo* = object
    budget*, allowanceGas*, reportGas*: Gas
    prefix*: AccumulationReportPrefix
    dispatch*: bool
  ## Private immutable acyclic storage retains exact queue provenance through the prepared inputs.
  RoundData = ref object
    info: AccumulationRoundInfo
    privileges: PrivilegeSnapshot
    inputs: PreparedAccumulationInputs
  ## Pure planning does not certify that the supplied privileges belong to any admitted parent.
  InitialAccumulationRound* = object
    data: nil RoundData
  ## Bound storage retains the genuine admitted queue and its exact parent-derived round together.
  BlockRoundData = ref object
    queue: BlockAccumulationQueue
    projection: InitialAccumulationRound
  ## Only the block adapter constructs this parent-state-bound plan.
  BlockAccumulationRound* = object
    data: nil BlockRoundData
  ## Private tagged results require selected success before extracting a complete payload.
  AccumulationRoundResult*[T] = object
    case status: AccumulationRoundError
    of None:
      completed: T # Only success carries a usable immutable owner or copied metadata.
    else:
      discard      # Default and failure carry only their reason.

## Read a reason without exposing writable discriminators.
func error*[T](outcome: AccumulationRoundResult[T]): AccumulationRoundError = outcome.status
## Extract selected success under compiler and runtime contracts.
func value*[T](outcome: AccumulationRoundResult[T]): T {.inline,
    requires: outcome.status == AccumulationRoundError.None.} = outcome.completed

## Read copied budget/prefix information without claiming execution or actual gas consumption.
proc roundInfo*(plan: InitialAccumulationRound): AccumulationRoundResult[AccumulationRoundInfo] =
  let data = plan.data
  if data == nil: return AccumulationRoundResult[AccumulationRoundInfo](
      status: AccumulationRoundError.Uninitialized) # No fabricated empty round.
  AccumulationRoundResult[AccumulationRoundInfo](status: AccumulationRoundError.None,
    completed: data.info)

## Retain independent immutable inputs after the plan or caller's source handles leave scope.
proc roundInputs*(plan: InitialAccumulationRound): AccumulationRoundResult[
    PreparedAccumulationInputs] =
  let data = plan.data
  if data == nil: return AccumulationRoundResult[PreparedAccumulationInputs](
      status: AccumulationRoundError.Uninitialized) # No fabricated input projection.
  AccumulationRoundResult[PreparedAccumulationInputs](status: AccumulationRoundError.None,
    completed: data.inputs)

## Retain the exact privilege snapshot, including roles and assigners needed by later execution.
proc roundPrivileges*(plan: InitialAccumulationRound): AccumulationRoundResult[PrivilegeSnapshot] =
  let data = plan.data
  if data == nil: return AccumulationRoundResult[PrivilegeSnapshot](
      status: AccumulationRoundError.Uninitialized) # No default privilege source.
  AccumulationRoundResult[PrivilegeSnapshot](status: AccumulationRoundError.None,
    completed: data.privileges)

## Select the largest whole-report prefix after reserving all free allowances; initial transfers are empty.
## Scan digest gas with subtraction so an unaffordable mathematical sum stops selection without wrapping.
## Local report/digest ceilings include inspected rejected work; no partial report is ever prepared.
proc planInitialAccumulation*(queue: AccumulationQueuePlan, privileges: PrivilegeSnapshot,
    config: AccumulationRoundConfig): AccumulationRoundResult[InitialAccumulationRound] =
  ## Refuse atomically without leaking a partially selected prefix or allowance sum.
  template fail(reason: AccumulationRoundError) =
    return AccumulationRoundResult[InitialAccumulationRound](status: reason)
  let cores = uint64(config.privileges.cores)
  if cores < 2 or cores > 341:
    fail(AccumulationRoundError.InvalidConfig) # Match supported chain profiles before multiplication.
  let count = queue.accumulationCount
  if count.error != AccumulationQueueError.None:
    fail(AccumulationRoundError.InvalidQueue) # Default handles are not empty validated queues.
  let info = privilegeInfo(privileges)
  if info.error != PrivilegeError.None or info.value.cores != int(cores):
    fail(AccumulationRoundError.InvalidPrivileges) # Bind pure snapshot to the configured core domain.
  if uint64(count.value) > uint64(config.operands.reports) or
      uint64(info.value.always) > uint64(config.privileges.maxAlways) or
      uint64(info.value.always) > uint64(config.inputs.allowances):
    fail(AccumulationRoundError.LimitExceeded) # Bound traversals before collecting allowances.
  if uint64(info.value.always) > uint64(high(int) div sizeof(AlwaysAccumulate)):
    fail(AccumulationRoundError.LimitExceeded) # Prove native array extent before allocation.
  var allowances: seq[AlwaysAccumulate] = @[]
  var free = 0'u64
  # Canonical snapshot order and uniqueness were already established by the C(12) decoder.
  for i in 0..<info.value.always:
    let item = alwaysAccumulateAt(privileges, PrivilegeEntryIndex(i)).value
    if uint64(item.gas) > high(uint64)-free:
      fail(AccumulationRoundError.GasOverflow) # Mathematical allowance sum must fit GP gas=N_64.
    free += uint64(item.gas)
    allowances.add(item)
  if uint64(config.reportGas) > (high(uint64)-free) div cores:
    fail(AccumulationRoundError.GasOverflow) # Prove multiply-and-add before Nimony's wrapping arithmetic.
  let floor = uint64(config.reportGas)*cores+free
  let budget = max(uint64(config.blockGas), floor)
  var remaining = budget-free
  var prefix = 0'u64
  var inspected = 0'u64
  # Nonnegative digest gas makes feasible report prefixes monotone, including zero-cost reports.
  for i in 0..<count.value:
    let report = queue.accumulationAt(AccumulationIndex(i)).value
    let digests = ownedReportInfo(report).value.digestCount
    var candidate = remaining
    var fits = true
    # Stop at the first over-budget digest; no later report may bypass this whole-report boundary.
    for j in 0..<digests:
      if inspected >= uint64(config.operands.operands):
        fail(AccumulationRoundError.LimitExceeded) # Bound even work inspected in a rejected report.
      inc inspected
      let amount = uint64(ownedReportDigest(report, j).value.accumulateGas)
      if amount > candidate:
        fits = false # Reject the entire report without charging any of its earlier digests.
        break
      candidate -= amount
    if not fits: break # Preserve strict prefix priority instead of searching for cheaper later work.
    remaining = candidate
    inc prefix
  let operands = prepareAccumulationOperands(queue, AccumulationReportPrefix(prefix),
      config.operands)
  if operands.error != AccumulationOperandError.None:
    if operands.error == AccumulationOperandError.LimitExceeded:
      fail(AccumulationRoundError.LimitExceeded) # Preserve local resource refusals.
    fail(AccumulationRoundError.InvalidOperands) # No incomplete C.2 preparation is published.
  let inputs = prepareAccumulationInputs(operands.value, [], allowances, config.inputs)
  if inputs.error != AccumulationInputError.None:
    if inputs.error == AccumulationInputError.LimitExceeded:
      fail(AccumulationRoundError.LimitExceeded) # Union/input ceilings remain independent.
    fail(AccumulationRoundError.InvalidInputs) # No partial service set is usable.
  AccumulationRoundResult[InitialAccumulationRound](status: AccumulationRoundError.None,
    completed: InitialAccumulationRound(data: RoundData(privileges: privileges,
      inputs: inputs.value,
      info: AccumulationRoundInfo(budget: Gas(budget), allowanceGas: Gas(free),
        reportGas: Gas(budget-free-remaining), prefix: AccumulationReportPrefix(prefix),
        dispatch: prefix != 0 or allowances.len != 0))))

## Retain the original admitted queue independently of the round projection's lifetime.
proc roundBlockQueue*(plan: BlockAccumulationRound): AccumulationRoundResult[
    BlockAccumulationQueue] =
  let data = plan.data
  if data == nil: return AccumulationRoundResult[BlockAccumulationQueue](
      status: AccumulationRoundError.Uninitialized) # No synthetic admission certificate.
  AccumulationRoundResult[BlockAccumulationQueue](status: AccumulationRoundError.None,
      completed: data.queue)

## Extract a pure immutable view without discarding the separately retained admission source.
proc roundProjection*(plan: BlockAccumulationRound): AccumulationRoundResult[
    InitialAccumulationRound] =
  let data = plan.data
  if data == nil: return AccumulationRoundResult[InitialAccumulationRound](
      status: AccumulationRoundError.Uninitialized) # No synthetic successful round.
  AccumulationRoundResult[InitialAccumulationRound](status: AccumulationRoundError.None,
    completed: data.projection)

## Decode exact admitted-parent C(12), never the stage's posterior map or an unrelated caller buffer.
## Check complete chapter extent before copying, reject suffixes, and retain the genuine block queue.
proc planBlockInitialAccumulation*(queue: BlockAccumulationQueue,
    config: AccumulationRoundConfig): AccumulationRoundResult[BlockAccumulationRound] =
  ## Preserve typed refusal without exposing an earlier decoded chapter or pure projection.
  template fail(reason: AccumulationRoundError) =
    return AccumulationRoundResult[BlockAccumulationRound](status: reason)
  let admission = queue.accumulationAdmission
  if admission.error != AccumulationQueueError.None:
    fail(AccumulationRoundError.InvalidQueue) # Only a genuine completed queue binds parent state.
  let stage = admission.value.reportBlockStage.value
  let profile = stage.blockTransitionProfile
  if uint64(config.privileges.cores) != uint64(profile.cores):
    fail(AccumulationRoundError.InvalidConfig) # Refuse cross-profile parent decoding.
  let parent = stage.value.admitted.admittedState
  let chapter = parent.lookup(chapterKey(StateChapter(12)))
  if chapter.error == StateStoreError.MissingKey:
    fail(AccumulationRoundError.MissingState) # Missing privileges cannot become an empty dictionary.
  if chapter.error != StateStoreError.None:
    fail(AccumulationRoundError.InvalidPrivileges) # Invalid parent lookup carries no value.
  if uint64(chapter.value.byteLength) > uint64(config.privileges.maxBytes):
    fail(AccumulationRoundError.LimitExceeded) # Bound the complete retained chapter before copying.
  let raw = chapter.value.bytes
  let decoded = decodePrivilegeState(raw, config.privileges)
  if decoded.error != PrivilegeError.None:
    if decoded.error == PrivilegeError.LimitExceeded:
      fail(AccumulationRoundError.LimitExceeded) # Preserve bounded parsing refusal.
    fail(AccumulationRoundError.InvalidPrivileges) # Malformed/noncanonical state is never normalized.
  if decoded.value.consumed != raw.len:
    fail(AccumulationRoundError.InvalidPrivileges) # State components must consume the complete value.
  let projection = planInitialAccumulation(queue.accumulationProjection.value,
    decoded.value.snapshot, config)
  if projection.error != AccumulationRoundError.None:
    fail(projection.error) # No bound owner is published until all input preparation succeeds.
  AccumulationRoundResult[BlockAccumulationRound](status: AccumulationRoundError.None,
    completed: BlockAccumulationRound(data: BlockRoundData(queue: queue,
        projection: projection.value)))
