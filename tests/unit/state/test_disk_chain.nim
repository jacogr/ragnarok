# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Disk creation/restart and genuine prepared publication remain atomic across canonical/RPC boundaries.
import std/[assertions, envvars, syncio]
import std/posix/posix
import ../../support/[disk_history_context, durable_chain_context, accumulation_completion_context, accumulation_provision_integration]
import ../../../src/app/[chain, disk_chain]
import ../../../src/chain/[genesis, provider]
import ../../../src/state/[store, disk_store]
import ../../../src/storage/[file_repository, node_repository, node_records, record_codec, database_identity]
import ../../../src/codec/[bounded, state_trie, report_owned]
import ../../../src/rpc/server
proc journalLimits(): JournalLimits =
  ## Explicit broad fixture ceilings bound all physical records, individual batches and history context.
  JournalLimits(repository: RepositoryLimits(codec: RecordLimits(trie: StateTrieLimits(
    items: ElementLimit(100000), perValue: ByteLimit(1048576), totalValueBytes: ByteLimit(16777216),
    nodes: TrieNodeLimit(1000000)), records: TrieExportLimits(records: TrieNodeLimit(1000000),
      valueBytes: ByteLimit(16777216)), encoded: ByteLimit(33554432)),
    records: ElementLimit(2000000), valueBytes: ByteLimit(67108864)),
    bytes: ByteLimit(134217728), contextBytes: ByteLimit(1048576))
