# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authenticate the next block against an actual computed predecessor and retain exact prior-computed availability outputs.

import ../chain/[genesis, parameters]
import ../codec/[block_codec, report_owned, owned, bounded]
import ./[computed_chain, computed_state_publication, computed_composition, computed_finalization,
    computed_execution, computed_round, computed_publication, computed_admission,
    computed_inclusion, computed_batch, computed_envelope, block_transition, block_admission,
    disputes, safrole_transition, availability, store]

type
  ComputedAssuranceConfig* = object ## Maintained transition policies and independent report comparison/storage ceilings.
    admission*: BlockAdmissionConfig
    disputes*: DisputesConfig
    safrole*: SafroleTransitionConfig
    availability*: AvailabilityTransitionConfig
    reports*: ElementLimit
    reportBytes*, totalReportBytes*: ByteLimit
  ComputedAssuranceError* {.pure.} = enum ## Only selected failed child operations carry their precise guarded reason.
    Uninitialized, None, InvalidSource, ProfileMismatch, LimitExceeded, StateFailure,
      TransitionFailure, ReportFailure, ReportMismatch, InvalidIndex
  ComputedAvailableIndex* = distinct uint64 ## Dense ordinal identifies a matched actual availability output, not a core or detached report.
  ComputedAssuranceInfo* = object ## Copied counts distinguish actual available outputs from those retaining prior local computation.
    available*, computed*: int
  ComputedAssuranceData = ref object ## Immutable acyclic ownership retains the full predecessor and real authenticated successor with bounded output indices.
    source: AdvancedComputedChain
    stage: BlockTransitionResult
    indices: seq[int]
  AssuredComputedReports* = object ## Authenticated prefix preparation is not report admission, accumulation or successor publication.
    data: nil ComputedAssuranceData
  ComputedAssuranceResult*[T] = object ## Defaults and refusals expose no successful earlier private state or available-report prefix.
    case status: ComputedAssuranceError
    of None: completed: T
    of StateFailure: stateReason: StateStoreError
    of TransitionFailure: transitionReason: BlockTransitionResult
    of ReportFailure: reportReason: OwnershipError
    else: discard # Ordinary profile/resource/source/index refusals carry reasons alone.

func error*[T](outcome: ComputedAssuranceResult[T]): ComputedAssuranceError =
  ## Inspect selection without writable discriminator access.
  outcome.status
func value*[T](outcome: ComputedAssuranceResult[T]): T {.requires: outcome.status ==
    ComputedAssuranceError.None.} =
  ## Extract only complete success under optimized contracts.
  outcome.completed
func stateError*[T](outcome: ComputedAssuranceResult[
    T]): StateStoreError {.requires: outcome.status == ComputedAssuranceError.StateFailure.} =
  ## Inspect only failed private-parent forking.
  outcome.stateReason
func transitionFailure*[T](outcome: ComputedAssuranceResult[
    T]): BlockTransitionResult {.requires: outcome.status ==
    ComputedAssuranceError.TransitionFailure.} =
  ## Retain the whole refused maintained phase and its own guarded nested reasons.
  outcome.transitionReason
func reportError*[T](outcome: ComputedAssuranceResult[
    T]): OwnershipError {.requires: outcome.status == ComputedAssuranceError.ReportFailure.} =
  ## Inspect only a failed canonical owner-bound report encoding.
  outcome.reportReason
proc computedAssuranceSource*(assured: AssuredComputedReports): ComputedAssuranceResult[
    AdvancedComputedChain] =
  ## Share exact computed predecessor authority after caller handles retire.
  let data = assured.data
  if data == nil: return ComputedAssuranceResult[AdvancedComputedChain](
      status: ComputedAssuranceError.Uninitialized)
  ComputedAssuranceResult[AdvancedComputedChain](status: ComputedAssuranceError.None,
      completed: data.source)
proc computedAssuranceStage*(assured: AssuredComputedReports): ComputedAssuranceResult[
    BlockTransitionResult] =
  ## Share the actual complete authenticated coordinator result, including all maintained availability outputs.
  let data = assured.data
  if data == nil: return ComputedAssuranceResult[BlockTransitionResult](
      status: ComputedAssuranceError.Uninitialized)
  ComputedAssuranceResult[BlockTransitionResult](status: ComputedAssuranceError.None,
      completed: data.stage)
proc computedAssuranceParameters*(assured: AssuredComputedReports): ComputedAssuranceResult[Parameters] =
  ## Derive the complete original tuple from the real computed chain child, never from caller replacements.
  let data = assured.data
  if data == nil: return ComputedAssuranceResult[Parameters](
      status: ComputedAssuranceError.Uninitialized)
  ComputedAssuranceResult[Parameters](status: ComputedAssuranceError.None,
      completed: data.source.computedChainBlock.value.chainParameters)
proc computedAssuranceInfo*(assured: AssuredComputedReports): ComputedAssuranceResult[
    ComputedAssuranceInfo] =
  ## Observe real availability and matched-computation counts without retaining mutable arrays.
  let data = assured.data
  if data == nil: return ComputedAssuranceResult[ComputedAssuranceInfo](
      status: ComputedAssuranceError.Uninitialized)
  ComputedAssuranceResult[ComputedAssuranceInfo](status: ComputedAssuranceError.None,
      completed: ComputedAssuranceInfo(
      available: data.stage.value.availability.availableReportCount, computed: data.indices.len))
