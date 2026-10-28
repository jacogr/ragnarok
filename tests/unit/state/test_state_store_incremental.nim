# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Cached unchanged subtrees and atomic rollback must hold through the existing StateStore interface.
import std/assertions
import std/syncio
import ../../../src/state/store as state_store
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/bounded as codec_bounded
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset observer state or refuse a required hash.
proc failAfter(count: cint) {.importc: "ro_blake_after", cdecl.}
  ## Allow a path prefix to hash before refusing the remaining candidate.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Count only the update under test; independent reference checks happen afterward.
proc key(index: int): StateKey =
  ## The first 256 identities form a balanced eight-level tree; 256 is independently absent.
  var raw = default(array[31, byte])
  raw[0] = byte(index mod 256)
  raw[1] = byte(index div 256)
  StateKey(raw)
proc run() =
  ## Failure never publishes either half of the map/trie candidate or corrupts a retained root.
  reset(0)
  let policy = StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(256),
    perValue: ByteLimit(33), totalValueBytes: ByteLimit(256*33), nodes: TrieNodeLimit(511)),
    writes: ElementLimit(2), writeValueBytes: ByteLimit(66))
  var entries = newSeq[StateEntry](256)
  for i in 0..<256: entries[i] = StateEntry(key: key(i), value: @[
      1'u8]) # Finite complete map, no partial-root claim.
  var state = newStateStore(entries, policy).value
  let original = state.snapshot.value
  let held = original.lookup(key(42)).value
  var fork = original.forkStateStore.value
  let writes = [StateWrite(key: key(42), kind: StateWriteKind.Put, value: newSeq[byte](33))]
  reset(1)
  assert state.apply(writes).error == StateStoreError.BackendFailure and calls() == 1
  assert sameStateSnapshot(original, state.snapshot.value)
  failAfter(4)
  assert state.apply(writes).error == StateStoreError.BackendFailure and calls() == 5
  assert sameStateSnapshot(original, state.snapshot.value)
  assert held.bytes == @[1'u8] and original.lookup(key(42)).value.bytes == @[1'u8]
  reset(0)
  let changed = state.apply(writes).value
  # Two hashes encode the long leaf; exactly eight new branches join cached complete subtrees.
  assert calls() == 10
  entries[42].value = newSeq[byte](33)
  let expected = stateTrieRoot(entries, policy.trie).value
  assert array[32, byte](changed.commitment.root) == array[32, byte](expected.root)
  assert changed.commitment.nodes == 511 and changed.lookup(key(42)).value.byteLength == 33
  for i in 0..<256:
    assert array[31, byte](changed.keyAt(StateEntryIndex(i)).value) == array[31, byte](key(i))
    assert changed.lookup(key(i)).value.bytes == entries[i].value
  reset(1)
  assert sameStateSnapshot(changed, state.apply([]).value) and calls() == 0
  let absent = state.apply([StateWrite(key: key(256), kind: StateWriteKind.Delete)]).value
  assert calls() == 0 and not sameStateSnapshot(changed, absent)
  assert array[32, byte](changed.commitment.root) == array[32, byte](absent.commitment.root)
  assert fork.snapshot.value.lookup(key(42)).value.bytes == @[1'u8]
  reset(0)
  let forked = fork.apply(writes).value
  assert calls() == 10
  assert array[32, byte](forked.commitment.root) == array[32, byte](changed.commitment.root)
  assert not sameStateSnapshot(forked, changed)
  state = default(StateStore)
  fork = default(StateStore)
  assert held.copySlice(0, 1, ByteLimit(1)).value == @[1'u8]
  assert changed.lookup(key(42)).value.bytes == newSeq[byte](33)
  reset(0)
run()
echo "PASS incremental state store: cached paths, precise hash work, atomic rollback, forks and retained maps"
