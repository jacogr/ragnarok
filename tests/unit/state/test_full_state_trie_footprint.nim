# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Public trie-owner measurements preserve independently checked roots, copied paths and retained singleton values.
import std/[assertions, envvars, syncio]
import ../../../src/storage/full/state_trie as full_state_trie
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]
import ../../../src/codec/bounded

type
  Fixture = object ## Construction retires every source map and independent reference scratch before measurement.
    trie: FullStateTrie
    expected: StateTrieCommitment
    count, size: int
  Observation = object ## Scalar receipts keep reporting outside graph/path/value allocator boundaries.
    nodes: uint64
    graph, path, leaf: int

proc policy(): FullStateTrieLimits =
  ## Complete maps and one-key mutation batches have independent fixed ceilings.
  FullStateTrieLimits(trie: StateTrieLimits(items: ElementLimit(8192), perValue: ByteLimit(257),
    totalValueBytes: ByteLimit(4194304), nodes: TrieNodeLimit(20000)),
    writes: ElementLimit(1), writeValueBytes: ByteLimit(257))

proc key(index: int): StateKey =
  ## Leading two-byte identities preserve full-key order and force real shared-prefix unary branches.
  var raw = default(array[31, byte])
  raw[0] = byte(index shr 8)
  raw[1] = byte(index and 255)
  StateKey(raw)

proc payload(index, size: int): seq[byte] =
  ## Reproduce every original value byte independently of trie extraction or physical export.
  result = newSeq[byte](size)
  for offset in 0..<size:
    result[offset] = byte((index+offset) and 255)

proc fixture(count, size: int): Fixture =
  ## The separate complete-map calculator supplies root/count authority without using incremental node caches.
  var entries = newSeq[StateEntry](count)
  for index in 0..<count:
    entries[index] = StateEntry(key: key(index), value: payload(index, size))
  let expected = stateTrieRoot(entries, policy().trie).value
  Fixture(trie: newFullStateTrie(entries, policy()).value, expected: expected,
    count: count, size: size)

proc check(source: Fixture) =
  ## Verify complete roots, exact topology and every value after independent mutation observations.
  let actual = source.trie.commitment
  assert array[32, byte](actual.root) == array[32, byte](source.expected.root)
  assert actual.entries == source.expected.entries and actual.nodes == source.expected.nodes
  for index in 0..<source.count:
    let value = source.trie.lookup(key(index)).value
    assert value.byteLength == source.size and value.bytes == payload(index, source.size)

proc observe(count, size: int): Observation =
  ## Retain a leaf beyond both revision lifetimes, then prove complete graph and leaf retirement separately.
  let before = getOccupiedMem()
  var held = default(TrieValue)
  result = Observation(nodes: 0, graph: 0, path: 0, leaf: 0)
  block:
    let source = fixture(count, size)
    result.graph = getOccupiedMem()-before
    result.nodes = source.expected.nodes
    assert result.graph > 0
    if count > 0:
      let middle = count div 2
      held = source.trie.lookup(key(middle)).value
      let replacement = payload(middle, size+1)
      let prior = getOccupiedMem()
      block:
        let changed = source.trie.apply([TrieWrite(key: key(middle), kind: TrieWriteKind.Put,
          value: replacement)]).value
        result.path = getOccupiedMem()-prior
        assert result.path > 0
        assert changed.lookup(key(middle)).value.bytes == replacement
        assert held.bytes == payload(middle, size)
        assert changed.commitment.entries == count
      assert getOccupiedMem() == prior # Copied path owners retire while the source graph and held value survive.
    check(source)
  result.leaf = getOccupiedMem()-before
  if count > 0:
    assert result.leaf > 0 and held.bytes == payload(count div 2, size)
  else:
    assert result.leaf == 0 # An empty initialized trie cannot manufacture a retained leaf owner.
  held = default(TrieValue)
  assert getOccupiedMem() == before

proc payloadHeap(size: int): int =
  ## Calibrate ordinary payload allocation so the node-owner budget excludes value-size rounding.
  let before = getOccupiedMem()
  block:
    let owned = payload(0, size)
    result = getOccupiedMem()-before
    assert owned.len == size
  assert getOccupiedMem() == before

proc panel(): string =
  ## Reverse the full count/value order and require identical graph, path and singleton-live observations.
  const Counts = [0, 1, 32, 512, 8192]
  const Sizes = [0, 32, 256]
  var seen = default(array[15, Observation])
  result = "entries\tvalue_bytes\tnodes\tgraph_bytes\tpath_bytes\tleaf_bytes\n"
  for turn in 0..1:
    for slot in 0..<15:
      let index = if turn == 0: slot else: 14-slot
      let observed = observe(Counts[index div 3], Sizes[index mod 3])
      let values = payloadHeap(Sizes[index mod 3])
      let budget = observed.nodes*128'u64+uint64(Counts[index div 3]*values)+96'u64
      assert uint64(observed.graph) <= budget # Keep live graph ownership below128 bytes per node plus values/revision.
      assert observed.leaf <= values+128 # A held value cannot retain the old graph or a redundant large leaf owner.
      if turn == 0:
        seen[index] = observed # First order records only current live allocations, never a process high-water value.
      else:
        assert observed.nodes == seen[index].nodes and observed.graph == seen[index].graph
        assert observed.path == seen[index].path and observed.leaf == seen[index].leaf
  for index in 3..<15:
    assert seen[index].leaf == seen[3+index mod 3].leaf # A held leaf's footprint is independent of source graph size.
  for index in 0..<15:
    result.add($Counts[index div 3] & "\t" & $Sizes[index mod 3] & "\t" & $seen[index].nodes &
      "\t" & $seen[index].graph & "\t" & $seen[index].path & "\t" & $seen[index].leaf & "\n")

proc run() =
  ## A file error must fail the supported runner instead of preserving stale measurement evidence.
  let report = panel()
  let directory = getEnv("RAGNAROK_TEST_EVIDENCE")
  if directory.len > 0:
    try:
      writeFile(directory & "/full-state-trie-footprint.tsv", report)
    except:
      assert false, "Trie footprint evidence write failed"

# Warm the persistent stdlib environment cache before observing test-owned graph and report release.
discard getEnv("RAGNAROK_TEST_EVIDENCE")
let before = getOccupiedMem()
run()
assert getOccupiedMem() == before
echo "PASS full state trie footprint: independent roots, copied paths, retained leaves and exact release"
