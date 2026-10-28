# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## History publication and Keccak refusals preserve retained state; ARC scopes release all
## scratch owners.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

# @@Verification={"arc": "history_transition_arc_release"}

import std/assertions
import std/syncio
import ../../support/state_history_transition_fixture
import ../../support/testing_arc_evidence
import ../../../src/state/history as state_history
import ../../../src/state/store as state_store
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie

## Test-only observer flags independently refuse Blake2b (1) and Keccak (2).
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
## Delay root refusal until private trie construction has begun.
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
## Distinguish failed hashing from validation that must reject before hashing.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

## Small complete-map policy independently controls atomic publication.
proc policy(): StateStoreLimits =
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(2), perValue: ByteLimit(10000),
    totalValueBytes: ByteLimit(20000), nodes: TrieNodeLimit(498)), writes: ElementLimit(1),
        writeValueBytes: ByteLimit(10000))

## Two present peaks force both carry and super-peak Keccak paths after append.
proc initial(): StateEntry =
  let source = HistoryState(blocks: @[HistoryBlock(header: HistoryHeaderHash(historyHash(1)),
      state: HistoryStateRoot(default(array[32, byte])), superPeak: HistorySuperPeak(historyHash(2)),
      slot: HistorySlot(1), packages: @[])],
      peaks: @[presentHistoryPeak(HistoryPeakHash(historyHash(3))), absentHistoryPeak(),
          presentHistoryPeak(HistoryPeakHash(historyHash(4)))])
  historyStateEntry(source, historyConfig()).value

## A validated header projection is separate from mutable store state.
proc input(): HistoryAdvance =
  HistoryAdvance(header: HistoryHeaderHash(historyHash(7)), parentState: HistoryStateRoot(
      historyHash(8)),
    slot: HistorySlot(2), accumulation: AccumulationRoot(historyHash(9)))

## Failed publication must preserve the complete old commitment and both values.
proc unchanged(state: StateStore, before: StateStoreSnapshot, entries: seq[StateEntry]) =
  let current = state.snapshot.value
  assert array[32, byte](current.commitment.root) == array[32, byte](before.commitment.root)
  for entry in entries:
    assert current.lookup(entry.key).value.bytes == entry.value # Includes unrelated state.

## Exercise primitive refusal, late-root rollback and successful recovery within one owner scope.
proc cycle() =
  fail(0)
  let entries = @[initial(), StateEntry(key: chapterKey(StateChapter(11)), value: @[99'u8])]
  let made = newStateStore(entries, policy())
  assert made.error == StateStoreError.None
  var state = made.value
  let before = state.snapshot.value
  fail(2)
  assert advanceHistoryState(state, input(), [], historyConfig()).error ==
      HistoryTransitionError.BackendFailure
  unchanged(state, before, entries)
  fail(1)
  assert advanceHistoryState(state, input(), [], historyConfig()).error ==
      HistoryTransitionError.BackendFailure
  assert hashCalls() == 1
  unchanged(state, before, entries)
  failAfter(2)
  assert advanceHistoryState(state, input(), [], historyConfig()).error ==
      HistoryTransitionError.BackendFailure
  assert hashCalls() == 3
  unchanged(state, before, entries)
  fail(0)
  let committed = advanceHistoryState(state, input(), [], historyConfig())
  assert committed.error == HistoryTransitionError.None
  assert committed.value.lookup(entries[0].key).value.bytes != entries[0].value
  assert committed.value.lookup(entries[1].key).value.bytes == entries[1].value
  assert before.lookup(entries[0].key).value.bytes == entries[0].value

## Reject missing/malformed state and independent budgets without attempting a trie publication.
proc invalid() =
  var defaultStore = default(StateStore)
  assert advanceHistoryState(defaultStore, input(), [], historyConfig()).error ==
      HistoryTransitionError.Uninitialized
  fail(0)
  let empty = newStateStore([], policy())
  var state = empty.value
  assert advanceHistoryState(state, input(), [], historyConfig()).error ==
      HistoryTransitionError.MissingState
  for which in 0..<4:
    fail(0)
    var entry = initial() # Each case starts from fresh independent bytes.
    if which == 0:
      entry.value.add 0 # A valid prefix plus suffix is not complete state.
    elif which == 1:
      entry.value.setLen(entry.value.len-1) # Never pad a truncated peak.
    let entries = @[entry]
    var limits = policy()
    if which == 2:
      limits.writes = ElementLimit(0) # Store policy independently refuses an otherwise valid transition.
    let made = newStateStore(entries, limits)
    assert made.error == StateStoreError.None
    var working = made.value
    let before = working.snapshot.value
    var config = historyConfig()
    if which == 3:
      config.maxBytes = ByteLimit(1) # Refuse before copying or decoding stored bytes.
    fail(1)
    let advanced = advanceHistoryState(working, input(), [], config)
    assert advanced.error == (if which < 2: HistoryTransitionError.InvalidState else: HistoryTransitionError.LimitExceeded)
    assert hashCalls() == 0
    unchanged(working, before, entries)
  fail(2)
  let outputs = @[AccumulationOutput(service: ServiceIndex(0), commitment: OutputCommitment(
      historyHash(1)))]
  let config = OutputLogConfig(items: ElementLimit(2), maxBytes: ByteLimit(1000))
  assert accumulationRoot(outputs, config).error == HistoryTransitionError.BackendFailure
  assert accumulationRoot(@[outputs[0], outputs[0]], config).error ==
      HistoryTransitionError.BackendFailure
  assert accumulationRoot([], config).error == HistoryTransitionError.None # Empty tree has a zero root without hashing.
  # Filling a pre-existing hole without carry can still fail during super-peak bagging.
  let holes = historyOwner(HistoryState(blocks: @[], peaks: @[absentHistoryPeak(),
      presentHistoryPeak(HistoryPeakHash(historyHash(3)))]))
  assert advanceHistory(holes, input(), [], historyConfig()).error ==
      HistoryTransitionError.BackendFailure
  fail(0)

invalid()
for i in 0..<25: cycle() # Warm allocator/runtime paths before observing retained occupancy.
let before = getOccupiedMem()
for i in 0..<1000: cycle() # Every iteration owns and retires success/failure/historical snapshots.
let after = getOccupiedMem()
assert before == after
recordArcRelease("state_history_transition_failure", 1000, before, after)
echo "PASS history transition failures: atomic rollback, Keccak refusal, recovery and ARC release"
