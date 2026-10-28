# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fixed checked workload for A/B crypto-work and live-memory observations through StateStore's public API.
## Compile the identical source against baseline/candidate trees; output is JSON lines, not timing claims.
import std/assertions
import std/syncio
import ../../src/state/store as state_store
import ../../src/codec/state_trie as codec_state_trie
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/bounded as codec_bounded

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset the maintained primitive observer without changing protocol hashing behavior.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Count exact Blake2b calls; setup and final independent root validation are outside the update region.
proc key(index: int): StateKey =
  ## Spread complete keys across early bits rather than measuring only a maximum-depth prefix.
  var raw = default(array[31, byte])
  raw[0] = byte(index mod 256)
  raw[1] = byte(index div 256)
  StateKey(raw)
proc sample(count, retained: int) =
  ## Freeze map size, 33-byte leaves, 64 sparse updates and a bounded snapshot-retention window.
  reset(0)
  let before = getOccupiedMem()
  let policy = StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(count),
    perValue: ByteLimit(33), totalValueBytes: ByteLimit(count*33),
    nodes: TrieNodeLimit(count*249)), writes: ElementLimit(1), writeValueBytes: ByteLimit(33))
  var entries = newSeq[StateEntry](count)
  for i in 0..<count:
    entries[i] = StateEntry(key: key(i), value: newSeq[byte](
        33)) # Owned authored values are stable during each call.
  var state = newStateStore(entries, policy).value
  var held = newSeq[StateStoreSnapshot](retained)
  let initialized = getOccupiedMem()-before
  var peak = initialized
  reset(0)
  for step in 0..<64:
    let index = (step*17) mod count
    entries[index].value[0] = byte(step+1)
    held[step mod retained] = state.snapshot.value
    let applied = state.apply([StateWrite(key: key(index), kind: StateWriteKind.Put,
      value: entries[index].value)])
    assert applied.error == StateStoreError.None
    peak = max(peak, getOccupiedMem()-before)
  let hashes = hashCalls()
  let retainedBytes = getOccupiedMem()-before
  let expected = stateTrieRoot(entries, policy.trie).value
  assert array[32, byte](state.snapshot.value.commitment.root) == array[32, byte](expected.root)
  assert state.snapshot.value.commitment.nodes == expected.nodes
  echo "{\"entries\":" & $count & ",\"retained\":" & $retained &
    ",\"updates\":64,\"hash_calls\":" & $hashes & ",\"initialized_bytes\":" & $initialized &
    ",\"peak_bytes\":" & $peak & ",\"retained_bytes\":" & $retainedBytes & "}"

for count in [128, 1024]:
  for retained in [1, 8]: sample(count, retained) # Each case retires every store/view before the next observation.
