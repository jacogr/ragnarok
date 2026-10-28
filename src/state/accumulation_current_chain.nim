# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Adopt genuine current composed state and a direct-child chain view only after every private stage succeeds.
## Existing aliases retain their owners; publication is single-threaded and has no fallible gap or callbacks.

import ../chain/[genesis, provider, parameters]
import ../codec/[bounded, header]
import ./[store, accumulation_current_publication, accumulation_current_consensus,
  accumulation_current_authorization, accumulation_current_preimages, accumulation_current_activity,
  accumulation_current_validators, accumulation_current_recent, accumulation_current_ready,
  accumulation_current_finalization, accumulation_current_accounts, accumulation_current_statistics,
  accumulation_current_driver, accumulation_current_sequence, accumulation_current_round,
  accumulation_block_guests, accumulation_round, accumulation_queue, preimages,
  report_admission, block_transition, block_admission]

type
  CurrentAccumulationChainError* {.pure.} = enum ## Each refused stage carries only its selected reason, never a candidate state or view.
    Uninitialized, None, InvalidSource, StateFailure, StaleState, UninitializedView, StaleView,
    ProfileMismatch, LimitExceeded, PublicationFailure, HeaderFailure, CaptureFailure, ViewFailure
  CurrentAccumulationChainResult* = object ## Success owns the exact child installed in both live handles; failure retains no successful prefix.
    case status: CurrentAccumulationChainError
    of None:
      completed: BlockSnapshot
    of StateFailure:
      stateReason: StateStoreError
    of PublicationFailure:
      publicationReason: CurrentAccumulationPublicationResult
    of HeaderFailure:
      headerReason: HeaderError
    of CaptureFailure:
      captureReason: GenesisError
    of ViewFailure:
      viewReason: ViewAdvanceError
    else:
      discard # Default, invalid, stale and profile alternatives contain neither candidate nor child payload.

func error*(outcome: CurrentAccumulationChainResult): CurrentAccumulationChainError =
  ## Observe the selected phase without granting mutation of its private discriminator.
  outcome.status
func value*(outcome: CurrentAccumulationChainResult): BlockSnapshot {.inline,
    requires: outcome.status == CurrentAccumulationChainError.None.} =
  ## Retain only the fully installed child with its exact applied-state version.
  outcome.completed
func stateError*(outcome: CurrentAccumulationChainResult): StateStoreError {.inline,
    requires: outcome.status == CurrentAccumulationChainError.StateFailure.} =
  ## Inspect only a failed target snapshot lookup.
  outcome.stateReason
func publicationFailure*(outcome: CurrentAccumulationChainResult): CurrentAccumulationPublicationResult {.inline,
    requires: outcome.status == CurrentAccumulationChainError.PublicationFailure.} =
  ## Preserve the actual failed state application and its guarded nested phase reasons.
  outcome.publicationReason
func headerError*(outcome: CurrentAccumulationChainResult): HeaderError {.inline,
    requires: outcome.status == CurrentAccumulationChainError.HeaderFailure.} =
  ## Inspect only a failed admitted-header metadata or encoding operation.
  outcome.headerReason
func captureError*(outcome: CurrentAccumulationChainResult): GenesisError {.inline,
    requires: outcome.status == CurrentAccumulationChainError.CaptureFailure.} =
  ## Inspect only a failed structural child capture, with no partially retained child.
  outcome.captureReason
func viewError*(outcome: CurrentAccumulationChainResult): ViewAdvanceError {.inline,
    requires: outcome.status == CurrentAccumulationChainError.ViewFailure.} =
  ## Inspect only an actual failed direct-child append.
  outcome.viewReason

