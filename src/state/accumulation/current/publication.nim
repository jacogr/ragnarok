# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Install a genuine current composed successor only over its exact retained original parent, without hashing or replay.
import ./[consensus as accumulation_current_consensus,
    authorization as accumulation_current_authorization,
    preimages as accumulation_current_preimages, activity as accumulation_current_activity]
import ../../[preimages, store]

type
  CurrentAccumulationPublicationError* {.pure.} = enum ## Refusals expose neither candidate state nor an earlier successful publication.
    Uninitialized, None, InvalidSource, StaleState, StateFailure
  CurrentAccumulationPublicationResult* = object ## Private alternatives guard exact adopted snapshots and actual store causes separately.
    case status: CurrentAccumulationPublicationError
    of None:
      completed: StateStoreSnapshot
    of StateFailure:
      stateReason: StateStoreError
    else:
      discard # Default, invalid and stale publication retains reasons alone.
func error*(outcome: CurrentAccumulationPublicationResult): CurrentAccumulationPublicationError =
  ## Inspect the selected immutable reason.
  outcome.status
func value*(outcome: CurrentAccumulationPublicationResult): StateStoreSnapshot {.inline,
    requires: outcome.status == CurrentAccumulationPublicationError.None.} =
  ## Extract only the exact successfully adopted snapshot.
  outcome.completed
func stateError*(outcome: CurrentAccumulationPublicationResult): StateStoreError {.inline,
    requires: outcome.status == CurrentAccumulationPublicationError.StateFailure.} =
  ## Inspect only an actual target initialization or candidate-fork refusal.
  outcome.stateReason
proc publishCurrentAccumulationState*(state: var StateStore,
    source: PreparedCurrentAccumulationConsensus): CurrentAccumulationPublicationResult =
  ## All potentially refusing checks precede the sole state-handle replacement; caller must separately coordinate any live chain view.
  let retained = source.currentConsensusSource
  if retained.error != CurrentAccumulationConsensusError.None:
    return CurrentAccumulationPublicationResult(status: CurrentAccumulationPublicationError.InvalidSource) # Defaults cannot authorize an initialized empty state.
  let current = state.snapshot
  if current.error != StateStoreError.None:
    return CurrentAccumulationPublicationResult(status: CurrentAccumulationPublicationError.StateFailure,
      stateReason: current.error) # Uninitialized targets remain untouched.
  let activity = retained.value.currentAuthorizationSource.value.currentPreimagesSource.value
  let parent = activity.currentActivityPreimages.value.preimagePrior.value
  if not sameStateSnapshot(current.value, parent):
    return CurrentAccumulationPublicationResult(status: CurrentAccumulationPublicationError.StaleState) # Cached admission binds the exact original parent; equal roots, replay and restored values grant no version identity.
  let candidate = source.currentConsensusState.value
  let adopted = forkStateStore(candidate)
  if adopted.error != StateStoreError.None:
    return CurrentAccumulationPublicationResult(status: CurrentAccumulationPublicationError.StateFailure,
      stateReason: adopted.error) # No target update before complete candidate adoption can succeed.
  state = adopted.value # Install the exact immutable map and inherited policy once, with no re-encoding, execution, copying or hashing.
  CurrentAccumulationPublicationResult(status: CurrentAccumulationPublicationError.None,
    completed: candidate)
