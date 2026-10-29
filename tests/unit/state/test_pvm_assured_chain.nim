# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "pvm_assured_chain_arc_release"}

## Actual assured successor publication installs both handles together or preserves both through every selected refusal.

import std/[assertions, syncio]
import ../../../src/state/assured/[chain as assured_chain, composition as assured_composition]
import ../../../src/state/accumulation/[consensus as accumulation_consensus,
    finalization as accumulation_finalization]
import ../../../src/state/store
import ../../../src/chain/[genesis, provider, parameters]
import ../../../src/codec/bounded
import ../../../src/codec/state/[layout as state_layout, trie as state_trie,
    accounts as state_accounts, service_values as state_service_values]
import ../../support/[pvm_assured_chain, pvm_computed_chain, arc_evidence]

proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Force actual structural capture to fail after prepared state adoption succeeds privately.
proc expect[T](outcome: AssuredChainResult[T], reason: AssuredChainError) =
  ## Print an originating selected cause on unexpected refusal before enforcing exact outcome selection.
  if outcome.error != reason:
    echo "expected ", reason, " got ", outcome.error
    if outcome.error == AssuredChainError.CaptureFailure: echo "capture ", outcome.captureError
    if outcome.error == AssuredChainError.ViewFailure: echo "view ", outcome.viewError
  assert outcome.error == reason, "assured chain reason"
proc unchanged(state: StateStore, view: ChainView, before: StateStoreSnapshot, prior: ChainView) =
  ## Refusal preserves exact state identity, retained headers and explicit caller-certified finality.
  assert sameStateSnapshot(state.snapshot.value, before)
  assert sameChainView(view, prior)
proc metadata(state: StateStoreSnapshot): ServiceMetadata =
  ## Decode the actual adopted service record without substituting copied metadata observations.
  decodeServiceMetadata(state.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(
      42))).value.bytes, ByteLimit(ServiceMetadataBytes)).value.metadata
let source = assuredChainFixture()
let seed = source.assuredChainSeed
let parent = seed.view.bestBlock.value
let original = seed.state.snapshot.value
let initial = seed.view
let candidate = source.assuredCompositionPlan.value.accumulationConsensusState.value
assert parent.slot == 2 and uint64(parent.activeValidators) == 9
assert sameStateSnapshot(parent.stateSnapshot, original)
assert uint32(metadata(original).lastAccumulation) == 2
var target = seed.state
var view = initial
let alias = target
let oldView = view
let outcome = advanceAssuredChain(target, view, source)
expect(outcome, AssuredChainError.None)
let receipt = outcome.value
let child = receipt.assuredChainBlock.value
assert child.slot == 3 and uint64(child.activeValidators) == 9
assert sameStateSnapshot(target.snapshot.value, candidate)
assert sameStateSnapshot(child.stateSnapshot, candidate)
assert sameStateSnapshot(receipt.assuredChainSnapshot.value, candidate)
assert sameStateSnapshot(receipt.assuredChainSource.value.assuredCompositionPlan.value.accumulationConsensusState.value, candidate)
assert sameStateSnapshot(view.bestBlock.value.stateSnapshot, candidate)
assert array[32, byte](view.bestBlock.value.blockHash) == array[32, byte](child.blockHash)
assert array[32, byte](child.parentHash) == array[32, byte](parent.blockHash)
assert array[32, byte](child.priorStateRoot) == array[32, byte](parent.stateRoot)
assert view.retainedCount == 3
assert view.finalizedBlock.value.slot == 1
assert array[32, byte](view.finalizedBlock.value.blockHash) == array[32, byte](
    initial.finalizedBlock.value.blockHash)
