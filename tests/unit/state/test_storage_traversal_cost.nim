# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Isolated physical repository workloads measure retained table memory and checked shallow/deep graph walks.
import std/[assertions, syncio, envvars, monotimes, times]
import ../../../src/storage/full/state_trie as full_state_trie
import ../../../src/storage/node/[repository as node_repository, records as node_records]
import ../../../src/storage/record_codec
import ../../../src/codec/bounded
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]

type
  Scenario = object ## One mutable owner and nine immutable readers keep all measured storage reachable.
    repository: NodeRepository
    views: seq[RepositoryView]
    policy: StateTrieLimits
  Measurement = object ## Fixed scalars survive scenario release without retaining heap allocations.
    withReaders, currentOnly, readersAfterClose, released: int
    publicationHashes, extractionHashes, cloneHashes, cloneBytes: int
    publicationNs, extractionNs, cloneNs: int64
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Observe genuine hashing while resetting the existing test-only primitive counter.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Count actual attempts independently of graph/table ownership.
proc key(index, offset: int): StateKey =
  ## Offset zero produces shallow routes; offset 29 exercises a 232-bit common prefix.
  assert index >= 0 and index < 65536 and offset in [0, 29]
  var bytes = default(array[31, byte])
  bytes[offset] = byte(index shr 8)
  bytes[offset+1] = byte(index and 255)
  StateKey(bytes)
proc payload(index, size, applied: int): seq[byte] =
  ## Authored deterministic values distinguish each changed key from its original mapping.
  result = newSeq[byte](size)
  let octet = if index < applied: byte(index+1) else: byte(index and 255)
  for position in 0..<size:
    result[position] = octet # Full bytes, including long payloads, participate in map checks.
proc scenario(count, size, offset: int): Scenario =
  ## Populate a bounded independent repository, retaining the initial and last eight of sixteen successors.
  let trie = StateTrieLimits(items: ElementLimit(8192), perValue: ByteLimit(256),
    totalValueBytes: ByteLimit(2097152), nodes: TrieNodeLimit(100000))
  let limits = RepositoryLimits(codec: RecordLimits(trie: trie,
    records: TrieExportLimits(records: TrieNodeLimit(100000), valueBytes: ByteLimit(4194304)),
    encoded: ByteLimit(16777216)), records: ElementLimit(200000), valueBytes: ByteLimit(8388608))
  var entries: seq[StateEntry] = @[]
  for index in 0..<count:
    entries.add(StateEntry(key: key(index, offset), value: payload(index, size, 0)))
  var state = newFullStateTrie(entries, FullStateTrieLimits(trie: trie, writes: ElementLimit(1),
    writeValueBytes: ByteLimit(256))).value
  var repository = newNodeRepository(limits)
  var readers: seq[RepositoryView] = @[repository.publish(repository.snapshot.value,
    exportFullTrie(state, limits.codec.records).value).value]
  reset(0)
  for index in 0..<16:
    let next = state.apply([TrieWrite(key: key(index, offset), kind: TrieWriteKind.Put,
      value: payload(index, size, index+1))]).value
    let view = repository.publish(repository.snapshot.value,
      exportTrieChanges(state, next, limits.codec.records).value).value
    state = next # Public trie and raw exports retire before measured repository ownership is observed.
    if index >= 8:
      readers.add(view) # Exactly eight successive readers plus the separated initial reader.
  Scenario(repository: repository, views: readers, policy: trie)
proc check(view: RepositoryView, policy: StateTrieLimits, count, size, offset, applied: int) =
  ## Compare every sorted key/value with an independently authored complete mapping.
  let entries = restoreStateEntries(view, view.commitment.root, policy).value
  assert entries.len == count
  for index, entry in entries:
    assert array[31, byte](entry.key) == array[31, byte](key(index, offset))
    assert entry.value == payload(index, size, applied)
