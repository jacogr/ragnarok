# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 header/judgments/safrole/reporting_assurance: atomic admission, disputes, Safrole
## and assurances. Lower-level prefix through assurances; report_transition.advanceBlockReports
## includes report publication. Other extrinsics, wall-clock admission and complete block
## execution remain separate stages.
##
## Exposes blockTransitionProfile and advanceBlockState with checked admission, disputes,
## Safrole and availability results.

import ../../codec/[block_codec, header, tickets]
import ../../codec/state/[disputes as state_disputes, safrole as state_safrole,
    layout as state_layout]
import ../../codec/assurances
from ../../crypto/assurance_context import AssuranceParent
import ../store
import ./admission as block_admission
import ../disputes
import ../safrole/transition as safrole_transition
import ../availability

type
  BlockTransitionError* {.pure.} = enum ## Failures select their precise stage cause without carrying staged state or a usable block.
    Uninitialized, None, AdmissionFailure, DisputesFailure, SafroleFailure, AvailabilityFailure
  BlockTransition* = object ## Success retains the original block binding, complete disputes plan and authenticated posterior state.
    profile: FrameConfig          # Retain the exact decoding/transition chain domains for later report binding.
    admitted*: BoundBlock
    disputes*: DisputesPlan
    safrole*: SafroleTransition   # Intermediate state before assurance-driven C(10) changes.
    availability*: AvailabilityPlan
    snapshot*: StateStoreSnapshot # Post-assurance prefix, before report admission/publication.
  BlockTransitionResult* = object ## Stage-specific reasons and success are mutually exclusive and private.
    case status: BlockTransitionError
    of None:
      completed: BlockTransition
    of AdmissionFailure:
      admissionReason: BlockAdmissionError
    of DisputesFailure:
      disputesReason: DisputesError
    of SafroleFailure:
      safroleReason: SafroleTransitionResult
    of AvailabilityFailure:
      availabilityReason: AvailabilityTransitionResult[AvailabilityUpdate]
    else:
      discard # Default carries no candidate, snapshot or reason payload.

func error*(outcome: BlockTransitionResult): BlockTransitionError =
  ## Observe the stage without granting safe-code access to its discriminator.
  outcome.status
func value*(outcome: BlockTransitionResult): BlockTransition {.inline,
    requires: outcome.status == BlockTransitionError.None.} =
  ## Read complete success only after all staged work has been accepted.
  outcome.completed
func blockTransitionProfile*(outcome: BlockTransitionResult): FrameConfig {.inline,
    requires: outcome.status == BlockTransitionError.None.} =
  ## Copy the profile from a completed coordinator result; callers cannot attach a different chain domain.
  outcome.completed.profile
func admissionError*(outcome: BlockTransitionResult): BlockAdmissionError {.inline,
    requires: outcome.status == BlockTransitionError.AdmissionFailure.} =
  ## Inspect only an admission failure's cause.
  outcome.admissionReason
func disputesError*(outcome: BlockTransitionResult): DisputesError {.inline,
    requires: outcome.status == BlockTransitionError.DisputesFailure.} =
  ## Inspect only a disputes failure's cause.
  outcome.disputesReason
func safroleError*(outcome: BlockTransitionResult): SafroleTransitionResult {.inline,
    requires: outcome.status == BlockTransitionError.SafroleFailure.} =
  ## Inspect only a Safrole failure's selected typed stage result.
  outcome.safroleReason

## Inspect only the selected availability failure; its nested refusal contains no update or available reports.
func availabilityError*(outcome: BlockTransitionResult): AvailabilityTransitionResult[
    AvailabilityUpdate] {.inline,

requires: outcome.status == BlockTransitionError.AvailabilityFailure.} = outcome.availabilityReason

