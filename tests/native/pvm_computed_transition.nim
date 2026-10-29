# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict optimized transition extraction guards with genuine signed success controls.

import std/[assertions, cmdline]
import ../../src/state/computed/[transition as computed_transition, profile as computed_profile]
import "../../src/state/block/transition" as block_transition
import ../../src/state/store
import ../../src/codec/[bounded, block_codec, header]
import ../../src/chain/parameters
import ../support/[pvm_computed_transition, pvm_computed_state, pvm_computed_profile,
  report_admission_context]

proc expect[T](outcome: ComputedTransitionResult[T], reason: ComputedTransitionError) =
  ## Verify selected failure identity before deliberately reading its absent payload.
  assert outcome.error == reason, "transition runtime control"
let fixture = transitionFixture()
let done = bindComputedTransition(fixture.source, fixture.context.staged, ByteLimit(4096))
expect(done, ComputedTransitionError.None)
assert sameStateSnapshot(done.value.computedTransitionStage.value.value.snapshot,
    fixture.context.staged.value.snapshot), "genuine posterior success control"
let missing = default(ComputedTransitionResult[TransitionBoundComputedReport])
let source = bindComputedTransition(default(ConfiguredComputedReport), fixture.context.staged,
    ByteLimit(4096))
expect(source, ComputedTransitionError.InvalidSource)
let transition = bindComputedTransition(fixture.source, default(BlockTransitionResult), ByteLimit(4096))
expect(transition, ComputedTransitionError.InvalidTransition)
var clone = clonedState(fixture.context.original.snapshot.value)
let cloned = stage(clone, fixture.context.candidate, fixture.context.parent)
assert cloned.error == BlockTransitionError.None, "genuine cloned transition control"
let state = bindComputedTransition(fixture.source, cloned, ByteLimit(4096))
expect(state, ComputedTransitionError.StateMismatch)
var execution = fixture.execution
execution.parameters = changedParameter(execution.parameters, maxTicketsPerBlock)
let alternate = transitionSource(fixture.context, execution, fixture.context.candidate)
let profile = bindComputedTransition(alternate, fixture.context.staged, ByteLimit(4096))
expect(profile, ComputedTransitionError.ProfileMismatch)
let boundedOutcome = bindComputedTransition(fixture.source, fixture.context.staged, ByteLimit(0))
expect(boundedOutcome, ComputedTransitionError.LimitExceeded)
var wire = newSeq[byte](blockInfo(fixture.context.candidate).value.consumed)
assert encodeOwnedBlock(fixture.context.candidate, wire).error == FrameError.None
let extent = headerInfo(fixture.context.staged.value.admitted.admittedHeader).value.consumed
wire[extent-1] = wire[extent-1] xor 1
let other = decodeBlock(wire, frame().frame).value.owner
let sealed = transitionSource(fixture.context, fixture.execution, other)
let candidate = bindComputedTransition(sealed, fixture.context.staged, ByteLimit(4096))
expect(candidate, ComputedTransitionError.HeaderMismatch)
case paramStr(1)
of "default": discard missing.value # Default alternatives contain no application data.
of "source": discard source.value # No original configured provenance.
of "transition": discard transition.value # No successful authenticated coordinator.
of "state": discard state.value # Equal roots cannot replace original identity.
of "profile": discard profile.value # Original framing differs.
of "bounded": discard boundedOutcome.value # Header copies exceed the independent byte ceiling.
of "candidate": discard candidate.value # Full sealed identity differs.
of "owner": discard default(TransitionBoundComputedReport).computedTransitionSource.value # No source owner.
else: discard default(TransitionBoundComputedReport).computedTransitionStage.value # No posterior stage.
