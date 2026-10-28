# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "pvm_assured_queue_arc_release"}

## Actual previously computed reports enter successor priority through verified assurances and real empty-body report admission.

import std/assertions
import std/syncio
import ../../../src/state/assured_queue as state_assured_queue
import ../../../src/state/computed_assurances as state_computed_assurances
import ../../../src/state/computed_chain as state_computed_chain
import ../../../src/state/accumulation_queue as state_accumulation_queue
import ../../../src/state/availability as state_availability
import ../../../src/state/report_admission as state_report_admission
import ../../../src/state/guarantee_credentials as state_guarantee_credentials
import ../../../src/state/report_assignments as state_report_assignments
import ../../../src/state/block_transition as state_block_transition
import ../../../src/state/block_admission as state_block_admission
import ../../../src/state/report_policy as state_report_policy
import ../../../src/state/report_anchors as state_report_anchors
import ../../../src/state/guarantors as state_guarantors
import ../../../src/state/store as state_store
import ../../../src/chain/parameters as chain_parameters
import ../../../src/chain/genesis as chain_genesis
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/header as codec_header
import ../../../src/codec/assurances as codec_assurances
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/owned as codec_owned
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_workqueues as codec_state_workqueues
import ../../support/pvm_assured_queue
import ../../support/testing_arc_evidence

proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Force genuine retained-ancestry hashing failure after predecessor and successor authentication complete.
proc expect[T](outcome: AssuredQueueResult[T], reason: AssuredQueueError) =
  ## Preserve originating maintained refusal diagnostics without accepting another local or protocol alternative.
  if outcome.error != reason:
    echo "expected ", reason, " got ", outcome.error
    if outcome.error == AssuredQueueError.AdmissionFailure: echo "admission ",
        outcome.admissionFailure.error
    if outcome.error == AssuredQueueError.QueueFailure: echo "queue ", outcome.queueFailure.error
  assert outcome.error == reason, "assured queue reason"
proc reportBytes(report: OwnedReport): seq[byte] =
  ## Independent complete encodings catch report substitution beyond matching core or package metadata.
  result = newSeq[byte](report.ownedReportInfo.value.consumed)
  assert encodeOwnedReport(report, result).error == OwnershipError.None
let source = assuredQueueFixture()
let config = assuredQueueConfig(source)
let stage = source.computedAssuranceStage.value
let original = stage.value.admitted.admittedState
let parent = source.computedAssuranceSource.value.computedChainBlock.value
assert sameStateSnapshot(original, parent.stateSnapshot)
let ready = decodeReadyState(original.lookup(chapterKey(StateChapter(14))).value.bytes,
    config.queue.queues).value.snapshot
assert ready.readyInfo.value.items == 0, "original ready ring must be empty"
let result = prepareAssuredQueue(source, config)
expect(result, AssuredQueueError.None)
let queue = result.value
let plan = queue.assuredQueuePlan.value
let projection = plan.accumulationProjection.value
assert projection.accumulationCount.value == 2, "two genuinely assured reports"
assert projection.accumulationImmediateCount.value == 2, "two dependency-free immediate reports"
assert projection.accumulationQueuedCount.value == 0, "no deferred queue rows"
let admission = queue.assuredQueueAdmission.value
assert admission.reportCredentials.value.verifiedGuaranteeCount.value == 0
assert admission.reportCredentials.value.verifiedReporterCount.value == 0
assert sameStateSnapshot(admission.reportBlockStage.value.value.admitted.admittedState, original)
assert sameStateSnapshot(plan.accumulationAdmission.value.reportBlockStage.value.value.snapshot,
    stage.value.snapshot)
assert uint32(admission.reportBlockStage.value.value.admitted.admittedHeader.headerInfo.value.unsigned.slot) == 3
assert admission.reportAssignments.value.reportAssignmentEntry.value.value ==
    stage.value.snapshot.lookup(chapterKey(StateChapter(10))).value.bytes
for index in 0..<2:
  let selected = projection.accumulationAt(AccumulationIndex(uint64(index))).value
  let computed = source.computedAssuredReportAt(ComputedAvailableIndex(uint64(index))).value
  assert reportBytes(selected) == reportBytes(computed)
  assert reportBytes(selected) == reportBytes(stage.value.availability.availableReportAt(index).value)
let left = projection.accumulationAt(AccumulationIndex(
    0)).value.ownedReportInfo.value.header.packageHash.bytes
let right = projection.accumulationAt(AccumulationIndex(
    1)).value.ownedReportInfo.value.header.packageHash.bytes
assert left != right
let inherited = queue.assuredQueueParameters.value
let originalParams = source.computedAssuranceParameters.value
for field in low(Parameter)..high(Parameter): assert inherited.get(field) == originalParams.get(
    field) # No later caller changes the original execution tuple.
assert sameStateSnapshot(queue.assuredQueueSource.value.computedAssuranceSource.value.computedChainBlock.value.stateSnapshot, original)
let insufficient = assuredQueueFixture(votes = 6)
let empty = prepareAssuredQueue(insufficient, assuredQueueConfig(insufficient))
expect(empty, AssuredQueueError.None)
assert empty.value.assuredQueuePlan.value.accumulationProjection.value.accumulationCount.value == 0
assert empty.value.assuredQueueAdmission.value.reportCredentials.value.verifiedGuaranteeCount.value == 0
expect(prepareAssuredQueue(default(AssuredComputedReports), config),
    AssuredQueueError.InvalidSource)
