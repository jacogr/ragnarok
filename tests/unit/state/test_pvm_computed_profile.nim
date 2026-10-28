# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "pvm_computed_profile_arc_release"}

## Complete original configured tuple, exact map/parent identity, fixed projections and immutable lifetime.

import std/assertions
import std/syncio
import ../../../src/state/computed_profile as state_computed_profile
import ../../../src/state/computed_lookup as state_computed_lookup
import ../../../src/state/computed_recent as state_computed_recent
import ../../../src/state/store as state_store
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/parameters as chain_parameters
import ../../../src/codec/header as codec_header
import ../../../src/codec/state_trie as codec_state_trie
import ../../support/pvm_computed_profile
import ../../support/pvm_computed_lookup
import ../../support/pvm_computed_lookup_vectors
import ../../support/pvm_computed_state
import ../../support/testing_arc_evidence

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse hashing only after original execution and configured context capture have completed.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Count actual primitive attempts rather than manufacturing successful commitments.
proc expect[T](outcome: ComputedProfileResult[T], reason: ComputedProfileError) =
  ## Compare precise alternatives before guarded application extraction.
  assert outcome.error == reason, "computed profile reason"
var fixture = profileFixture()
let source = fixture.source
let configured = fixture.configured
let original = fixture.state.snapshot.value
# The fixed projection must not duplicate the retained RPC key/service indexes.
let beforeProjection = getOccupiedMem()
let context = configured.blockSnapshotContext
let afterProjection = getOccupiedMem()
assert beforeProjection == afterProjection, "fixed snapshot context projection allocates no indexes"
assert sameStateSnapshot(context.state, original), "exact configured state projection"
assert array[32, byte](context.hash) == ParentHash, "independent full sealed parent identity"
assert context.slot == 20 and uint64(context.validators) == 6, "parent metadata from captured C11/C8"
let done = bindComputedProfile(source, configured).value
assert sameStateSnapshot(done.computedProfileContext.value.state, original), "exact original map binding"
assert uint32(headerInfo(done.computedProfileContext.value.header).value.unsigned.slot) == 20, "original configured parent retained"
assert done.computedProfileSource.value.computedLookupInfo.value.headers == 3, "original anchor provenance retained"
for field in low(Parameter)..high(Parameter):
  assert done.computedProfileContext.value.parameters.get(field) == fixture.parameters.get(field), "every original parameter retained"
  let changed = changedParameter(fixture.parameters, field)
  let alternate = captureBlockSnapshot(lookupWire(fixture.parent), original, changed)
  assert alternate.error == GenesisError.None, "genuine alternative configured context for each field"
  expect(bindComputedProfile(source, alternate), ComputedProfileError.ParameterMismatch)
# Core and epoch matching alone cannot authorize unrelated configured gas/deposit/age/fetch fields.
let changed = changedParameter(fixture.parameters, depositPerItem)
assert changed.get(coreCount) == fixture.parameters.get(coreCount)
assert changed.get(epochPeriod) == fixture.parameters.get(epochPeriod)
let mismatched = captureBlockSnapshot(lookupWire(fixture.parent), original, changed)
let clone = clonedState(original)
assert array[32, byte](clone.snapshot.value.commitment.root) == array[32, byte](
    original.commitment.root), "equal-root complete map"
let foreignState = captureBlockSnapshot(lookupWire(fixture.parent), clone.snapshot.value,
    fixture.parameters)
assert foreignState.error == GenesisError.None, "genuine independently rebuilt context"
expect(bindComputedProfile(source, foreignState), ComputedProfileError.StateMismatch)
let otherParent = alteredLookupHeader(fixture.parent, 201, 44)
let foreignParent = captureBlockSnapshot(lookupWire(otherParent), original, fixture.parameters)
assert foreignParent.error == GenesisError.None, "genuine same-state/config different sealed parent"
expect(bindComputedProfile(source, foreignParent), ComputedProfileError.ParentMismatch)
expect(bindComputedProfile(default(LookupAnchoredComputedReport), configured),
    ComputedProfileError.InvalidSource)
expect(bindComputedProfile(source, default(BlockSnapshotResult)),
    ComputedProfileError.InvalidContext)
expect(bindComputedProfile(source, invalidGenesis()), ComputedProfileError.InvalidContext)
expect(default(ComputedProfileResult[ConfiguredComputedReport]), ComputedProfileError.Uninitialized)
expect(default(ConfiguredComputedReport).computedProfileSource, ComputedProfileError.Uninitialized)
expect(default(ConfiguredComputedReport).computedProfileContext, ComputedProfileError.Uninitialized)
var copied = done.computedProfileContext.value
copied.parameters = changed
copied.state = clone.snapshot.value
copied.hash = BlockHash(default(array[32, byte]))
copied.slot = 99
assert sameStateSnapshot(done.computedProfileContext.value.state, original), "copied facts cannot replace retained state"
assert array[32, byte](done.computedProfileContext.value.hash) == ParentHash, "copied facts cannot replace parent identity"
assert done.computedProfileContext.value.parameters.get(depositPerItem) == fixture.parameters.get(
    depositPerItem), "copied facts cannot replace configured parameters"
changeState(fixture.state)
assert not sameStateSnapshot(fixture.state.snapshot.value, original), "caller state advanced"
assert sameStateSnapshot(done.computedProfileContext.value.state, original), "completed owner retains original version"
reset(1)
expect(bindComputedProfile(source, configured), ComputedProfileError.None)
expect(bindComputedProfile(source, mismatched), ComputedProfileError.ParameterMismatch)
expect(bindComputedProfile(source, foreignState), ComputedProfileError.StateMismatch)
expect(bindComputedProfile(source, foreignParent), ComputedProfileError.ParentMismatch)
discard configured.blockSnapshotContext
assert hashes() == 0, "projection and profile binding perform no hashes"
reset(0)
proc detached(): ConfiguredComputedReport =
  ## Preserve exact original source/map/header/parameters after the complete snapshot and RPC indexes retire.
  let fixture = profileFixture()
  bindComputedProfile(fixture.source, fixture.configured).value
let retained = detached()
assert array[32, byte](retained.computedProfileContext.value.hash) == ParentHash, "detached parent context lifetime"
assert retained.computedProfileSource.value.computedLookupInfo.value.headers == 3, "detached source lifetime"
proc cycle() =
  ## Release fixed ownership and refused alternatives while projecting only immutable fixed facts.
  let value = bindComputedProfile(source, configured).value
  assert sameStateSnapshot(value.computedProfileContext.value.state, original)
  discard value.computedProfileSource.value
  discard configured.blockSnapshotContext
  expect(bindComputedProfile(source, mismatched), ComputedProfileError.ParameterMismatch)
  expect(bindComputedProfile(source, foreignState), ComputedProfileError.StateMismatch)
  expect(bindComputedProfile(source, foreignParent), ComputedProfileError.ParentMismatch)
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after, "computed profile ARC release"
recordArcRelease("pvm_computed_profile", 1000, before, after)
echo "PVM computed profile passed"
echo "ARC_RELEASE cycles=1000 unchanged"
