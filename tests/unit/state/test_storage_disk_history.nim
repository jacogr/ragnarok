# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real contextual journals restore retained history and explicit finality with the current exact owner.
import std/assertions
import std/syncio
import std/posix/posix
import ../../support/storage_disk_history_context
import ../../../src/app/chain as app_chain
import ../../../src/app/disk_history as app_disk_history
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/provider as chain_provider
import ../../../src/state/store as state_store
import ../../../src/state/disk_store as state_disk_store
import ../../../src/storage/file_repository as storage_file_repository
import ../../../src/storage/node_repository as storage_node_repository
import ../../../src/storage/node_records as storage_node_records
import ../../../src/storage/record_codec as storage_record_codec
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_trie as codec_state_trie
proc main() {.raises.} =
  ## Populate authentic complete roots before context selection; modified fixture headers are structural only.
  let fixture = diskHistoryFixture()
  let owner = initApplicationChain(fixture.view).value
  let chain = default(StorageChainId)
  let limit = ByteLimit(1048576)
  let limits = JournalLimits(repository: RepositoryLimits(codec: RecordLimits(
    trie: fixture.policy.trie, records: TrieExportLimits(records: TrieNodeLimit(100000),
      valueBytes: ByteLimit(1048576)), encoded: ByteLimit(4194304)),
    records: ElementLimit(100000), valueBytes: ByteLimit(16777216)),
    bytes: ByteLimit(33554432), contextBytes: limit)
  var path = "disk-history.db"
  var disk = default(DiskStateStore)
  defer:
    if disk.opened: discard disk.close # Every assertion/refusal still retires the journal owner.
  discard initializeDiskStateStore(disk, path, chain, fixture.blocks[0].value.stateSnapshot,
    limits, StorageSchema.FullStateV1, [1'u8]).value
  defer: discard posix.unlink(path.toCString())
  for index in 1..<fixture.blocks.len:
    discard disk.commit(disk.snapshot.value, fixture.blocks[index].value.stateSnapshot, [1'u8]).value
  let generation = RepositoryGeneration(uint64(disk.generation.value)+1)
  let wire = encodeDiskHistory(owner, chain, generation, limit).value
  discard disk.commit(disk.snapshot.value, owner.stateSnapshot.value, wire).value
  assert disk.close == FileError.None
  discard openLocalDiskStateStore(disk, path, chain, fixture.policy, limits).value
  let restored = restoreDiskHistory(disk.snapshotContext.value, chain, generation,
    fixture.view.bestBlock.value.chainParameters, disk, fixture.policy, limit).value
  assert sameStateSnapshot(restored.stateSnapshot.value, disk.snapshot.value)
  assert encodeDiskHistory(restored, chain, generation, limit).value == wire
  assert restored.chainView.retainedCount == MaxRetainedBlocks
  assert array[32, byte](restored.chainView.finalizedBlock.value.blockHash) ==
    array[32, byte](fixture.view.finalizedBlock.value.blockHash)
  for index in 0..<fixture.view.retainedCount:
    let expected = fixture.view.retainedBlockAt(RetainedBlockIndex(index)).value
    let selected = restored.chainView.blockAt(expected.blockHash).value
    assert array[32, byte](selected.stateRoot) == array[32, byte](expected.stateRoot)
    for ordinal in 0..<expected.stateSnapshot.commitment.entries:
      let key = expected.stateSnapshot.keyAt(StateEntryIndex(ordinal)).value
      assert selected.stateSnapshot.lookup(key).value.bytes == expected.stateSnapshot.lookup(
          key).value.bytes
  # Absent and in-window finality have distinct exact encodings and preserve owner sharing.
  var retained: seq[BlockSnapshotResult] = @[]
  for index in 0..<fixture.view.retainedCount:
    retained.add(fixture.view.retainedBlockAt(RetainedBlockIndex(index)))
  for tag in [0, 3]:
    let finalized = if tag == 0: unavailableGenesis() else: retained[tag-1]
    let selected = initApplicationChain(restoreLocalChainView(retained, finalized).value).value
    let encoded = encodeDiskHistory(selected, chain, generation, limit).value
    let decoded = restoreDiskHistory(encoded, chain, generation,
      fixture.view.bestBlock.value.chainParameters, disk, fixture.policy, limit).value.chainView
    if tag == 0:
      assert decoded.finalizedBlock.error == GenesisError.Unavailable
    else:
      assert sameStateSnapshot(decoded.finalizedBlock.value.stateSnapshot,
        decoded.retainedBlockAt(RetainedBlockIndex(tag-1)).value.stateSnapshot)
  # Every truncation, impossible length, unknown tag and changed hint refuses without publishing.
  for stop in 0..<wire.len:
    assert restoreDiskHistory(wire.toOpenArray(0, stop-1), chain, generation,
      fixture.view.bestBlock.value.chainParameters, disk, fixture.policy, limit).error !=
          DiskHistoryError.None
  for location in [0, HistoryPrefixBytes-2, HistoryPrefixBytes-1, HistoryPrefixBytes,
      HistoryPrefixBytes+32, wire.high]:
    var changed = wire
    changed[location] = changed[location] xor 127
    assert restoreDiskHistory(changed, chain, generation,
      fixture.view.bestBlock.value.chainParameters, disk, fixture.policy, limit).error !=
          DiskHistoryError.None
  var trailing = wire
  trailing.add(0'u8)
  assert restoreDiskHistory(trailing, chain, generation,
    fixture.view.bestBlock.value.chainParameters, disk, fixture.policy, limit).error ==
        DiskHistoryError.InvalidFormat
  assert encodeDiskHistory(owner, chain, generation, ByteLimit(wire.len-1)).error ==
      DiskHistoryError.LimitExceeded
  assert restoreDiskHistory(wire, chain, RepositoryGeneration(uint64(generation)+1),
    fixture.view.bestBlock.value.chainParameters, disk, fixture.policy, limit).error ==
        DiskHistoryError.StoreFailure
  var huge = wire
  for index in HistoryPrefixBytes+32..<HistoryPrefixBytes+40: huge[index] = 255
  assert restoreDiskHistory(huge, chain, generation,
    fixture.view.bestBlock.value.chainParameters, disk, fixture.policy, limit).error ==
        DiskHistoryError.InvalidFormat
  var narrow = fixture.policy
  narrow.writes = ElementLimit(0)
  assert restoreDiskHistory(wire, chain, generation,
    fixture.view.bestBlock.value.chainParameters, disk, narrow, limit).error ==
        DiskHistoryError.StoreFailure
  let held = disk.snapshot.value
  assert sameStateSnapshot(held, restored.stateSnapshot.value)
  assert uint64(disk.generation.value) == uint64(generation)
  assert disk.close == FileError.None
  assert posix.unlink(path.toCString()) == 0
  # A context with complete historical bindings cannot substitute for absent historical node records.
  let missing = encodeDiskHistory(owner, chain, RepositoryGeneration(1), limit).value
  discard initializeDiskStateStore(disk, path, chain, owner.stateSnapshot.value,
    limits, StorageSchema.FullStateV1, missing).value
  assert restoreDiskHistory(missing, chain, RepositoryGeneration(1),
    fixture.view.bestBlock.value.chainParameters, disk, fixture.policy, limit).error ==
        DiskHistoryError.StoreFailure
try:
  main()
except:
  quit(2) # Fixture and real IO failures cannot satisfy restoration witnesses.
echo "PASS disk history: durable bounded suffix, evicted finality, exact head owner and malformed-context refusals"
