# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Advance a fully composed computed state and its direct-child chain view only after every private phase succeeds.

import ../chain/genesis as chain_genesis
import ../chain/provider as chain_provider
import ../chain/parameters as chain_parameters
import ../codec/header as codec_header
import ./computed_composition as state_computed_composition
import ./computed_state_publication as state_computed_state_publication
import ./computed_finalization as state_computed_finalization
import ./computed_execution as state_computed_execution
import ./computed_round as state_computed_round
import ./accumulation_finalization as state_accumulation_finalization
import ./report_admission as state_report_admission
import ./block_transition as state_block_transition
import ./block_admission as state_block_admission
import ./store as state_store

type
  ComputedChainError* {.pure.} = enum ## Refusals expose no earlier successful private map, receipt or captured child.
    Uninitialized, None, InvalidSource, StateFailure, StaleState, UninitializedView, StaleView,
      ProfileMismatch, ParametersMismatch, PublicationFailure, HeaderFailure, CaptureFailure, ViewFailure
  ComputedChainData = ref object ## Immutable acyclic ownership retains actual computation/publication and real installed child.
    publication: PublishedComputedState
    child: BlockSnapshot
  AdvancedComputedChain* = object ## A direct-child append does not claim reorg handling, finality or whole-block parity.
    data: nil ComputedChainData
  ComputedChainResult*[T] = object ## Only success carries the installed child authority; selected causes have independent guards.
    case status: ComputedChainError
    of None: completed: T
    of StateFailure: stateReason: StateStoreError
    of PublicationFailure: publicationReason: ComputedStatePublicationResult[PublishedComputedState]
    of HeaderFailure: headerReason: HeaderError
    of CaptureFailure: captureReason: GenesisError
    of ViewFailure: viewReason: ViewAdvanceError
    else: discard # Ordinary stale/profile/default alternatives retain their reason alone.

func error*[T](outcome: ComputedChainResult[T]): ComputedChainError =
  ## Inspect selected reason without writable discriminator access.
  outcome.status
func value*[T](outcome: ComputedChainResult[T]): T {.requires: outcome.status ==
    ComputedChainError.None.} =
  ## Extract only a fully installed child receipt under optimized contracts.
  outcome.completed
func stateError*[T](outcome: ComputedChainResult[T]): StateStoreError {.requires: outcome.status ==
    ComputedChainError.StateFailure.} =
  ## Inspect only a failed live-target lookup.
  outcome.stateReason
func publicationFailure*[T](outcome: ComputedChainResult[T]): ComputedStatePublicationResult[
    PublishedComputedState] {.requires: outcome.status == ComputedChainError.PublicationFailure.} =
  ## Preserve the complete failed private publication and its selected nested cause.
  outcome.publicationReason
func headerError*[T](outcome: ComputedChainResult[T]): HeaderError {.requires: outcome.status ==
    ComputedChainError.HeaderFailure.} =
  ## Inspect only failed actual-header metadata or canonical encoding.
  outcome.headerReason
func captureError*[T](outcome: ComputedChainResult[T]): GenesisError {.requires: outcome.status ==
    ComputedChainError.CaptureFailure.} =
  ## Inspect only a failed structural child capture.
  outcome.captureReason
func viewError*[T](outcome: ComputedChainResult[T]): ViewAdvanceError {.requires: outcome.status ==
    ComputedChainError.ViewFailure.} =
  ## Inspect only an actual direct-child append refusal.
  outcome.viewReason
proc computedChainPublication*(advanced: AdvancedComputedChain): ComputedChainResult[
    PublishedComputedState] =
  ## Share original computed provenance and exact privately published map after caller handles retire.
  let data = advanced.data
  if data == nil: return ComputedChainResult[PublishedComputedState](
      status: ComputedChainError.Uninitialized)
  ComputedChainResult[PublishedComputedState](status: ComputedChainError.None,
      completed: data.publication)
proc computedChainBlock*(advanced: AdvancedComputedChain): ComputedChainResult[BlockSnapshot] =
  ## Share the actual fully installed child, never a caller-supplied observation.
  let data = advanced.data
  if data == nil: return ComputedChainResult[BlockSnapshot](
      status: ComputedChainError.Uninitialized)
  ComputedChainResult[BlockSnapshot](status: ComputedChainError.None, completed: data.child)
