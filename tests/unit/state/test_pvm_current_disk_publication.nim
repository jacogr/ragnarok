# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_current_disk_publication_arc_release"}

## Genuine current PVM successors commit before canonical/RPC visibility and reopen with exact state/history.
import std/assertions
import std/envvars
import std/syncio
import std/posix/posix
import ../../support/state_accumulation_current_chain_context
import ../../support/state_accumulation_provision_integration
import ../../support/app_managed_storage_samples
import ../../support/rpc_socket
import ../../support/testing_arc_evidence
import ../../../src/app/chain as app_chain
import ../../../src/app/disk_chain as app_disk_chain
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/provider as chain_provider
import ../../../src/chain/parameters as chain_parameters
import ../../../src/state/store as state_store
import ../../../src/state/disk_store as state_disk_store
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/storage/file_repository as storage_file_repository
import ../../../src/storage/node_repository as storage_node_repository
import ../../../src/storage/node_records as storage_node_records
import ../../../src/storage/record_codec as storage_record_codec
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/storage/managed_repository as storage_managed_repository
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/rpc/server as rpc_server
proc journalLimits(): JournalLimits =
  ## Explicit broad fixture ceilings bound all physical records, individual batches and history context.
  JournalLimits(repository: RepositoryLimits(codec: RecordLimits(trie: StateTrieLimits(
    items: ElementLimit(100000), perValue: ByteLimit(1048576), totalValueBytes: ByteLimit(16777216),
    nodes: TrieNodeLimit(1000000)), records: TrieExportLimits(records: TrieNodeLimit(1000000),
      valueBytes: ByteLimit(16777216)), encoded: ByteLimit(33554432)),
    records: ElementLimit(2000000), valueBytes: ByteLimit(67108864)),
    bytes: ByteLimit(134217728), contextBytes: ByteLimit(1048576))

proc listener(rpc: var Server, view: ChainView) =
  ## Reserve ephemeral ports, with bounded retry for the release/start race.
  let parameters = decodeParameters(currentChainSettings().encodeParameters)
  for attempt in 0..<8:
    let selected = reservation()
    discard posix.close(selected.fd)
    if rpc.start(selected.port, "current-disk-test", parameters, view): return
  assert false, "current disk RPC startup failed"
