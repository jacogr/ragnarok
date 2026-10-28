# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real contextual journals restore retained history and explicit finality with the current exact owner.
import std/[assertions, syncio]
import std/posix/posix
import ../../support/disk_history_context
import ../../../src/app/[chain, disk_history]
import ../../../src/chain/[genesis, provider]
import ../../../src/state/[store, disk_store]
import ../../../src/storage/[file_repository, node_repository, node_records, record_codec, database_identity]
import ../../../src/codec/[bounded, state_trie]
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
  let legacy = legacyHistoryBytes(wire)
  let legacyOwner = restoreDiskHistory(legacy, chain, generation,
    fixture.view.bestBlock.value.chainParameters, disk, fixture.policy, limit).value
  assert encodeDiskHistory(legacyOwner, chain, generation, limit).value == wire
  assert encodeMatchingDiskHistory(legacyOwner, chain, generation, limit, legacy).value == legacy
  assert encodeMatchingDiskHistory(owner, chain, generation, limit, [0'u8]).error ==
      DiskHistoryError.InvalidFormat
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
  # V2 persists available count separately from selected capacity, including values above one byte.
  for capacity in [1, 3, 12, 300]:
    let configured = owner.chainView.withRetentionLimit(ElementLimit(capacity)).value
    let selected = initApplicationChain(configured).value
    let encoded = encodeDiskHistory(selected, chain, generation, limit).value
    let decoded = restoreDiskHistory(encoded, chain, generation,
      fixture.view.bestBlock.value.chainParameters, disk, fixture.policy, limit).value
    assert uint64(decoded.chainView.retentionLimit) == uint64(capacity)
    assert decoded.chainView.retainedCount == min(capacity, owner.chainView.retainedCount)
    assert encodeDiskHistory(decoded, chain, generation, limit).value == encoded
    assert sameStateSnapshot(decoded.stateSnapshot.value, disk.snapshot.value)
    assert decoded.chainView.finalizedBlock.error == GenesisError.None
    if capacity != MaxRetainedBlocks:
      assert encodeMatchingDiskHistory(selected, chain, generation, limit, legacy).error ==
          DiskHistoryError.ChainFailure
  # Huge counts/capacities/tags refuse before count-derived allocation or any graph restore.
  for field in 0..<3:
    var invalid = wire
    let offset = HistoryPrefixBytes-24+field*8
    for index in 0..<8: invalid[offset+index] = 255
    if field < 2:
      assert restoreDiskHistory(invalid, chain, generation,
        fixture.view.bestBlock.value.chainParameters, disk, fixture.policy, limit).error ==
            DiskHistoryError.InvalidFormat
  for field in 0..<2:
    var invalid = wire
    let offset = HistoryPrefixBytes-24+field*8
    for index in 0..<8: invalid[offset+index] = 0
    assert restoreDiskHistory(invalid, chain, generation,
      fixture.view.bestBlock.value.chainParameters, disk, fixture.policy, limit).error ==
          DiskHistoryError.InvalidFormat
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
proc wideWitness() {.raises.} =
  ## A real 256-entry journal proves count/finality ordinals no longer truncate to a single byte.
  let fixture = diskHistoryFixture(255, false, ElementLimit(300))
  let selected = fixture.view.finalizeView(fixture.blocks[^1].value.blockHash).value
  let owner = initApplicationChain(selected).value
  let chain = default(StorageChainId)
  let limit = ByteLimit(1048576)
  let limits = JournalLimits(repository: RepositoryLimits(codec: RecordLimits(
    trie: fixture.policy.trie, records: TrieExportLimits(records: TrieNodeLimit(100000),
      valueBytes: ByteLimit(1048576)), encoded: ByteLimit(4194304)),
    records: ElementLimit(100000), valueBytes: ByteLimit(16777216)),
    bytes: ByteLimit(33554432), contextBytes: limit)
  var path = "disk-history-wide.db"
  var disk = default(DiskStateStore)
  defer:
    if disk.opened: discard disk.close # Retained maps outlive the native journal owner.
    discard posix.unlink(path.toCString())
  discard initializeDiskStateStore(disk, path, chain, fixture.blocks[0].value.stateSnapshot,
    limits, StorageSchema.FullStateV1, [1'u8]).value
  for index in 1..<fixture.blocks.len:
    discard disk.commit(disk.snapshot.value, fixture.blocks[index].value.stateSnapshot, [1'u8]).value
  let generation = RepositoryGeneration(uint64(disk.generation.value)+1)
  let encoded = encodeDiskHistory(owner, chain, generation, limit).value
  discard disk.commit(disk.snapshot.value, owner.stateSnapshot.value, encoded).value
  assert disk.close == FileError.None
  discard openLocalDiskStateStore(disk, path, chain, fixture.policy, limits).value
  let restored = restoreDiskHistory(disk.snapshotContext.value, chain, generation,
    selected.bestBlock.value.chainParameters, disk, fixture.policy, limit).value.chainView
  assert restored.retainedCount == 256 and uint64(restored.retentionLimit) == 300
  assert sameStateSnapshot(restored.bestBlock.value.stateSnapshot, disk.snapshot.value)
  assert sameStateSnapshot(restored.finalizedBlock.value.stateSnapshot, disk.snapshot.value)
  for index in 0..<fixture.blocks.len:
    let expected = fixture.blocks[index].value
    let actual = restored.blockAt(expected.blockHash).value
    assert array[32, byte](actual.stateRoot) == array[32, byte](expected.stateRoot)
  # A well-formed ordinal is still bounded by count; declared count cannot exceed actual entries.
  for field in [1, 2]:
    var invalid = encoded
    let offset = HistoryPrefixBytes-24+field*8
    for index in 0..<8: invalid[offset+index] = 0
    invalid[offset] = 1
    invalid[offset+1] = 1 # 257 claims one more entry than the encoded context contains.
    assert restoreDiskHistory(invalid, chain, generation,
      selected.bestBlock.value.chainParameters, disk, fixture.policy, limit).error ==
          DiskHistoryError.InvalidFormat
try:
  main()
  wideWitness()
except:
  quit(2) # Fixture and real IO failures cannot satisfy restoration witnesses.
echo "PASS disk history: durable bounded suffix, evicted finality, exact head owner and malformed-context refusals"