proc advanceComputedChain*(state: var StateStore, view: var ChainView,
    source: ComposedComputedState): ComputedChainResult[AdvancedComputedChain] =
  ## Check retained parents/domains, privately publish/capture/append, then replace both single-threaded handles without callbacks.
  let retained = source.computedCompositionSource
  if retained.error != ComputedCompositionError.None:
    return ComputedChainResult[AdvancedComputedChain](status: ComputedChainError.InvalidSource)
  let finalized = retained.value.computedFinalizationPlan.value
  let parent = finalized.finalAccumulationParent.value
  let current = state.snapshot
  if current.error != StateStoreError.None:
    return ComputedChainResult[AdvancedComputedChain](status: ComputedChainError.StateFailure,
        stateReason: current.error)
  if not sameStateSnapshot(current.value, parent):
    return ComputedChainResult[AdvancedComputedChain](status: ComputedChainError.StaleState)
  let head = view.bestBlock
  if head.error != GenesisError.None:
    return ComputedChainResult[AdvancedComputedChain](status: ComputedChainError.UninitializedView)
  if not sameStateSnapshot(head.value.stateSnapshot, parent):
    return ComputedChainResult[AdvancedComputedChain](status: ComputedChainError.StaleView)
  let stage = finalized.finalAccumulationAdmission.value.reportBlockStage.value
  let profile = stage.blockTransitionProfile
  if uint64(profile.cores) != uint64(head.value.cores) or uint64(profile.epochSlots) != uint64(
      head.value.epochSlots) or uint64(profile.validators) != uint64(head.value.activeValidators):
    return ComputedChainResult[AdvancedComputedChain](status: ComputedChainError.ProfileMismatch)
  let original = retained.value.computedFinalizationSource.value.computedExecutionSource.value.computedRoundParameters.value
  let selected = head.value.chainParameters
  for field in low(Parameter)..high(Parameter):
    if original.get(field) != selected.get(field):
      return ComputedChainResult[AdvancedComputedChain](
          status: ComputedChainError.ParametersMismatch) # Matching framing alone cannot substitute a different complete original chain tuple.
  var working = state
  let published = publishComputedState(working, source)
  if published.error != ComputedStatePublicationError.None:
    return ComputedChainResult[AdvancedComputedChain](status: ComputedChainError.PublicationFailure,
        publicationReason: published)
  let header = stage.value.admitted.admittedHeader
  let info = header.headerInfo
  if info.error != HeaderError.None:
    return ComputedChainResult[AdvancedComputedChain](status: ComputedChainError.HeaderFailure,
        headerReason: info.error)
  if info.value.consumed > 256 * 1024:
    return ComputedChainResult[AdvancedComputedChain](status: ComputedChainError.CaptureFailure,
        captureReason: GenesisError.Invalid) # Bound allocation under the maintained chain capture ceiling.
  var wire = newSeq[byte](info.value.consumed)
  let encoded = encodeOwnedHeader(header, wire)
  if encoded.error != HeaderError.None:
    return ComputedChainResult[AdvancedComputedChain](status: ComputedChainError.HeaderFailure,
        headerReason: encoded.error)
  let child = captureBlockSnapshot(wire, published.value.computedPublishedSnapshot.value, original)
  if child.error != GenesisError.None:
    return ComputedChainResult[AdvancedComputedChain](status: ComputedChainError.CaptureFailure,
        captureReason: child.error)
  let advanced = view.advanceView(child)
  if advanced.error != ViewAdvanceError.None:
    return ComputedChainResult[AdvancedComputedChain](status: ComputedChainError.ViewFailure,
        viewReason: advanced.error)
  let receipt = AdvancedComputedChain(data: ComputedChainData(publication: published.value,
      child: child.value))
  state = working # Every potentially refusing operation is complete before either live handle changes.
  view = advanced.value
  ComputedChainResult[AdvancedComputedChain](status: ComputedChainError.None, completed: receipt)