proc computedAssuredReportAt*(assured: AssuredComputedReports,
    index: ComputedAvailableIndex): ComputedAssuranceResult[OwnedReport] =
  ## Select only a real available report whose canonical bytes matched retained original computation.
  let data = assured.data
  if data == nil: return ComputedAssuranceResult[OwnedReport](
      status: ComputedAssuranceError.Uninitialized)
  if uint64(index) >= uint64(data.indices.len): return ComputedAssuranceResult[OwnedReport](
      status: ComputedAssuranceError.InvalidIndex)
  ComputedAssuranceResult[OwnedReport](status: ComputedAssuranceError.None,
      completed: data.stage.value.availability.availableReportAt(data.indices[int(uint64(
      index))]).value)
proc prepareComputedAssurances*(source: AdvancedComputedChain, candidate: OwnedBlock,
    config: ComputedAssuranceConfig): ComputedAssuranceResult[AssuredComputedReports] =
  ## Privately authenticate against the exact predecessor, then prove matched report bytes before exposing any successor prefix.
  let retained = source.computedChainBlock
  if retained.error != ComputedChainError.None:
    return ComputedAssuranceResult[AssuredComputedReports](
        status: ComputedAssuranceError.InvalidSource) # Defaults cannot supply historical state or parameters.
  let parent = retained.value
  let params = parent.chainParameters
  if uint64(config.admission.frame.cores) != uint64(parent.cores) or uint64(
      config.admission.frame.validators) != uint64(parent.activeValidators) or uint64(
      config.admission.frame.epochSlots) != uint64(parent.epochSlots) or uint64(
      config.admission.frame.ticketLimit) != params.get(maxTicketsPerBlock) or uint64(
      config.safrole.tailStart) != params.get(epochTailStart):
    return ComputedAssuranceResult[AssuredComputedReports](
        status: ComputedAssuranceError.ProfileMismatch) # Preserve the implemented original chain domains before native work.
  let batch = source.computedChainPublication.value.computedPublishedSource.value.computedCompositionSource.value.computedFinalizationSource.value.computedExecutionSource.value.computedRoundSource.value.computedSuccessorSource.value.computedAdmissionSource.value.computedInclusionSource.value
  let count = batch.computedBatchInfo.value.guarantees
  if uint64(count) > uint64(config.reports):
    return ComputedAssuranceResult[AssuredComputedReports](
        status: ComputedAssuranceError.LimitExceeded) # Bound comparison work before staging or allocating indices.
  let forked = forkStateStore(parent.stateSnapshot)
  if forked.error != StateStoreError.None:
    return ComputedAssuranceResult[AssuredComputedReports](
        status: ComputedAssuranceError.StateFailure, stateReason: forked.error)
  var working = forked.value
  let stage = advanceBlockState(working, candidate, parent.header, config.admission,
      config.disputes, config.safrole, config.availability)
  if stage.error != BlockTransitionError.None:
    return ComputedAssuranceResult[AssuredComputedReports](
        status: ComputedAssuranceError.TransitionFailure,
        transitionReason: stage) # Preserve all precise authentication/availability/store refusals.
  let available = stage.value.availability
  if uint64(available.availableReportCount) > uint64(config.reports):
    return ComputedAssuranceResult[AssuredComputedReports](
        status: ComputedAssuranceError.LimitExceeded)
  var remaining = uint64(config.totalReportBytes)
  var indices: seq[int] = @[]
  for index in 0..<available.availableReportCount:
    # Match by the genuine unique core first; available older untracked cores remain in the actual stage without a computed label.
    let report = available.availableReportAt(index).value
    let info = report.ownedReportInfo.value
    for original in 0..<count:
      let expected = batch.computedBatchSourceAt(ComputedBatchIndex(uint64(
          original))).value.computedEnvelopeGuarantee.value.report
      let prior = expected.ownedReportInfo.value
      if uint64(info.core) != uint64(prior.core): continue # Only overlapping prior-computed cores require canonical byte comparison.
      if info.consumed != prior.consumed:
        return ComputedAssuranceResult[AssuredComputedReports](
            status: ComputedAssuranceError.ReportMismatch)
      let length = uint64(info.consumed)
      if length > uint64(config.reportBytes) or length > remaining div 2:
        return ComputedAssuranceResult[AssuredComputedReports](
            status: ComputedAssuranceError.LimitExceeded) # Prove both allocations and doubled subtraction before materialization.
      remaining -= 2*length
      var actual = newSeq[byte](info.consumed)
      var canonical = newSeq[byte](prior.consumed)
      let encoded = encodeOwnedReport(report, actual)
      if encoded.error != OwnershipError.None:
        return ComputedAssuranceResult[AssuredComputedReports](
            status: ComputedAssuranceError.ReportFailure, reportReason: encoded.error)
      let encodedPrior = encodeOwnedReport(expected, canonical)
      if encodedPrior.error != OwnershipError.None:
        return ComputedAssuranceResult[AssuredComputedReports](
            status: ComputedAssuranceError.ReportFailure, reportReason: encodedPrior.error)
      if actual != canonical:
        return ComputedAssuranceResult[AssuredComputedReports](
            status: ComputedAssuranceError.ReportMismatch) # Equal metadata alone cannot replace the original computed report.
      indices.add(index)
      break # Canonical batch cores are unique, so each actual report obtains at most one computed identity.
  ComputedAssuranceResult[AssuredComputedReports](status: ComputedAssuranceError.None,
      completed: AssuredComputedReports(data: ComputedAssuranceData(source: source, stage: stage,
      indices: indices)))
