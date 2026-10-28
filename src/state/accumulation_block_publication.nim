# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Adopt one genuinely composed accumulation successor only while the target retains its exact admitted parent.
## A single final handle replacement preserves historical aliases and inherited policies without payload copies or hashing.

import ./accumulation_consensus as state_accumulation_consensus
import ./accumulation_authorization as state_accumulation_authorization
import ./accumulation_preimages as state_accumulation_preimages
import ./accumulation_activity as state_accumulation_activity
import ./accumulation_validators as state_accumulation_validators
import ./accumulation_times as state_accumulation_times
import ./accumulation_statistics as state_accumulation_statistics
import ./accumulation_finalization as state_accumulation_finalization
import ./accumulation_outputs as state_accumulation_outputs
import ./accumulation_execution as state_accumulation_execution
import ./accumulation_round as state_accumulation_round
import ./accumulation_queue as state_accumulation_queue
import ./report_admission as state_report_admission
import ./block_transition as state_block_transition
import ./block_admission as state_block_admission
import ./store as state_store

type
  AccumulationPublicationError* {.pure.} = enum ## Refused/default alternatives retain neither a usable candidate nor earlier successful publication.
    Uninitialized, None, InvalidSource, StaleState, StateFailure
  AccumulationPublicationResult* = object ## Only success carries the exact adopted immutable snapshot; store causes are separately guarded.
    case status: AccumulationPublicationError
    of None:
      completed: StateStoreSnapshot
    of StateFailure:
      stateReason: StateStoreError
    else:
      discard # Defaults, invalid sources and stale targets contain reasons alone.

func error*(outcome: AccumulationPublicationResult): AccumulationPublicationError =
  ## Inspect the selected reason without exposing mutable tags.
  outcome.status
func value*(outcome: AccumulationPublicationResult): StateStoreSnapshot {.inline,
    requires: outcome.status == AccumulationPublicationError.None.} =
  ## Extract only the exact successfully adopted snapshot under checked optimized contracts.
  outcome.completed
func stateError*(outcome: AccumulationPublicationResult): StateStoreError {.inline,
    requires: outcome.status == AccumulationPublicationError.StateFailure.} =
  ## Inspect only a selected target initialization or private fork refusal.
  outcome.stateReason

proc publishAccumulationState*(state: var StateStore, source: PreparedAccumulationConsensus):
    AccumulationPublicationResult =
  ## Check exact source/parent ownership before adopting the prepared successor once on this single-threaded handle.
  let retained = source.accumulationConsensusSource
  if retained.error != AccumulationConsensusError.None:
    return AccumulationPublicationResult(status: AccumulationPublicationError.InvalidSource) # Defaults cannot authorize publication of an empty state.
  let current = state.snapshot
  if current.error != StateStoreError.None:
    return AccumulationPublicationResult(status: AccumulationPublicationError.StateFailure,
      stateReason: current.error) # Uninitialized targets remain untouched.
  let finalized = retained.value.accumulationAuthorizationSource.value.accumulationPreimagesSource.value.accumulationActivitySource.value.accumulationValidatorsSource.value.accumulationTimesStatistics.value.statisticsSource.value
  let parent = finalized.finalAccumulationParent.value
  if not sameStateSnapshot(current.value, parent):
    return AccumulationPublicationResult(status: AccumulationPublicationError.StaleState) # Equal roots, restored versions and replay do not replace exact owner identity.
  let candidate = source.accumulationConsensusState.value
  let adopted = forkStateStore(candidate)
  if adopted.error != StateStoreError.None:
    return AccumulationPublicationResult(status: AccumulationPublicationError.StateFailure,
      stateReason: adopted.error) # Every potentially refusing step precedes the sole target replacement.
  state = adopted.value # Adopt the exact prepared complete map and its inherited resource policies without replay or hashing.
  AccumulationPublicationResult(status: AccumulationPublicationError.None, completed: candidate)
