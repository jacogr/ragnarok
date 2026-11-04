# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## JAMNP-S CE134 shard populations derive from the H slots after the authenticated anchor, not only the present roster.
## Fixed copied facts retain no map/roster aliases and grant no report-signing authority.
import ./[work_submission, work_anchors]
import ../chain/[provider, genesis, parameters]
import ../codec/bounded
import ../codec/work/report
import ../codec/state/[safrole, consensus, layout]
import ../state/store

type
  WorkPopulationError* {.pure.} = enum ## Failure exposes no accepted population prefix or source capability.
    Uninitialized, None, InvalidSource, InvalidPolicy, InvalidSlot, UncertainWindow,
    LimitExceeded, StateFailure, ComponentFailure, InvalidState
  WorkShardWindow* = object ## Only populations with at least one actual candidate slot are retained in successful fixed facts.
    ready, current, next: bool
    active, pending: ErasureShards
    first, last: StateTime
  WorkPopulationResult*[T] = object ## Success alone carries facts; selected child failures preserve actual causes and chapters.
    case status: WorkPopulationError
    of None: completed: T
    of StateFailure:
      storeReason: StateStoreError
      storeChapter: StateChapter
    of ComponentFailure:
      codecReason: StateComponentError
      codecChapter: StateChapter
    of InvalidState: invalidChapter: StateChapter
    else: discard # Local/source refusals never expose guessed counts.
func error*[T](outcome: WorkPopulationResult[T]): WorkPopulationError =
  ## Inspect the refusal without writable discriminators.
  outcome.status
func value*[T](outcome: WorkPopulationResult[T]): T {.requires: outcome.status ==
    WorkPopulationError.None.} =
  ## Only a fully bounded established window has extractable facts.
  outcome.completed
func stateError*[T](outcome: WorkPopulationResult[T]): StateStoreError {.requires: outcome.status ==
    WorkPopulationError.StateFailure.} =
  ## Missing chapters remain genuine source lookup failures.
  outcome.storeReason
func componentError*[T](outcome: WorkPopulationResult[
    T]): StateComponentError {.requires: outcome.status == WorkPopulationError.ComponentFailure.} =
  ## Retain exact decoder resource/framing causes.
  outcome.codecReason
func chapter*[T](outcome: WorkPopulationResult[T]): StateChapter {.requires: outcome.status in {
    WorkPopulationError.StateFailure, WorkPopulationError.ComponentFailure,
    WorkPopulationError.InvalidState}.} =
  ## Return only the chapter selected by a real source failure.
  case outcome.status
  of WorkPopulationError.StateFailure: outcome.storeChapter
  of WorkPopulationError.ComponentFailure: outcome.codecChapter
  else: outcome.invalidChapter
func accepts*(window: WorkShardWindow, shards: ErasureShards): bool =
  ## A default or a roster absent from every candidate slot cannot authorize this erasure population.
  window.ready and ((window.current and uint16(shards) == uint16(window.active)) or
    (window.next and uint16(shards) == uint16(window.pending)))
func firstSlot*(window: WorkShardWindow): StateTime {.requires: window.ready.} =
  ## The anchor slot itself is excluded by the protocol's following-slot window.
  window.first
func lastSlot*(window: WorkShardWindow): StateTime {.requires: window.ready.} =
  ## The Hth following slot is included, with overflow proved before construction.
  window.last
