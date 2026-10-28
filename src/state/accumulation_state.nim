# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Apply one finalized execution successor through state-owned composition and exact-parent publication.
## Preflight is hash-free; only complete success replaces the caller's single-threaded full-map handle.

import ./accumulation_finalization as state_accumulation_finalization
import ./accumulation_completion as state_accumulation_completion
import ./accumulation_block_publication as state_accumulation_block_publication
import ./store as state_store

type
  AccumulationStateError* {.pure.} = enum ## Each refusal selects its own reason without an earlier candidate or snapshot.
    Uninitialized, None, InvalidSource, StaleState, StateFailure, CompositionFailure, PublicationFailure
  AccumulationStateResult* = object ## Private selected alternatives retain only a published snapshot or an actual failed child result.
    case status: AccumulationStateError
    of None:
      completed: StateStoreSnapshot                    # The exact immutable snapshot adopted by the caller handle.
    of StateFailure:
      stateReason: StateStoreError                     # Preflight target refusal retains no usable target value.
    of CompositionFailure:
      compositionReason: AccumulationCompletionResult  # Always an actual failed private composition.
    of PublicationFailure:
      publicationReason: AccumulationPublicationResult # Always an actual failed guarded publication.
    else:
      discard # Invalid/default/stale alternatives contain neither a snapshot nor a child success.

func error*(outcome: AccumulationStateResult): AccumulationStateError =
  ## Inspect the selected reason without exposing retagging or payload mutation.
  outcome.status

func value*(outcome: AccumulationStateResult): StateStoreSnapshot {.inline,
    requires: outcome.status == AccumulationStateError.None.} =
  ## Retain only the exact successfully published complete snapshot under checked optimized contracts.
  outcome.completed

func stateError*(outcome: AccumulationStateResult): StateStoreError {.inline,
    requires: outcome.status == AccumulationStateError.StateFailure.} =
  ## Inspect only a selected target preflight failure.
  outcome.stateReason

func compositionFailure*(outcome: AccumulationStateResult): AccumulationCompletionResult {.inline,
    requires: outcome.status == AccumulationStateError.CompositionFailure.} =
  ## Preserve the original failed phase and its guarded nested codec/transition/store causes.
  outcome.compositionReason

func publicationFailure*(outcome: AccumulationStateResult): AccumulationPublicationResult {.inline,
    requires: outcome.status == AccumulationStateError.PublicationFailure.} =
  ## Preserve only an actual failed publication; no composed candidate escapes that refusal.
  outcome.publicationReason

proc applyAccumulationState*(state: var StateStore, source: PreparedFinalAccumulation,
    limits: AccumulationCompositionLimits): AccumulationStateResult =
  ## Validate exact parent authority before work, privately compose once, and publish only complete success.
  let parent = source.finalAccumulationParent
  if parent.error != AccumulationFinalizationError.None:
    return AccumulationStateResult(status: AccumulationStateError.InvalidSource) # Defaults authorize no target inspection or composition.
  let current = state.snapshot
  if current.error != StateStoreError.None:
    return AccumulationStateResult(status: AccumulationStateError.StateFailure,
      stateReason: current.error) # An uninitialized handle stays uninitialized.
  if not sameStateSnapshot(current.value, parent.value):
    return AccumulationStateResult(status: AccumulationStateError.StaleState) # Root equality, prefixes and replay cannot substitute for parent identity.
  let composed = prepareAccumulationComposition(source, limits)
  if composed.error != AccumulationCompletionError.None:
    return AccumulationStateResult(status: AccumulationStateError.CompositionFailure,
      compositionReason: composed) # All successful intermediate forks remain private and are released.
  let published = publishAccumulationState(state, composed.value)
  if published.error != AccumulationPublicationError.None:
    return AccumulationStateResult(status: AccumulationStateError.PublicationFailure,
      publicationReason: published) # Existing publication owns the final parent check and sole handle replacement.
  AccumulationStateResult(status: AccumulationStateError.None, completed: published.value)
