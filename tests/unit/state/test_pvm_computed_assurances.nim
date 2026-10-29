# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "pvm_computed_assurances_arc_release"}

## Actual successor signatures free prior computed reports at strict quorum while retaining original chain ownership and precise refusals.

import std/[assertions, syncio]
import ../../../src/state/computed/[assurances as computed_assurances, chain as computed_chain]
import "../../../src/state/block/transition" as block_transition
import "../../../src/state/block/admission" as block_admission
import ../../../src/state/availability
import ../../../src/state/safrole/[transition as safrole_transition,
    authentication as safrole_authentication]
import ../../../src/state/store
import ../../../src/chain/[genesis, parameters]
import ../../../src/codec/[bounded, header, block_codec]
import ../../../src/codec/state/[layout as state_layout, availability as state_availability]
import ../../../src/codec/[report_owned, owned, assurances, tickets]
import ../../../src/codec/state/safrole as state_safrole
import ../../../src/crypto/assurance_context
import ../../support/[pvm_computed_assurances, arc_evidence]

proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Force actual maintained admission hashing refusal after all genuine source/candidate construction.
proc expect[T](outcome: ComputedAssuranceResult[T], reason: ComputedAssuranceError) =
  ## Identify the actual rejected maintained phase before asserting the exact expected selection.
  if outcome.error != reason:
    echo "expected ", reason, " got ", outcome.error
    if outcome.error == ComputedAssuranceError.TransitionFailure:
      let child = outcome.transitionFailure
      echo "transition ", child.error
      if child.error == BlockTransitionError.AdmissionFailure: echo "admission ",
          child.admissionError
      if child.error == BlockTransitionError.DisputesFailure: echo "disputes ", child.disputesError
      if child.error == BlockTransitionError.SafroleFailure: echo "safrole ",
          child.safroleError.error
      if child.error == BlockTransitionError.AvailabilityFailure: echo "availability ",
          child.availabilityError.error
  assert outcome.error == reason, "computed assurance reason"
proc reportBytes(report: OwnedReport): seq[byte] =
  ## Independently compare the entire original pending assignment with each exposed computed availability output.
  result = newSeq[byte](report.ownedReportInfo.value.consumed)
  assert encodeOwnedReport(report, result).error == OwnershipError.None
let prior = assurancePrior()
let parent = prior.computedChainBlock.value
let original = parent.stateSnapshot
let candidate = assuranceCandidate(prior)
let config = computedAssuranceConfig()
let result = prepareComputedAssurances(prior, candidate, config)
expect(result, ComputedAssuranceError.None)
let assured = result.value
let info = assured.computedAssuranceInfo.value
assert info.available == 2 and info.computed == 2
let stage = assured.computedAssuranceStage.value
assert sameStateSnapshot(stage.value.admitted.admittedState, original)
assert sameStateSnapshot(assured.computedAssuranceSource.value.computedChainBlock.value.stateSnapshot, original)
assert uint32(stage.value.admitted.admittedHeader.headerInfo.value.unsigned.slot) == 3
let assignments = decodeAvailabilityState(stage.value.snapshot.lookup(chapterKey(StateChapter(
    10))).value.bytes, config.availability.assignments).value.snapshot
assert not assignments.availabilityAt(AssignmentCoreIndex(0)).value.present
assert not assignments.availabilityAt(AssignmentCoreIndex(1)).value.present
for index in 0..<2:
  let report = assured.computedAssuredReportAt(ComputedAvailableIndex(uint64(index))).value
  assert uint64(report.ownedReportInfo.value.core) == uint64(
      index) # Maintained core order survives the computed-output mapping.
let originalPending = original.lookup(chapterKey(StateChapter(10))).value.bytes
let originalAssignments = decodeAvailabilityState(originalPending,
    config.availability.assignments).value.snapshot
