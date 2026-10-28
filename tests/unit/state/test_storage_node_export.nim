# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Full/delta exports detach exact physical nodes, reuse cached identities and bound output.
# @@Verification={"arc": "storage_node_export_arc_release"}

import std/assertions
import std/syncio
import ../../support/testing_arc_evidence
import ../../../src/storage/full_state_trie as storage_full_state_trie
import ../../../src/storage/node_records as storage_node_records
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/bounded as codec_bounded

proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Existing observer proves detachment needs no fresh crypto work.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Count primitive attempts independently of cached metadata.
proc key(number: byte): StateKey =
  ## Select the two root branches with authored full identities.
  var bytes = default(array[31, byte])
  bytes[0] = number
  StateKey(bytes)
proc cycle() =
  ## Detached exports survive all source graphs and mutable input/output isolation.
  fail(0)
  let policy = FullStateTrieLimits(trie: StateTrieLimits(items: ElementLimit(4),
    perValue: ByteLimit(33), totalValueBytes: ByteLimit(132), nodes: TrieNodeLimit(1000)),
    writes: ElementLimit(4), writeValueBytes: ByteLimit(132))
  let before = newFullStateTrie([StateEntry(key: key(0), value: @[1'u8]),
    StateEntry(key: key(128), value: @[2'u8])], policy).value
  let after = before.apply([TrieWrite(key: key(128), kind: TrieWriteKind.Put,
    value: @[3'u8])]).value
  let limits = TrieExportLimits(records: TrieNodeLimit(3), valueBytes: ByteLimit(2))
  fail(1)
  var full = exportFullTrie(before, limits).value
  assert full.records.len == 3 and full.entries == 2 and full.nodes == 3
  assert full.records[0].kind == TrieRecordKind.Leaf and full.records[2].kind ==
      TrieRecordKind.Branch
  let delta = exportTrieChanges(before, after, limits).value
  assert delta.records.len == 2 and delta.records[0].payload == @[3'u8]
  assert delta.records[1].kind == TrieRecordKind.Branch
  assert array[32, byte](delta.base) == array[32, byte](before.commitment.root)
  assert array[32, byte](delta.root) == array[32, byte](after.commitment.root)
  full.records[0].payload[0] = 99
  assert before.lookup(key(0)).value.bytes == @[1'u8]
  let collapsed = after.apply([TrieWrite(key: key(128), kind: TrieWriteKind.Delete)]).value
  assert exportTrieChanges(after, collapsed, default(TrieExportLimits)).value.records.len == 0
  assert exportTrieChanges(before, before, default(TrieExportLimits)).value.records.len == 0
  assert exportFullTrie(before, TrieExportLimits(records: TrieNodeLimit(2),
    valueBytes: ByteLimit(2))).error == TrieError.LimitExceeded
  assert exportFullTrie(before, TrieExportLimits(records: TrieNodeLimit(3),
    valueBytes: ByteLimit(1))).error == TrieError.LimitExceeded
  assert exportFullTrie(default(FullStateTrie), limits).error == TrieError.Uninitialized
  assert calls() == 0
  fail(0)

for i in 0..<25: cycle() # Warm the precise isolated success/refusal workload.
let before = getOccupiedMem()
for i in 0..<1000: cycle() # Canonical owners and detached output buffers retire independently.
let after = getOccupiedMem()
assert before == after
recordArcRelease("storage_node_export", 1000, before, after)
echo "PASS storage node export: full/delta, detached values, cached subtrees, budgets and ARC"
