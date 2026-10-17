## Backend refusal and ARC lifetime tests use the existing project-owned primitive observer.
import std/[assertions, syncio]
import ../../support/arc_evidence
import ../../../src/state/store
import ../../../src/codec/[state_trie, state_layout, bounded]

## Refuse all hashing or reset the existing deterministic observer state.
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
## Permit some child hashes before refusing, so rollback covers a partly built candidate root.
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
## Observe preflight/no-op behavior without inspecting a store's private state.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

## Construct a bounded two-key map and prove hash failure cannot publish partially updated values.
proc cycle() =
  fail(0)
  let zero = StateKey(default(array[31, byte]))
  var raw = default(array[31, byte])
  raw[0] = 128
  let one = StateKey(raw)
  let limits = StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(2),
    perValue: ByteLimit(33), totalValueBytes: ByteLimit(66), nodes: TrieNodeLimit(3)),
    writes: ElementLimit(2), writeValueBytes: ByteLimit(66))
  let initial = @[StateEntry(key: zero, value: newSeq[byte](33))]
  let made = newStateStore(initial, limits)
  assert made.error == StateStoreError.None
  var state = made.value
  let before = state.snapshot.value
  let retained = before.lookup(zero).value
  let root = array[32, byte](before.commitment.root)
  let writes = @[StateWrite(key: zero, kind: StateWriteKind.Put, value: @[9'u8]),
    StateWrite(key: one, kind: StateWriteKind.Put, value: @[8'u8])]
  fail(1)
  assert state.apply(writes).error == StateStoreError.BackendFailure
  assert hashCalls() == 1
  assert newStateStore(initial, limits).error == StateStoreError.BackendFailure
  failAfter(2)
  assert state.apply(writes).error == StateStoreError.BackendFailure
  assert hashCalls() == 3
  assert array[32, byte](state.snapshot.value.commitment.root) == root
  assert state.snapshot.value.lookup(one).error == StateStoreError.MissingKey
  assert retained.bytes == newSeq[byte](33)
  fail(1)
  assert state.apply([]).error == StateStoreError.None
  assert hashCalls() == 0
  assert state.apply(@[writes[0], writes[0]]).error == StateStoreError.DuplicateKey
  assert hashCalls() == 0
  fail(0)
  let after = state.apply(writes)
  assert after.error == StateStoreError.None and after.value.commitment.entries == 2
  assert after.value.lookup(zero).value.bytes == @[9'u8]
  assert retained.bytes == newSeq[byte](33)

# Warm allocator setup before checking acyclic owners are released through success and rollback.
for i in 0..<25: cycle()
let beforeRelease = getOccupiedMem()
# Each iteration drops stores, results, retained views and historical snapshots with no owner cycle.
for i in 0..<1000: cycle()
let afterRelease = getOccupiedMem()
assert beforeRelease == afterRelease
recordArcRelease("state_store_failure", 1000, beforeRelease, afterRelease)
fail(0)
echo "PASS state store failures: early/late backend rollback, recovery, no-op and ARC release"
