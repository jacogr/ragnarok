# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "pvm_computed_state_arc_release"}

## Exact original execution/admission map ownership, equal-root/stale refusal and fixed acyclic lifetime.

import std/[assertions, syncio]
import ../../../src/state/[computed_state, computed_links, computed_guarantee, computed_report,
  block_admission, store]
import ../../../src/codec/[state_trie, header]
import ../../support/[pvm_computed_state, arc_evidence]

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse all new hashes only after completing original execution and genuine block commitment admissions.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Count actual backend attempts without replacing successful primitive behavior.
proc expect[T](outcome: ComputedStateResult[T], reason: ComputedStateError) =
  ## Compare typed alternatives before guarded extraction.
  assert outcome.error == reason, "computed state reason"
var fixture = stateFixture()
let source = fixture.source
let admission = fixture.admission
let original = fixture.state.snapshot.value
let bound = bindComputedState(source, admission).value
assert sameStateSnapshot(bound.computedStateSnapshot.value, original), "exact original execution version"
assert sameStateSnapshot(bound.computedStateAdmission.value.admittedState, original), "exact admitted complete map"
assert bound.computedStateSource.value.computedLinkCount.value == 0, "original initialized empty correspondence retained"
let wire = source.computedLinkSource.value.computedGuaranteeReport.value.computedReportBytes.value
assert bound.computedStateSource.value.computedLinkSource.value.computedGuaranteeReport.value.computedReportBytes.value ==
    wire, "exact original canonical report retained"
let root = array[32, byte](original.commitment.root)
assert array[32, byte](headerInfo(bound.computedStateAdmission.value.admittedHeader).value.unsigned.priorState) ==
    root, "child commits original complete map"
# Historical lookups may run from a later state; the claimed lookup root remains a separate unverified field.
let claimed = source.computedLinkSource.value.computedGuaranteeReport.value.computedReportInfo.value.header.lookupStateRoot.bytes
assert claimed != root, "state binding does not invent lookup-root equality"
let copied = original
expect(bindComputedState(source, stateAdmission(copied)), ComputedStateError.None)
let unchanged = forkStateStore(original).value
assert sameStateSnapshot(unchanged.snapshot.value, original), "unchanged fork shares exact snapshot"
expect(bindComputedState(source, stateAdmission(unchanged.snapshot.value)), ComputedStateError.None)
# Equal complete roots under independently rebuilt ownership cannot replace the original execution identity.
let clone = clonedState(original)
assert array[32, byte](clone.snapshot.value.commitment.root) == root, "independently rebuilt equal-root map"
assert not sameStateSnapshot(clone.snapshot.value, original), "independent owner identity"
let foreignAdmission = stateAdmission(clone.snapshot.value)
assert foreignAdmission.error == BlockAdmissionError.None, "equal-root foreign map independently admitted"
expect(bindComputedState(source, foreignAdmission), ComputedStateError.StateMismatch)
var changed = forkStateStore(original).value
changeState(changed)
let changedSnapshot = changed.snapshot.value
assert array[32, byte](changedSnapshot.commitment.root) != root, "changed complete map root"
let staleAdmission = stateAdmission(changedSnapshot)
assert staleAdmission.error == BlockAdmissionError.None, "new complete-map version independently admitted"
expect(bindComputedState(source, staleAdmission), ComputedStateError.StateMismatch)
let failed = stateAdmission(original, wrongRoot = true)
assert failed.error == BlockAdmissionError.InvalidStateRoot, "genuine refused child prior-state commitment"
expect(bindComputedState(source, failed), ComputedStateError.InvalidAdmission)
expect(bindComputedState(source, default(BlockAdmissionResult)),
    ComputedStateError.InvalidAdmission)
expect(bindComputedState(default(ComputedReportLinks), admission), ComputedStateError.InvalidSource)
expect(bindComputedState(default(ComputedReportLinks), default(BlockAdmissionResult)),
    ComputedStateError.InvalidSource)
expect(default(ComputedStateResult[StateBoundComputedReport]), ComputedStateError.Uninitialized)
expect(default(StateBoundComputedReport).computedStateSource, ComputedStateError.Uninitialized)
expect(default(StateBoundComputedReport).computedStateAdmission, ComputedStateError.Uninitialized)
expect(default(StateBoundComputedReport).computedStateSnapshot, ComputedStateError.Uninitialized)
# Caller publication creates a new version without replacing any original source/admission retained by the completed owner.
changeState(fixture.state)
assert not sameStateSnapshot(fixture.state.snapshot.value, original), "caller store advanced"
assert sameStateSnapshot(bound.computedStateSnapshot.value, original), "old bound version survives caller publication"
reset(1)
expect(bindComputedState(source, admission), ComputedStateError.None)
expect(bindComputedState(source, foreignAdmission), ComputedStateError.StateMismatch)
expect(bindComputedState(source, staleAdmission), ComputedStateError.StateMismatch)
expect(bindComputedState(source, failed), ComputedStateError.InvalidAdmission)
assert hashes() == 0, "state binding performs no hashes or state publication"
reset(0)
proc detached(): StateBoundComputedReport =
  ## One retained owner preserves original computation, both sealed headers and exact map after fixture locals retire.
  let temporary = stateFixture()
  bindComputedState(temporary.source, temporary.admission).value
let retained = detached()
assert sameStateSnapshot(retained.computedStateSnapshot.value,
  retained.computedStateAdmission.value.admittedState), "detached exact map lifetime"
assert retained.computedStateSource.value.computedLinkCount.value == 0, "detached source lifetime"
assert uint32(headerInfo(retained.computedStateAdmission.value.admittedHeader).value.unsigned.slot) ==
    21, "detached admitted header lifetime"
proc cycle() =
  ## Release fixed source/admission sharing every iteration, including refused state substitutions and failed admissions.
  let done = bindComputedState(source, admission).value
  assert sameStateSnapshot(done.computedStateSnapshot.value, original)
  discard done.computedStateSource.value
  discard done.computedStateAdmission.value
  expect(bindComputedState(source, foreignAdmission), ComputedStateError.StateMismatch)
  expect(bindComputedState(source, failed), ComputedStateError.InvalidAdmission)
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after, "computed state ARC release"
recordArcRelease("pvm_computed_state", 1000, before, after)
echo "PVM computed state passed"
echo "ARC_RELEASE cycles=1000 unchanged"
