# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fixed real-file sparse-update workload reports deterministic bytes, crypto work and live ARC memory.
import std/[assertions, syncio, monotimes]
import std/posix/posix
import ../../src/state/[store, disk_store]
import ../../src/storage/[file_repository, node_repository, node_records, record_codec,
  journal_codec, database_identity]
import ../../src/codec/[state_trie, state_layout, bounded]
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Delimit measured update work without counting fixture and independent reference hashing.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Include real graph/codec/frame integrity hashing as well as changed-path commitment work.
proc key(index: int): StateKey =
  ## Deterministically distribute complete identities across early serialized key bits.
  var raw = default(array[31, byte])
  raw[0] = byte(index mod 256)
  raw[1] = byte(index div 256)
  StateKey(raw)
proc sample(count, retained: int) {.raises.} =
  ## Compare 64 one-key updates with equivalent fully encoded frames, retaining one/eight snapshots.
  reset(0)
  let before = getOccupiedMem()
  let policy = StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(count),
    perValue: ByteLimit(33), totalValueBytes: ByteLimit(count*33), nodes: TrieNodeLimit(count*249)),
    writes: ElementLimit(1), writeValueBytes: ByteLimit(33))
  let limits = JournalLimits(repository: RepositoryLimits(codec: RecordLimits(trie: policy.trie,
    records: TrieExportLimits(records: policy.trie.nodes, valueBytes: policy.trie.totalValueBytes),
    encoded: ByteLimit(4000000)), records: ElementLimit(100000), valueBytes: ByteLimit(4000000)),
    bytes: ByteLimit(16000000))
  var entries = newSeq[StateEntry](count)
  for i in 0..<count: entries[i] = StateEntry(key: key(i), value: newSeq[byte](33))
  let seed = newStateStore(entries, policy).value.snapshot.value
  var path = "build/tests/disk-store-workload.db"
  var disk = default(DiskStateStore)
  defer:
    if disk.opened: discard disk.close # Fixture failures retain the file but never leak its native owner.
  assert initializeDiskStateStore(disk, path, default(StorageChainId), seed, limits).error ==
      DiskStoreError.None
  defer: discard posix.unlink(path.toCString())
  var fullBytes = uint64(readFile(path).len)
  var held = newSeq[StateStoreSnapshot](retained)
  let initialized = getOccupiedMem()-before
  var peak = initialized
  var hashes = 0
  var publishNanoseconds = 0'i64
  for step in 0..<64:
    let index = (step*17) mod count
    entries[index].value[0] = byte(step+1)
    let prior = disk.snapshot.value
    held[step mod retained] = prior
    reset(0)
    let started = getMonoTime().ticks
    let changed = disk.apply([StateWrite(key: key(index), kind: StateWriteKind.Put,
      value: entries[index].value)]).value
    publishNanoseconds += getMonoTime().ticks-started
    hashes += int(hashCalls())
    peak = max(peak, getOccupiedMem()-before)
    # Full-frame reference encoding is outside the measured crypto/live-memory region.
    var full = changed.exportStateSnapshot(limits.repository.codec.records).value
    full.base = prior.commitment.root
    fullBytes += uint64(encodeJournalFrame(RepositoryGeneration(uint64(step)+2), full,
      limits.repository.codec, limits.bytes).value.len)
  let occupied = getOccupiedMem()-before
  let expected = stateTrieRoot(entries, policy.trie).value
  let root = disk.snapshot.value.commitment.root
  assert array[32, byte](root) == array[32, byte](expected.root)
  assert uint64(disk.generation.value) == 65
  assert disk.close == FileError.None
  let bytes = readFile(path).len
  let reopenStarted = getMonoTime().ticks
  let restored = openDiskStateStore(disk, path, default(StorageChainId), root,
    RepositoryGeneration(65), policy, limits).value
  let reopenNanoseconds = getMonoTime().ticks-reopenStarted
  assert restored.commitment.entries == count
  for i in 0..<count:
    assert restored.lookup(key(i)).value.bytes == entries[
        i].value # Check every restored value, not only the root.
  assert disk.close == FileError.None
  echo "{\"entries\":" & $count & ",\"retained\":" & $retained & ",\"updates\":64,\"hash_calls\":" &
      $hashes &
    ",\"initialized_bytes\":" & $initialized & ",\"peak_bytes\":" & $peak & ",\"retained_bytes\":" &
        $occupied &
    ",\"journal_bytes\":" & $bytes & ",\"full_frame_bytes\":" & $fullBytes & ",\"publish_ns\":" &
        $publishNanoseconds &
    ",\"reopen_ns\":" & $reopenNanoseconds & "}"
try:
  for count in [128, 1024]:
    for retained in [1, 8]: sample(count, retained) # Each fixture retires all handles before the next case.
except:
  quit(2) # IO/setup failures never produce a partial passing measurement report.
