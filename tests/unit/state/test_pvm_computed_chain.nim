# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "pvm_computed_chain_arc_release"}

## Genuine computed publication and direct-child capture advance both live handles or preserve both on every selected refusal.

import std/assertions
import std/syncio
import ../../../src/state/computed_chain as state_computed_chain
import ../../../src/state/computed_composition as state_computed_composition
import ../../../src/state/computed_state_publication as state_computed_state_publication
import ../../../src/state/accumulation_consensus as state_accumulation_consensus
import ../../../src/state/store as state_store
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/provider as chain_provider
import ../../../src/chain/parameters as chain_parameters
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../support/pvm_computed_chain
import ../../support/pvm_computed_state_publication
import ../../support/testing_arc_evidence

proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Force real late child capture to fail after private state publication succeeds.
let source = chainFixture()
let parent = source.chainFixtureParent(source.chainFixtureParameters)
assert parent.error == GenesisError.None
assert uint64(parent.value.activeValidators) == 9
let candidate = source.computedCompositionPlan.value.accumulationConsensusState.value
let initial = genesisView(parent).finalizeView(parent.value.blockHash).value
proc unchanged(state: StateStore, view: ChainView, before: StateStoreSnapshot, prior: ChainView) =
  ## Verify exact state owner, whole retained view and explicit finality after every refusing phase.
  assert sameStateSnapshot(state.snapshot.value, before)
  assert sameChainView(view, prior)
var target = forkStateStore(parent.value.stateSnapshot).value
var view = initial
let alias = target
let oldView = view
let done = advanceComputedChain(target, view, source)
if done.error != ComputedChainError.None: echo "chain advance ", done.error
assert done.error == ComputedChainError.None
let receipt = done.value
let child = receipt.computedChainBlock.value
assert child.slot == 2
assert uint64(child.activeValidators) == 9
assert sameStateSnapshot(target.snapshot.value, candidate)
assert sameStateSnapshot(child.stateSnapshot, candidate)
assert sameStateSnapshot(receipt.computedChainPublication.value.computedPublishedSnapshot.value, candidate)
assert array[32, byte](view.bestBlock.value.blockHash) == array[32, byte](child.blockHash)
assert array[32, byte](child.parentHash) == array[32, byte](parent.value.blockHash)
assert array[32, byte](child.priorStateRoot) == array[32, byte](parent.value.stateRoot)
assert view.retainedCount == 2
assert array[32, byte](view.finalizedBlock.value.blockHash) == array[32, byte](
    parent.value.blockHash)
