# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Full paged application bootstrap and strict restart bind every rolling root, complete header/profile and older explicit finality.
import std/[assertions, syncio]
import ../../support/[disk_history_context, application_checkpoint_context]
import ../../../src/app/chain
import ../../../src/app/disk/[chain as disk_chain, history as disk_history]
import ../../../src/app/paged/policy as paged_policy
import ../../../src/chain/[genesis, provider]
import ../../../src/state/[store, disk_store]
import ../../../src/storage/file/repository as file_repository
import ../../../src/storage/node/[repository as node_repository, records as node_records]
import ../../../src/storage/[record_codec, database_identity]
import ../../../src/codec/bounded
import ../../../src/codec/state/trie as state_trie
proc appPid(): cint {.importc: "getpid", cdecl, header: "<unistd.h>".}
  ## Process-private application namespaces preserve earlier forensic artifacts without stale test collisions.
proc main() {.raises.} =
  ## Only the final atomic V2 selection can restore a canonical history; failed identity/profile binding retires every lease.
  let fixture = diskHistoryFixture()
  let owner = initApplicationChain(fixture.view).value
  let identity = default(StorageChainId)
  let limits = JournalLimits(repository: RepositoryLimits(codec: RecordLimits(
    trie: fixture.policy.trie, records: TrieExportLimits(records: TrieNodeLimit(100000),
      valueBytes: ByteLimit(1048576)), encoded: ByteLimit(4194304)),
    records: ElementLimit(100000), valueBytes: ByteLimit(16777216)),
    bytes: ByteLimit(33554432), contextBytes: ByteLimit(1048576))
  let path = "paged-disk-chain-" & $appPid()
  var disk = default(DiskStateStore)
  defer:
    if disk.opened: discard disk.close # Every successful and refused application binding retires its native owner.
  let bounded = pagedApplicationPolicy(identity, owner.stateSnapshot.value.commitment.root, limits)
  assert uint64(bounded.native.limits.dataset.bytes) == uint64(limits.bytes)
  assert uint64(bounded.native.limits.contextBytes) == uint64(limits.contextBytes)
  assert uint64(bounded.contextBytes)+uint64(PagedDiskContextOverhead) == uint64(
      limits.contextBytes)
  assert uint64(bounded.transport.staging.records) == 900000
  assert uint64(bounded.transport.staging.valueBytes) == 9437184'u64
  let initialized = initializePagedDiskChain(disk, path, identity, owner, limits)
  assert initialized.error == DiskChainError.None and uint64(initialized.value) == 1
  assert disk.pagedStorage and sameStateSnapshot(disk.snapshot.value, owner.stateSnapshot.value)
  let context = disk.snapshotContext.value
  assert encodeDiskHistory(owner, identity, initialized.value, limits.contextBytes).value == context
  assert initializePagedDiskChain(disk, path, identity, owner, limits).error == DiskChainError.Busy
  assert disk.close == FileError.None
  let restored = openPagedDiskChain(disk, path, identity,
    fixture.view.bestBlock.value.chainParameters, fixture.policy, limits)
  assert restored.error == DiskChainError.None
  assert sameStateSnapshot(restored.value.stateSnapshot.value, disk.snapshot.value)
  assert disk.snapshotContext.value == context and uint64(disk.generation.value) == 1
  let view = restored.value.chainView
  assert view.retainedCount == MaxRetainedBlocks
  assert array[32, byte](view.finalizedBlock.value.blockHash) == array[32, byte](
      fixture.view.finalizedBlock.value.blockHash)
  for index in 0..<fixture.view.retainedCount:
    # Every historical header must resolve to its exact complete map from the same admitted native root union.
    let expected = fixture.view.retainedBlockAt(RetainedBlockIndex(index)).value
    let selected = view.blockAt(expected.blockHash).value
    assert array[32, byte](selected.stateRoot) == array[32, byte](expected.stateRoot)
    assert array[32, byte](selected.stateSnapshot.commitment.root) == array[32, byte](
        expected.stateRoot)
  assert disk.close == FileError.None
  let current = readFile(path & "/CURRENT")
  let wrongProfile = checkpointFixture(CheckpointFixtureVariant.Profile).chainView.bestBlock.value.chainParameters
  let refusedProfile = openPagedDiskChain(disk, path, identity, wrongProfile, fixture.policy, limits)
  assert refusedProfile.error == DiskChainError.ContextFailure and not disk.opened
  assert readFile(path & "/CURRENT") == current
  var wrong = default(array[32, byte])
  wrong[0] = 1
  assert openPagedDiskChain(disk, path, StorageChainId(wrong),
    fixture.view.bestBlock.value.chainParameters, fixture.policy, limits).error ==
        DiskChainError.StoreFailure
  assert not disk.opened and readFile(path & "/CURRENT") == current
  assert initializePagedDiskChain(disk, path, identity, owner, limits).error ==
      DiskChainError.StoreFailure
  assert not disk.opened and readFile(path & "/CURRENT") == current
  assert openPagedDiskChain(disk, path, identity,
    fixture.view.bestBlock.value.chainParameters, fixture.policy, limits).error ==
        DiskChainError.None
  assert disk.close == FileError.None
try:
  main()
except:
  quit(2) # Fixture and real IO failures cannot establish local application authority.
echo "PASS paged disk chain: atomic complete roots/context, rolling history, finality and profile/identity refusal"
