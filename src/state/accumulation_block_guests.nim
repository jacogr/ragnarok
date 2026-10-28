# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind current guest execution to genuine initial-round admission, posterior entropy and chain shape.
## Coverage remains private preparation; complete selected publication owns the subsequent state transition.
import ../chain/parameters as chain_parameters
import ../codec/header as codec_header
import ../codec/state_layout as codec_state_layout
import ../codec/state_safrole as codec_state_safrole
import ./accumulation_guest_runner as state_accumulation_guest_runner
import ./accumulation_coverage as state_accumulation_coverage
import ./accumulation_round as state_accumulation_round
import ./accumulation_queue as state_accumulation_queue
import ./report_admission as state_report_admission
import ./block_transition as state_block_transition
import ./block_admission as state_block_admission
import ./store as state_store

type
  BlockGuestError* {.pure.} = enum ## Refusals expose neither partial coverage nor an earlier guest result.
    Uninitialized, None, InvalidRound, InvalidParameters, InvalidEntropy, GuestFailure
  BlockGuestData = ref object # Immutable acyclic owners retain genuine round authority and its complete providers.
    round: BlockAccumulationRound
    coverage: PreparedAccumulationCoverage
  BlockAccumulationGuests* = object ## Only authenticated execution constructs this source-bound owner.
    data: nil BlockGuestData
  BlockGuestResult*[T] = object ## Default/refused alternatives contain no successful owner.
    case status: BlockGuestError
    of None:
      completed: T              # Extraction requires selected success even in optimized builds.
    of GuestFailure:
      failed: AccumulationGuestResult # Invariant: genuinely refused core result with its exact nested reason.
    else:
      discard                   # No fabricated zero-guest result on preflight failure.

func error*[T](outcome: BlockGuestResult[T]): BlockGuestError =
  ## Inspect only the selected reason without allowing retagging.
  outcome.status
func value*[T](outcome: BlockGuestResult[T]): T {.inline,
    requires: outcome.status == BlockGuestError.None.} =
  ## Extract the complete owner or projection only after success.
  outcome.completed
func guestFailure*[T](outcome: BlockGuestResult[T]): AccumulationGuestResult {.inline,
    requires: outcome.status == BlockGuestError.GuestFailure.} =
  ## Retain the actual failed core result, never an earlier successful provider.
  outcome.failed
proc guestRound*(guests: BlockAccumulationGuests): BlockGuestResult[BlockAccumulationRound] =
  ## Retain the exact admitted round; default handles cannot fabricate block authority.
  let data = guests.data
  if data == nil:
    return BlockGuestResult[BlockAccumulationRound](status: BlockGuestError.Uninitialized)
  BlockGuestResult[BlockAccumulationRound](status: BlockGuestError.None, completed: data.round)
proc guestCoverage*(guests: BlockAccumulationGuests): BlockGuestResult[
    PreparedAccumulationCoverage] =
  ## Retain complete current providers without claiming atomic publication or history completion.
  let data = guests.data
  if data == nil:
    return BlockGuestResult[PreparedAccumulationCoverage](status: BlockGuestError.Uninitialized)
  BlockGuestResult[PreparedAccumulationCoverage](status: BlockGuestError.None,
      completed: data.coverage)
proc runBlockAccumulationGuests*(round: BlockAccumulationRound, parameters: Parameters,
    limits: AccumulationGuestLimits): BlockGuestResult[BlockAccumulationGuests] =
  ## Derive state, slot and entropy from the genuine round; bind caller Parameters to the admitted profile before any guest work.
  template fail(reason: BlockGuestError) =
    return BlockGuestResult[BlockAccumulationGuests](status: reason)
  let queue = round.roundBlockQueue
  if queue.error != AccumulationRoundError.None:
    fail(BlockGuestError.InvalidRound) # No default or detached pure round can grant admission authority.
  let boundStage = queue.value.accumulationAdmission.value.reportBlockStage.value
  let profile = boundStage.blockTransitionProfile
  let contexts = limits.contexts
  if not parameters.valid:
    fail(BlockGuestError.InvalidParameters) # Never read invalid parameter ownership, including empty rounds.
  if parameters.get(coreCount) != uint64(profile.cores) or
      parameters.get(epochPeriod) != uint64(profile.epochSlots) or
      parameters.get(authQueueLen) != 80 or
      uint64(contexts.validators) != uint64(profile.validators) or
      uint64(contexts.queues.cores) != uint64(profile.cores) or
      uint64(contexts.staging.cores) != uint64(profile.cores) or
      uint64(contexts.privileges.cores) != uint64(profile.cores):
    fail(BlockGuestError.InvalidParameters) # Caller-local ceilings never replace the authenticated population/core shape.
  let stage = boundStage.value
  let entropyEntry = stage.snapshot.lookup(chapterKey(StateChapter(6)))
  if entropyEntry.error != StateStoreError.None:
    fail(BlockGuestError.InvalidEntropy) # Posterior C6 is mandatory; admitted-parent entropy is not a fallback.
  if entropyEntry.value.byteLength != 128:
    fail(BlockGuestError.InvalidEntropy) # Prove the exact fixed chapter before decoding or guest setup.
  let entropy = decodeStateEntropy(entropyEntry.value.bytes)
  if entropy.error != StateComponentError.None:
    fail(BlockGuestError.InvalidEntropy) # Do not construct an explicit-input bootstrap from malformed authority.
  let projection = round.roundProjection.value
  let slot = headerInfo(stage.admitted.admittedHeader).value.unsigned.slot
  var bounded = limits
  let budget = projection.roundInfo.value.budget
  if uint64(bounded.coverage.gas) > uint64(budget):
    bounded.coverage.gas = budget # Preserve a stricter local cap; a generous caller cap cannot relax protocol gas.
  let completed = runAccumulationGuests(projection.roundInputs.value, stage.admitted.admittedState,
    slot, entropy.value.value[0], parameters, bounded)
  if completed.error != AccumulationGuestError.None:
    return BlockGuestResult[BlockAccumulationGuests](status: BlockGuestError.GuestFailure,
      failed: completed) # Earlier successes remain local and source state remains unchanged.
  BlockGuestResult[BlockAccumulationGuests](status: BlockGuestError.None,
    completed: BlockAccumulationGuests(data: BlockGuestData(round: round,
        coverage: completed.value)))
