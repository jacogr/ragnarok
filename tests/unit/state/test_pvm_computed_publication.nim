# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_computed_publication_arc_release"}

## Exact computed report successors preserve all posterior chapters and publish only to their original parent handles.

import std/[assertions, syncio]
import ../../../src/state/[computed_publication, computed_admission, report_admission,
  report_assignments, block_transition, block_admission, store]
import ../../../src/codec/[bounded, state_layout, state_trie]
import ../../support/[pvm_computed_publication, arc_evidence]

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Force the maintained hash backend to refuse during successor preparation, after real admission completes.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe whether final publication performs any new hashing.
proc expect[T](outcome: ComputedPublicationResult[T], reason: ComputedPublicationError) =
  ## Check exact alternative before extracting a completed map or selected store cause.
  assert outcome.error == reason, "computed publication reason"
let source = publicationFixture()
let reports = source.computedAdmissionReports.value
let staged = reports.reportBlockStage.value.value
let parent = staged.admitted.admittedState
let prefix = staged.snapshot
let assignment = reports.reportAssignments.value
let entry = assignment.reportAssignmentEntry.value
let exact = ByteLimit(uint64(assignment.reportAssignmentByteLength.value))
let successor = prepareComputedPublication(source, exact).value
let final = successor.computedSuccessorSnapshot.value
assert final.lookup(chapterKey(StateChapter(10))).value.bytes == entry.value
assert prefix.lookup(chapterKey(StateChapter(10))).value.bytes != entry.value
for ordinal in 0..<prefix.commitment.entries:
  let key = prefix.keyAt(StateEntryIndex(ordinal)).value
  if array[31, byte](key) != array[31, byte](chapterKey(StateChapter(10))):
    assert final.lookup(key).value.bytes == prefix.lookup(
        key).value.bytes # Every other authenticated posterior chapter remains byte-identical.
expect(prepareComputedPublication(source, ByteLimit(uint64(exact)-1)),
    ComputedPublicationError.LimitExceeded)
expect(prepareComputedPublication(default(AdmittedComputedReports), exact),
    ComputedPublicationError.InvalidSource)
reset(1)
let refused = prepareComputedPublication(source, exact)
expect(refused, ComputedPublicationError.StoreFailure)
assert refused.storeError == StateStoreError.BackendFailure
reset(0)
assert prefix.lookup(chapterKey(StateChapter(10))).value.bytes != entry.value
var receiver = forkStateStore(parent).value
reset(1)
let published = publishComputedReports(receiver, successor)
expect(published, ComputedPublicationError.None)
assert hashes() == 0, "final handle publication performs no new hashing"
reset(0)
assert sameStateSnapshot(receiver.snapshot.value, final)
assert sameStateSnapshot(published.value, final)
expect(publishComputedReports(receiver, successor), ComputedPublicationError.StateMismatch)
assert sameStateSnapshot(receiver.snapshot.value, final)
var rebuilt = rebuiltStore(parent)
assert array[32, byte](rebuilt.snapshot.value.commitment.root) == array[32, byte](
    parent.commitment.root)
expect(publishComputedReports(rebuilt, successor), ComputedPublicationError.StateMismatch)
var posterior = forkStateStore(prefix).value
expect(publishComputedReports(posterior, successor), ComputedPublicationError.StateMismatch)
var absent = default(StateStore)
expect(publishComputedReports(absent, successor), ComputedPublicationError.StateMismatch)
var original = forkStateStore(parent).value
expect(publishComputedReports(original, default(ComputedReportSuccessor)),
    ComputedPublicationError.InvalidSource)
assert sameStateSnapshot(original.snapshot.value, parent)
expect(default(ComputedReportSuccessor).computedSuccessorSource,
    ComputedPublicationError.Uninitialized)
expect(default(ComputedReportSuccessor).computedSuccessorSnapshot,
    ComputedPublicationError.Uninitialized)
proc detached(): ComputedReportSuccessor =
  ## Retain complete provenance and final map after all original mutable handles retire.
  prepareComputedPublication(publicationFixture(), ByteLimit(100000)).value
let retained = detached()
assert retained.computedSuccessorSnapshot.error == ComputedPublicationError.None
proc cycle(source: AdmittedComputedReports, parent: StateStoreSnapshot, bytes: ByteLimit) =
  ## Hash a private successor, publish a local parent handle and release every new map/source/copy.
  let successor = prepareComputedPublication(source, bytes).value
  var receiver = forkStateStore(parent).value
  discard publishComputedReports(receiver, successor).value
  discard successor.computedSuccessorSource.value
  expect(publishComputedReports(receiver, successor), ComputedPublicationError.StateMismatch)
cycle(source, parent, exact)
let before = getOccupiedMem()
for i in 0..<1000: cycle(source, parent, exact) # Complete successor and local publication roots retire each cycle.
let after = getOccupiedMem()
assert before == after, "computed publication ARC release"
recordArcRelease("pvm_computed_publication", 1000, before, after)
echo "PVM computed publication passed"
echo "ARC_RELEASE cycles=1000 unchanged"
