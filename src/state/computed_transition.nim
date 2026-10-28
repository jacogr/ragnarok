# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind configured original computation to its exact authenticated pre-report block prefix.

import ../chain/parameters as chain_parameters
import ../codec/bounded as codec_bounded
import ../codec/header as codec_header
import ./computed_profile as state_computed_profile
import ./computed_lookup as state_computed_lookup
import ./computed_recent as state_computed_recent
import ./computed_state as state_computed_state
import ./block_admission as state_block_admission
import ./block_transition as state_block_transition
import ./store as state_store

type
  ComputedTransitionError* {.pure.} = enum ## Refusals retain no detached or partially authenticated posterior state.
    Uninitialized, None, InvalidSource, InvalidTransition, StateMismatch, ProfileMismatch,
    LimitExceeded, HeaderMismatch
  ComputedTransitionData = ref object ## Acyclic immutable provenance retains private successful transition selection, never caller-edited payloads.
    source: ConfiguredComputedReport
    transition: BlockTransitionResult
  TransitionBoundComputedReport* = object ## Authenticated prefix binding precedes posterior roster eligibility and report signing.
    data: nil ComputedTransitionData
  ComputedTransitionResult*[T] = object ## Only private complete success carries application data.
    case status: ComputedTransitionError
    of None:
      completed: T
    else:
      discard                           # Defaults and refusals carry reasons alone.

func error*[T](outcome: ComputedTransitionResult[T]): ComputedTransitionError =
  ## Inspect the reason without writable selection access.
  outcome.status
func value*[T](outcome: ComputedTransitionResult[T]): T
    {.requires: outcome.status == ComputedTransitionError.None.} =
  ## Preserve successful extraction contracts in optimized builds.
  outcome.completed
proc computedTransitionSource*(bound: TransitionBoundComputedReport): ComputedTransitionResult[
    ConfiguredComputedReport] =
  ## Retain exact original computation, anchors and configured parent provenance.
  let data = bound.data
  if data == nil: return ComputedTransitionResult[ConfiguredComputedReport](
      status: ComputedTransitionError.Uninitialized)
  ComputedTransitionResult[ConfiguredComputedReport](status: ComputedTransitionError.None,
      completed: data.source)
proc computedTransitionStage*(bound: TransitionBoundComputedReport): ComputedTransitionResult[
    BlockTransitionResult] =
  ## Share the genuine immutable successful result; its extracted public payload remains a separate copy.
  let data = bound.data
  if data == nil: return ComputedTransitionResult[BlockTransitionResult](
      status: ComputedTransitionError.Uninitialized)
  ComputedTransitionResult[BlockTransitionResult](status: ComputedTransitionError.None,
      completed: data.transition)
proc bindComputedTransition*(source: ConfiguredComputedReport, staged: BlockTransitionResult,
    headerBytes: ByteLimit): ComputedTransitionResult[TransitionBoundComputedReport] =
  ## Check original map/profile and all sealed candidate bytes before retaining any authenticated posterior owner.
  template fail(reason: ComputedTransitionError) =
    return ComputedTransitionResult[TransitionBoundComputedReport](status: reason)
  if source.computedProfileSource.error != ComputedProfileError.None:
    fail(ComputedTransitionError.InvalidSource) # No detached report or configuration enters authentication binding.
  if staged.error != BlockTransitionError.None:
    fail(ComputedTransitionError.InvalidTransition) # Failed/default coordinators have no usable posterior payload.
  let original = source.computedProfileContext.value
  let step = staged.value
  if not sameStateSnapshot(original.state, step.admitted.admittedState):
    fail(ComputedTransitionError.StateMismatch) # Equal roots do not replace the actual original execution map.
  let profile = staged.blockTransitionProfile
  let cores = original.parameters.get(coreCount)
  let sameDomain = uint64(profile.cores) == cores and
    uint64(profile.epochSlots) == original.parameters.get(epochPeriod)
  let sameCeilings = uint64(profile.validators) == 3*cores and
    uint64(profile.ticketLimit) == original.parameters.get(maxTicketsPerBlock)
  if not sameDomain or not sameCeilings:
    fail(ComputedTransitionError.ProfileMismatch) # Completed lookup validation already proves 2<=cores<=341 before multiplication.
  let prior = source.computedProfileSource.value.computedLookupSource.value.computedRecentSource.value
  let expected = prior.computedStateAdmission.value.admittedHeader
  let actual = step.admitted.admittedHeader
  let expectedSize = headerInfo(expected).value.consumed
  let actualSize = headerInfo(actual).value.consumed
  if uint64(expectedSize) > uint64(headerBytes) or uint64(actualSize) > uint64(headerBytes):
    fail(ComputedTransitionError.LimitExceeded) # Both positive owner extents are bounded before allocating either encoding.
  if expectedSize != actualSize: fail(ComputedTransitionError.HeaderMismatch)
  var expectedWire = newSeq[byte](expectedSize)
  var actualWire = newSeq[byte](actualSize)
  if encodeOwnedHeader(expected, expectedWire).error != HeaderError.None or
      encodeOwnedHeader(actual, actualWire).error != HeaderError.None:
    fail(ComputedTransitionError.HeaderMismatch) # No serialization refusal can publish a posterior binding.
  if expectedWire != actualWire:
    fail(ComputedTransitionError.HeaderMismatch) # Full seal, markers, proofs and commitments participate; parent/slot alone are insufficient.
  ComputedTransitionResult[TransitionBoundComputedReport](status: ComputedTransitionError.None,
    completed: TransitionBoundComputedReport(data: ComputedTransitionData(source: source,
        transition: staged)))
