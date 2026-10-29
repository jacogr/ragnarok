# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "pvm_computed_transition_arc_release"}

## Exact authenticated candidate and posterior provenance, rejection boundaries and ARC lifetime.

import std/[assertions, syncio]
import ../../../src/state/computed/[transition as computed_transition, profile as computed_profile,
    lookup as computed_lookup]
import "../../../src/state/block/transition" as block_transition
import "../../../src/state/block/admission" as block_admission
import ../../../src/state/store
import ../../../src/codec/[bounded, header, block_codec]
import ../../../src/codec/state/[layout as state_layout, safrole as state_safrole]
import ../../../src/chain/parameters
import ../../support/[pvm_computed_transition, pvm_computed_profile, pvm_computed_state,
  report_admission_context, arc_evidence]

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse hashing after genuine signed authentication and original execution complete.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe real primitive attempts at the composition boundary.
proc expect[T](outcome: ComputedTransitionResult[T], reason: ComputedTransitionError) =
  ## Compare precise selected reasons before application extraction.
  assert outcome.error == reason, "computed transition reason: " & $outcome.error
let fixture = transitionFixture()
let source = fixture.source
let staged = fixture.context.staged
let original = fixture.context.original.snapshot.value
let posterior = staged.value.snapshot
let extent = headerInfo(staged.value.admitted.admittedHeader).value.consumed
let limit = ByteLimit(uint64(extent))
let completed = bindComputedTransition(source, staged, limit)
expect(completed, ComputedTransitionError.None)
let done = completed.value
assert sameStateSnapshot(done.computedTransitionStage.value.value.snapshot, posterior), "exact posterior identity"
assert sameStateSnapshot(done.computedTransitionSource.value.computedProfileContext.value.state,
    original), "original configured execution identity"
assert not sameStateSnapshot(original, posterior), "actual authenticated prefix advances state"
expect(bindComputedTransition(source, staged, ByteLimit(uint64(extent-1))),
    ComputedTransitionError.LimitExceeded)
expect(bindComputedTransition(source, staged, ByteLimit(0)), ComputedTransitionError.LimitExceeded)
expect(bindComputedTransition(default(ConfiguredComputedReport), staged, limit),
    ComputedTransitionError.InvalidSource)
expect(bindComputedTransition(source, default(BlockTransitionResult), limit),
    ComputedTransitionError.InvalidTransition)
expect(default(ComputedTransitionResult[TransitionBoundComputedReport]),
    ComputedTransitionError.Uninitialized)
expect(default(TransitionBoundComputedReport).computedTransitionSource,
    ComputedTransitionError.Uninitialized)
expect(default(TransitionBoundComputedReport).computedTransitionStage,
    ComputedTransitionError.Uninitialized)
# Equal-root reconstructed maps are genuine inputs to the coordinator but cannot replace original execution identity.
var clone = clonedState(original)
assert array[32, byte](clone.snapshot.value.commitment.root) == array[32, byte](
    original.commitment.root)
let clonedStage = stage(clone, fixture.context.candidate, fixture.context.parent)
assert clonedStage.error == BlockTransitionError.None, "genuine equal-root cloned transition"
expect(bindComputedTransition(source, clonedStage, limit), ComputedTransitionError.StateMismatch)
# A distinct correctly signed child of the same parent/map cannot donate posterior state to this computed source.
var otherOptions = fixture.options
otherOptions.targetSlot = 3
let other = authored(fixture.base, otherOptions)
var sameOriginal = fixture.context.original
let otherStage = stage(sameOriginal, other.candidate, fixture.context.parent)
assert otherStage.error == BlockTransitionError.None, "genuine same-map different signed candidate"
expect(bindComputedTransition(source, otherStage, ByteLimit(4096)),
    ComputedTransitionError.HeaderMismatch)
