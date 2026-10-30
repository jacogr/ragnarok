# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Atomically install actual assured successor state and its direct-child view only after every private phase succeeds.

import ../../chain/[genesis, provider, parameters]
import ../../codec/header
import ./composition as assured_composition
import "../accumulation/block/publication" as accumulation_block_publication
import ../accumulation/finalization as accumulation_finalization
import ../report/admission as report_admission
import "../block/transition" as block_transition
import "../block/admission" as block_admission
import ../store

type
  AssuredChainError* {.pure.} = enum ## Refusals expose no earlier successful private map, receipt or captured child.
    Uninitialized, None, InvalidSource, StateFailure, StaleState, UninitializedView, StaleView,
      ProfileMismatch, ParametersMismatch, PublicationFailure, HeaderFailure, CaptureFailure, ViewFailure
  AssuredChainData = ref object ## Immutable acyclic ownership retains actual assured composition/publication and real installed child.
    source: ComposedAssuredState
    snapshot: StateStoreSnapshot
    child: BlockSnapshot
  AdvancedAssuredChain* = object ## A direct-child append does not claim reorg handling, finality or whole-block parity.
    data: nil AssuredChainData
  AssuredChainResult*[T] = object ## Only success carries the installed child authority; selected causes have independent guards.
    case status: AssuredChainError
    of None: completed: T
    of StateFailure: stateReason: StateStoreError
    of PublicationFailure: publicationReason: AccumulationPublicationResult
    of HeaderFailure: headerReason: HeaderError
    of CaptureFailure: captureReason: GenesisError
    of ViewFailure: viewReason: ViewAdvanceError
    else: discard # Ordinary stale/profile/default alternatives retain their reason alone.

func error*[T](outcome: AssuredChainResult[T]): AssuredChainError =
  ## Inspect selected reason without writable discriminator access.
  outcome.status

func value*[T](outcome: AssuredChainResult[T]): T {.requires: outcome.status ==
    AssuredChainError.None.} =
  ## Extract only a fully installed child receipt under optimized contracts.
  outcome.completed

func stateError*[T](outcome: AssuredChainResult[T]): StateStoreError {.requires: outcome.status ==
    AssuredChainError.StateFailure.} =
  ## Inspect only a failed live-target lookup.
  outcome.stateReason

func publicationFailure*[T](outcome: AssuredChainResult[
    T]): AccumulationPublicationResult {.requires: outcome.status ==
    AssuredChainError.PublicationFailure.} =
  ## Preserve the complete failed private publication and its selected nested cause.
  outcome.publicationReason

func headerError*[T](outcome: AssuredChainResult[T]): HeaderError {.requires: outcome.status ==
    AssuredChainError.HeaderFailure.} =
  ## Inspect only failed actual-header metadata or canonical encoding.
  outcome.headerReason

func captureError*[T](outcome: AssuredChainResult[T]): GenesisError {.requires: outcome.status ==
    AssuredChainError.CaptureFailure.} =
  ## Inspect only a failed structural child capture.
  outcome.captureReason

func viewError*[T](outcome: AssuredChainResult[T]): ViewAdvanceError {.requires: outcome.status ==
    AssuredChainError.ViewFailure.} =
  ## Inspect only an actual direct-child append refusal.
  outcome.viewReason

proc assuredChainSource*(advanced: AdvancedAssuredChain): AssuredChainResult[ComposedAssuredState] =
  ## Retain actual authenticated assurance, execution and complete composition authority after caller handles retire.
  let data = advanced.data
  if data == nil: return AssuredChainResult[ComposedAssuredState](
      status: AssuredChainError.Uninitialized)
  AssuredChainResult[ComposedAssuredState](status: AssuredChainError.None, completed: data.source)

proc assuredChainSnapshot*(advanced: AdvancedAssuredChain): AssuredChainResult[StateStoreSnapshot] =
  ## Share the exact adopted complete map without copying payloads or substituting an equal-root owner.
  let data = advanced.data
  if data == nil: return AssuredChainResult[StateStoreSnapshot](
      status: AssuredChainError.Uninitialized)
  AssuredChainResult[StateStoreSnapshot](status: AssuredChainError.None, completed: data.snapshot)