assert originalAssignments.availabilityAt(AssignmentCoreIndex(0)).value.present
assert originalAssignments.availabilityAt(AssignmentCoreIndex(1)).value.present
var totalBytes = 0'u64
for index in 0..<2:
  let actual = reportBytes(assured.computedAssuredReportAt(ComputedAvailableIndex(uint64(index))).value)
  let pending = originalAssignments.availabilityAt(AssignmentCoreIndex(uint64(
      index))).value.guarantee.report
  assert actual == reportBytes(pending)
  assert actual == reportBytes(stage.value.availability.availableReportAt(index).value)
  totalBytes += 2*uint64(actual.len) # Both real canonical buffers count against the independent aggregate policy.
var exact = config
exact.totalReportBytes = ByteLimit(totalBytes)
expect(prepareComputedAssurances(prior, candidate, exact), ComputedAssuranceError.None)
exact.totalReportBytes = ByteLimit(totalBytes-1)
expect(prepareComputedAssurances(prior, candidate, exact),
    ComputedAssuranceError.LimitExceeded) # The first compared report cannot leak after the second exhausts the aggregate budget.

let selectedParams = assured.computedAssuranceParameters.value
for field in low(Parameter)..high(Parameter): assert selectedParams.get(field) ==
    parent.chainParameters.get(field) # Complete tuple remains inherited, not just framing.
let insufficient = prepareComputedAssurances(prior, assuranceCandidate(prior, votes = 6), config)
expect(insufficient, ComputedAssuranceError.None)
assert insufficient.value.computedAssuranceInfo.value.computed == 0
assert insufficient.value.computedAssuranceInfo.value.available == 0
expect(insufficient.value.computedAssuredReportAt(ComputedAvailableIndex(0)),
    ComputedAssuranceError.InvalidIndex)
let retained = insufficient.value.computedAssuranceStage.value.value.snapshot
assert retained.lookup(chapterKey(StateChapter(10))).value.bytes == originalPending
let signature = prepareComputedAssurances(prior, assuranceCandidate(prior, badSignature = true), config)
expect(signature, ComputedAssuranceError.TransitionFailure)
assert signature.transitionFailure.error == BlockTransitionError.AvailabilityFailure
assert signature.transitionFailure.availabilityError.error ==
    AvailabilityTransitionError.ContextFailure
assert signature.transitionFailure.availabilityError.contextError ==
    AssuranceContextError.InvalidSignature
let anchor = prepareComputedAssurances(prior, assuranceCandidate(prior, badAnchor = true), config)
expect(anchor, ComputedAssuranceError.TransitionFailure)
assert anchor.transitionFailure.error == BlockTransitionError.AvailabilityFailure
assert anchor.transitionFailure.availabilityError.error ==
    AvailabilityTransitionError.ContextFailure
assert anchor.transitionFailure.availabilityError.contextError == AssuranceContextError.WrongParent
let seal = prepareComputedAssurances(prior, assuranceCandidate(prior, badSeal = true), config)
expect(seal, ComputedAssuranceError.TransitionFailure)
assert seal.transitionFailure.error == BlockTransitionError.SafroleFailure
assert seal.transitionFailure.safroleError.error == SafroleTransitionError.AuthenticationFailure
assert seal.transitionFailure.safroleError.authenticationError == SafroleAuthError.InvalidSeal
expect(prepareComputedAssurances(default(AdvancedComputedChain), candidate, config),
    ComputedAssuranceError.InvalidSource)
expect(prepareComputedAssurances(prior, default(OwnedBlock), config),
    ComputedAssuranceError.TransitionFailure)