# Syntactic admission alone can retain a changed opaque seal; authenticated binding must compare those bytes too.
var wire = newSeq[byte](blockInfo(fixture.context.candidate).value.consumed)
assert encodeOwnedBlock(fixture.context.candidate, wire).error == FrameError.None
wire[extent-1] = wire[extent-1] xor 1
let replaced = decodeBlock(wire, frame().frame).value.owner
let sealSource = transitionSource(fixture.context, fixture.execution, replaced)
expect(bindComputedTransition(sealSource, staged, limit), ComputedTransitionError.HeaderMismatch)
# All original configuration is retained, and a mismatched transition framing ceiling cannot replace it.
var changedExecution = fixture.execution
changedExecution.parameters = changedParameter(changedExecution.parameters, maxTicketsPerBlock)
let otherProfile = transitionSource(fixture.context, changedExecution, fixture.context.candidate)
expect(bindComputedTransition(otherProfile, staged, limit), ComputedTransitionError.ProfileMismatch)
var wrongOriginal = fixture.context.original
changeState(wrongOriginal)
let failed = stage(wrongOriginal, fixture.context.candidate, fixture.context.parent)
assert failed.error == BlockTransitionError.AdmissionFailure, "genuine root refusal"
expect(bindComputedTransition(source, failed, limit), ComputedTransitionError.InvalidTransition)
# Public payload copies cannot alter the private successful result retained by the new owner.
var copied = done.computedTransitionStage.value.value
copied.snapshot = original
copied.admitted = otherStage.value.admitted
assert sameStateSnapshot(done.computedTransitionStage.value.value.snapshot, posterior), "copied payload isolation"
reset(1)
expect(bindComputedTransition(source, staged, limit), ComputedTransitionError.None)
expect(bindComputedTransition(source, clonedStage, limit), ComputedTransitionError.StateMismatch)
expect(bindComputedTransition(sealSource, staged, limit), ComputedTransitionError.HeaderMismatch)
assert hashes() == 0, "binding performs no hashing or authentication replay"
reset(0)
# Epoch crossing must preserve the exact posterior owner, including its independently changed active identities.
let epoch = transitionFixture(epoch = true)
let crossing = bindComputedTransition(epoch.source, epoch.context.staged, ByteLimit(4096)).value
let beforeKeys = original.lookup(chapterKey(StateChapter(8))).value.bytes
let afterKeys = crossing.computedTransitionStage.value.value.snapshot.lookup(chapterKey(
    StateChapter(8))).value.bytes
assert beforeKeys != afterKeys, "genuine epoch-crossing posterior active roster differs"
proc detached(): TransitionBoundComputedReport =
  ## Preserve original and posterior owners after all local mutable source handles retire.
  let fixture = transitionFixture()
  bindComputedTransition(fixture.source, fixture.context.staged, ByteLimit(4096)).value
let retained = detached()
assert uint32(headerInfo(retained.computedTransitionStage.value.value.admitted.admittedHeader).value.unsigned.slot) == 2
var caller = fixture.context.original
changeState(caller)
assert sameStateSnapshot(done.computedTransitionSource.value.computedProfileContext.value.state, original)
proc cycle(source: ConfiguredComputedReport, staged, cloned: BlockTransitionResult,
    limit: ByteLimit) =
  ## Retire successful shared provenance and refused alternatives without replaying execution/authentication.
  let value = bindComputedTransition(source, staged, limit).value
  discard value.computedTransitionSource.value
  discard value.computedTransitionStage.value
  expect(bindComputedTransition(source, cloned, limit), ComputedTransitionError.StateMismatch)
cycle(source, staged, clonedStage, limit)
let before = getOccupiedMem()
for iteration in 0..<1000: cycle(source, staged, clonedStage, limit)
let after = getOccupiedMem()
assert before == after, "computed transition ARC release"
recordArcRelease("pvm_computed_transition", 1000, before, after)
echo "PVM computed transition passed"
echo "ARC_RELEASE cycles=1000 unchanged"
