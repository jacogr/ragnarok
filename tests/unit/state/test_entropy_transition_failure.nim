## Fixed-size entropy/time failures preserve both chapters and all retained historical owners.
import std/[assertions, syncio]
import ../../support/[entropy_transition_fixture, arc_evidence]
import ../../../src/state/[entropy, store]
import ../../../src/codec/[state_trie, state_layout, bounded]

## The test-only observer can refuse the very first entropy or commitment hash.
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
## Allow a known successful hash prefix before refusing private store-root construction.
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
## Count actual hash attempts so slot/configuration/state rejection cannot hide crypto work.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

## Finite independent store budgets require two valid writes as a single batch.
proc policy(): StateStoreLimits =
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(3), perValue: ByteLimit(129),
    totalValueBytes: ByteLimit(135), nodes: TrieNodeLimit(747)), writes: ElementLimit(2),
        writeValueBytes: ByteLimit(132))

## Typed source words/time are independent of any origin store or later write batch.
proc entries(): seq[StateEntry] =
  @[entropyEntry(entropyWords()), timeEntry(StateTime(11)),
      StateEntry(key: chapterKey(StateChapter(1)), value: @[99'u8])]

## Compare every value and the full prior commitment after each refused candidate.
proc unchanged(state: StateStore, before: StateStoreSnapshot, source: seq[StateEntry]) =
  let current = state.snapshot.value
  assert array[32, byte](current.commitment.root) == array[32, byte](before.commitment.root)
  for entry in source:
    assert current.lookup(entry.key).value.bytes ==
        entry.value # Neither entropy nor time nor unrelated state may change.

## Initial entropy refusal, first/late commitment refusal and recovery share one scoped ownership lifecycle.
proc cycle() =
  fail(0)
  let source = entries()
  let made = newStateStore(source, policy())
  assert made.error == StateStoreError.None
  var state = made.value
  let before = state.snapshot.value
  let randomness = default(EntropyInput)
  for successful in [0, 1, 3]:
    failAfter(cint(successful)) # One success means entropy computed but neither chapter committed.
    assert advanceEntropyTimeState(state, StateTime(12), randomness,
        EpochSlots(12)).error == EntropyTransitionError.BackendFailure
    assert hashCalls() == cint(successful+1)
    unchanged(state, before, source)
  fail(0)
  let committed = advanceEntropyTimeState(state, StateTime(12), randomness, EpochSlots(12))
  assert committed.error == EntropyTransitionError.None
  assert committed.value.lookup(source[0].key).value.bytes != source[0].value
  assert committed.value.lookup(source[1].key).value.bytes == timeEntry(StateTime(12)).value
  assert committed.value.lookup(source[2].key).value.bytes == source[2].value
  assert before.lookup(source[0].key).value.bytes == source[0].value
  assert before.lookup(source[1].key).value.bytes == source[1].value

## Rejections before fixed input copying/hashing and independent batch/map policy failures remain atomic.
proc invalid() =
  var uninitialized = default(StateStore)
  assert advanceEntropyTimeState(uninitialized, StateTime(12), default(EntropyInput),
      EpochSlots(12)).error == EntropyTransitionError.Uninitialized
  for which in 0..<3:
    fail(0)
    let source = entries()
    let subset = if which == 0: newSeq[StateEntry](0) elif which == 1: @[source[0]] else: @[source[1]]
    let made = newStateStore(subset, policy())
    assert made.error == StateStoreError.None
    var state = made.value
    let before = state.snapshot.value
    fail(1)
    assert advanceEntropyTimeState(state, StateTime(12), default(EntropyInput),
        EpochSlots(12)).error == EntropyTransitionError.MissingState
    assert hashCalls() == 0
    unchanged(state, before, subset)
  for which in 0..<4:
    fail(0)
    var source = entries()
    let index = which div 2
    if which mod 2 == 0:
      source[index].value.setLen(source[index].value.len-1) # A truncated entropy word/slot cannot be padded.
    else:
      source[index].value.add 0 # Neither fixed chapter accepts a suffix.
    let made = newStateStore(source, policy())
    assert made.error == StateStoreError.None
    var state = made.value
    let before = state.snapshot.value
    fail(1)
    assert advanceEntropyTimeState(state, StateTime(12), default(EntropyInput),
        EpochSlots(12)).error == EntropyTransitionError.InvalidState
    assert hashCalls() == 0
    unchanged(state, before, source)
  for which in 0..<2:
    fail(0)
    let source = entries()
    var limits = policy()
    if which == 0:
      limits.writes = ElementLimit(1) # A one-write budget must not allow just the entropy update.
    else:
      limits.writeValueBytes = ByteLimit(131) # One byte below the combined 128+4 budget must refuse both.
    let limited = newStateStore(source, limits)
    assert limited.error == StateStoreError.None
    var state = limited.value
    let before = state.snapshot.value
    fail(0)
    assert advanceEntropyTimeState(state, StateTime(12), default(EntropyInput),
        EpochSlots(12)).error == EntropyTransitionError.LimitExceeded
    assert hashCalls() == 1 # Entropy computed, then batch preflight refuses before root hashing.
    unchanged(state, before, source)
  fail(1)
  assert advanceEntropyTime(entropyWords(), StateTime(11), StateTime(11), default(EntropyInput),
      EpochSlots(12)).error == EntropyTransitionError.InvalidSlot
  assert advanceEntropyTime(entropyWords(), StateTime(11), StateTime(12), default(EntropyInput),
      EpochSlots(0)).error == EntropyTransitionError.InvalidConfig
  assert hashCalls() == 0
  fail(0)

invalid()
for i in 0..<25: cycle() # Warm allocation/runtime paths before checking retained occupancy.
let before = getOccupiedMem()
for i in 0..<1000: cycle() # Each scope retires computed values, two-entry candidates and historical snapshots.
let after = getOccupiedMem()
assert before == after
recordArcRelease("entropy_transition_failure", 1000, before, after)
echo "PASS entropy/time failures: fixed-state validation, atomic rollback, backend recovery and ARC release"
