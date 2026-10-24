# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The complete disk facade preserves exact owned state/context, retained application history and native uncertainty on paged storage.
# @@Verification={"arc":"paged_disk_state_store_arc_release"}
import std/[assertions, syncio]
import ../../support/[arc_evidence, storage_io, full_paged_reference, full_paged_native_fixture,
  disk_history_context]
import ../../../src/state/[store, paged_state, disk_store]
import ../../../src/app/[chain, disk_history]
import ../../../src/chain/[genesis, provider]
import ../../../src/storage/[full_paged_codec, full_paged_store, full_paged_stream,
  full_paged_build,
  node_records, node_repository, paged_codec, managed_manifest, file_errors, durability,
  database_identity]
import ../../../src/codec/[bounded, state_trie]
func statePolicy(): StateStoreLimits =
  ## Full-map limits remain separate from native context, export and physical working policies.
  StateStoreLimits(trie: policy().trie, writes: ElementLimit(10), writeValueBytes: ByteLimit(10000))
proc state(value: byte): StateStoreSnapshot =
  ## Independent ordinary complete maps contain one changed value and a present-empty value.
  newStateStore(@[StateEntry(key: key(0), value: @[value]), StateEntry(key: key(128), value: @[])],
      statePolicy()).value.snapshot.value
proc path(label: string): string =
  ## Every native workload owns its exact test namespace without a cleanup sweep.
  "paged-disk-state-" & $storageProcessId() & "-" & label
proc configuration(source: StateStoreSnapshot, stateLimits: StateStoreLimits): FullPagedNativeConfig =
  ## Finite application-sized policies admit nine retained roots and independently bounded opaque history context.
  result = sample(5).config
  result.root = source.commitment.root
  result.limits.trie = stateLimits.trie
  result.limits.roots = ElementLimit(9)
  result.limits.dataset = PagedLimits(entries: ElementLimit(1000000), bytes: ByteLimit(64000000))
  result.limits.contextBytes = ByteLimit(4194304)
  result.limits.workingBytes = ByteLimit(32000000)
  result.limits.scratchBytes = ByteLimit(8000000)
  result.limits.work.ioCalls = ElementLimit(10000000)
  result.limits.work.hashes = ElementLimit(10000000)
  result.limits.work.visits = ElementLimit(10000000)
  result.limits.work.readBytes = ByteLimit(1000000000)
  result.limits.work.writeBytes = ByteLimit(64000000)
  result.construction = FullPagedConstructionLimits(producerCalls: ElementLimit(10000000),
    ioCalls: ElementLimit(10000000), hashes: ElementLimit(10000000),
    readBytes: ByteLimit(1000000000), writeBytes: ByteLimit(64000000))
proc transport(config: FullPagedNativeConfig): PagedStateLimits =
  ## Aggregate staging charges every retained map before physical record deduplication.
  PagedStateLimits(roots: ElementLimit(9), staging: TrieExportLimits(records: TrieNodeLimit(
      10000000),
    valueBytes: ByteLimit(64000000)), dataset: config.limits.dataset)
