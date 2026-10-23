# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Calibrated payload and independent-clone observations separate retained graph components through public APIs.
import std/[assertions, envvars, syncio]
import ../../../src/storage/[full_state_trie, node_records, record_codec, node_repository]
import ../../../src/codec/[state_layout, state_trie, bounded]

type
  Fixture = object ## Stable serialized input survives preparation without a source graph owner.
    wire: seq[byte]
    root: StateRoot
    count, size, nodes: int
  Observation = object ## Scalar receipts keep report formatting outside every allocator boundary.
    graph, selection, clone: int

proc policy(): RepositoryLimits =
  ## Fixed checked ceilings admit all finite calibration cases without input-derived policy relaxation.
  RepositoryLimits(codec: RecordLimits(trie: StateTrieLimits(items: ElementLimit(8192),
    perValue: ByteLimit(257), totalValueBytes: ByteLimit(4194304), nodes: TrieNodeLimit(20000)),
    records: TrieExportLimits(records: TrieNodeLimit(20000), valueBytes: ByteLimit(4194304)),
    encoded: ByteLimit(16777216)), records: ElementLimit(20000), valueBytes: ByteLimit(4194304))

proc fixture(count, size: int): Fixture =
  ## Authored keys and complete values reproduce the prior layout panel at larger directory thresholds.
  var entries = newSeq[StateEntry](count)
  for index in 0..<count:
    var key = default(array[31, byte])
    key[0] = byte(index shr 8)
    key[1] = byte(index and 255)
    var payload = newSeq[byte](size)
    for offset in 0..<size:
      payload[offset] = byte((index+offset) and 255) # Every payload byte is checked after explicit owner close.
    entries[index] = StateEntry(key: StateKey(key), value: payload)
  let limits = policy()
  let trie = newFullStateTrie(entries, FullStateTrieLimits(trie: limits.codec.trie)).value
  let physical = exportFullTrie(trie, limits.codec.records).value
  Fixture(wire: encodeTrieExport(physical, limits.codec).value, root: trie.commitment.root,
    count: count, size: size, nodes: physical.records.len)

proc check(view: RepositoryView, source: Fixture) =
  ## Complete extraction checks all keys and values without contributing to the retained measurement.
  let entries = restoreStateEntries(view, source.root, policy().codec.trie).value
  assert entries.len == source.count and view.storedNodes == source.nodes
  for index, entry in entries:
    var expected = default(array[31, byte])
    expected[0] = byte(index shr 8)
    expected[1] = byte(index and 255)
    assert array[31, byte](entry.key) == expected and entry.value.len == source.size
    for offset, octet in entry.value:
      assert octet == byte((index+offset) and 255) # Source and cloned owners cannot share caller-mutable bytes.

proc admitted(source: Fixture): RepositoryView =
  ## Retire admission's empty snapshot and result temporaries before measuring the sole complete graph owner.
  var owner = newNodeRepository(policy())
  result = owner.publishEncoded(owner.snapshot.value, source.wire).value
  assert owner.close == RepositoryError.None

proc observe(source: Fixture): Observation =
  ## A complete selection clone owns a fresh table while sharing immutable cells with the retained source.
  let before = getOccupiedMem()
  block:
    let held = admitted(source)
    result = Observation(graph: getOccupiedMem()-before, selection: 0, clone: 0)
    assert result.graph > 0
    let beforeSelection = getOccupiedMem()
    let selection = selectRepositoryRoots(held, [source.root], ElementLimit(1)).value
    result.selection = getOccupiedMem()-beforeSelection
    assert result.selection > 0
    assert selection.retainedNodes == source.nodes
    assert selection.retainedValueBytes == uint64(source.count)*uint64(source.size)
    let selected = getOccupiedMem()
    block:
      var cloned = cloneRepositorySelection(selection, policy()).value
      result.clone = getOccupiedMem()-selected
      assert result.clone > 0 and result.clone < result.graph # A clone must not duplicate the complete immutable cell graph.
      let independent = cloned.snapshot.value
      assert cloned.close == RepositoryError.None
      check(independent, source)
    assert getOccupiedMem() == selected # The clone's references/index/metadata retire independently.
    check(held, source)
  assert getOccupiedMem() == before

