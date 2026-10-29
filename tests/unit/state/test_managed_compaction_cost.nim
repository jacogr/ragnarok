# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fixed checked compaction workloads record actual hash attempts and retained bytes before/after trusted-path changes.
import std/[assertions, syncio, envvars, monotimes, times]
import ../../support/managed_storage_samples
import ../../../src/state/store
import ../../../src/storage/managed/[repository as managed_repository, manifest as managed_manifest]
import ../../../src/storage/node/[repository as node_repository, records as node_records]
import ../../../src/storage/[database_identity, record_codec]
import ../../../src/storage/file/errors as file_errors
import ../../../src/codec/bounded
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Existing observer restores real primitive behavior and resets counters, without replacing runtime implementations.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Count actual primitive attempts independently of source-level measurement claims.
proc key(number: int): StateKey =
  ## Authored workloads bound the two nonzero prefix bytes before conversion.
  var raw = default(array[31, byte])
  raw[0] = byte(number shr 8)
  raw[1] = byte(number and 255)
  StateKey(raw)
proc hex(bytes: array[32, byte]): string =
  ## Fixed public digests produce deterministic evidence without another hash operation.
  const digits = "0123456789abcdef"
  result = ""
  for octet in bytes:
    result.add(digits[int(octet shr 4)]); result.add(digits[int(octet and 15)])
proc workload(count, iteration: int): string {.raises.} =
  ## Each isolated file receives 64 sparse commits then retains the last eight roots plus the initial root.
  assert count in [128, 1024]
  reset(0)
  let trie = StateTrieLimits(items: ElementLimit(4096), perValue: ByteLimit(64),
    totalValueBytes: ByteLimit(1048576), nodes: TrieNodeLimit(100000))
  let physical = RepositoryLimits(codec: RecordLimits(trie: trie,
    records: TrieExportLimits(records: TrieNodeLimit(100000), valueBytes: ByteLimit(1048576)),
    encoded: ByteLimit(16777216)), records: ElementLimit(1000000), valueBytes: ByteLimit(16777216))
  let limits = ManagedLimits(repository: physical, roots: ElementLimit(9), snapshotBytes: ByteLimit(
      67108864),
    journalBytes: ByteLimit(134217728), contextBytes: ByteLimit(64))
  var entries: seq[StateEntry] = @[]
  for index in 0..<count:
    var value = newSeq[byte](16)
    for position in 0..<value.len: value[position] = byte(index and 255)
    entries.add(StateEntry(key: key(index), value: value))
  var state = newStateStore(entries, StateStoreLimits(trie: trie, writes: ElementLimit(1),
      writeValueBytes: ByteLimit(16))).value
  var source = newNodeRepository(physical)
  let initial = source.publish(source.snapshot.value, state.snapshot.value.exportStateSnapshot(
      physical.codec.records).value).value
  let selection = selectRepositoryRoots(initial, [initial.commitment.root], limits.roots).value
  let path = "managed-compaction-cost-" & $count & "-" & $iteration
  var repository = default(ManagedRepository)
  defer:
    if repository.opened: discard repository.close
  assert initializeManagedRepository(repository, path, default(StorageChainId), selection, [0'u8],
    limits, StorageSchema.FullStateV1) == FileError.None
  var roots: seq[StateRoot] = @[initial.commitment.root]
  for index in 0..<64:
    let previous = state.snapshot.value
    var value = newSeq[byte](16)
    for position in 0..<value.len: value[position] = byte(index+1)
    let changed = state.apply([StateWrite(key: key(index), kind: StateWriteKind.Put,
        value: value)]).value
    let batch = exportStateChanges(previous, changed, physical.codec.records).value
    let committed = repository.publish(repository.snapshot.value, batch, [byte(index+1)]).value
    if index >= 56: roots.add(committed.commitment.root)
  let before = repository.usage.value
  let selected = repository.snapshot.value
  reset(0)
  let started = getMonoTime()
  let compacted = repository.compact(selected, roots).value
  let elapsed = (getMonoTime()-started).inNanoseconds
  let hashes = int(calls())
  let after = repository.usage.value
  assert compacted.cleanup == FileError.None and compacted.reclaimedNodes > 0
  assert uint64(after.generation) == 65 and uint64(after.epoch) == 2
  assert array[32, byte](after.root) == array[32, byte](state.snapshot.value.commitment.root)
  assert after.storedNodes < before.storedNodes and after.journalBytes == uint64(ManagedJournalHeaderBytes)
  assert repository.close == FileError.None
  reset(0)
  assert openManagedRepository(repository, path, default(StorageChainId), limits,
      StorageSchema.FullStateV1) == FileError.None
  let reopenedHashes = int(calls())
  for root in roots:
    assert restoreHistoricalStateEntries(repository.snapshot.value, root, trie).value.len == count
  let snapshot = readFile(path & "/snapshot-0000000000000002.bin")
  assert uint64(snapshot.len) == after.snapshotBytes and snapshot.len >= 32
  var checksum = default(array[32, byte])
  for index in 0..<32: checksum[index] = byte(snapshot[snapshot.len-32+index])
  assert repository.close == FileError.None
  removeManagedSample(path, [ManagedEpoch(1), ManagedEpoch(2)])
  assert source.close == RepositoryError.None
  "{\"items\":" & $count & ",\"sample\":" & $iteration & ",\"compaction_hashes\":" & $hashes &
    ",\"reopen_hashes\":" & $reopenedHashes & ",\"nanoseconds\":" & $elapsed &
    ",\"before_nodes\":" & $before.storedNodes & ",\"after_nodes\":" & $after.storedNodes &
    ",\"snapshot_bytes\":" & $after.snapshotBytes & ",\"journal_bytes\":" & $after.journalBytes &
    ",\"root\":\"" & hex(array[32, byte](after.root)) & "\",\"checksum\":\"" & hex(checksum) & "\"}"
proc main() {.raises.} =
  ## Ten identical repeats per size record deterministic counters/bytes and descriptive timing, never a speed threshold.
  var evidence = "["
  for count in [128, 1024]:
    for iteration in 0..<10:
      if evidence.len > 1: evidence.add(",")
      evidence.add(workload(count, iteration))
  evidence.add("]\n")
  let folder = getEnv("RAGNAROK_TEST_EVIDENCE")
  if folder.len > 0: writeFile(folder & "/managed_compaction_cost.json", evidence)
try:
  main()
except:
  quit(2)
echo "PASS managed compaction cost: checked sparse history, retained roots, exact snapshot bytes and observed hash counts"
