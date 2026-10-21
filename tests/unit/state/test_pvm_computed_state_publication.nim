# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "pvm_computed_state_publication_arc_release"}

## Exact-parent publication retains original computed work and the whole prepared state without hashing or guest replay.

import std/[assertions, syncio]
import ../../../src/state/[computed_state_publication, computed_composition, accumulation_consensus,
    accumulation_block_publication, store]
import ../../../src/codec/[state_layout, state_trie]
import ../../support/[pvm_computed_state_publication, arc_evidence]

proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse hashing after genuine composition so publication cannot hide replay or reconstruction.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe the maintained primitive independently of state identity assertions.
let source = statePublicationFixture()
let parent = source.statePublicationParent
let candidate = source.computedCompositionPlan.value.accumulationConsensusState.value
var target = forkStateStore(parent).value
let alias = target
let history = parent.lookup(chapterKey(StateChapter(13))).value
let historyBytes = history.bytes
failHash(1)
let result = publishComputedState(target, source)
assert result.error == ComputedStatePublicationError.None
let receipt = result.value
assert sameStateSnapshot(target.snapshot.value, candidate)
assert sameStateSnapshot(receipt.computedPublishedSnapshot.value, candidate)
assert sameStateSnapshot(receipt.computedPublishedSource.value.statePublicationParent, parent)
assert sameStateSnapshot(alias.snapshot.value, parent)
assert history.bytes == historyBytes
assert hashCalls() == 0
let replay = publishComputedState(target, source)
assert replay.error == ComputedStatePublicationError.PublicationFailure
assert replay.publicationFailure.error == AccumulationPublicationError.StaleState
assert sameStateSnapshot(target.snapshot.value, candidate)
var empty = default(StateStore)
let refused = publishComputedState(empty, source)
assert refused.error == ComputedStatePublicationError.PublicationFailure
assert refused.publicationFailure.error == AccumulationPublicationError.StateFailure
assert refused.publicationFailure.stateError == StateStoreError.Uninitialized
assert empty.snapshot.error == StateStoreError.Uninitialized
var fresh = forkStateStore(parent).value
assert publishComputedState(fresh, default(ComposedComputedState)).error ==
    ComputedStatePublicationError.InvalidSource
assert sameStateSnapshot(fresh.snapshot.value, parent)
assert hashCalls() == 0
failHash(0)
proc stale(target: var StateStore) =
  ## Every wrong owner refuses before mutation, even when hashing cannot work.
  let before = target.snapshot.value
  failHash(1)
  let refused = publishComputedState(target, source)
  assert refused.error == ComputedStatePublicationError.PublicationFailure
  assert refused.publicationFailure.error == AccumulationPublicationError.StaleState
  assert sameStateSnapshot(target.snapshot.value, before)
  assert hashCalls() == 0
  failHash(0)
var equalRoot = forkStateStore(parent).value
let key = chapterKey(StateChapter(13))
assert equalRoot.apply([StateWrite(kind: StateWriteKind.Put, key: key,
    value: historyBytes)]).error == StateStoreError.None
assert array[32, byte](equalRoot.snapshot.value.commitment.root) == array[32, byte](
    parent.commitment.root)
assert not sameStateSnapshot(equalRoot.snapshot.value, parent)
stale(equalRoot)
var changed = forkStateStore(parent).value
assert changed.apply([StateWrite(kind: StateWriteKind.Put, key: key, value: @[0'u8])]).error ==
    StateStoreError.None
stale(changed)
var prepared = forkStateStore(candidate).value
stale(prepared)
assert publishComputedState(fresh, source).error == ComputedStatePublicationError.None
assert sameStateSnapshot(fresh.snapshot.value, candidate)
assert fresh.snapshot.value.lookup(chapterKey(StateChapter(10))).value.bytes == candidate.lookup(
    chapterKey(StateChapter(10))).value.bytes
assert fresh.snapshot.value.lookup(chapterKey(StateChapter(16))).value.bytes == @[0'u8]
var copied = receipt.computedPublishedSnapshot.value
copied = default(StateStoreSnapshot)
assert sameStateSnapshot(receipt.computedPublishedSnapshot.value, candidate)
assert default(PublishedComputedState).computedPublishedSource.error ==
    ComputedStatePublicationError.Uninitialized
assert default(PublishedComputedState).computedPublishedSnapshot.error ==
    ComputedStatePublicationError.Uninitialized
proc detached(): PublishedComputedState =
  ## Keep provenance and adopted map alive after every preparation and target handle leaves scope.
  let local = statePublicationFixture()
  var canonical = forkStateStore(local.statePublicationParent).value
  publishComputedState(canonical, local).value
let held = detached()
assert held.computedPublishedSnapshot.value.lookup(chapterKey(StateChapter(16))).value.bytes == @[0'u8]
proc cycle() =
  ## Release independent receipt, target, replay and missing-target refusals on each bounded iteration.
  var canonical = forkStateStore(parent).value
  failHash(1)
  let done = publishComputedState(canonical, source)
  assert done.error == ComputedStatePublicationError.None
  assert sameStateSnapshot(done.value.computedPublishedSnapshot.value, candidate)
  assert publishComputedState(canonical, source).publicationFailure.error ==
      AccumulationPublicationError.StaleState
  var missing = default(StateStore)
  assert publishComputedState(missing, source).publicationFailure.stateError ==
      StateStoreError.Uninitialized
  assert hashCalls() == 0
  failHash(0)
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle() # New receipts share only immutable original authority and retire each iteration.
let after = getOccupiedMem()
assert before == after, "computed state publication ARC release"
recordArcRelease("pvm_computed_state_publication", 1000, before, after)
echo "PVM computed state publication passed"
echo "ARC_RELEASE cycles=1000 unchanged"
