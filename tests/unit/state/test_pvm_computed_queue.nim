# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_computed_queue_arc_release"}

## Actual computed reports remain pending; only authenticated historical ready reports enter accumulation priority.

import std/assertions
import std/syncio
import ../../../src/state/computed_publication as state_computed_publication
import ../../../src/state/computed_admission as state_computed_admission
import ../../../src/state/computed_inclusion as state_computed_inclusion
import ../../../src/state/computed_batch as state_computed_batch
import ../../../src/state/computed_envelope as state_computed_envelope
import ../../../src/state/report_admission as state_report_admission
import ../../../src/state/report_assignments as state_report_assignments
import ../../../src/state/accumulation_queue as state_accumulation_queue
import ../../../src/state/block_transition as state_block_transition
import ../../../src/state/block_admission as state_block_admission
import ../../../src/state/store as state_store
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/assurances as codec_assurances
import ../../../src/codec/header as codec_header
import ../../../src/codec/state_workqueues as codec_state_workqueues
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_availability as codec_state_availability
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/owned as codec_owned
import ../../support/pvm_computed_publication
import ../../support/pvm_computed_admission
import ../../support/testing_arc_evidence

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Any unexpected planning hash must refuse after the full signed computed pipeline is prepared.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Inspect real hashing observations without replacing protocol assertions.
proc config(): AccumulationQueueConfig =
  ## Use the source's three-core/twelve-slot domain with independent bounded queue scratch/serialization policies.
  AccumulationQueueConfig(queues: WorkQueueConfig(cores: CoreCount(3), epochSlots: EpochSlots(12),
    perSlot: ElementLimit(8), totalItems: ElementLimit(32), perDependencies: ElementLimit(8),
    totalDependencies: ElementLimit(256), reportBytes: ByteLimit(100000), maxBytes: ByteLimit(
        1000000)),
    items: ElementLimit(32), dependencies: ElementLimit(256))
proc expect[T](outcome: AccumulationQueueResult[T], reason: AccumulationQueueError) =
  ## Preserve exact local profile/limit/default reasons from the maintained queue implementation.
  assert outcome.error == reason, "computed queue reason"
proc reportWire(report: OwnedReport): seq[byte] =
  ## Capture independent complete canonical report bytes for historical identity and mutation tests.
  result = newSeq[byte](ownedReportInfo(report).value.consumed)
  assert encodeOwnedReport(report, result).error == OwnershipError.None
let emptySource = publicationFixture()
let emptySuccessor = prepareComputedPublication(emptySource, ByteLimit(100000)).value
let emptyReports = emptySuccessor.computedSuccessorSource.value.computedAdmissionReports.value
let empty = planBlockAccumulationQueue(emptyReports, config()).value.accumulationProjection.value
assert empty.accumulationCount.value == 0, "guaranteed current work is not immediately available"
assert empty.accumulationImmediateCount.value == 0
let source = publicationFixture(withReady = true)
let successor = prepareComputedPublication(source, ByteLimit(100000)).value
let reports = successor.computedSuccessorSource.value.computedAdmissionReports.value
let staged = reports.reportBlockStage.value.value
let parent = staged.admitted.admittedState
let bound = planBlockAccumulationQueue(reports, config()).value
let projection = bound.accumulationProjection.value
assert projection.accumulationCount.value == 1, "one eligible original historical ready report"
assert projection.accumulationImmediateCount.value == 0, "historical ready work is selected through Q, not new assurances"
assert projection.accumulationQueuedCount.value == 1
let historical = projection.accumulationAt(AccumulationIndex(0)).value
let key = ownedReportInfo(historical).value.header.packageHash.bytes
let ready = decodeReadyState(parent.lookup(chapterKey(StateChapter(14))).value.bytes, config().queues).value.snapshot
let original = readyItemAt(ready, WorkQueueSlot(0), ReadyItemIndex(0)).value
assert reportWire(historical) == reportWire(original.report)
let batch = source.computedAdmissionSource.value.computedInclusionSource.value
for i in 0..<batch.computedBatchInfo.value.guarantees:
  let current = batch.computedBatchSourceAt(ComputedBatchIndex(uint64(
      i))).value.computedEnvelopeGuarantee.value.report
  assert ownedReportInfo(current).value.header.packageHash.bytes != key, "current computed package is still pending"
let final = successor.computedSuccessorSnapshot.value
assert final.lookup(chapterKey(StateChapter(10))).value.bytes ==
    reports.reportAssignments.value.reportAssignmentEntry.value.value
for chapter in [14'u8, 15]:
  assert final.lookup(chapterKey(StateChapter(chapter))).value.bytes == parent.lookup(chapterKey(
      StateChapter(chapter))).value.bytes # Queue planning publishes neither ready nor accumulated state.
assert sameStateSnapshot(bound.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedState, parent)
var short = config()
short.items = ElementLimit(0)
expect(planBlockAccumulationQueue(reports, short), AccumulationQueueError.LimitExceeded)
short = config()
short.queues.maxBytes = ByteLimit(0)
expect(planBlockAccumulationQueue(reports, short), AccumulationQueueError.LimitExceeded)
short = config()
short.queues.cores = CoreCount(2)
expect(planBlockAccumulationQueue(reports, short), AccumulationQueueError.InvalidConfig)
expect(planBlockAccumulationQueue(default(AdmittedReports), config()),
    AccumulationQueueError.InvalidAdmission)
expect(projection.accumulationAt(AccumulationIndex(high(uint64))),
    AccumulationQueueError.InvalidIndex)
var mutable = reportWire(historical)
mutable[0] = mutable[0] xor 1
assert reportWire(projection.accumulationAt(AccumulationIndex(0)).value) == reportWire(
    original.report)
reset(1)
expect(planBlockAccumulationQueue(reports, config()), AccumulationQueueError.None)
assert hashes() == 0, "queue planning performs no new hashing"
reset(0)
proc detached(): BlockAccumulationQueue =
  ## Retain original parent queue/admission after every caller-owned computed successor handle retires.
  let source = publicationFixture(withReady = true)
  let successor = prepareComputedPublication(source, ByteLimit(100000)).value
  planBlockAccumulationQueue(successor.computedSuccessorSource.value.computedAdmissionReports.value,
      config()).value
let retained = detached()
assert retained.accumulationProjection.value.accumulationCount.value == 1
proc cycle(reports: AdmittedReports) =
  ## Release real queue projection scratch and retained historical report handles independently each time.
  let queue = planBlockAccumulationQueue(reports, config()).value
  discard reportWire(queue.accumulationProjection.value.accumulationAt(AccumulationIndex(0)).value)
cycle(reports)
let before = getOccupiedMem()
for i in 0..<1000: cycle(reports) # Every original-parent queue plan and returned report copy retires.
let after = getOccupiedMem()
assert before == after, "computed queue ARC release"
recordArcRelease("pvm_computed_queue", 1000, before, after)
echo "PVM computed queue passed"
echo "ARC_RELEASE cycles=1000 unchanged"
