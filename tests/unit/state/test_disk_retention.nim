# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Configured disk history preserves exact state/body records, header-only validation anchors and honest policy transitions.
import std/[assertions, syncio, envvars]
import std/posix/posix
import ../../support/[disk_history_context, historical_samples, managed_storage_samples,
  durable_chain_context, accumulation_completion_context, accumulation_provision_integration]
import ../../support/report_context as signed_fixture
import ../../../src/app/chain
import ../../../src/app/disk/[chain as disk_chain, history as disk_history]
import ../../../src/app/historical/[context as historical_context, record as historical_record,
    disk as historical_disk]
import ../../../src/app/ancestor/inputs as ancestor_inputs
import ../../../src/chain/[genesis, provider]
import ../../../src/state/[store, disk_store]
import ../../../src/storage/history/[index as history_index, files as history_files]
import ../../../src/storage/file/repository as file_repository
import ../../../src/storage/managed/manifest as managed_manifest
import ../../../src/storage/node/repository as node_repository
import ../../../src/storage/database_identity
import ../../../src/codec/[bounded, header, report_owned]

proc retentionPid(): cint {.importc: "getpid", cdecl, header: "<unistd.h>".}
  ## Process-private paged fixtures never reuse another invocation's files.
proc bodies(source: seq[BlockSnapshotResult]): seq[BlockSnapshotResult] =
  ## Storage fixtures use structural empty extrinsics; genuine producer bytes are exercised separately below.
  result = source
  for index in 1..<result.len:
    let snapshot = result[index].value
    var wire = newSeq[byte](snapshot.header.headerInfo.value.consumed+7)
    assert encodeOwnedHeader(snapshot.header, wire).error == HeaderError.None
    result[index] = withBlockBody(snapshot, wire)
    assert result[index].error == GenesisError.None
proc retainedView(blocks: openArray[BlockSnapshotResult]): ChainView =
  ## Build an authentic linked local suffix while keeping the first structural snapshot as an explicit old anchor.
  result = genesisView(blocks[0]).finalizeView(blocks[0].value.blockHash).value
  for index in 1..<blocks.len: result = result.advanceView(blocks[index]).value
proc compareHeaders(left, right: ChainView) =
  ## User retention cannot change the local ancestor input bytes used by report validation.
  assert left.validationHeaderCount == right.validationHeaderCount
  let config = HeaderConfig(cores: left.bestBlock.value.cores,
    authorValidators: left.bestBlock.value.activeValidators,
    epochSlots: left.bestBlock.value.epochSlots,
    maxBytes: ByteLimit(262144))
  let a = prependLocalAncestors(left, @[], config, ElementLimit(16), ByteLimit(1048576))
  let b = prependLocalAncestors(right, @[], config, ElementLimit(16), ByteLimit(1048576))
  assert a.error == AncestorInputError.None and b.error == AncestorInputError.None
  let first = a.headers
  let second = b.headers
  assert first.len == second.len
  for index in 0..<first.len:
    var x = newSeq[byte](first[index].headerInfo.value.consumed)
    var y = newSeq[byte](second[index].headerInfo.value.consumed)
    assert encodeOwnedHeader(first[index], x).error == HeaderError.None
    assert encodeOwnedHeader(second[index], y).error == HeaderError.None
    assert x == y