proc advanceState(state: var StateStore, candidate: OwnedBlock, parent: OwnedHeader,
    admission: BlockAdmissionConfig, policy: DisputesConfig,
    safrole: SafroleTransitionConfig, availability: AvailabilityTransitionConfig,
        fuzzSeed: bool): BlockTransitionResult =
  ## Derive all offenders from this block and the parent C(5), never from a separately supplied projection.
  ## Work on a private store handle and replace the caller's handle once, after complete success.
  if uint64(availability.assignments.guarantee.cores) != uint64(policy.rosters.cores) or
      uint64(availability.assignments.guarantee.validators) != uint64(policy.rosters.validators) or
      uint64(availability.rosters.cores) != uint64(policy.rosters.cores) or
      uint64(availability.rosters.validators) != uint64(policy.rosters.validators) or
      uint64(policy.epochSlots) != uint64(safrole.state.epochSlots) or
      uint64(policy.rosters.cores) != uint64(safrole.state.validators.cores) or
      uint64(policy.rosters.validators) != uint64(safrole.state.validators.validators) or
      uint64(admission.frame.cores) != uint64(policy.rosters.cores) or
      uint64(admission.frame.validators) != uint64(policy.rosters.validators) or
      uint64(admission.frame.epochSlots) != uint64(policy.epochSlots) or
      uint64(admission.frame.ticketLimit) != uint64(safrole.blockTickets):
    return BlockTransitionResult(status: BlockTransitionError.AdmissionFailure,
      admissionReason: BlockAdmissionError.InvalidConfig) # Reject divergent chain domains before native work.
  let retained = state.snapshot
  if retained.error != StateStoreError.None:
    return BlockTransitionResult(status: BlockTransitionError.AdmissionFailure,
      admissionReason: BlockAdmissionError.Uninitialized) # No synthesized empty parent.
  let admitted = if fuzzSeed: validateFuzzSeedCommitments(candidate, parent, retained.value, admission)
    else: validateBlockCommitments(candidate, parent, retained.value, admission)
  if admitted.error != BlockAdmissionError.None:
    return BlockTransitionResult(status: BlockTransitionError.AdmissionFailure,
      admissionReason: admitted.error) # No disputes or Safrole work after invalid commitments.
  let exact = admitted.value
  let child = readDisputes(extrinsicDisputes(blockExtrinsic(
      exact.admittedBlock).value).value).value.owner
  let plan = planDisputes(retained.value, child, policy)
  if plan.error != DisputesError.None:
    return BlockTransitionResult(status: BlockTransitionError.DisputesFailure,
      disputesReason: plan.error) # No partial offenders or assignments escape.
  let marker = checkDisputeMarker(plan.value, exact.admittedHeader)
  if marker != DisputesError.None:
    return BlockTransitionResult(status: BlockTransitionError.DisputesFailure,
      disputesReason: marker) # Marker order and duplicates are checked before publication/authentication.
  let judged = plan.value.disputeJudgments
  var offenders = newSeq[OffenderKey](disputeStateInfo(judged).value.offenders)
  for i in 0..<offenders.len:
    offenders[i] = stateOffenderAt(judged, DisputeStateIndex(uint64(i))).value # Complete derived cumulative set.
  let originalActive = retained.value.lookup(chapterKey(StateChapter(8)))
  if originalActive.error != StateStoreError.None:
    return BlockTransitionResult(status: BlockTransitionError.AdmissionFailure,
      admissionReason: BlockAdmissionError.MissingState) # Parent signing context is mandatory.
  if uint64(originalActive.value.byteLength) > uint64(availability.rosters.maxBytes):
    return BlockTransitionResult(status: BlockTransitionError.AdmissionFailure,
      admissionReason: BlockAdmissionError.LimitExceeded) # Bound the parent roster copy under assurance policy.
  let parentActive = decodeStateValidators(originalActive.value.bytes, availability.rosters)
  if parentActive.error != StateComponentError.None:
    return BlockTransitionResult(status: BlockTransitionError.AdmissionFailure,
      admissionReason: BlockAdmissionError.InvalidState) # No invalid parent signing roster reaches any staged writes.
  if parentActive.value.consumed != originalActive.value.byteLength:
    return BlockTransitionResult(status: BlockTransitionError.AdmissionFailure,
      admissionReason: BlockAdmissionError.InvalidState) # The exact retained chapter cannot carry a suffix.
  var working = state
  let published = publishDisputes(working, plan.value)
  if published.error != DisputesError.None:
    return BlockTransitionResult(status: BlockTransitionError.DisputesFailure,
      disputesReason: published.error) # Original handle still owns every parent byte/root.
  let submitted = readTickets(extrinsicTickets(blockExtrinsic(
      exact.admittedBlock).value).value).value
  let advanced = advanceSafroleState(working, exact.admittedHeader, submitted, offenders, safrole)
  if advanced.error != SafroleTransitionError.None:
    return BlockTransitionResult(status: BlockTransitionError.SafroleFailure,
      safroleReason: advanced) # Includes late refusal after privately staged disputes writes.
  let assurances = readAssurances(extrinsicAssurances(blockExtrinsic(
      exact.admittedBlock).value).value).value
  let fields = headerInfo(exact.admittedHeader).value.unsigned
  let available = advanceAvailabilityState(working, parentActive.value.value, assurances,
    AssuranceParent(array[32, byte](fields.parent)), StateTime(uint32(fields.slot)), availability)
  if available.error != AvailabilityTransitionError.None:
    return BlockTransitionResult(status: BlockTransitionError.AvailabilityFailure,
      availabilityReason: available) # Even fully authenticated Safrole changes remain private on this refusal.
  state = working # One canonical handle replacement publishes every accepted stage together.
  BlockTransitionResult(status: BlockTransitionError.None,
    completed: BlockTransition(profile: admission.frame, admitted: exact, disputes: plan.value,
      safrole: advanced.value,
      availability: available.value.plan, snapshot: available.value.snapshot))

proc advanceBlockState*(state: var StateStore, candidate: OwnedBlock, parent: OwnedHeader,
    admission: BlockAdmissionConfig, policy: DisputesConfig,
    safrole: SafroleTransitionConfig, availability: AvailabilityTransitionConfig): BlockTransitionResult =
  ## Canonical callers retain strict parent/state pairing through the shared complete transition.
  advanceState(state, candidate, parent, admission, policy, safrole, availability, false)
proc advanceFuzzSeedState*(state: var StateStore, candidate: OwnedBlock, parent: OwnedHeader,
    admission: BlockAdmissionConfig, policy: DisputesConfig,
    safrole: SafroleTransitionConfig, availability: AvailabilityTransitionConfig): BlockTransitionResult =
  ## Only the application fuzz-domain seed branch selects genesis-like pairing; every later stage and atomic publication is shared.
  advanceState(state, candidate, parent, admission, policy, safrole, availability, true)
