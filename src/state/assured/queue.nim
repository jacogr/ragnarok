# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Admit an authenticated computed successor and derive its actual assurance-fed accumulation queue through maintained planners.

import ../../chain/parameters
import ../../codec/[header, bounded]
import ../computed/[assurances as computed_assurances, chain as computed_chain]
import ../computed/state/publication as computed_state_publication
import ../computed/[composition as computed_composition, finalization as computed_finalization,
    execution as computed_execution, round as computed_round, publication as computed_publication,
    admission as computed_admission, inclusion as computed_inclusion, batch as computed_batch,
    envelope as computed_envelope, credentials as computed_credentials,
    guarantors as computed_guarantors, roster as computed_roster, transition as computed_transition,
    profile as computed_profile, lookup as computed_lookup]
import ../report/admission as report_admission
import ../accumulation/queue as accumulation_queue

type
  AssuredQueueConfig* = object ## Semantic admission controls stay original; queue and ancestor resources remain independently bounded.
    admission*: ReportAdmissionConfig
    queue*: AccumulationQueueConfig
  AssuredQueueError* {.pure.} = enum ## Only selected refused maintained phases carry precise complete child results.
    Uninitialized, None, InvalidSource, ProfileMismatch, LimitExceeded, AdmissionFailure, QueueFailure
  AssuredQueueData = ref object ## Immutable acyclic ownership retains actual authenticated successor and the real admitted block queue.
    source: AssuredComputedReports
    plan: BlockAccumulationQueue
  AssuredAccumulationQueue* = object ## Queue preparation does not certify guest execution or publish successor state.
    data: nil AssuredQueueData
  AssuredQueueResult*[T] = object ## Defaults and refusals own no earlier successful admission or queue prefix.
    case status: AssuredQueueError
    of None: completed: T
    of AdmissionFailure: admissionReason: ReportAdmissionResult[AdmittedReports]
    of QueueFailure: queueReason: AccumulationQueueResult[BlockAccumulationQueue]
    else: discard # Source/profile/resource failures retain their reason alone.

func error*[T](outcome: AssuredQueueResult[T]): AssuredQueueError =
  ## Inspect the selected reason without writable discriminator access.
  outcome.status

func value*[T](outcome: AssuredQueueResult[T]): T {.requires: outcome.status ==
    AssuredQueueError.None.} =
  ## Extract complete success under checked optimized contracts.
  outcome.completed

func admissionFailure*[T](outcome: AssuredQueueResult[T]): ReportAdmissionResult[
    AdmittedReports] {.requires: outcome.status == AssuredQueueError.AdmissionFailure.} =
  ## Preserve the real refused admission and its independently guarded nested reason.
  outcome.admissionReason

func queueFailure*[T](outcome: AssuredQueueResult[T]): AccumulationQueueResult[
    BlockAccumulationQueue] {.requires: outcome.status == AssuredQueueError.QueueFailure.} =
  ## Preserve the actual failed maintained queue planner without exposing completed admission.
  outcome.queueReason

proc assuredQueueSource*(queue: AssuredAccumulationQueue): AssuredQueueResult[
    AssuredComputedReports] =
  ## Share original computed predecessor and authenticated assurance authority after caller handles retire.
  let data = queue.data
  if data == nil: return AssuredQueueResult[AssuredComputedReports](
      status: AssuredQueueError.Uninitialized)
  AssuredQueueResult[AssuredComputedReports](status: AssuredQueueError.None, completed: data.source)

proc assuredQueuePlan*(queue: AssuredAccumulationQueue): AssuredQueueResult[
    BlockAccumulationQueue] =
  ## Share the actual source-bound block queue, never a copied priority observation.
  let data = queue.data
  if data == nil: return AssuredQueueResult[BlockAccumulationQueue](
      status: AssuredQueueError.Uninitialized)
  AssuredQueueResult[BlockAccumulationQueue](status: AssuredQueueError.None, completed: data.plan)