proc policyWitness(layout: int) {.raises.} =
  ## Shrink to one complete state while retaining only bounded header inputs and explicit finality outside the window.
  let fixture = diskHistoryFixture(16)
  let blocks = bodies(fixture.blocks)
  let original = retainedView(blocks)
  var owner = initApplicationChain(original).value
  let chain = default(StorageChainId)
  let limits = historicalJournalLimits(fixture.policy)
  let managed = historicalManagedLimits(fixture.policy)
  var path = "disk-retention-" & $layout
  if layout == 2: path.add("-" & $int(retentionPid()))
  var disk = default(DiskStateStore)
  defer:
    if disk.opened: discard disk.close
    removeHistorySample(path, blocks)
    if layout == 0: discard posix.unlink(path.toCString())
    elif layout == 1: removeManagedSample(path, [ManagedEpoch(1), ManagedEpoch(2)])
    # Paged native artifacts remain under the process-private ignored test namespace for inspection.
  if layout == 0: discard initializeDiskChain(disk, path, chain, owner, limits).value
  elif layout == 1: discard initializeManagedDiskChain(disk, path, chain, owner, managed).value
  else: discard initializePagedDiskChain(disk, path, chain, owner, limits).value
  let root = owner.stateSnapshot.value.commitment.root
  discard configureDiskHistory(disk, owner, chain, archiveHistoryPolicy(),
      limits.contextBytes).value
  let before = disk.generation.value
  assert uint64(configureDiskHistory(disk, owner, chain, archiveHistoryPolicy(),
      limits.contextBytes).value) == uint64(before)
  let indexed = checkedDiskHistory(disk, owner, chain, limits.contextBytes).value
  assert indexed.historyCursor.len == 8 and owner.chainView.retainedCount == 8
  let held = readDiskHistoricalSnapshot(disk, owner, chain, HistoryOrdinal(2),
    fixture.policy, limits.contextBytes).value
  let heldHash = held.chainView.bestBlock.value.blockHash
  let heldBody = held.chainView.bestBlock.value.blockBody
  discard configureDiskHistory(disk, owner, chain, boundedHistoryPolicy(1).value,
      limits.contextBytes).value
  assert owner.chainView.retainedCount == 1 and owner.chainView.validationHeaderCount == 8
  assert array[32, byte](owner.stateSnapshot.value.commitment.root) == array[32, byte](root)
  assert sameStateSnapshot(owner.stateSnapshot.value, disk.snapshot.value)
  compareHeaders(original, owner.chainView)
  assert readDiskHistoricalSnapshot(disk, owner, chain, HistoryOrdinal(2), fixture.policy,
    limits.contextBytes).error == HistoryError.Pruned
  assert readDiskHistoricalSnapshot(disk, owner, chain, heldHash, fixture.policy,
    limits.contextBytes).error == HistoryError.Unavailable
  let finalized = readDiskHistoricalSnapshot(disk, owner, chain, blocks[0].value.blockHash,
    fixture.policy, limits.contextBytes).value
  assert array[32, byte](finalized.stateSnapshot.value.commitment.root) == array[32, byte](blocks[
      0].value.stateRoot)
  assert not finalized.chainView.bestBlock.value.hasBlockBody
  if layout == 1:
    let maintenance = prepareDiskMaintenance(disk, owner, chain, limits.contextBytes).value
    discard commitDiskMaintenance(disk, maintenance).value
    assert disk.restoreDiskSnapshot(held.stateSnapshot.value.commitment.root,
      fixture.policy).error != DiskStoreError.None
  assert held.chainView.bestBlock.value.blockBody == heldBody
  assert disk.close == FileError.None
  let opened = if layout == 0: openDiskChain(disk, path, chain, blocks[0].value.chainParameters,
      fixture.policy, limits)
    elif layout == 1: openManagedDiskChain(disk, path, chain, blocks[0].value.chainParameters,
        fixture.policy, managed)
    else: openPagedDiskChain(disk, path, chain, blocks[0].value.chainParameters, fixture.policy, limits)
  owner = opened.value
  assert owner.chainView.retainedCount == 1 and owner.chainView.validationHeaderCount == 8
  compareHeaders(original, owner.chainView)
  assert disk.historyCleanupError == HistoryError.None
  discard configureDiskHistory(disk, owner, chain, archiveHistoryPolicy(),
      limits.contextBytes).value
  let expanded = checkedDiskHistory(disk, owner, chain, limits.contextBytes).value.historyCursor
  assert expanded.len == 1 and uint64(expanded.firstOrdinal) == 8
  assert owner.chainView.retainedCount == 1 # Capacity expansion does not fabricate pruned complete states.
  assert held.chainView.bestBlock.value.blockBody == heldBody
  assert disk.close == FileError.None
