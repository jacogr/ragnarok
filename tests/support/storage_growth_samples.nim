# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Deterministic sustained-publication fixtures keep preparation separate from timed physical IO.
import std/assertions
import ../../src/storage/[full_state_trie, node_repository, node_records, record_codec, file_repository]
import ../../src/codec/[bounded, state_layout, state_trie]

type
  StorageGrowthFixture* = object ## Test-owned changes and complete roots never authorize protocol history.
    seed*: TrieExport
    changes*: seq[TrieExport]
    roots*: seq[StateRoot]

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
  assert count in [1024, 8192] and publications >= 0 and publications <= 256
  assert index >= 0 and index < count
  let writes = publications*4
  let period = if hot: 256 else: count
  if index >= min(writes, period): return 0 # Untouched entries retain their exact seed payload.
  let ordinal = index+((writes-1-index) div period)*period
  ordinal div 4+1
proc growthLimits*(): RepositoryLimits =
  ## Bound complete graphs and accumulated revisions without weakening production admission checks.
  let trie = StateTrieLimits(items: ElementLimit(8192), perValue: ByteLimit(256),
    totalValueBytes: ByteLimit(2097152), nodes: TrieNodeLimit(100000))
  RepositoryLimits(codec: RecordLimits(trie: trie,
    records: TrieExportLimits(records: TrieNodeLimit(100000), valueBytes: ByteLimit(4194304)),
    encoded: ByteLimit(16777216)), records: ElementLimit(200000), valueBytes: ByteLimit(8388608))
proc prepareGrowth*(count, publications: int, hot = false): StorageGrowthFixture =
  ## Prepare Merklized seed/changes once, outside all measured publication/reopen/retention intervals.
  assert count in [1024, 8192] and publications in [64, 256]
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
proc checkGrowth*(view: RepositoryView, root: StateRoot, count, publications: int, hot = false) =
  ## Check every authored key/value using closed-form update expectations outside measured intervals.
  let entries = restoreHistoricalStateEntries(view, root, growthLimits().codec.trie).value
  assert entries.len == count
  for index, entry in entries:
    assert array[31, byte](entry.key) == array[31, byte](growthKey(index))
    assert entry.value == growthValue(index, growthRevision(index, count, publications, hot))
