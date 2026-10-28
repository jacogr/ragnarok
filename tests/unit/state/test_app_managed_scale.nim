# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded larger-state lifecycle measurements verify all retained maps and record exact hash/space counters.
import std/assertions
import std/syncio
import std/envvars
import std/monotimes
import std/times
import ../../support/app_managed_storage_samples
import ../../../src/state/store as state_store
import ../../../src/storage/managed_repository as storage_managed_repository
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/storage/node_repository as storage_node_repository
import ../../../src/storage/node_records as storage_node_records
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/storage/record_codec as storage_record_codec
import ../../../src/storage/file_errors as storage_file_errors
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset the existing real-primitive observer before each measured phase.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Count real hash attempts without changing their results.
proc hex(bytes: string): string =
  ## Preserve exact already-written digest bytes without extra hash attempts in measured phases.
  const digits = "0123456789abcdef"
  result = ""
  for octet in bytes:
    result.add(digits[int(byte(octet) shr 4)])
    result.add(digits[int(byte(octet) and 15)])
proc key(number: int): StateKey =
  ## Authored indices fit two bytes and produce canonical lexical key order.
  assert number >= 0 and number < 65536
  var raw = default(array[31, byte])
  raw[0] = byte(number shr 8)
  raw[1] = byte(number and 255)
  StateKey(raw)
proc value(number, size, applied: int): seq[byte] =
  ## The first applied keys have their new value; all other keys retain their original bytes.
  result = newSeq[byte](size)
  let octet = if number < applied: byte(number+1) else: byte(number and 255)
  for index in 0..<size:
    result[index] = octet # Fixed authored values let map validation stay independent of repository extraction.
proc checkMap(view: RepositoryView, root: StateRoot, trie: StateTrieLimits,
    count, size, applied: int) =
  ## Compare every sorted key/value against the authored history, including the separated oldest root.
  let restored = restoreHistoricalStateEntries(view, root, trie)
  assert restored.error == RepositoryError.None
  let entries = restored.value
  assert entries.len == count
  for index, entry in entries:
    assert array[31, byte](entry.key) == array[31, byte](key(index))
    assert entry.value == value(index, size, applied)