proc witness(context: CurrentChainFixture, managed, enabled: bool) {.raises.} =
  ## Both physical backends retain the exact prepared child; refusal never writes or installs a prefix.
  let original = initApplicationChain(context.currentChainSeeded).value
  var owner = original
  let prepared = owner.prepareAccumulation(context.source, ByteLimit(100000)).value
  let limits = journalLimits()
  let physical = ManagedLimits(repository: limits.repository, roots: ElementLimit(9),
    snapshotBytes: ByteLimit(33554432), journalBytes: limits.bytes,
        contextBytes: limits.contextBytes)
  let identity = default(StorageChainId)
  var path = if managed: "current-managed-disk" else: "current-disk.db"
  var disk = default(DiskStateStore)
  var rpc = default(Server)
  defer:
    rpc.close()
    if disk.opened: discard disk.close # Close every native owner even after refusal or restart failure.
  let before = if managed: initializeManagedDiskChain(disk, path, identity, owner, physical).value
    else: initializeDiskChain(disk, path, identity, owner, limits).value
  let initialContext = disk.snapshotContext.value
  let staged = prepareDiskPublication(disk, owner, prepared, identity, limits.contextBytes).value
  assert staged.ready and sameChainView(staged.chainUpdate.currentUpdateView,
      prepared.currentUpdateView)
  var wrong = default(array[32, byte])
  wrong[0] = 1
  let badIdentity = publishDiskChain(disk, owner, prepared, StorageChainId(wrong),
      limits.contextBytes)
  assert badIdentity.error == DiskChainError.CanonicalMismatch
  let tooSmall = publishDiskChain(disk, owner, prepared, identity, ByteLimit(1))
  assert tooSmall.error == DiskChainError.ContextFailure
  let closed = publishDiskChain(disk, owner, rpc, prepared, identity, limits.contextBytes)
  assert closed.error == DiskChainError.CanonicalMismatch
  var absent = default(PreparedCurrentDiskPublication)
  assert not absent.ready
  assert commitDiskPublication(disk, absent).error == DiskChainError.CanonicalMismatch
  assert uint64(disk.generation.value) == uint64(before)
  assert disk.snapshotContext.value == initialContext
  assert sameStateSnapshot(owner.stateSnapshot.value, original.stateSnapshot.value)
  if enabled:
    listener(rpc, original.chainView)
    let lease = rpc.pauseChain()
    assert lease != nil
    let noLease = publishDiskChain(disk, owner, rpc, prepared, identity, limits.contextBytes)
    assert noLease.error == DiskChainError.CanonicalMismatch
    discard publishDiskChain(disk, owner, rpc, prepared, identity, limits.contextBytes, lease).value
    assert rpc.chainPaused and rpc.resumeChain(lease)
  else:
    discard publishDiskChain(disk, owner, prepared, identity, limits.contextBytes).value
  assert sameStateSnapshot(owner.stateSnapshot.value, prepared.currentUpdateState)
  assert sameStateSnapshot(owner.stateSnapshot.value, disk.snapshot.value)
  assert sameChainView(owner.chainView, prepared.currentUpdateView)
  assert uint64(disk.generation.value) == uint64(before)+1
  let selectedContext = disk.snapshotContext.value
  assert commitDiskPublication(disk, staged).error == DiskChainError.CanonicalMismatch
  assert disk.snapshotContext.value == selectedContext
  assert disk.close == FileError.None
  let reopened = if managed: openManagedDiskChain(disk, path, identity, currentChainSettings(),
      integrationStoreLimits(), physical)
    else: openDiskChain(disk, path, identity, currentChainSettings(), integrationStoreLimits(), limits)
  assert reopened.error == DiskChainError.None
  let restored = reopened.value
  assert sameStateSnapshot(restored.stateSnapshot.value, disk.snapshot.value)
  assert array[32, byte](restored.stateSnapshot.value.commitment.root) ==
    array[32, byte](prepared.currentUpdateState.commitment.root)
  assert array[32, byte](restored.chainView.bestBlock.value.blockHash) ==
    array[32, byte](prepared.currentUpdateChild.blockHash)
  assert restored.chainView.retainedCount == 2
  assert array[32, byte](restored.chainView.finalizedBlock.value.blockHash) ==
    array[32, byte](context.parent.value.blockHash)
  assert disk.close == FileError.None
  if managed:
    removeManagedSample(path, [ManagedEpoch(1)]) # The test creates one managed epoch and no compaction.
  else:
    assert posix.unlink(path.toCString()) == 0 # Each repeated witness starts with an absent database.
proc cycle(context: CurrentChainFixture, disk: DiskStateStore, owner: ApplicationChain) =
  ## Context encoding and retained current update copies release their immutable graph without journal mutation.
  let prepared = owner.prepareAccumulation(context.source, ByteLimit(100000)).value
  let staged = prepareDiskPublication(disk, owner, prepared, default(StorageChainId), ByteLimit(1048576)).value
  assert staged.ready
proc main() {.raises.} =
  ## Use signed report data and the complete current production chain for every durable successor.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index in 0..<raw.len: bytes[index] = byte(raw[index])
  let context = currentChainFixture(decodeOwnedReport(bytes, 2).value, uses = 2, available = true, blobs = true)
  for managed in [false, true]:
    for enabled in [false, true]: witness(context, managed,
        enabled) # Backend and RPC modes remain separate complete checks.
  let owner = initApplicationChain(context.currentChainSeeded).value
  var disk = default(DiskStateStore)
  discard initializeDiskChain(disk, "current-disk-arc.db", default(StorageChainId), owner,
      journalLimits()).value
  cycle(context, disk, owner)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(context, disk, owner) # Every staged context and candidate graph leaves its local scope.
  let after = getOccupiedMem()
  assert before == after, "current disk preparation releases"
  recordArcRelease("pvm_current_disk_publication", 1000, before, after)
  assert disk.close == FileError.None
  var path = "current-disk-arc.db"
  assert posix.unlink(path.toCString()) == 0
  echo "PVM current disk publication passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main() # Unexpected storage, fixture or socket failure is never a passing publication witness.
except:
  quit(2)