var short = config
short.admission.policy.reportGas = ReportGasLimit(99999)
expect(prepareAssuredQueue(source, short), AssuredQueueError.ProfileMismatch)
short = config
short.admission.credentials.assignments.rotationSlots = GuarantorRotationSlots(5)
expect(prepareAssuredQueue(source, short), AssuredQueueError.ProfileMismatch)
short = config
short.admission.anchors.lookupAge = LookupAge(0)
expect(prepareAssuredQueue(source, short), AssuredQueueError.ProfileMismatch)
short = config
short.queue.queues.cores = CoreCount(2)
expect(prepareAssuredQueue(source, short), AssuredQueueError.ProfileMismatch)
short = config
short.queue.queues.epochSlots = EpochSlots(24)
expect(prepareAssuredQueue(source, short), AssuredQueueError.ProfileMismatch)
short = config
short.admission.ancestors.headers = ElementLimit(3)
expect(prepareAssuredQueue(source, short), AssuredQueueError.None)
short.admission.ancestors.headers = ElementLimit(2)
expect(prepareAssuredQueue(source, short), AssuredQueueError.LimitExceeded)
short = config
short.admission.credentials.assignments.roster.cores = CoreCount(2)
let domains = prepareAssuredQueue(source, short)
expect(domains, AssuredQueueError.AdmissionFailure)
assert domains.admissionFailure.error == ReportAdmissionError.InvalidConfig
short = config
short.admission.credentials.assignments.roster.maxBytes = ByteLimit(0)
let admissionLimit = prepareAssuredQueue(source, short)
expect(admissionLimit, AssuredQueueError.AdmissionFailure)
assert admissionLimit.admissionFailure.error == ReportAdmissionError.LimitExceeded
short = config
short.admission.ancestors.header.maxBytes = ByteLimit(0)
let ancestorBytes = prepareAssuredQueue(source, short)
expect(ancestorBytes, AssuredQueueError.AdmissionFailure)
assert ancestorBytes.admissionFailure.error == ReportAdmissionError.AnchorFailure
assert ancestorBytes.admissionFailure.anchorError == ReportAnchorError.LimitExceeded
short = config
short.queue.items = ElementLimit(1)
let queueLimit = prepareAssuredQueue(source, short)
expect(queueLimit, AssuredQueueError.QueueFailure)
assert queueLimit.queueFailure.error == AccumulationQueueError.LimitExceeded
short = config
short.queue.queues.maxBytes = ByteLimit(0)
let chapterLimit = prepareAssuredQueue(source, short)
expect(chapterLimit, AssuredQueueError.QueueFailure)
assert chapterLimit.queueFailure.error == AccumulationQueueError.LimitExceeded
failHash(1)
let backend = prepareAssuredQueue(source, config)
expect(backend, AssuredQueueError.AdmissionFailure)
assert backend.admissionFailure.error == ReportAdmissionError.CredentialFailure
assert backend.admissionFailure.credentialError.error == GuaranteeCredentialError.AssignmentFailure
assert backend.admissionFailure.credentialError.assignmentError == GuarantorError.BackendFailure
failHash(0)
assert sameStateSnapshot(source.computedAssuranceSource.value.computedChainBlock.value.stateSnapshot, original)
assert ready.readyInfo.value.items == 0, "original ready ring must be empty"
expect(default(AssuredAccumulationQueue).assuredQueueSource, AssuredQueueError.Uninitialized)
expect(default(AssuredAccumulationQueue).assuredQueuePlan, AssuredQueueError.Uninitialized)
expect(default(AssuredAccumulationQueue).assuredQueueAdmission, AssuredQueueError.Uninitialized)
expect(default(AssuredAccumulationQueue).assuredQueueParameters, AssuredQueueError.Uninitialized)
var copied = queue.assuredQueuePlan.value
copied = default(BlockAccumulationQueue)
assert queue.assuredQueuePlan.value.accumulationProjection.value.accumulationCount.value == 2
proc detached(): AssuredAccumulationQueue =
  ## Retain authenticated source, genuine zero-new-report admission, priority and original tuple after fixture handles retire.
  let source = assuredQueueFixture()
  prepareAssuredQueue(source, assuredQueueConfig(source)).value
let held = detached()
assert held.assuredQueuePlan.value.accumulationProjection.value.accumulationImmediateCount.value == 2
proc cycle(source: AssuredComputedReports, config: AssuredQueueConfig) =
  ## Release a complete queue and a later queue refusal after genuine report admission has already succeeded.
  let queue = prepareAssuredQueue(source, config).value
  discard queue.assuredQueueSource.value
  discard queue.assuredQueueAdmission.value
  var short = config
  short.queue.items = ElementLimit(1)
  expect(prepareAssuredQueue(source, short), AssuredQueueError.QueueFailure)
cycle(source, config)
let before = getOccupiedMem()
for iteration in 0..<1000: cycle(source, config) # Actual ancestor hashing, empty report admission and assurance queue planning repeat.
let after = getOccupiedMem()
assert before == after, "assured queue ARC release"
recordArcRelease("pvm_assured_queue", 1000, before, after)
echo "PVM assured queue passed"
echo "ARC_RELEASE cycles=1000 unchanged"