var short = config
short.admission.frame.cores = CoreCount(2)
expect(prepareComputedAssurances(prior, candidate, short), ComputedAssuranceError.ProfileMismatch)
short = config
short.admission.frame.validators = ValidatorCount(8)
expect(prepareComputedAssurances(prior, candidate, short), ComputedAssuranceError.ProfileMismatch)
short = config
short.admission.frame.epochSlots = EpochSlots(24)
expect(prepareComputedAssurances(prior, candidate, short), ComputedAssuranceError.ProfileMismatch)
short = config
short.admission.frame.ticketLimit = TicketLimit(2)
expect(prepareComputedAssurances(prior, candidate, short), ComputedAssuranceError.ProfileMismatch)
short = config
short.safrole.tailStart = EpochSlots(11)
expect(prepareComputedAssurances(prior, candidate, short), ComputedAssuranceError.ProfileMismatch)
short = config
short.reports = ElementLimit(1)
expect(prepareComputedAssurances(prior, candidate, short), ComputedAssuranceError.LimitExceeded)
short = config
short.reportBytes = ByteLimit(0)
expect(prepareComputedAssurances(prior, candidate, short), ComputedAssuranceError.LimitExceeded)
short = config
short.totalReportBytes = ByteLimit(1)
expect(prepareComputedAssurances(prior, candidate, short), ComputedAssuranceError.LimitExceeded)
failHash(1)
let backend = prepareComputedAssurances(prior, candidate, config)
expect(backend, ComputedAssuranceError.TransitionFailure)
assert backend.transitionFailure.error == BlockTransitionError.AdmissionFailure
assert backend.transitionFailure.admissionError == BlockAdmissionError.BackendFailure
failHash(0)
assert sameStateSnapshot(prior.computedChainBlock.value.stateSnapshot, original)
assert original.lookup(chapterKey(StateChapter(10))).value.bytes == originalPending
expect(default(AssuredComputedReports).computedAssuranceSource,
    ComputedAssuranceError.Uninitialized)
expect(default(AssuredComputedReports).computedAssuranceStage, ComputedAssuranceError.Uninitialized)
expect(default(AssuredComputedReports).computedAssuranceParameters,
    ComputedAssuranceError.Uninitialized)
expect(default(AssuredComputedReports).computedAssuranceInfo, ComputedAssuranceError.Uninitialized)
expect(default(AssuredComputedReports).computedAssuredReportAt(ComputedAvailableIndex(0)),
    ComputedAssuranceError.Uninitialized)
expect(assured.computedAssuredReportAt(ComputedAvailableIndex(high(uint64))),
    ComputedAssuranceError.InvalidIndex)
var copied = assured.computedAssuranceSource.value
copied = default(AdvancedComputedChain)
assert sameStateSnapshot(assured.computedAssuranceSource.value.computedChainBlock.value.stateSnapshot, original)
proc detached(): AssuredComputedReports =
  ## Retain real source, signed successor and report views after every local preparation handle retires.
  let prior = assurancePrior()
  prepareComputedAssurances(prior, assuranceCandidate(prior), computedAssuranceConfig()).value
let held = detached()
assert held.computedAssuranceInfo.value.computed == 2
assert uint64(held.computedAssuredReportAt(ComputedAvailableIndex(
    1)).value.ownedReportInfo.value.core) == 1
proc cycle(prior: AdvancedComputedChain, candidate: OwnedBlock,
    config: ComputedAssuranceConfig, requiredBytes: uint64) =
  ## Release successful state and a later refused prefix after its first computed report index has been prepared.
  let assured = prepareComputedAssurances(prior, candidate, config).value
  discard assured.computedAssuredReportAt(ComputedAvailableIndex(1)).value
  discard assured.computedAssuranceSource.value
  var short = config
  short.totalReportBytes = ByteLimit(requiredBytes-1)
  let refused = prepareComputedAssurances(prior, candidate, short)
  expect(refused, ComputedAssuranceError.LimitExceeded) # Late canonical comparison must release the first private matched output too.
cycle(prior, candidate, config, totalBytes)
let before = getOccupiedMem()
for iteration in 0..<1000: cycle(prior, candidate, config,
    totalBytes) # Every assurance verification and state-prefix computation is genuine.
let after = getOccupiedMem()
assert before == after, "computed assurances ARC release"
recordArcRelease("pvm_computed_assurances", 1000, before, after)
echo "PVM computed assurances passed"
echo "ARC_RELEASE cycles=1000 unchanged"