proc assuredQueueAdmission*(queue: AssuredAccumulationQueue): AssuredQueueResult[AdmittedReports] =
  ## Derive the real completed admission from the retained maintained queue.
  let data = queue.data
  if data == nil: return AssuredQueueResult[AdmittedReports](
      status: AssuredQueueError.Uninitialized)
  AssuredQueueResult[AdmittedReports](status: AssuredQueueError.None,
      completed: data.plan.accumulationAdmission.value)

proc assuredQueueParameters*(queue: AssuredAccumulationQueue): AssuredQueueResult[Parameters] =
  ## Inherit the whole original parameter tuple; callers cannot replace individual execution policies.
  let data = queue.data
  if data == nil: return AssuredQueueResult[Parameters](status: AssuredQueueError.Uninitialized)
  AssuredQueueResult[Parameters](status: AssuredQueueError.None,
      completed: data.source.computedAssuranceParameters.value)

proc prepareAssuredQueue*(source: AssuredComputedReports,
    config: AssuredQueueConfig): AssuredQueueResult[AssuredAccumulationQueue] =
  ## Bind original semantic controls and retained ancestry, then admit and plan from actual assurance outputs without publishing.
  let stage = source.computedAssuranceStage
  if stage.error != ComputedAssuranceError.None:
    return AssuredQueueResult[AssuredAccumulationQueue](
        status: AssuredQueueError.InvalidSource) # Empty authority cannot supply a successful stage or parent.
  let params = source.computedAssuranceParameters.value
  let sameGas = uint64(config.admission.policy.reportGas) == params.get(maxAccumulateGas)
  let sameRotation = uint64(config.admission.credentials.assignments.rotationSlots) == params.get(rotationPeriod)
  let sameLookup = uint64(config.admission.anchors.lookupAge) == params.get(maxLookupAnchorAge)
  let sameCores = uint64(config.queue.queues.cores) == params.get(coreCount)
  let sameEpoch = uint64(config.queue.queues.epochSlots) == params.get(epochPeriod)
  if not sameGas or not sameRotation or not sameLookup or not sameCores or not sameEpoch:
    return AssuredQueueResult[AssuredAccumulationQueue](
        status: AssuredQueueError.ProfileMismatch) # Independent resource caps cannot change protocol knobs.
  let previous = source.computedAssuranceSource.value
  let batch = previous.computedChainPublication.value.computedPublishedSource.value.computedCompositionSource.value.computedFinalizationSource.value.computedExecutionSource.value.computedRoundSource.value.computedSuccessorSource.value.computedAdmissionSource.value.computedInclusionSource.value
  let first = batch.computedBatchSourceAt(ComputedBatchIndex(0)).value
  let lookup = first.computedEnvelopeSource.value.computedCredentialSource.value.computedGuarantorSource.value.computedRosterSource.value.computedTransitionSource.value.computedProfileSource.value
  let count = lookup.computedLookupInfo.value.headers
  if count > high(int) div sizeof(OwnedHeader) or uint64(count) >= uint64(
      config.admission.ancestors.headers):
    return AssuredQueueResult[AssuredAccumulationQueue](
        status: AssuredQueueError.LimitExceeded) # One extra current parent precedes all retained lookup headers; prove its count before allocation.
  var older = newSeq[OwnedHeader](count)
  for index in 0..<count:
    older[index] = lookup.computedLookupHeader(ComputedAncestorIndex(uint64(
        index))).value # Unlike original admission, its former parent is now an older ancestor.
  let admitted = planBlockReports(stage.value, older, config.admission)
  if admitted.error != ReportAdmissionError.None:
    return AssuredQueueResult[AssuredAccumulationQueue](status: AssuredQueueError.AdmissionFailure,
        admissionReason: admitted) # No successfully checked report prefix escapes a later refusal.
  let planned = planBlockAccumulationQueue(admitted.value, config.queue)
  if planned.error != AccumulationQueueError.None:
    return AssuredQueueResult[AssuredAccumulationQueue](status: AssuredQueueError.QueueFailure,
        queueReason: planned) # The completed admission remains private if queue planning fails.
  AssuredQueueResult[AssuredAccumulationQueue](status: AssuredQueueError.None,
      completed: AssuredAccumulationQueue(data: AssuredQueueData(source: source,
      plan: planned.value)))