proc workload(count, size, sample: int): string {.raises.} =
  ## Sixteen sparse commits retain eight successive roots plus the initial root across replay/compaction.
  assert count in [1024, 8192] and size in [16, 256]
  let trie = StateTrieLimits(items: ElementLimit(8192), perValue: ByteLimit(256),
    totalValueBytes: ByteLimit(2097152), nodes: TrieNodeLimit(100000))
  let physical = RepositoryLimits(codec: RecordLimits(trie: trie,
    records: TrieExportLimits(records: TrieNodeLimit(100000), valueBytes: ByteLimit(4194304)),
    encoded: ByteLimit(16777216)), records: ElementLimit(200000), valueBytes: ByteLimit(8388608))
  let limits = ManagedLimits(repository: physical, roots: ElementLimit(9),
    snapshotBytes: ByteLimit(33554432), journalBytes: ByteLimit(33554432), contextBytes: ByteLimit(64))
  var entries: seq[StateEntry] = @[]
  for index in 0..<count:
    entries.add(StateEntry(key: key(index), value: value(index, size, 0)))
  var state = newStateStore(entries, StateStoreLimits(trie: trie, writes: ElementLimit(1),
    writeValueBytes: ByteLimit(256))).value
  var source = newNodeRepository(physical)
  let initial = source.publish(source.snapshot.value,
    state.snapshot.value.exportStateSnapshot(physical.codec.records).value).value
  let selection = selectRepositoryRoots(initial, [initial.commitment.root], limits.roots).value
  let path = "managed-scale-" & $count & "-" & $size & "-" & $sample
  var repository = default(ManagedRepository)
  defer:
    if repository.opened:
      discard repository.close # Release the directory even if an IO exception interrupts the fixture.
  assert initializeManagedRepository(repository, path, default(StorageChainId), selection, [0'u8],
    limits, StorageSchema.FullStateV1) == FileError.None
  var roots: seq[StateRoot] = @[initial.commitment.root]
  var applied: seq[int] = @[0]
  reset(0)
  let publicationStart = getMonoTime()
  for index in 0..<16:
    let previous = state.snapshot.value
    let changed = state.apply([StateWrite(key: key(index), kind: StateWriteKind.Put,
      value: value(index, size, index+1))]).value
    let batch = exportStateChanges(previous, changed, physical.codec.records).value
    let committed = repository.publish(repository.snapshot.value, batch, [byte(index+1)]).value
    if index >= 8:
      roots.add(committed.commitment.root) # The rolling eight are separate from explicit initial retention.
      applied.add(index+1)
  let publicationNs = (getMonoTime()-publicationStart).inNanoseconds
  let publicationHashes = int(calls())
  let retained = repository.snapshot.value
  let occupiedWithReader = getOccupiedMem()
  let before = repository.usage.value
  assert repository.close == FileError.None
  reset(0)
  let replayStart = getMonoTime()
  assert openManagedRepository(repository, path, default(StorageChainId), limits,
    StorageSchema.FullStateV1) == FileError.None
  let replayNs = (getMonoTime()-replayStart).inNanoseconds
  let replayHashes = int(calls())
  let extraValues = if size > 32: count+16 else: 0
  assert replayHashes == before.storedNodes+18+extraValues # One physical integrity pass plus16 frame and2 selected-file checks.
  reset(0)
  let extractionStart = getMonoTime()
  for index, root in roots:
    checkMap(repository.snapshot.value, root, trie, count, size, applied[index])
  let extractionNs = (getMonoTime()-extractionStart).inNanoseconds
  let extractionHashes = int(calls())
  assert extractionHashes == 0
  reset(0)
  let compactStart = getMonoTime()
  let compacted = repository.compact(repository.snapshot.value, roots).value
  let compactNs = (getMonoTime()-compactStart).inNanoseconds
  let compactHashes = int(calls())
  let after = repository.usage.value
  assert compacted.cleanup == FileError.None and compacted.reclaimedNodes > 0
  assert uint64(after.generation) == 17 and uint64(after.epoch) == 2
  assert array[32, byte](after.root) == array[32, byte](state.snapshot.value.commitment.root)
  assert after.storedNodes < before.storedNodes
  assert after.journalBytes == uint64(ManagedJournalHeaderBytes)
  assert repository.close == FileError.None
  reset(0)
  let reopenStart = getMonoTime()
  assert openManagedRepository(repository, path, default(StorageChainId), limits,
    StorageSchema.FullStateV1) == FileError.None
  let reopenNs = (getMonoTime()-reopenStart).inNanoseconds
  let reopenHashes = int(calls())
  assert reopenHashes == after.storedNodes+2+extraValues # Compacted header-only journals add no revision-frame hashes.
  for index, root in roots:
    checkMap(repository.snapshot.value, root, trie, count, size, applied[index])
  assert repository.close == FileError.None
  for index, root in roots:
    checkMap(retained, root, trie, count, size, applied[
        index]) # Readers survive physical retirement and owner close.
  let snapshotBytes = readFile(path & "/snapshot-0000000000000002.bin")
  assert snapshotBytes.len >= 32
  let checksum = hex(snapshotBytes[snapshotBytes.len-32..<snapshotBytes.len])
  assert source.close == RepositoryError.None
  removeManagedSample(path, [ManagedEpoch(1), ManagedEpoch(2)])
  "{\"items\":" & $count & ",\"value_bytes\":" & $size & ",\"sample\":" & $sample &
    ",\"publication_hashes\":" & $publicationHashes & ",\"publication_ns\":" & $publicationNs &
    ",\"replay_hashes\":" & $replayHashes & ",\"replay_ns\":" & $replayNs &
    ",\"extraction_hashes\":" & $extractionHashes & ",\"extraction_ns\":" & $extractionNs &
    ",\"compaction_hashes\":" & $compactHashes & ",\"compaction_ns\":" & $compactNs &
    ",\"reopen_hashes\":" & $reopenHashes & ",\"reopen_ns\":" & $reopenNs &
    ",\"before_nodes\":" & $before.storedNodes & ",\"after_nodes\":" & $after.storedNodes &
    ",\"snapshot_bytes\":" & $after.snapshotBytes & ",\"occupied_with_reader\":" &
        $occupiedWithReader & ",\"checksum\":\"" & checksum & "\"}"
proc main() {.raises.} =
  ## Three repetitions describe timing spread; deterministic counters must agree across each identical workload.
  var evidence = "["
  for count in [1024, 8192]:
    for size in [16, 256]:
      for sample in 0..<3:
        if evidence.len > 1:
          evidence.add(",") # Separate complete records without a trailing JSON separator.
        evidence.add(workload(count, size, sample))
  evidence.add("]\n")
  let folder = getEnv("RAGNAROK_TEST_EVIDENCE")
  if folder.len > 0:
    writeFile(folder & "/managed_scale.json", evidence) # The native runner owns this isolated evidence directory.
try:
  main()
except:
  quit(2)
echo "PASS managed scale: complete nine-root maps, replay/compaction/reopen counters and retained readers"
