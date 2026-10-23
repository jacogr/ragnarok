# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact owning full/delta/inverse exports preserve canonical records, source isolation, strict admission and release.
# @@Verification={"arc": "full_state_trie_exports_arc_release"}
import std/[assertions, syncio]
import ../../support/arc_evidence
import ../../../src/storage/[full_state_trie, node_records, node_repository, record_codec]
import ../../../src/codec/[state_layout, state_trie, bounded]
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Admitted immutable graph export needs no new hash, including typed preflight refusals.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Count actual primitive attempts across full/delta/inverse ownership extraction.
proc policy(): RepositoryLimits =
  ## Complete maps, copied batch transport and aggregate physical history keep separate fixed ceilings.
  let trie = StateTrieLimits(items: ElementLimit(8192), perValue: ByteLimit(256),
    totalValueBytes: ByteLimit(2097152), nodes: TrieNodeLimit(200000))
  RepositoryLimits(codec: RecordLimits(trie: trie, records: TrieExportLimits(records: TrieNodeLimit(200000),
    valueBytes: ByteLimit(2097152)), encoded: ByteLimit(67108864)), records: ElementLimit(400000),
        valueBytes: ByteLimit(8388608))
proc key(number: int): StateKey =
  ## Bounded ordinal bytes produce real shared-prefix branches and both bitmap/descriptor size boundaries.
  var raw = default(array[31, byte])
  raw[0] = byte(number shr 8)
  raw[1] = byte(number and 255)
  StateKey(raw)
proc fixture(count, size: int): FullStateTrie =
  ## Independently checked complete roots and source retirement precede all transport memory observations.
  var entries = newSeq[StateEntry](count)
  for index in 0..<count:
    var bytes = newSeq[byte](size)
    for offset in 0..<size: bytes[offset] = byte((index+offset) and 255)
    entries[index] = StateEntry(key: key(index), value: bytes)
  let reference = stateTrieRoot(entries, policy().codec.trie).value
  var initialized = newFullStateTrie(entries, FullStateTrieLimits(trie: policy().codec.trie,
    writes: ElementLimit(1), writeValueBytes: ByteLimit(256)))
  let before = getOccupiedMem()
  let trie = initialized.takeValue
  assert initialized.error == TrieError.Uninitialized and getOccupiedMem() == before
  assert array[32, byte](trie.commitment.root) == array[32, byte](reference.root)
  assert trie.commitment.entries == count and trie.commitment.nodes == reference.nodes
  trie
proc allocation(records: seq[TrieRecord]): int =
  ## Separate exact descriptor/value allocations calibrate real allocator classes without inspecting seq capacity.
  let before = getOccupiedMem()
  var total = 0
  block:
    let descriptors = newSeq[TrieRecord](records.len)
    total = getOccupiedMem()-before
    assert descriptors.len == records.len
  assert getOccupiedMem() == before
  for record in records:
    if record.kind == TrieRecordKind.Leaf:
      let bytes = newSeq[byte](record.payload.len)
      total+=getOccupiedMem()-before
      assert bytes.len == record.payload.len
    # Each calibration value retires before measuring another; no scratch becomes returned transport storage.
  assert getOccupiedMem() == before
  total
proc exported(base, target: FullStateTrie): TrieExport =
  ## Calibrate the still-held result, preserve copying access, then transfer the exact owned transport once.
  let limits = policy().codec.records
  reset(1)
  let before = getOccupiedMem()
  var outcome = exportTrieChanges(base, target, limits)
  assert outcome.error == TrieError.None and calls() == 0
  let retained = getOccupiedMem()-before
  block:
    var copy = outcome.value
    assert retained == allocation(copy.records)
    for index in 0..<copy.records.len:
      if copy.records[index].kind == TrieRecordKind.Leaf and copy.records[index].payload.len > 0:
        copy.records[index].payload[0] = copy.records[index].payload[0] xor 255
        # Changing the detached copy cannot mutate either the original result or its immutable trie source.
  assert getOccupiedMem()-before == retained
  let beforeTransfer = getOccupiedMem()
  result = outcome.takeValue
  assert outcome.error == TrieError.Uninitialized and getOccupiedMem() == beforeTransfer
  assert array[32, byte](result.base) == array[32, byte](base.commitment.root)
  assert array[32, byte](result.root) == array[32, byte](target.commitment.root)
  assert result.entries == uint64(target.commitment.entries) and result.nodes ==
      target.commitment.nodes
  if result.records.len > 0:
    var short = limits
    short.records = TrieNodeLimit(result.records.len-1)
    assert exportTrieChanges(base, target, short).error == TrieError.LimitExceeded
    var values = 0'u64
    for record in result.records:
      if record.kind == TrieRecordKind.Leaf: values+=uint64(record.payload.len)
    if values > 0:
      short = limits
      short.valueBytes = ByteLimit(values-1)
      assert exportTrieChanges(base, target, short).error == TrieError.LimitExceeded
  assert calls() == 0
  reset(0)
proc exercise(count, size: int) =
  ## Independent complete repository admission validates every exported full/delta/inverse graph and historical reader.
  let empty = fixture(0, 0)
  let first = fixture(count, size)
  let full = exported(empty, first)
  var owner = newNodeRepository(policy())
  let initial = owner.publish(owner.snapshot.value, full).value
  assert array[32, byte](initial.commitment.root) == array[32, byte](first.commitment.root)
  let noChange = exported(first, first)
  assert noChange.records.len == 0
  if count > 0:
    let changed = first.apply([TrieWrite(key: key(count div 2), kind: TrieWriteKind.Put, value: @[19'u8])]).value
    let delta = exported(first, changed)
    let next = owner.publish(initial, delta).value
    let inverse = exported(changed, first)
    let restored = owner.publish(next, inverse).value
    assert array[32, byte](restored.commitment.root) == array[32, byte](initial.commitment.root)
    assert restoreHistoricalStateEntries(restored, next.commitment.root, policy().codec.trie).value.len == count
    assert first.lookup(key(count div 2)).value.byteLength == size
    let removed = exported(first, empty)
    assert removed.records.len == 0
    assert owner.publish(restored, removed).value.commitment.entries == 0
    var valueResult = first.lookup(key(count div 2))
    let before = getOccupiedMem()
    let held = valueResult.takeValue
    assert valueResult.error == TrieError.Uninitialized and held.byteLength == size
    assert getOccupiedMem() == before
  assert owner.close == RepositoryError.None
  assert restoreStateEntries(initial, initial.commitment.root, policy().codec.trie).value.len == count

for size in [0, 33, 256]:
  for count in [0, 1, 31, 32, 33, 127, 128, 129, 8192]: exercise(count, size)
for warmup in 0..<10: exercise(2, 33)
let before = getOccupiedMem()
for iteration in 0..<1000: exercise(2, 33)
let after = getOccupiedMem()
assert before == after
recordArcRelease("full_state_trie_exports", 1000, before, after)
echo "PASS full state trie exports: exact owned buffers, copy/transfer isolation, inverse replay, refusals and ARC"