proc applyCurrentAccumulationChain*(state: var StateStore, view: var ChainView,
    source: PreparedCurrentAccumulationConsensus, headerBytes: ByteLimit): CurrentAccumulationChainResult =
  ## Privately apply, capture the source's own header and append; publish both handles only after full success.
  let retained = source.currentConsensusSource
  if retained.error != CurrentAccumulationConsensusError.None:
    return CurrentAccumulationChainResult(status: CurrentAccumulationChainError.InvalidSource) # Defaults authorize neither target inspection nor synthetic chain state.
  let activity = retained.value.currentAuthorizationSource.value.currentPreimagesSource.value
  let parent = activity.currentActivityPreimages.value.preimagePrior.value
  let current = state.snapshot
  if current.error != StateStoreError.None:
    return CurrentAccumulationChainResult(status: CurrentAccumulationChainError.StateFailure,
      stateReason: current.error) # No implicit empty target is synthesized.
  if not sameStateSnapshot(current.value, parent):
    return CurrentAccumulationChainResult(status: CurrentAccumulationChainError.StaleState) # Replay and equal-root reconstructions fail before composition.
  let head = view.bestBlock
  if head.error != GenesisError.None:
    return CurrentAccumulationChainResult(status: CurrentAccumulationChainError.UninitializedView) # An explicit selected parent is mandatory.
  if not sameStateSnapshot(head.value.stateSnapshot, parent):
    return CurrentAccumulationChainResult(status: CurrentAccumulationChainError.StaleView) # A matching root cannot replace retained parent identity.
  let finalized = activity.currentActivitySource.value.currentValidatorsSource.value.currentRecentSource.value.currentReadySource.value
  let completed = finalized.currentFinalizationAccounts.value.currentAccountsSource.value.currentStatisticsSource.value
  let sequence = completed.completedSequenceSource.value
  let reports = sequence.currentSequenceInitial.value.currentRoundGuests.value.guestRound.value.roundBlockQueue.value.accumulationAdmission.value
  if reports.requiresFuzzView and not view.fuzzOnly:
    return CurrentAccumulationChainResult(status: CurrentAccumulationChainError.ProfileMismatch) # Test-seed facts cannot authorize a production chain.
  let admission = reports.reportBlockStage.value
  let profile = admission.blockTransitionProfile
  # GP valcount permits independent roster sizes; the decoder ceiling covers the head up to three validators per core.
  if uint64(profile.cores) != uint64(head.value.cores) or
      uint64(profile.epochSlots) != uint64(head.value.epochSlots) or
      uint64(profile.validators) < uint64(head.value.activeValidators) or
      uint64(profile.validators) mod 3 != 0 or
      uint64(profile.validators) div 3 > uint64(head.value.cores):
    return CurrentAccumulationChainResult(status: CurrentAccumulationChainError.ProfileMismatch) # Preserve the authenticated header decoding domains.
  let executedParameters = sequence.currentSequenceInitial.value.currentRoundParameters.value
  let selectedParameters = head.value.chainParameters
  for field in low(Parameter)..high(Parameter):
    if executedParameters.get(field) != selectedParameters.get(field):
      return CurrentAccumulationChainResult(status: CurrentAccumulationChainError.ProfileMismatch) # Every frozen fetch/price/configuration field belongs to the selected chain, not merely core/epoch domains.
  let ownedHeader = admission.value.admitted.admittedHeader
  let info = ownedHeader.headerInfo
  if info.error != HeaderError.None:
    return CurrentAccumulationChainResult(status: CurrentAccumulationChainError.HeaderFailure,
      headerReason: info.error) # Never infer an empty sealed header from absent metadata.
  if info.value.consumed > 256 * 1024:
    return CurrentAccumulationChainResult(status: CurrentAccumulationChainError.CaptureFailure,
      captureReason: GenesisError.Invalid) # Bound serialization before allocating under chain capture's fixed ceiling.
  if uint64(info.value.consumed) > uint64(headerBytes):
    return CurrentAccumulationChainResult(status: CurrentAccumulationChainError.LimitExceeded) # Bound exact sealed-header capture before allocation, adoption or hashing.
  var working = state
  let applied = publishCurrentAccumulationState(working, source)
  if applied.error != CurrentAccumulationPublicationError.None:
    return CurrentAccumulationChainResult(status: CurrentAccumulationChainError.PublicationFailure,
      publicationReason: applied) # Private handle adoption never re-executes guests or reruns composition.
  var wire = newSeq[byte](info.value.consumed)
  let encoded = encodeOwnedHeader(ownedHeader, wire)
  if encoded.error != HeaderError.None:
    return CurrentAccumulationChainResult(status: CurrentAccumulationChainError.HeaderFailure,
      headerReason: encoded.error) # No encoded prefix or partly applied state escapes.
  let captured = captureBlockSnapshot(wire, applied.value, head.value.chainParameters)
  let child = if captured.error == GenesisError.None:
    withBlockBody(captured.value, admission.value.admitted.admittedBlock)
    else: captured # Body retention failure stays private alongside the already prepared state.
  if child.error != GenesisError.None:
    return CurrentAccumulationChainResult(status: CurrentAccumulationChainError.CaptureFailure,
      captureReason: child.error) # Late native hash or structural refusal leaves both live handles intact.
  let advanced = view.advanceView(child)
  if advanced.error != ViewAdvanceError.None:
    return CurrentAccumulationChainResult(status: CurrentAccumulationChainError.ViewFailure,
      viewReason: advanced.error) # Even fully composed/captured state stays private on a failed append.
  state = working # No fallible work or user callbacks occurs between these single-threaded replacements.
  view = advanced.value
  CurrentAccumulationChainResult(status: CurrentAccumulationChainError.None, completed: child.value)