proc captureWorkPopulation*(context: AnchoredWorkContext, original: WorkSubmissionHeader,
    view: ChainView, config: SafroleStateConfig): WorkPopulationResult[WorkShardWindow] =
  ## Use exact qualified head/package identity and the trusted retained anchor's complete C8/C4 state.
  ## GP Safrole pins the next active roster in C4; a farther epoch cannot be inferred from this snapshot.
  template fail(reason: WorkPopulationError) =
    return WorkPopulationResult[WorkShardWindow](status: reason)
  let head = view.bestBlock
  if head.error != GenesisError.None: fail(WorkPopulationError.InvalidSource)
  if not context.anchoredWorkMatches(original, head.value.stateSnapshot):
    fail(WorkPopulationError.InvalidSource)
  let info = context.anchorInfo
  if info.error != WorkAnchorError.None: fail(WorkPopulationError.InvalidSource)
  if array[32, byte](info.value.head) != array[32, byte](head.value.blockHash):
    fail(WorkPopulationError.InvalidSource)
  let parameters = head.value.chainParameters
  let epoch = parameters.get(epochPeriod)
  let history = parameters.get(recentBlockCount)
  if epoch == 0 or history == 0 or uint64(config.epochSlots) != epoch:
    fail(WorkPopulationError.InvalidPolicy)
  if uint64(config.validators.cores) != parameters.get(coreCount):
    fail(WorkPopulationError.InvalidPolicy)
  let declared = original.submissionContext.value
  let anchor = view.blockAt(genesis.BlockHash(declared.anchor.bytes))
  if anchor.error != GenesisError.None: fail(WorkPopulationError.InvalidSource)
  if anchor.value.slot != uint32(declared.anchorSlot): fail(WorkPopulationError.InvalidSource)
  if array[32, byte](anchor.value.stateRoot) != declared.stateRoot.bytes:
    fail(WorkPopulationError.InvalidSource)
  if not anchor.value.chainParameters.sameParameterProfile(parameters):
    fail(WorkPopulationError.InvalidPolicy)
  let slot = uint64(anchor.value.slot)
  if history > uint64(high(uint32))-slot: fail(WorkPopulationError.InvalidSlot)
  let first = slot+1 # Positive history and the checked final slot prove this sum.
  let last = slot+history
  let currentEpoch = slot div epoch
  if last div epoch-currentEpoch > 1: fail(WorkPopulationError.UncertainWindow)
  let current = first div epoch == currentEpoch
  let next = last div epoch != currentEpoch
  let source = anchor.value.stateSnapshot
  let active = source.lookup(chapterKey(StateChapter(8)))
  if active.error != StateStoreError.None:
    return WorkPopulationResult[WorkShardWindow](status: WorkPopulationError.StateFailure,
      storeReason: active.error, storeChapter: StateChapter(8))
  if uint64(active.value.byteLength) > uint64(config.validators.maxBytes):
    fail(WorkPopulationError.LimitExceeded)
  let decoded = decodeStateValidators(active.value.bytes, config.validators)
  if decoded.error != StateComponentError.None:
    return WorkPopulationResult[WorkShardWindow](status: WorkPopulationError.ComponentFailure,
      codecReason: decoded.error, codecChapter: StateChapter(8))
  if decoded.value.consumed != active.value.byteLength:
    return WorkPopulationResult[WorkShardWindow](status: WorkPopulationError.InvalidState,
      invalidChapter: StateChapter(8))
  let count = decoded.value.value.validatorCount.value
  if count < 6 or count > 1023:
    return WorkPopulationResult[WorkShardWindow](status: WorkPopulationError.InvalidState,
      invalidChapter: StateChapter(8))
  var pendingCount = 0
  if next:
    # C4 is needed only when the possible inclusion interval reaches the next epoch.
    let pending = source.lookup(chapterKey(StateChapter(4)))
    if pending.error != StateStoreError.None:
      return WorkPopulationResult[WorkShardWindow](status: WorkPopulationError.StateFailure,
        storeReason: pending.error, storeChapter: StateChapter(4))
    if uint64(pending.value.byteLength) > uint64(config.maxBytes):
      fail(WorkPopulationError.LimitExceeded)
    let decodedPending = decodeSafroleState(pending.value.bytes, config)
    if decodedPending.error != StateComponentError.None:
      return WorkPopulationResult[WorkShardWindow](status: WorkPopulationError.ComponentFailure,
        codecReason: decodedPending.error, codecChapter: StateChapter(4))
    if decodedPending.value.consumed != pending.value.byteLength:
      return WorkPopulationResult[WorkShardWindow](status: WorkPopulationError.InvalidState,
        invalidChapter: StateChapter(4))
    pendingCount = decodedPending.value.snapshot.safroleInfo.value.validators
    if pendingCount < 6 or pendingCount > 1023:
      return WorkPopulationResult[WorkShardWindow](status: WorkPopulationError.InvalidState,
        invalidChapter: StateChapter(4))
  WorkPopulationResult[WorkShardWindow](status: WorkPopulationError.None,
    completed: WorkShardWindow(ready: true, current: current, next: next,
      active: ErasureShards(uint16(count)), pending: ErasureShards(uint16(pendingCount)),
      first: StateTime(uint32(first)), last: StateTime(uint32(last))))