proc normal() =
  ## Successful publication adopts the exact target owner only after one durable complete-root/context selection.
  let source = state(5)
  let target = state(9)
  let config = configuration(source, statePolicy())
  let limits = transport(config)
  let directory = path("normal")
  var disk = default(DiskStateStore)
  var other = default(DiskStateStore)
  defer:
    # Native retirement remains explicit across successful, busy and uncertain owners.
    resetIo()
    if other.opened: discard other.close
    if disk.opened: discard disk.close
  assert initializePagedDiskStateStore(disk, directory, source, config, limits, [7'u8]).error ==
      DiskStoreError.None
  assert sameStateSnapshot(disk.snapshot.value, source)
  assert uint64(disk.generation.value) == 1 and disk.snapshotContext.value == @[7'u8]
  assert disk.synchronize.value == StorageDurability.FileAndDirectorySynced
  assert disk.managedDiskUsage.error == FileError.UnsupportedLayout
  assert disk.cleanupManagedDiskFiles == FileError.UnsupportedLayout
  let busy = openLocalPagedDiskStateStore(other, directory, config.chain, statePolicy(), config, limits)
  assert busy.error == DiskStoreError.FileFailure and busy.fileError == FileError.Busy
  assert not other.opened
  assert disk.commit(target, source, [9'u8]).error == DiskStoreError.StaleSnapshot
  assert disk.commit(source, target).error == DiskStoreError.ContextRequired
  assert disk.commit(source, target, [9'u8], [source]).error == DiskStoreError.None
  assert sameStateSnapshot(disk.snapshot.value, target)
  assert uint64(disk.generation.value) == 2 and disk.snapshotContext.value == @[9'u8]
  assert disk.restoreDiskSnapshot(source.commitment.root, statePolicy()).value.lookup(key(
      0)).value.bytes == @[5'u8]
  let retained = disk.snapshot.value
  assert disk.close == FileError.None
  assert retained.lookup(key(0)).value.bytes == @[9'u8]
  assert openLocalPagedDiskStateStore(disk, directory, config.chain, statePolicy(), config,
      limits).error == DiskStoreError.None
  assert disk.snapshot.value.lookup(key(0)).value.bytes == @[9'u8]
  assert uint64(disk.generation.value) == 2 and disk.snapshotContext.value == @[9'u8]
  assert disk.restoreDiskSnapshot(source.commitment.root, statePolicy()).value.lookup(key(
      0)).value.bytes == @[5'u8]
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    # Independent historical complete maps and detached context values must release every temporary owner.
    assert disk.restoreDiskSnapshot(source.commitment.root, statePolicy()).value.lookup(key(
        0)).value.bytes == @[5'u8]
    assert disk.snapshotContext.value == @[9'u8]
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("paged_disk_state_store", 1000, before, after)
  assert disk.close == FileError.None
proc history() {.raises.} =
  ## Existing application restoration binds rolling headers, nine complete roots and older explicit finality on the paged facade.
  let fixture = diskHistoryFixture()
  let owner = initApplicationChain(fixture.view).value
  let source = owner.stateSnapshot.value
  let config = configuration(source, fixture.policy)
  var retained: seq[StateStoreSnapshot] = @[]
  for index in 0..<fixture.view.retainedCount-1:
    # The exact current owner is supplied separately; every older rolling snapshot remains complete.
    retained.add(fixture.view.retainedBlockAt(RetainedBlockIndex(index)).value.stateSnapshot)
  retained.add(fixture.view.finalizedBlock.value.stateSnapshot)
  let context = encodeDiskHistory(owner, config.chain, RepositoryGeneration(1),
      config.limits.contextBytes).value
  let directory = path("history")
  var disk = default(DiskStateStore)
  defer:
    if disk.opened: discard disk.close # Failed context binding never abandons the native writer lease.
  assert initializePagedDiskStateStore(disk, directory, source, config, transport(config), context,
      retained).error == DiskStoreError.None
  assert disk.close == FileError.None
  assert openLocalPagedDiskStateStore(disk, directory, config.chain, fixture.policy, config,
      transport(config)).error == DiskStoreError.None
  let restored = restoreDiskHistory(disk.snapshotContext.value, config.chain, disk.generation.value,
    fixture.view.bestBlock.value.chainParameters, disk, fixture.policy, config.limits.contextBytes)
  assert restored.error == DiskHistoryError.None
  assert sameStateSnapshot(restored.value.stateSnapshot.value, disk.snapshot.value)
  assert encodeDiskHistory(restored.value, config.chain, disk.generation.value,
      config.limits.contextBytes).value == context
  assert restored.value.chainView.retainedCount == MaxRetainedBlocks
  assert array[32, byte](restored.value.chainView.finalizedBlock.value.blockHash) == array[32,
      byte](fixture.view.finalizedBlock.value.blockHash)
  assert disk.close == FileError.None
proc faults() =
  ## Real publication rename and fresh durability failures retain old owned memory without claiming a successful writable head.
  let source = state(5)
  let target = state(9)
  let config = configuration(source, statePolicy())
  let limits = transport(config)
  for operation in [renameIo, syncIo]:
    # Each fault gets an independently synchronized source namespace and a fresh explicit native incarnation.
    let directory = path("fault-" & $operation)
    var disk = default(DiskStateStore)
    assert initializePagedDiskStateStore(disk, directory, source, config, limits, [7'u8]).error ==
        DiskStoreError.None
    armIo(operation, 0, 1, failedIo)
    let failed = if operation == renameIo: disk.commit(source, target, [9'u8], [source])
      else:
        # A failed explicit barrier is a file failure, not a publication result with a fabricated snapshot.
        let synced = disk.synchronize
        assert synced.error != FileError.None
        disk.snapshot
    assert pendingIo() == 0
    resetIo()
    assert failed.error == DiskStoreError.FileFailure
    assert source.lookup(key(0)).value.bytes == @[5'u8]
    assert disk.snapshot.error != DiskStoreError.None
    assert disk.close == FileError.None
    assert openLocalPagedDiskStateStore(disk, directory, config.chain, statePolicy(), config,
        limits).error == DiskStoreError.None
    assert disk.snapshot.value.lookup(key(0)).value.bytes == @[5'u8]
    assert disk.snapshotContext.value == @[7'u8] and uint64(disk.generation.value) == 1
    assert disk.close == FileError.None
proc lateBarrier() =
  ## A failed final directory barrier leaves old memory private while fresh recovery resolves the actual new CURRENT/context pair.
  let source = state(5)
  let target = state(9)
  let config = configuration(source, statePolicy())
  let limits = transport(config)
  var disk = default(DiskStateStore)
  let baseline = path("barrier-baseline")
  assert initializePagedDiskStateStore(disk, baseline, source, config, limits, [7'u8]).error ==
      DiskStoreError.None
  resetIo()
  assert disk.commit(source, target, [9'u8], [source]).error == DiskStoreError.None
  let calls = ioCalls(syncIo)
  assert calls > 0 and calls <= uint64(high(cint))
  assert disk.close == FileError.None
  let directory = path("late-barrier")
  assert initializePagedDiskStateStore(disk, directory, source, config, limits, [7'u8]).error ==
      DiskStoreError.None
  armIo(syncIo, cint(calls-1), 1, failedIo)
  let failed = disk.commit(source, target, [9'u8], [source])
  assert failed.error == DiskStoreError.FileFailure and failed.fileError ==
      FileError.PublishedUnsynced
  assert pendingIo() == 0
  resetIo()
  assert disk.snapshot.error != DiskStoreError.None
  assert source.lookup(key(0)).value.bytes == @[5'u8]
  assert disk.close == FileError.None
  assert openLocalPagedDiskStateStore(disk, directory, config.chain, statePolicy(), config,
      limits).error == DiskStoreError.None
  assert disk.snapshot.value.lookup(key(0)).value.bytes == @[9'u8]
  assert disk.snapshotContext.value == @[9'u8] and uint64(disk.generation.value) == 2
  assert disk.close == FileError.None
proc main() {.raises.} =
  ## Native facade behavior and complete application context restoration share one supported runner and exact fixture contract.
  normal()
  history()
  faults()
  lateBarrier()
  echo "paged disk state store PASS"
try:
  main()
except:
  quit(2) # Fixture IO failure cannot masquerade as a passing history-restoration witness.