proc publicationWitness() {.raises.} =
  ## A genuine signed opaque producer publishes its original complete body and exact state through indexed canonical IO.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  let fixture = durableFixture(decodeOwnedReport(bytes, 2).value)
  var owner = initApplicationChain(genesisView(fixture.parent)).value
  let limits = historicalJournalLimits(signed_fixture.limits())
  let chain = default(StorageChainId)
  var path = "disk-retention-certified-" & $retentionPid()
  var disk = default(DiskStateStore)
  var inventory = @[fixture.parent]
  defer:
    if disk.opened: discard disk.close
    removeHistorySample(path, inventory, 3)
    discard posix.unlink(path.toCString())
  discard initializeDiskChain(disk, path, chain, owner, limits).value
  discard configureDiskHistory(disk, owner, chain, archiveHistoryPolicy(),
      limits.contextBytes).value
  let prepared = owner.prepareAccumulation(fixture.source, completionLimits().composition).value
  inventory.add(prepared.chainView.bestBlock)
  let prior = disk.snapshotContext.value
  let staged = prepareHistoricalRecord(prior, prepared.chainView.bestBlock, chain,
      limits.contextBytes).value
  let stagedResult = stagePreparedHistory(disk, staged)
  discard stagedResult.value # Fully durable orphan bytes still lack canonical selection.
  let future = readDiskHistoricalSnapshot(disk, owner, chain, prepared.child.blockHash,
    signed_fixture.limits(), limits.contextBytes)
  assert future.error == HistoryError.Unavailable
  let published = publishDiskChain(disk, owner, prepared, chain, limits.contextBytes)
  discard published.value
  let loaded = readDiskHistoricalSnapshot(disk, owner, chain, prepared.child.blockHash,
    signed_fixture.limits(), limits.contextBytes).value
  assert loaded.chainView.bestBlock.value.blockBody == prepared.child.blockBody
  assert array[32, byte](loaded.stateSnapshot.value.commitment.root) == array[32, byte](
      prepared.child.stateRoot)
  assert disk.close == FileError.None
  owner = openDiskChain(disk, path, chain, fixture.parent.value.chainParameters,
    signed_fixture.limits(), limits).value
  let restored = readDiskHistoricalSnapshot(disk, owner, chain, HistoryOrdinal(2),
    signed_fixture.limits(), limits.contextBytes).value
  assert restored.chainView.bestBlock.value.blockBody == prepared.child.blockBody
  assert array[32, byte](restored.chainView.bestBlock.value.blockHash) == array[32, byte](
      prepared.child.blockHash)
  assert disk.close == FileError.None

proc stagedCrashWitness() {.raises.} =
  ## A process exits after complete historical staging but before canonical selection; strict reopen keeps the old head.
  let fixture = diskHistoryFixture(1)
  let blocks = bodies(fixture.blocks)
  let chain = default(StorageChainId)
  let limits = historicalJournalLimits(fixture.policy)
  var owner = initApplicationChain(genesisView(blocks[0])).value
  var disk = default(DiskStateStore)
  var path = "disk-retention-staged-crash-" & $retentionPid()
  defer:
    if disk.opened: discard disk.close
    removeHistorySample(path, blocks)
    discard posix.unlink(path.toCString())
  discard initializeDiskChain(disk, path, chain, owner, limits).value
  discard configureDiskHistory(disk, owner, chain, archiveHistoryPolicy(),
      limits.contextBytes).value
  let prepared = prepareHistoricalRecord(disk.snapshotContext.value, blocks[1], chain,
      limits.contextBytes).value
  let generation = uint64(disk.generation.value)
  let child = posix.fork()
  assert int(child) >= 0
  if int(child) == 0:
    let staged = stagePreparedHistory(disk, prepared)
    posix.exitnow(cint(if staged.error == HistoryError.None: 0 else: 3)) # No destructors or core publication run after staging.
  var status = cint(0)
  assert posix.waitpid(child, status, 0) == child and status == 0
  assert disk.close == FileError.None
  owner = openDiskChain(disk, path, chain, blocks[0].value.chainParameters, fixture.policy, limits).value
  assert uint64(disk.generation.value) == generation
  assert array[32, byte](owner.chainView.bestBlock.value.blockHash) == array[32, byte](blocks[
      0].value.blockHash)
  assert readDiskHistoricalSnapshot(disk, owner, chain, HistoryOrdinal(2), fixture.policy,
      limits.contextBytes).error == HistoryError.Unavailable
  assert readDiskHistoricalSnapshot(disk, owner, chain, blocks[1].value.blockHash, fixture.policy,
      limits.contextBytes).error == HistoryError.Unavailable
  assert disk.close == FileError.None