proc payloadHeap(count, size: int): int =
  ## Exclude the live descriptor array before allocating exactly one ordinary sequence per leaf value.
  let initial = getOccupiedMem()
  block:
    var values = newSeq[seq[byte]](count)
    let before = getOccupiedMem()
    for index in 0..<count:
      values[index] = newSeq[byte](size)
      if size > 0:
        values[index][size-1] = byte(index and 255) # Keep every allocation live and independently observable.
    result = getOccupiedMem()-before
    for index in 0..<count:
      assert values[index].len == size
      if size > 0:
        assert values[index][size-1] == byte(index and 255)
  assert getOccupiedMem() == initial

proc offsetHeap(count: int): int =
  ## Calibrate an exact machine-word sequence without any private allocator or repository inspection API.
  let before = getOccupiedMem()
  block:
    var offsets = newSeq[int](count)
    offsets[count-1] = count
    result = getOccupiedMem()-before
    assert offsets[count-1] == count
  assert getOccupiedMem() == before

proc panel(): string =
  ## Reverse payload order and compare scalar observations before publishing component receipts.
  result = "entries\tvalue_bytes\tnodes\tgraph_bytes\tselection_bytes\tclone_bytes\tpayload_heap_bytes\treference_array_bytes\n"
  const Sizes = [0, 1, 15, 16, 17, 31, 32, 33, 255, 256, 257]
  for count in [32, 512, 8192]:
    var graphs = default(array[11, int])
    var selections = default(array[11, int])
    var clones = default(array[11, int])
    var payloads = default(array[11, int])
    var nodes = 0
    for turn in 0..1:
      for slot in 0..<Sizes.len:
        let index = if turn == 0: slot else: Sizes.len-1-slot
        let source = fixture(count, Sizes[index])
        let observation = observe(source)
        let calibrated = payloadHeap(count, Sizes[index])
        if turn == 0:
          graphs[index] = observation.graph
          selections[index] = observation.selection
          clones[index] = observation.clone
          payloads[index] = calibrated
          nodes = source.nodes
        else:
          assert observation.graph == graphs[index] and observation.clone == clones[index]
          assert observation.selection == selections[index]
          assert calibrated == payloads[index] and source.nodes == nodes
    assert payloads[0] == 0
    for index in 0..<Sizes.len:
      assert selections[index] == selections[0] # Reachability indices depend on physical inventory, not value sizes.
      assert clones[index] == clones[0] # Table references/index cost depends on node count, not payload size.
      assert graphs[index]-graphs[0] == payloads[index] # Assign payload growth only when independent calibration agrees.
      assert payloads[index] >= count*Sizes[index]
      result.add($count & "\t" & $Sizes[index] & "\t" & $nodes & "\t" & $graphs[index] &
        "\t" & $selections[index] & "\t" & $clones[index] & "\t" & $payloads[index] & "\t" &
            $offsetHeap(nodes) & "\n")
  result.add("directory_offsets\t4\t" & $offsetHeap(17) & "\n")
  result.add("directory_offsets\t8\t" & $offsetHeap(257) & "\n")
  result.add("directory_offsets\t12\t" & $offsetHeap(4097) & "\n")

proc run() =
  ## The supported runner owns the evidence namespace; file errors fail instead of preserving a stale pass.
  let report = panel()
  let directory = getEnv("RAGNAROK_TEST_EVIDENCE")
  if directory.len > 0:
    try:
      writeFile(directory & "/storage-retained-components.tsv", report)
    except:
      assert false, "Retained component evidence write failed"

# The stdlib's persistent environment cache is not part of repository-owned allocation.
discard getEnv("RAGNAROK_TEST_EVIDENCE")
let before = getOccupiedMem()
run()
assert getOccupiedMem() == before
echo "PASS storage retained components: calibrated payloads, independent clones, reversed cases and exact release"
