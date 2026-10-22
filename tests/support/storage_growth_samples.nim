# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Deterministic sustained-publication fixtures keep preparation separate from timed physical IO.
import std/assertions
import ../../src/storage/[full_state_trie, node_repository, node_records, record_codec, file_repository]
import ../../src/codec/[bounded, state_layout, state_trie]

type
  StorageGrowthFixture* = object ## Test-owned changes and complete roots never authorize protocol history.
    seed*: TrieExport          ## Complete physical seed; it grants no protocol-state or checkpoint authority.
    changes*: seq[TrieExport]  ## One prepared four-key physical delta per local revision.
    roots*: seq[StateRoot]     ## Seed root followed by each exact prepared revision.
    reads*: seq[StateNodeHash] ## Final leaf addresses prepared outside measured operations.

proc growthKey*(index: int): StateKey =
  ## Leading two-byte identities preserve sorted complete-map iteration and bound every fixture key.
  assert index >= 0 and index < 65536
  var raw = default(array[31, byte])
  raw[0] = byte(index shr 8)
  raw[1] = byte(index and 255)
  StateKey(raw)
proc growthValue*(index, revision: int): seq[byte] =
  ## Four revision bytes keep generation256 distinct from the seed even when low bytes wrap.
  assert index >= 0 and index < 65536 and revision >= 0 and revision <= 256
  result = newSeq[byte](256)
  for position in 0..<256:
    result[position] = byte((index+position) and 255) # Deterministic full payload is checked after timing.
  for position in 0..<4:
    result[position] = byte((revision shr (position*8)) and 255) # Independent complete revision encoding.
proc growthRevision*(index, count, publications: int, hot = false): int =
  ## Closed-form latest write ordinal is independent of the mutation-preparation loop.
  assert count in [1024, 8192, 32768] and publications >= 0 and publications <= 256
  assert index >= 0 and index < count
  let writes = publications*4
  let period = if hot: 256 else: count
  if index >= min(writes, period): return 0 # Untouched entries retain their exact seed payload.
  let ordinal = index+((writes-1-index) div period)*period
  ordinal div 4+1
proc growthLimits*(): RepositoryLimits =
  ## Bound complete graphs and accumulated revisions without weakening production admission checks.
  let trie = StateTrieLimits(items: ElementLimit(32768), perValue: ByteLimit(256),
    totalValueBytes: ByteLimit(8388608), nodes: TrieNodeLimit(100000))
  RepositoryLimits(codec: RecordLimits(trie: trie,
    records: TrieExportLimits(records: TrieNodeLimit(100000), valueBytes: ByteLimit(16777216)),
    encoded: ByteLimit(67108864)), records: ElementLimit(200000), valueBytes: ByteLimit(33554432))
proc prepareGrowth*(count, publications: int, hot = false): StorageGrowthFixture =
  ## Prepare Merklized seed/changes once, outside all measured publication/reopen/retention intervals.
  assert count in [1024, 8192, 32768] and publications in [64, 256]
  result = default(StorageGrowthFixture)
  let limits = growthLimits()
  var entries: seq[StateEntry] = @[]
  for index in 0..<count:
    entries.add(StateEntry(key: growthKey(index), value: growthValue(index, 0)))
  var state = newFullStateTrie(entries, FullStateTrieLimits(trie: limits.codec.trie,
    writes: ElementLimit(4), writeValueBytes: ByteLimit(1024))).value
  result.seed = exportFullTrie(state, limits.codec.records).value
  result.roots.add(result.seed.root)
  for revision in 1..publications:
    var writes: seq[TrieWrite] = @[]
    for offset in 0..<4:
      let index = ((revision-1)*4+offset) mod (if hot: 256 else: count)
      writes.add(TrieWrite(key: growthKey(index), kind: TrieWriteKind.Put,
        value: growthValue(index, revision)))
    let next = state.apply(writes).value
    result.changes.add(exportTrieChanges(state, next, limits.codec.records).value)
    result.roots.add(next.commitment.root)
    state = next # Every root corresponds to exactly one prepared four-key physical publication.
  let current = exportFullTrie(state, limits.codec.records).value
  for record in current.records:
    if record.kind == TrieRecordKind.Leaf:
      result.reads.add(record.digest) # Prepare only final complete-map leaf addresses, outside timing.
  assert result.reads.len == count
proc checkGrowthEntries*(entries: openArray[StateEntry], count, publications: int, hot = false) =
  ## Independently validate already returned complete maps without hiding a second extraction in timing.
  assert entries.len == count
  for index, entry in entries:
    assert array[31, byte](entry.key) == array[31, byte](growthKey(index))
    assert entry.value == growthValue(index, growthRevision(index, count, publications, hot))
proc checkGrowth*(view: RepositoryView, root: StateRoot, count, publications: int,
    hot = false) =
  ## Historical reachability remains explicitly selected and does not imply canonical/finality authority.
  let entries = restoreHistoricalStateEntries(view, root, growthLimits().codec.trie).value
  checkGrowthEntries(entries, count, publications, hot)

proc checkGrowthHead*(view: RepositoryView, root: StateRoot, count, publications: int,
    hot = false) =
  ## Complete historical reachability alone cannot substitute for the selected head and generation.
  assert array[32, byte](view.commitment.root) == array[32, byte](root)
  assert uint64(view.generation) == uint64(publications+1)
  checkGrowth(view, root, count, publications, hot)

proc checkGrowthRecord*(record: TrieRecord, count, publications: int, hot = false) =
  ## Validate an owned resident lookup result by its full key and independently authored revision payload.
  assert record.kind == TrieRecordKind.Leaf
  let raw = array[31, byte](record.key)
  let index = int(raw[0])*256+int(raw[1])
  assert index < count
  assert raw == array[31, byte](growthKey(index))
  assert record.payload == growthValue(index, growthRevision(index, count, publications, hot))
