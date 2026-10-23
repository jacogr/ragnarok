# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Public-operation retained heap measurements separate payload slopes from immutable graph overhead.
import std/[assertions, envvars, syncio]
import ../../../src/storage/[full_state_trie, node_records, record_codec, node_repository]
import ../../../src/codec/[state_layout, state_trie, bounded]

type
  Fixture = object ## Only serialized transport and scalar expectations outlive graph construction.
    wire: seq[byte]
    root: StateRoot
    count, size, nodes: int

proc policy(): RepositoryLimits =
  ## Fixed independent ceilings bound every authored count, graph and value-size combination.
  RepositoryLimits(codec: RecordLimits(trie: StateTrieLimits(items: ElementLimit(1024),
    perValue: ByteLimit(257), totalValueBytes: ByteLimit(1048576), nodes: TrieNodeLimit(10000)),
    records: TrieExportLimits(records: TrieNodeLimit(10000), valueBytes: ByteLimit(1048576)),
    encoded: ByteLimit(2097152)), records: ElementLimit(10000), valueBytes: ByteLimit(1048576))

proc fixture(count, size: int): Fixture =
  ## Build deterministic distinct leaves, then retire the source map, trie and detached records.
  var entries = newSeq[StateEntry](count)
  for index in 0..<count:
    var key = default(array[31, byte])
    key[0] = byte(index shr 8)
    key[1] = byte(index and 255)
    var payload = newSeq[byte](size)
    for offset in 0..<size:
      payload[offset] = byte((index+offset) and 255) # Every byte has an independently reproducible expectation.
    entries[index] = StateEntry(key: StateKey(key), value: payload)
  let limits = policy()
  let trie = newFullStateTrie(entries, FullStateTrieLimits(trie: limits.codec.trie)).value
  let physical = exportFullTrie(trie, limits.codec.records).value
  Fixture(wire: encodeTrieExport(physical, limits.codec).value, root: trie.commitment.root,
    count: count, size: size, nodes: physical.records.len)

proc observe(source: Fixture): int =
  ## Observe only the admitted graph, keeping the exact serialized source live on both boundaries.
  let before = getOccupiedMem()
  block:
    var repository = newNodeRepository(policy())
    let held = repository.publishEncoded(repository.snapshot.value, source.wire).value
    assert repository.close == RepositoryError.None
    let occupied = getOccupiedMem()
    assert occupied > before
    result = occupied-before
    assert held.storedNodes == source.nodes
    let entries = restoreStateEntries(held, source.root, policy().codec.trie).value
    assert entries.len == source.count
    for index, entry in entries:
      var expected = default(array[31, byte])
      expected[0] = byte(index shr 8)
      expected[1] = byte(index and 255)
      assert array[31, byte](entry.key) == expected
      assert entry.value.len == source.size
      for offset, octet in entry.value:
        assert octet == byte((index+offset) and 255) # Closed owners cannot revoke complete retained values.
  assert getOccupiedMem() == before
  assert source.wire.len > 0 # Stable transport remains outside the measured graph footprint.

proc panel(): string =
  ## Reverse fixture order and require identical live-heap observations before emitting any report.
  result = "entries\tvalue_bytes\tnodes\tretained_bytes\n"
  for count in [32, 512]:
    var measured = default(array[3, int])
    let sizes = [0, 32, 257]
    for turn in 0..1:
      for slot in 0..<3:
        let index = if turn == 0: slot else: 2-slot
        let source = fixture(count, sizes[index])
        let retained = observe(source)
        if turn == 0:
          measured[index] = retained # First order records the same-process absolute live graph footprint.
        else:
          assert retained == measured[index] # Order and prior allocator history cannot explain the retained slope.
    assert measured[1] >= measured[0]+count*32
    assert measured[2] >= measured[1]+count*(257-32)
    for index in 0..<3:
      let source = fixture(count, sizes[index])
      result.add($count & "\t" & $sizes[index] & "\t" & $source.nodes & "\t" & $measured[index] & "\n")

proc run() =
  ## Keep report and environment strings in a procedure scope so their ARC owners retire before accounting.
  let report = panel()
  let directory = getEnv("RAGNAROK_TEST_EVIDENCE")
  if directory.len > 0:
    try:
      writeFile(directory & "/storage-retained-layout.tsv", report)
    except:
      assert false, "Retained layout evidence write failed" # An IO failure cannot leave a passing stale observation.

# Warm the stdlib process-environment cache before measuring test-owned report retirement.
discard getEnv("RAGNAROK_TEST_EVIDENCE")
let before = getOccupiedMem()
run()
assert getOccupiedMem() == before, "Panel report owners must retire"
echo "PASS storage retained layout: reversed heap slopes, closed-owner maps and exact release"