proc archiveWitness() {.raises.} =
  ## Structural storage acceptance spans both old root/count ceilings without asserting consensus admission.
  let fixture = diskHistoryFixture(260)
  let blocks = bodies(fixture.blocks)
  let chain = default(StorageChainId)
  let limits = historicalJournalLimits(fixture.policy)
  let managed = historicalManagedLimits(fixture.policy)
  var path = "disk-retention-archive-" & $retentionPid()
  var destinationPath = "disk-retention-migrated-" & $retentionPid()
  var owner = initApplicationChain(genesisView(blocks[0]).finalizeView(blocks[
      0].value.blockHash).value).value
  var disk = default(DiskStateStore)
  var destination = default(DiskStateStore)
  defer:
    if destination.opened: discard destination.close
    if disk.opened: discard disk.close
    removeHistorySample(path, blocks)
    removeHistorySample(destinationPath, blocks)
    discard posix.unlink(path.toCString())
    removeManagedSample(destinationPath, [ManagedEpoch(1), ManagedEpoch(2)])
  discard initializeDiskChain(disk, path, chain, owner, limits).value
  discard configureDiskHistory(disk, owner, chain, archiveHistoryPolicy(),
      limits.contextBytes).value
  for index in 1..<blocks.len:
    let next = initApplicationChain(owner.chainView.advanceView(blocks[index]).value).value
    let previous = disk.snapshotContext.value
    let staged = prepareHistoricalRecord(previous, blocks[index], chain, limits.contextBytes).value
    let generation = RepositoryGeneration(uint64(disk.generation.value)+1)
    let inner = encodeDiskHistory(next, chain, generation,
      ByteLimit(uint64(limits.contextBytes)-uint64(HistoricalContextPrefixBytes))).value
    let context = encodeHistoricalContext(staged.nextCursor, inner, limits.contextBytes).value
    let selection = stagePreparedHistory(disk, staged).value
    discard disk.commit(owner.stateSnapshot.value, next.stateSnapshot.value, context).value
    owner = next # This explicit structural storage fixture grants no opaque execution certificate.
    assert completePreparedHistory(disk, staged, selection) == HistoryError.None
    assert owner.chainView.retainedCount <= 8
  assert checkedDiskHistory(disk, owner, chain, limits.contextBytes).value.historyCursor.len == 261
  let old = readDiskHistoricalSnapshot(disk, owner, chain, HistoryOrdinal(2), fixture.policy,
      limits.contextBytes).value
  let root = old.stateSnapshot.value.commitment.root
  discard migrateDiskChain(disk, destination, destinationPath, chain, owner, managed).value
  let migrated = restoreDiskHistory(destination.snapshotContext.value, chain,
      destination.generation.value, blocks[0].value.chainParameters, destination, fixture.policy,
      limits.contextBytes).value
  assert readDiskHistoricalSnapshot(destination, migrated, chain, HistoryOrdinal(2), fixture.policy,
    limits.contextBytes).value.chainView.bestBlock.value.blockBody ==
        old.chainView.bestBlock.value.blockBody
  let maintenance = prepareDiskMaintenance(destination, migrated, chain, limits.contextBytes).value
  discard commitDiskMaintenance(destination, maintenance).value
  assert destination.restoreDiskSnapshot(root, fixture.policy).error != DiskStoreError.None
  assert destination.close == FileError.None
  let reopened = openManagedDiskChain(destination, destinationPath, chain, blocks[
      0].value.chainParameters, fixture.policy, managed).value
  let saved = readDiskHistoricalSnapshot(destination, reopened, chain, HistoryOrdinal(2),
      fixture.policy, limits.contextBytes).value
  assert array[32, byte](saved.stateSnapshot.value.commitment.root) == array[32, byte](root)
  assert saved.chainView.bestBlock.value.blockBody == old.chainView.bestBlock.value.blockBody
  assert checkedDiskHistory(disk, owner, chain, limits.contextBytes).value.historyCursor.len == 261
  assert destination.close == FileError.None
  # Existing destinations refuse without replacing their primary data or historical namespace.
  assert migrateDiskChain(disk, destination, destinationPath, chain, owner, managed).error ==
      DiskChainError.HistoryFailure
  assert disk.close == FileError.None

try:
  for layout in 0..2: policyWitness(layout)
  publicationWitness()
  archiveWitness()
  stagedCrashWitness()
except:
  quit(2) # Missing fixtures, failed native publication and wrong historical data cannot pass retention evidence.
echo "PASS disk retention: atomic policy selection, exact accepted records, independent validation headers, finality and restart"
