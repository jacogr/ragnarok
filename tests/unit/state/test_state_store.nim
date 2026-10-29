# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Storage semantics and ownership tests; published transition-map replay is a separate
## increment.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import std/[assertions, syncio]
import ../../../src/state/store
import ../../../src/codec/state/[trie as state_trie, layout as state_layout]
import ../../../src/codec/bounded

## Derive distinct fixed keys without relying on hashed protocol namespace inference.
proc key(index: byte): StateKey =
  var raw = default(array[31, byte])
  raw[0] = index
  StateKey(raw)

## Keep small explicit policy budgets so every ceiling is reachable in a native test.
proc policy(): StateStoreLimits =
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(4), perValue: ByteLimit(33),
    totalValueBytes: ByteLimit(66), nodes: TrieNodeLimit(1024)),
    writes: ElementLimit(4), writeValueBytes: ByteLimit(66))

## A successful lookup copies only through the public owned view; absence remains a typed failure.
proc read(snapshot: StateStoreSnapshot, index: byte): seq[byte] =
  let found = snapshot.lookup(key(index))
  assert found.error == StateStoreError.None
  let view = found.value
  let copied = view.bytes
  assert view.byteLength == copied.len
  copied

## Return only a retained view so all originating stores, results, snapshots and caller bytes die here.
proc scopedValue(): StateValue =
  var source = @[StateEntry(key: key(3), value: @[41'u8, 42, 43])]
  let made = newStateStore(source, policy())
  assert made.error == StateStoreError.None
  result = made.value.snapshot.value.lookup(key(3)).value
  source[0].value[0] = 99
  source.setLen(0)

## Return only a snapshot; it must retain its mapping after every originating local leaves scope.
proc scopedSnapshot(): StateStoreSnapshot =
  let made = newStateStore(@[StateEntry(key: key(2), value: @[51'u8, 52])], policy())
  assert made.error == StateStoreError.None
  made.value.snapshot.value

## Cover owned input/output, atomic mixed writes, snapshots, missing/empty and independent handles.
proc semantics() =
  let escaped = scopedValue()
  assert escaped.bytes == @[41'u8, 42, 43]
  let historical = scopedSnapshot()
  assert historical.read(2) == @[51'u8, 52]
  let limits = policy()
  let absent = default(StateStoreResult[StateStore])
  assert absent.error == StateStoreError.Uninitialized
  var invalid = default(StateStore)
  assert invalid.snapshot.error == StateStoreError.Uninitialized
  assert invalid.apply([]).error == StateStoreError.Uninitialized
  let missing = default(StateStoreSnapshot)
  assert missing.forkStateStore.error == StateStoreError.Uninitialized
  assert missing.lookup(key(0)).error == StateStoreError.Uninitialized
  var input = @[StateEntry(key: key(2), value: @[2'u8]),
                StateEntry(key: key(0), value: newSeq[byte](0))]
  let initialized = newStateStore(input, limits)
  assert initialized.error == StateStoreError.None
  var state = initialized.value
  let before = state.snapshot.value
  let retained = before.lookup(key(2)).value
  let oldRoot = array[32, byte](before.commitment.root)
  var forked = before.forkStateStore.value
  assert forked.apply([StateWrite(key: key(2), kind: StateWriteKind.Put, value: @[8'u8])]).error ==
      StateStoreError.None
  assert before.read(2) == @[2'u8] and forked.snapshot.value.read(2) == @[8'u8]
  assert forked.apply([StateWrite(key: key(2), kind: StateWriteKind.Put, value: newSeq[byte](
      34))]).error == StateStoreError.LimitExceeded
  assert forked.snapshot.value.read(2) == @[8'u8] # Inherited per-value ceiling survives fork and publication.
  input[0].value[0] = 99
  input.setLen(0)
  assert before.read(2) == @[2'u8]
  assert before.lookup(key(0)).error == StateStoreError.None
  assert before.lookup(key(0)).value.byteLength == 0
  assert before.lookup(key(1)).error == StateStoreError.MissingKey
  var copied = retained.bytes
  copied[0] = 88
  assert retained.bytes == @[2'u8]
  var writes = @[StateWrite(key: key(2), kind: StateWriteKind.Put, value: @[7'u8]),
                 StateWrite(key: key(1), kind: StateWriteKind.Put, value: newSeq[byte](33)),
                 StateWrite(key: key(0), kind: StateWriteKind.Delete),
                 StateWrite(key: key(3), kind: StateWriteKind.Delete)]
  let applied = state.apply(writes)
  assert applied.error == StateStoreError.None
  let after = applied.value
  assert after.commitment.entries == 2
  assert after.read(2) == @[7'u8] and after.read(1).len == 33
  assert after.lookup(key(0)).error == StateStoreError.MissingKey
  assert after.lookup(key(3)).error == StateStoreError.MissingKey
  assert before.read(2) == @[2'u8] and before.lookup(key(0)).error == StateStoreError.None
  assert array[32, byte](before.commitment.root) == oldRoot
  let expected = stateTrieRoot(@[StateEntry(key: key(2), value: @[7'u8]),
    StateEntry(key: key(1), value: newSeq[byte](33))], limits.trie)
  assert expected.error == StateTrieError.None
  assert array[32, byte](after.commitment.root) == array[32, byte](expected.value.root)
  writes[0].value[0] = 33
  writes[1].value[0] = 34
  assert after.read(2) == @[7'u8] and after.read(1)[0] == 0
  var independent = state
  assert independent.apply(@[StateWrite(key: key(2), kind: StateWriteKind.Delete)]).error ==
      StateStoreError.None
  assert state.snapshot.value.read(2) == @[7'u8]
  assert state.apply([]).error == StateStoreError.None
  let cleared = state.apply(@[StateWrite(key: key(1), kind: StateWriteKind.Delete),
    StateWrite(key: key(2), kind: StateWriteKind.Delete)])
  assert cleared.error == StateStoreError.None and cleared.value.commitment.entries == 0
  assert array[32, byte](cleared.value.commitment.root) == default(array[32, byte])
  state = default(StateStore)
  independent = default(StateStore)
  assert retained.bytes == @[2'u8] and after.read(2) == @[7'u8]

## A failed multi-write batch must leave both the published head and retained bytes unchanged.
proc rejects(writes: seq[StateWrite], limits: StateStoreLimits, reason: StateStoreError) =
  let made = newStateStore(@[StateEntry(key: key(0), value: @[1'u8])], limits)
  assert made.error == StateStoreError.None
  var state = made.value
  let before = state.snapshot.value
  assert state.apply(writes).error == reason
  assert array[32, byte](state.snapshot.value.commitment.root) == array[32, byte](
      before.commitment.root)
  assert state.snapshot.value.commitment.entries == 1
  assert state.snapshot.value.read(0) == @[1'u8]

## Bind every batch/map resource budget, invalid delete and duplicate rejection to actual small inputs.
proc policies() =
  let limits = policy()
  assert newStateStore(@[StateEntry(key: key(0)), StateEntry(key: key(0))], limits).error ==
      StateStoreError.DuplicateKey
  assert newStateStore(@[StateEntry(key: key(0), value: newSeq[byte](34))], limits).error ==
      StateStoreError.LimitExceeded
  let two = @[StateWrite(key: key(0), kind: StateWriteKind.Put, value: @[9'u8]),
    StateWrite(key: key(1), kind: StateWriteKind.Put, value: @[8'u8])]
  var short = limits
  short.writes = ElementLimit(1)
  rejects(two, short, StateStoreError.LimitExceeded)
  short = limits
  short.writeValueBytes = ByteLimit(1)
  rejects(two, short, StateStoreError.LimitExceeded)
  short = limits
  short.trie.items = ElementLimit(1)
  rejects(two, short, StateStoreError.LimitExceeded)
  short = limits
  short.trie.totalValueBytes = ByteLimit(1)
  rejects(two, short, StateStoreError.LimitExceeded)
  short = limits
  short.trie.nodes = TrieNodeLimit(1)
  rejects(two, short, StateStoreError.LimitExceeded)
  rejects(@[two[0], two[0]], limits, StateStoreError.DuplicateKey)
  rejects(@[two[0], StateWrite(key: key(0), kind: StateWriteKind.Delete)], limits,
      StateStoreError.DuplicateKey)
  rejects(@[two[0], StateWrite(key: key(1), kind: StateWriteKind.Put,
    value: newSeq[byte](34))], limits, StateStoreError.LimitExceeded)
  rejects(@[two[0], StateWrite(key: key(1), kind: StateWriteKind.Delete,
    value: @[1'u8])], limits, StateStoreError.InvalidWrite)
  let empty = newStateStore([], default(StateStoreLimits))
  assert empty.error == StateStoreError.None
  var state = empty.value
  assert state.apply([]).error == StateStoreError.None
  assert state.apply(@[StateWrite(key: key(0), kind: StateWriteKind.Put)]).error ==
      StateStoreError.LimitExceeded
  short = limits
  short.trie.totalValueBytes = ByteLimit(33)
  short.trie.items = ElementLimit(1)
  let full = newStateStore(@[StateEntry(key: key(0), value: newSeq[byte](33))], short)
  assert full.error == StateStoreError.None
  state = full.value
  # The final-map budget permits delete-plus-insert at full capacity, regardless of write order.
  let replaced = state.apply(@[StateWrite(key: key(1), kind: StateWriteKind.Put, value: newSeq[
      byte](33)),
    StateWrite(key: key(0), kind: StateWriteKind.Delete)])
  assert replaced.error == StateStoreError.None and replaced.value.commitment.entries == 1
  assert replaced.value.lookup(key(0)).error == StateStoreError.MissingKey

## Compare a deterministic update history against a separate four-slot logical model after every batch.
proc histories() =
  let limits = policy()
  let made = newStateStore([], limits)
  assert made.error == StateStoreError.None
  var state = made.value
  var present = default(array[4, bool])
  var model = default(array[4, seq[byte]])
  # Repeated keys across batches exercise recreation, deletion, replacement and empty values.
  for round in 0..<64:
    var changes = newSeq[StateWrite](2)
    let before = state.snapshot.value
    let oldRoot = array[32, byte](before.commitment.root)
    # The two keys are unique within each batch; their caller order deliberately varies.
    for j in 0..<2:
      let index = (round+j) mod 4
      let remove = (round+j) mod 3 == 0
      changes[j] = StateWrite(key: key(byte(index)), kind: StateWriteKind.Delete)
      present[index] = not remove
      if not remove:
        # Short varying values include present-empty entries and repeated replacements.
        model[index] = newSeq[byte]((round+j) mod 9)
        for k in 0..<model[index].len: model[index][k] = byte(round+k)
        changes[j] = StateWrite(key: key(byte(index)), kind: StateWriteKind.Put, value: model[index])
    let applied = state.apply(changes)
    assert applied.error == StateStoreError.None
    var expected = newSeq[StateEntry](0)
    # Independently rebuild the expected map from logical slots instead of using the store's merge algorithm.
    for index in 0..<4:
      let found = applied.value.lookup(key(byte(index)))
      if present[index]:
        assert found.error == StateStoreError.None and found.value.bytes == model[index]
        expected.add StateEntry(key: key(byte(index)), value: model[index])
      else:
        assert found.error == StateStoreError.MissingKey
    let root = stateTrieRoot(expected, limits.trie)
    assert root.error == StateTrieError.None
    assert array[32, byte](root.value.root) == array[32, byte](applied.value.commitment.root)
    assert array[32, byte](before.commitment.root) == oldRoot

## Cover leaf representation transitions, full-key ordering and zero/high resource domains without unsafe inputs.
proc boundaries() =
  let limits = policy()
  let made = newStateStore([], limits)
  assert made.error == StateStoreError.None
  var state = made.value
  # Replace the same leaf through empty, inline and hashed-value sizes, retaining the preceding view.
  for size in [0, 1, 31, 32, 33, 32, 1, 0]:
    let before = state.snapshot.value
    var bytes = newSeq[byte](size)
    for i in 0..<bytes.len: bytes[i] = byte(i+size) # Distinct payloads detect stale/hash-boundary updates.
    let expected = stateTrieRoot(@[StateEntry(key: key(0), value: bytes)], limits.trie)
    assert expected.error == StateTrieError.None
    let changed = state.apply(@[StateWrite(key: key(0), kind: StateWriteKind.Put, value: bytes)])
    assert changed.error == StateStoreError.None
    assert array[32, byte](changed.value.commitment.root) == array[32, byte](expected.value.root)
    let held = changed.value.lookup(key(0)).value
    assert held.byteLength == size and held.bytes == bytes
    if before.commitment.entries == 1:
      # Even resizing across the leaf boundary cannot mutate the old retained version.
      assert before.lookup(key(0)).error == StateStoreError.None
    if size > 0:
      # Mutating the caller buffer after apply must not alter the retained view.
      let original = held.bytes[0]
      bytes[0] = bytes[0] xor 255
      assert held.bytes[0] == original
  var last = default(array[31, byte])
  last[30] = 1
  let close = StateKey(last)
  let deep = StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(2), perValue: ByteLimit(1),
    totalValueBytes: ByteLimit(2), nodes: TrieNodeLimit(250)), writes: ElementLimit(2),
        writeValueBytes: ByteLimit(2))
  let empty = newStateStore([], deep)
  assert empty.error == StateStoreError.None
  state = empty.value
  let changed = state.apply(@[StateWrite(key: close, kind: StateWriteKind.Put, value: @[2'u8]),
    StateWrite(key: key(0), kind: StateWriteKind.Put, value: @[1'u8])])
  assert changed.error == StateStoreError.None and changed.value.commitment.nodes == 250
  assert changed.value.lookup(close).value.bytes == @[2'u8]
  assert changed.value.lookup(key(0)).value.bytes == @[1'u8]
  let removed = state.apply(@[StateWrite(key: close, kind: StateWriteKind.Delete)])
  assert removed.error == StateStoreError.None and removed.value.commitment.nodes == 1
  assert removed.value.lookup(close).error == StateStoreError.MissingKey
  var zero = default(StateStoreLimits)
  zero.writes = ElementLimit(1)
  let none = newStateStore([], zero)
  assert none.error == StateStoreError.None
  state = none.value
  # An absent delete fits zero map/value/node budgets and must not insert an empty leaf.
  let absent = state.apply(@[StateWrite(key: key(3), kind: StateWriteKind.Delete)])
  assert absent.error == StateStoreError.None and absent.value.commitment.entries == 0
  assert array[32, byte](absent.value.commitment.root) == default(array[32, byte])
  let maximum = StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(high(uint64)),
    perValue: ByteLimit(high(uint64)), totalValueBytes: ByteLimit(high(uint64)),
        nodes: TrieNodeLimit(high(uint64))),
    writes: ElementLimit(high(uint64)), writeValueBytes: ByteLimit(high(uint64)))
  let wide = newStateStore([], maximum)
  assert wide.error == StateStoreError.None
  state = wide.value
  assert state.apply(@[StateWrite(key: key(0), kind: StateWriteKind.Put, value: newSeq[byte](
      33))]).error == StateStoreError.None

## Bounded slices retain exact view ownership and validate full-width ranges before allocation.
proc slices() =
  var input = @[10'u8, 11, 12, 13, 14, 15, 16, 17]
  var state = newStateStore([StateEntry(key: key(0), value: input)], policy()).value
  let view = state.snapshot.value.lookup(key(0)).value
  input[0] = 99 # The retained view owns the original bytes, independent of caller storage.
  for offset in 0..9:
    for length in 0..9:
      let copied = view.copySlice(uint64(offset), uint64(length), ByteLimit(8))
      if offset > 8 or length > 8-offset:
        assert copied.error == StateStoreError.InvalidRange # No invalid interval can expose an empty/partial success.
      else:
        assert copied.error == StateStoreError.None and copied.value.len == length
        for i in 0..<length:
          assert copied.value[i] == byte(10+offset+i) # Exact original bytes in source order.
        if length > 0:
          assert view.copySlice(uint64(offset), uint64(length), ByteLimit(length-1)).error ==
              StateStoreError.LimitExceeded
  assert view.copySlice(high(uint64), 0, ByteLimit(0)).error == StateStoreError.InvalidRange
  assert view.copySlice(0, high(uint64), ByteLimit(high(uint64))).error ==
      StateStoreError.InvalidRange
  assert default(StateValue).copySlice(0, 0, ByteLimit(0)).error == StateStoreError.Uninitialized
  var detached = view.copySlice(2, 3, ByteLimit(3)).value
  detached[0] = 255
  assert view.copySlice(2, 3, ByteLimit(3)).value == @[12'u8, 13, 14]
  assert state.apply([StateWrite(key: key(0), kind: StateWriteKind.Put, value: @[0'u8])]).error ==
      StateStoreError.None
  assert view.copySlice(0, 8, ByteLimit(8)).value[0] ==
      10 # Older owners remain independent of later map publication.

slices()
semantics()
policies()
histories()
boundaries()
echo "PASS state store: owned values, stable snapshots, atomic batches and exact resource policies"