assert uint32(metadata(child.stateSnapshot).lastAccumulation) == 3
let key = serviceStorageKey(ServiceIndex(42), @[11'u8], ByteLimit(1)).value
assert child.stateSnapshot.lookup(key).value.bytes == @[21'u8, 22, 23]
for field in low(Parameter)..high(Parameter):
  assert child.chainParameters.get(field) == source.assuredCompositionParameters.value.get(
      field) # Structural capture retains the entire original chain tuple.
assert sameStateSnapshot(alias.snapshot.value, original)
assert uint32(metadata(alias.snapshot.value).lastAccumulation) == 2
assert sameChainView(oldView, initial)
let installed = view
let replay = advanceAssuredChain(target, view, source)
expect(replay, AssuredChainError.StaleState)
unchanged(target, view, candidate, installed)
var fresh = seed.state
var freshView = initial
expect(advanceAssuredChain(fresh, freshView, default(ComposedAssuredState)),
    AssuredChainError.InvalidSource)
unchanged(fresh, freshView, original, initial)
var absentState = default(StateStore)
let missing = advanceAssuredChain(absentState, freshView, source)
expect(missing, AssuredChainError.StateFailure)
assert missing.stateError == StateStoreError.Uninitialized
assert absentState.snapshot.error == StateStoreError.Uninitialized
assert sameChainView(freshView, initial)
var absentView = default(ChainView)
expect(advanceAssuredChain(fresh, absentView, source), AssuredChainError.UninitializedView)
assert sameStateSnapshot(fresh.snapshot.value, original) and absentView.retainedCount == 0
var equalRoot = seed.state
let chapter = chapterKey(StateChapter(13))
assert equalRoot.apply([StateWrite(kind: StateWriteKind.Put, key: chapter, value: original.lookup(
    chapter).value.bytes)]).error == StateStoreError.None
let otherOwner = equalRoot.snapshot.value
assert array[32, byte](otherOwner.commitment.root) == array[32, byte](original.commitment.root)
assert not sameStateSnapshot(otherOwner, original)
expect(advanceAssuredChain(equalRoot, freshView, source), AssuredChainError.StaleState)
unchanged(equalRoot, freshView, otherOwner, initial)
let structuralOther = captureBlockSnapshot(chainHeaderBytes(parent.header), otherOwner,
    source.assuredCompositionParameters.value)
assert structuralOther.error == GenesisError.None
var staleView = genesisView(structuralOther)
let beforeStaleView = staleView
expect(advanceAssuredChain(fresh, staleView, source), AssuredChainError.StaleView)
unchanged(fresh, staleView, original, beforeStaleView)
var parameterWire = source.assuredCompositionParameters.value.encodeParameters
parameterWire[58] = parameterWire[58] xor 1 # Change actual block gas while preserving all header framing domains.
let otherParameters = decodeParameters(parameterWire).value
let structuralParameters = captureBlockSnapshot(chainHeaderBytes(parent.header), original,
    otherParameters)
assert structuralParameters.error == GenesisError.None
var wrongParameters = genesisView(structuralParameters)
let beforeParameters = wrongParameters
expect(advanceAssuredChain(fresh, wrongParameters, source), AssuredChainError.ParametersMismatch)
unchanged(fresh, wrongParameters, original, beforeParameters)
failHash(1)
let capture = advanceAssuredChain(fresh, freshView, source)
expect(capture, AssuredChainError.CaptureFailure)
assert capture.captureError == GenesisError.Invalid
unchanged(fresh, freshView, original, initial)
failHash(0)
var wrongHeader = chainHeaderBytes(parent.header)
wrongHeader[0] = wrongHeader[0] xor 1 # A different structurally captured head cannot authorize the authentic next child's parent identity.
let structuralWrong = captureBlockSnapshot(wrongHeader, original,
    source.assuredCompositionParameters.value)
assert structuralWrong.error == GenesisError.None
var wrongParent = genesisView(structuralWrong)
let beforeWrongParent = wrongParent
let append = advanceAssuredChain(fresh, wrongParent, source)
expect(append, AssuredChainError.ViewFailure)
assert append.viewError == ViewAdvanceError.NotChild
unchanged(fresh, wrongParent, original, beforeWrongParent)
expect(advanceAssuredChain(fresh, freshView, source), AssuredChainError.None)
assert sameStateSnapshot(fresh.snapshot.value, candidate)
let emptySource = assuredChainFixture(votes = 6)
let emptySeed = emptySource.assuredChainSeed
var emptyState = emptySeed.state
var emptyView = emptySeed.view
let empty = advanceAssuredChain(emptyState, emptyView, emptySource)
expect(empty, AssuredChainError.None)
assert empty.value.assuredChainBlock.value.slot == 3 and emptyView.retainedCount == 3
assert uint32(metadata(emptyState.snapshot.value).lastAccumulation) == 2
assert emptyState.snapshot.value.lookup(chapterKey(StateChapter(10))).value.bytes ==
    emptySeed.state.snapshot.value.lookup(chapterKey(StateChapter(10))).value.bytes
expect(default(AdvancedAssuredChain).assuredChainSource, AssuredChainError.Uninitialized)
expect(default(AdvancedAssuredChain).assuredChainSnapshot, AssuredChainError.Uninitialized)
expect(default(AdvancedAssuredChain).assuredChainBlock, AssuredChainError.Uninitialized)
var copied = receipt.assuredChainSnapshot.value
copied = default(StateStoreSnapshot)
assert sameStateSnapshot(receipt.assuredChainSnapshot.value, candidate)
proc detached(): AdvancedAssuredChain =
  ## Retain real slot3 state/header/source authority after all live preparation and predecessor handles retire.
  let source = assuredChainFixture()
  let seed = source.assuredChainSeed
  var state = seed.state
  var view = seed.view
  advanceAssuredChain(state, view, source).value
let held = detached()
assert held.assuredChainBlock.value.slot == 3
assert uint32(metadata(held.assuredChainSnapshot.value).lastAccumulation) == 3
proc cycle(source: ComposedAssuredState, seed: AssuredChainSeed) =
  ## Release actual successful publication/capture and a late capture refusal while both original handles stay stable.
  var state = seed.state
  var view = seed.view
  let done = advanceAssuredChain(state, view, source).value
  discard done.assuredChainSource.value
  discard done.assuredChainSnapshot.value
  var refusedState = seed.state
  var refusedView = seed.view
  failHash(1)
  let late = advanceAssuredChain(refusedState, refusedView, source)
  expect(late, AssuredChainError.CaptureFailure)
  failHash(0)
  unchanged(refusedState, refusedView, seed.state.snapshot.value, seed.view)
cycle(source, seed)
let before = getOccupiedMem()
for iteration in 0..<1000: cycle(source, seed) # Every actual captured child and refused private publication retires without guest replay.
let after = getOccupiedMem()
assert before == after, "assured chain ARC release"
recordArcRelease("pvm_assured_chain", 1000, before, after)
echo "PVM assured chain passed"
echo "ARC_RELEASE cycles=1000 unchanged"