proc assuredChainBlock*(advanced: AdvancedAssuredChain): AssuredChainResult[BlockSnapshot] =
  ## Share the actual fully installed child, never a caller-supplied observation.
  let data = advanced.data
  if data == nil: return AssuredChainResult[BlockSnapshot](
      status: AssuredChainError.Uninitialized)
  AssuredChainResult[BlockSnapshot](status: AssuredChainError.None, completed: data.child)

proc advanceAssuredChain*(state: var StateStore, view: var ChainView,
    source: ComposedAssuredState): AssuredChainResult[AdvancedAssuredChain] =
  ## Check retained parents/domains, privately publish/capture/append, then replace both single-threaded handles without callbacks.
  let retained = source.assuredCompositionFinal
  if retained.error != AssuredCompositionError.None:
    return AssuredChainResult[AdvancedAssuredChain](status: AssuredChainError.InvalidSource)
  let finalized = retained.value
  let parent = finalized.finalAccumulationParent.value
  let current = state.snapshot
  if current.error != StateStoreError.None:
    return AssuredChainResult[AdvancedAssuredChain](status: AssuredChainError.StateFailure,
        stateReason: current.error)
  if not sameStateSnapshot(current.value, parent):
    return AssuredChainResult[AdvancedAssuredChain](status: AssuredChainError.StaleState)
  let head = view.bestBlock
  if head.error != GenesisError.None:
    return AssuredChainResult[AdvancedAssuredChain](status: AssuredChainError.UninitializedView)
  if not sameStateSnapshot(head.value.stateSnapshot, parent):
    return AssuredChainResult[AdvancedAssuredChain](status: AssuredChainError.StaleView)
  let stage = finalized.finalAccumulationAdmission.value.reportBlockStage.value
  let profile = stage.blockTransitionProfile
  if uint64(profile.cores) != uint64(head.value.cores) or uint64(profile.epochSlots) != uint64(
      head.value.epochSlots) or uint64(profile.validators) != uint64(head.value.activeValidators):
    return AssuredChainResult[AdvancedAssuredChain](status: AssuredChainError.ProfileMismatch)
  let original = source.assuredCompositionParameters.value
  let selected = head.value.chainParameters
  for field in low(Parameter)..high(Parameter):
    if original.get(field) != selected.get(field):
      return AssuredChainResult[AdvancedAssuredChain](
          status: AssuredChainError.ParametersMismatch) # Matching framing alone cannot substitute a different complete original chain tuple.
  var working = state
  let published = publishAccumulationState(working, source.assuredCompositionPlan.value)
  if published.error != AccumulationPublicationError.None:
    return AssuredChainResult[AdvancedAssuredChain](status: AssuredChainError.PublicationFailure,
        publicationReason: published)
  let header = stage.value.admitted.admittedHeader
  let info = header.headerInfo
  if info.error != HeaderError.None:
    return AssuredChainResult[AdvancedAssuredChain](status: AssuredChainError.HeaderFailure,
        headerReason: info.error)
  if info.value.consumed > 256 * 1024:
    return AssuredChainResult[AdvancedAssuredChain](status: AssuredChainError.CaptureFailure,
        captureReason: GenesisError.Invalid) # Bound allocation under the maintained chain capture ceiling.
  var wire = newSeq[byte](info.value.consumed)
  let encoded = encodeOwnedHeader(header, wire)
  if encoded.error != HeaderError.None:
    return AssuredChainResult[AdvancedAssuredChain](status: AssuredChainError.HeaderFailure,
        headerReason: encoded.error)
  let child = captureBlockSnapshot(wire, published.value, original)
  if child.error != GenesisError.None:
    return AssuredChainResult[AdvancedAssuredChain](status: AssuredChainError.CaptureFailure,
        captureReason: child.error)
  let advanced = view.advanceView(child)
  if advanced.error != ViewAdvanceError.None:
    return AssuredChainResult[AdvancedAssuredChain](status: AssuredChainError.ViewFailure,
        viewReason: advanced.error)
  let receipt = AdvancedAssuredChain(data: AssuredChainData(source: source,
      snapshot: published.value, child: child.value))
  state = working # Every potentially refusing operation is complete before either live handle changes.
  view = advanced.value
  AssuredChainResult[AdvancedAssuredChain](status: AssuredChainError.None, completed: receipt)