assert sameStateSnapshot(alias.snapshot.value, parent.value.stateSnapshot)
assert sameChainView(oldView, initial)
assert target.snapshot.value.lookup(chapterKey(StateChapter(16))).value.bytes == @[0'u8]
let installedView = view
let replay = advanceComputedChain(target, view, source)
assert replay.error == ComputedChainError.StaleState
unchanged(target, view, candidate, installedView)
var fresh = forkStateStore(parent.value.stateSnapshot).value
var freshView = initial
assert advanceComputedChain(fresh, freshView, default(ComposedComputedState)).error ==
    ComputedChainError.InvalidSource
unchanged(fresh, freshView, parent.value.stateSnapshot, initial)
var empty = default(StateStore)
let missing = advanceComputedChain(empty, freshView, source)
assert missing.error == ComputedChainError.StateFailure
assert missing.stateError == StateStoreError.Uninitialized
assert empty.snapshot.error == StateStoreError.Uninitialized
assert sameChainView(freshView, initial)
var absentView = default(ChainView)
assert advanceComputedChain(fresh, absentView, source).error == ComputedChainError.UninitializedView
assert sameStateSnapshot(fresh.snapshot.value, parent.value.stateSnapshot)
assert absentView.retainedCount == 0
let key = chapterKey(StateChapter(13))
var equalRoot = forkStateStore(parent.value.stateSnapshot).value
assert equalRoot.apply([StateWrite(kind: StateWriteKind.Put, key: key,
    value: equalRoot.snapshot.value.lookup(key).value.bytes)]).error == StateStoreError.None
assert array[32, byte](equalRoot.snapshot.value.commitment.root) == array[32, byte](
    parent.value.stateRoot)
let differentOwner = equalRoot.snapshot.value
assert advanceComputedChain(equalRoot, freshView, source).error == ComputedChainError.StaleState
unchanged(equalRoot, freshView, differentOwner, initial)
var staleView = genesisView(captureBlockSnapshot(chainHeaderBytes(parent.value.header),
    differentOwner, source.chainFixtureParameters))
let staleViewBefore = staleView
assert advanceComputedChain(fresh, staleView, source).error == ComputedChainError.StaleView
unchanged(fresh, staleView, parent.value.stateSnapshot, staleViewBefore)
var parameterWire = source.chainFixtureParameters.encodeParameters
parameterWire[58] = parameterWire[58] xor 1 # Actual block gas changes while header framing domains remain identical.
let otherParameters = decodeParameters(parameterWire).value
var wrongParameters = genesisView(source.chainFixtureParent(otherParameters))
let wrongParametersBefore = wrongParameters
assert advanceComputedChain(fresh, wrongParameters, source).error ==
    ComputedChainError.ParametersMismatch
unchanged(fresh, wrongParameters, parent.value.stateSnapshot, wrongParametersBefore)
failHash(1)
let late = advanceComputedChain(fresh, freshView, source)
assert late.error == ComputedChainError.CaptureFailure
assert late.captureError == GenesisError.Invalid
unchanged(fresh, freshView, parent.value.stateSnapshot, initial)
failHash(0)
var changedHeader = chainHeaderBytes(parent.value.header)
changedHeader[0] = changedHeader[0] xor 1 # Real structural capture of another parent identity cannot authorize this actual direct child.
var otherParent = genesisView(captureBlockSnapshot(changedHeader, parent.value.stateSnapshot,
    source.chainFixtureParameters))
let otherParentBefore = otherParent
let notChild = advanceComputedChain(fresh, otherParent, source)
assert notChild.error == ComputedChainError.ViewFailure
assert notChild.viewError == ViewAdvanceError.NotChild
unchanged(fresh, otherParent, parent.value.stateSnapshot, otherParentBefore)
let bounded = chainFixture(coherent = false)
let boundedParent = bounded.chainFixtureParent(bounded.chainFixtureParameters)
assert boundedParent.error == GenesisError.None
var boundedState = forkStateStore(boundedParent.value.stateSnapshot).value
var boundedView = genesisView(boundedParent)
let boundedBefore = boundedView
assert advanceComputedChain(boundedState, boundedView, bounded).error ==
    ComputedChainError.ProfileMismatch
unchanged(boundedState, boundedView, boundedParent.value.stateSnapshot, boundedBefore)
assert advanceComputedChain(fresh, freshView, source).error == ComputedChainError.None
assert sameStateSnapshot(fresh.snapshot.value, candidate)
assert default(AdvancedComputedChain).computedChainPublication.error ==
    ComputedChainError.Uninitialized
assert default(AdvancedComputedChain).computedChainBlock.error == ComputedChainError.Uninitialized
var copied = receipt.computedChainPublication.value
copied = default(PublishedComputedState)
assert sameStateSnapshot(receipt.computedChainPublication.value.computedPublishedSnapshot.value, candidate)
proc detached(): AdvancedComputedChain =
  ## Actual installed child retains its state, original computation and sealed-header owner after all live fixture handles retire.
  let local = chainFixture()
  let retained = local.chainFixtureParent(local.chainFixtureParameters)
  var canonical = forkStateStore(retained.value.stateSnapshot).value
  var selected = genesisView(retained)
  advanceComputedChain(canonical, selected, local).value
let held = detached()
assert held.computedChainBlock.value.slot == 2
assert held.computedChainBlock.value.stateSnapshot.lookup(chapterKey(StateChapter(
    16))).value.bytes == @[0'u8]
proc cycle() =
  ## Release fresh receipts, captured child indexes, private publication and view histories per successful/refused iteration.
  var canonical = forkStateStore(parent.value.stateSnapshot).value
  var selected = initial
  let advanced = advanceComputedChain(canonical, selected, source)
  assert advanced.error == ComputedChainError.None
  assert sameStateSnapshot(advanced.value.computedChainBlock.value.stateSnapshot, candidate)
  assert advanceComputedChain(canonical, selected, source).error == ComputedChainError.StaleState
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle() # Child/header/index owners and independent immutable chain histories retire every cycle.
let after = getOccupiedMem()
assert before == after, "computed chain ARC release"
recordArcRelease("pvm_computed_chain", 1000, before, after)
echo "PVM computed chain passed"
echo "ARC_RELEASE cycles=1000 unchanged"