proc measure(count, size, offset: int): Measurement =
  ## Scoped owners let occupied bytes distinguish shared table storage from unrelated input/trie lifetimes.
  result = default(Measurement)
  let before = getOccupiedMem()
  let publicationStart = getMonoTime()
  var owned = scenario(count, size, offset)
  result.publicationNs = (getMonoTime()-publicationStart).inNanoseconds
  result.publicationHashes = int(calls())
  result.withReaders = getOccupiedMem()-before
  reset(0)
  let extractionStart = getMonoTime()
  for index, view in owned.views:
    let applied = if index == 0: 0 else: index+8
    check(view, owned.policy, count, size, offset, applied)
  result.extractionNs = (getMonoTime()-extractionStart).inNanoseconds
  result.extractionHashes = int(calls())
  assert result.extractionHashes == 0
  block:
    # The plan pins the source independently; measure only additional clone storage under the same policy.
    var roots: seq[StateRoot] = @[]
    for view in owned.views:
      roots.add(view.commitment.root)
    let selection = selectRepositoryRoots(owned.views[^1], roots, ElementLimit(9)).value
    let beforeClone = getOccupiedMem()
    reset(0)
    let cloneStart = getMonoTime()
    var cloned = cloneRepositorySelection(selection, selection.repositoryLimits).value
    result.cloneNs = (getMonoTime()-cloneStart).inNanoseconds
    result.cloneHashes = int(calls())
    result.cloneBytes = getOccupiedMem()-beforeClone
    assert result.cloneHashes == 0
    assert cloned.snapshot.value.storedNodes == selection.retainedNodes
    for index, root in roots:
      let entries = restoreHistoricalStateEntries(cloned.snapshot.value, root, owned.policy).value
      assert entries.len == count
      let applied = if index == 0: 0 else: index+8
      for position, entry in entries:
        assert array[31, byte](entry.key) == array[31, byte](key(position, offset))
        assert entry.value == payload(position, size, applied)
    assert cloned.close == RepositoryError.None
  assert owned.repository.close == RepositoryError.None
  result.readersAfterClose = getOccupiedMem()-before
  for index, view in owned.views:
    let applied = if index == 0: 0 else: index+8
    check(view, owned.policy, count, size, offset, applied) # Every retained reader remains valid after close.
  var latest = owned.views[^1]
  owned.views = @[]
  result.currentOnly = getOccupiedMem()-before # Only the final immutable view retains repository storage.
  latest = default(RepositoryView)
  result.released = getOccupiedMem()-before
  assert result.released == 0
proc row(count, size, offset, sample: int, m: Measurement): string =
  ## Fixed decimal fields keep the evidence independent of any production JSON/parsing path.
  "{\"items\":" & $count & ",\"value_bytes\":" & $size & ",\"offset\":" & $offset &
    ",\"sample\":" & $sample & ",\"with_readers\":" & $m.withReaders &
    ",\"after_close\":" & $m.readersAfterClose & ",\"current_only\":" & $m.currentOnly &
    ",\"publication_hashes\":" & $m.publicationHashes & ",\"extraction_hashes\":" &
        $m.extractionHashes &
    ",\"publication_ns\":" & $m.publicationNs & ",\"extraction_ns\":" & $m.extractionNs &
        ",\"clone_bytes\":" & $m.cloneBytes &
    ",\"clone_hashes\":" & $m.cloneHashes & ",\"clone_ns\":" & $m.cloneNs & "}"
proc main() {.raises.} =
  ## Three repeated samples cover payload size and deep-prefix topology without changing production policies.
  var evidence = "["
  for count in [1024, 8192]:
    for size in [16, 256]:
      for offset in [0, 29]:
        for sample in 0..<3:
          let before = getOccupiedMem()
          let measured = measure(count, size, offset)
          assert getOccupiedMem() == before # No repository/readers/transport scratch can escape the scoped workload.
          if evidence.len > 1:
            evidence.add(",") # Emit one canonical separator between complete measurement rows.
          evidence.add(row(count, size, offset, sample, measured))
  evidence.add("]\n")
  let folder = getEnv("RAGNAROK_TEST_EVIDENCE")
  if folder.len > 0:
    writeFile(folder & "/storage_traversal_cost.json", evidence)
try:
  main()
except:
  quit(2)
echo "PASS storage traversal cost: complete retained maps, shallow/deep routes, scoped memory and hash counters"