proc historyWitness() {.raises.} =
  ## Bootstrap all required old roots; only the final bounded canonical context authorizes restart.
  let fixture = diskHistoryFixture()
  let owner = initApplicationChain(fixture.view).value
  let limits = journalLimits()
  let chain = default(StorageChainId)
  var path = "disk-chain-history.db"
  var disk = default(DiskStateStore)
  defer:
    if disk.opened: discard disk.close # Every refusal must release native ownership before fixture teardown.
  let generation = initializeDiskChain(disk, path, chain, owner, limits).value
  defer: discard posix.unlink(path.toCString())
  assert uint64(generation) == uint64(MaxRetainedBlocks+2)
  assert sameStateSnapshot(owner.stateSnapshot.value, disk.snapshot.value)
  assert initializeDiskChain(disk, path, chain, owner, limits).error == DiskChainError.Busy
  assert disk.close == FileError.None
  let restored = openDiskChain(disk, path, chain, fixture.view.bestBlock.value.chainParameters,
    fixture.policy, limits).value
  assert restored.chainView.retainedCount == MaxRetainedBlocks
  assert array[32, byte](restored.chainView.finalizedBlock.value.blockHash) ==
    array[32, byte](fixture.view.finalizedBlock.value.blockHash)
  assert sameStateSnapshot(restored.stateSnapshot.value, disk.snapshot.value)
  assert disk.close == FileError.None
  # Incomplete initialization has no canonical fallback, and failure releases its lock without changing bytes.
  assert posix.unlink(path.toCString()) == 0
  discard initializeDiskStateStore(disk, path, chain, owner.stateSnapshot.value, limits,
    StorageSchema.FullStateV1, [1'u8]).value
  assert disk.close == FileError.None
  let previous = readFile(path)
  assert openDiskChain(disk, path, chain, fixture.view.bestBlock.value.chainParameters,
    fixture.policy, limits).error == DiskChainError.ContextFailure
  assert not disk.opened and readFile(path) == previous
proc publicationWitness() {.raises.} =
  ## Use real signed execution, never the structural history fixture, for live successor publication.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index in 0..<raw.len: bytes[index] = byte(raw[index])
  let fixture = durableFixture(decodeOwnedReport(bytes, 2).value)
  let original = initApplicationChain(genesisView(fixture.parent)).value
  let prepared = original.prepareAccumulation(fixture.source, completionLimits().composition).value
  let limits = journalLimits()
  let chain = default(StorageChainId)
  for enabled in [false, true]:
    var owner = original
    var path = if enabled: "disk-chain-rpc.db" else: "disk-chain-canonical.db"
    var disk = default(DiskStateStore)
    var rpc = default(Server)
    defer:
      rpc.close
      if disk.opened: discard disk.close # Native owners retire before all retained fixture snapshots.
    let before = initializeDiskChain(disk, path, chain, owner, limits).value
    defer: discard posix.unlink(path.toCString())
    let journal = readFile(path)
    # Shared seed identity and generation cannot authorize another journal's different context.
    let staged = prepareDiskPublication(disk, owner, prepared, chain, limits.contextBytes).value
    var foreign = default(DiskStateStore)
    var otherPath = "disk-chain-foreign.db"
    discard initializeDiskStateStore(foreign, otherPath, chain, owner.stateSnapshot.value,
      limits, StorageSchema.FullStateV1, [1'u8]).value
    discard foreign.commit(foreign.snapshot.value, owner.stateSnapshot.value, [2'u8]).value
    assert uint64(foreign.generation.value) == uint64(before)
    let otherBytes = readFile(otherPath)
    assert commitDiskPublication(foreign, staged).error == DiskChainError.CanonicalMismatch
    assert readFile(otherPath) == otherBytes
    assert foreign.close == FileError.None
    assert posix.unlink(otherPath.toCString()) == 0
    var wrong = default(array[32, byte])
    wrong[0] = 1
    assert publishDiskChain(disk, owner, prepared, StorageChainId(wrong),
      limits.contextBytes).error == DiskChainError.CanonicalMismatch
    var alternate = initApplicationChain(owner.chainView.finalizeView(
        fixture.parent.value.blockHash).value).value
    let other = alternate.prepareAccumulation(fixture.source, completionLimits().composition).value
    assert publishDiskChain(disk, alternate, other, chain,
      limits.contextBytes).error == DiskChainError.CanonicalMismatch
    assert publishDiskChain(disk, owner, prepared, chain, ByteLimit(1)).error ==
        DiskChainError.ContextFailure
    assert publishDiskChain(disk, owner, rpc, prepared, chain,
      limits.contextBytes).error == DiskChainError.CanonicalMismatch
    assert uint64(disk.generation.value) == uint64(before) and readFile(path) == journal
    assert sameStateSnapshot(owner.stateSnapshot.value, original.stateSnapshot.value)
    if enabled:
      var listening = false
      for port in 54100'u16..54132'u16:
        if not listening: listening = rpc.start(port, "full", durableSettings(), fixture.parent)
      assert listening
      let lease = rpc.pauseChain()
      assert lease != nil
      assert publishDiskChain(disk, owner, rpc, prepared, chain,
        limits.contextBytes).error == DiskChainError.CanonicalMismatch
      discard publishDiskChain(disk, owner, rpc, prepared, chain, limits.contextBytes, lease).value
      assert rpc.resumeChain(lease)
    else:
      discard publishDiskChain(disk, owner, prepared, chain, limits.contextBytes).value
    assert sameStateSnapshot(owner.stateSnapshot.value, disk.snapshot.value)
    assert sameChainView(owner.chainView, prepared.chainView)
    assert uint64(disk.generation.value) == uint64(before)+1
    let source = owner.stateSnapshot.value
    assert disk.close == FileError.None
    # Reopen with the same inherited source policy; all exact header/map facts are checked again.
    let restored = openDiskChain(disk, path, chain, fixture.parent.value.chainParameters,
      integrationStoreLimits(),
      limits).value
    assert restored.chainView.retainedCount == 2
    assert array[32, byte](restored.stateSnapshot.value.commitment.root) == array[32, byte](
        source.commitment.root)
    assert sameStateSnapshot(restored.stateSnapshot.value, disk.snapshot.value)
try:
  historyWitness()
  publicationWitness()
except:
  quit(2) # Missing fixtures or IO failures cannot produce passing publication evidence.
echo "PASS disk chain: bounded bootstrap, strict restart, real durable successors and exact canonical/RPC authority"
