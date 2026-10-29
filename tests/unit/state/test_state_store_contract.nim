# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Freeze public StateStore observations before adopting a new commitment implementation.
import std/[assertions, syncio]
import ../../../src/state/store
import ../../../src/codec/state/[trie as state_trie, layout as state_layout]
import ../../../src/codec/bounded

proc key(index: byte): StateKey =
  ## Full serialized identities include far branches and maximum shared-prefix cases.
  var raw = default(array[31, byte])
  if index < 3: raw[30] = index
  else: raw[0] = 128
  StateKey(raw)
proc limits(): StateStoreLimits =
  ## Finite budgets cover every value boundary and permit at most four complete keys.
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(4), perValue: ByteLimit(33),
    totalValueBytes: ByteLimit(132), nodes: TrieNodeLimit(1000)),
    writes: ElementLimit(4), writeValueBytes: ByteLimit(132))
proc check(snapshot: StateStoreSnapshot, entries: seq[StateEntry]) =
  ## Sorted public enumeration plus an independent whole-map root excludes stale/extra map data.
  let expected = stateTrieRoot(entries, limits().trie).value
  let actual = snapshot.commitment
  assert actual.entries == entries.len and actual.nodes == expected.nodes
  assert array[32, byte](actual.root) == array[32, byte](expected.root)
  for i, entry in entries:
    assert array[31, byte](snapshot.keyAt(StateEntryIndex(i)).value) == array[31, byte](entry.key)
    let value = snapshot.lookup(entry.key).value
    assert value.byteLength == entry.value.len and value.bytes == entry.value
    assert value.copySlice(0, uint64(entry.value.len), ByteLimit(33)).value == entry.value
  assert snapshot.keyAt(StateEntryIndex(-1)).error == StateStoreError.InvalidRange
  assert snapshot.keyAt(StateEntryIndex(entries.len)).error == StateStoreError.InvalidRange

proc run() =
  ## Public identity, ownership, ordering and failure contracts are representation-independent.
  let policy = limits()
  var source = @[StateEntry(key: key(3), value: @[9'u8]), StateEntry(key: key(0))]
  var state = newStateStore(source, policy).value
  let initial = state.snapshot.value
  let held = initial.lookup(key(3)).value
  check(initial, @[StateEntry(key: key(0)), StateEntry(key: key(3), value: @[9'u8])])
  source[0].value[0] = 99
  source.setLen(0)
  assert held.bytes == @[9'u8]
  assert sameStateSnapshot(initial, state.apply([]).value)
  assert not sameStateSnapshot(default(StateStoreSnapshot), default(StateStoreSnapshot))
  let equivalent = newStateStore([StateEntry(key: key(0)),
    StateEntry(key: key(3), value: @[9'u8])], policy).value.snapshot.value
  assert not sameStateSnapshot(initial, equivalent)
  # Nonempty successful batches still publish a distinct map owner, even when their roots match.
  let absent = state.apply([StateWrite(key: key(2), kind: StateWriteKind.Delete)]).value
  assert not sameStateSnapshot(initial, absent)
  assert array[32, byte](initial.commitment.root) == array[32, byte](absent.commitment.root)
  let identical = state.apply([StateWrite(key: key(3), kind: StateWriteKind.Put,
    value: @[9'u8])]).value
  assert not sameStateSnapshot(absent, identical)
  var fork = initial.forkStateStore.value
  assert sameStateSnapshot(initial, fork.snapshot.value)
  let deep = fork.apply([StateWrite(key: key(1), kind: StateWriteKind.Put)]).value
  check(deep, @[StateEntry(key: key(0)), StateEntry(key: key(1)),
    StateEntry(key: key(3), value: @[9'u8])])
  # Exhaust inline/hashed leaf sizes while a previous full-depth mapping stays retained.
  for size in [1, 32, 33, 0]:
    var payload = newSeq[byte](size)
    for i in 0..<size: payload[i] = byte(i+size) # Deterministic unequal bytes bind copied ownership.
    let changed = state.apply([StateWrite(key: key(1), kind: StateWriteKind.Put, value: payload),
      StateWrite(key: key(0), kind: StateWriteKind.Delete)]).value
    check(changed, @[StateEntry(key: key(1), value: payload),
      StateEntry(key: key(3), value: @[9'u8])])
    if size > 0:
      payload[0] = payload[0] xor 255
      assert changed.lookup(key(1)).value.bytes[0] == byte(size)
  let current = state.snapshot.value
  let rejected = [
    @[StateWrite(key: key(1), kind: StateWriteKind.Put, value: newSeq[byte](34))],
    @[StateWrite(key: key(1), kind: StateWriteKind.Delete, value: @[1'u8])],
    @[StateWrite(key: key(1), kind: StateWriteKind.Delete),
      StateWrite(key: key(1), kind: StateWriteKind.Delete)]]
  let reasons = [StateStoreError.LimitExceeded, StateStoreError.InvalidWrite,
    StateStoreError.DuplicateKey]
  for i, writes in rejected:
    assert state.apply(writes).error == reasons[i]
    assert sameStateSnapshot(current, state.snapshot.value)
  # Inherited batch and complete-map budgets survive private forks and successful publication.
  var short = policy
  short.writes = ElementLimit(0)
  var bounded = newStateStore([StateEntry(key: key(3), value: @[9'u8])], short).value
  var boundedFork = bounded.snapshot.value.forkStateStore.value
  assert boundedFork.apply([StateWrite(key: key(3), kind: StateWriteKind.Delete)]).error ==
    StateStoreError.LimitExceeded
  discard fork.apply([StateWrite(key: key(3), kind: StateWriteKind.Delete)]).value
  assert initial.lookup(key(3)).value.bytes == @[9'u8]
  let empty = state.apply([StateWrite(key: key(1), kind: StateWriteKind.Delete),
    StateWrite(key: key(3), kind: StateWriteKind.Delete)]).value
  check(empty, @[])
  state = default(StateStore)
  fork = default(StateStore)
  assert held.copySlice(0, 1, ByteLimit(1)).value == @[9'u8]
  assert held.copySlice(high(uint64), 1, ByteLimit(1)).error == StateStoreError.InvalidRange
  assert held.copySlice(0, 1, ByteLimit(0)).error == StateStoreError.LimitExceeded
  var copied = held.bytes
  copied[0] = 55
  assert held.bytes == @[9'u8] and initial.lookup(key(0)).value.byteLength == 0

run()
echo "PASS state store contract: sorted keys, identity, retained slices, forks, limits and root parity"
