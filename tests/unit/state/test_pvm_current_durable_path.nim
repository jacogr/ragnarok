# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real signed guarantees, ancestor lookup and current PVM effects reach native durability, RPC notification and strict restart.
import std/[assertions, envvars, syncio, base64, strutils]
import std/posix/posix
import ../../../src/app/[chain, candidate, disk_chain, disk_worker]
import ../../../src/chain/[genesis, provider, parameters]
import ../../../src/rpc/server
import ../../../src/codec/[bounded, report_owned, block_codec, composite]
import ../../../src/state/[store, disk_store, block_admission, report_admission,
  accumulation_current_consensus, accumulation_current_update]
import ../../../src/storage/[file_repository, database_identity, node_repository,
    managed_repository, managed_manifest]
import ../../support/[accumulation_current_chain_context, accumulation_current_candidate_context,
  accumulation_current_disk_context, accumulation_provision_integration,
  pvm_accumulation_provision, managed_storage_samples, rpc_socket]
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
const Subscribe = """{"jsonrpc":"2.0","method":"subscribeBestBlock","params":[],"id":2}"""
const Best = """{"jsonrpc":"2.0","method":"bestBlock","id":1}"""
proc listener(rpc: var Server, view: ChainView): uint16 =
  ## Actual loopback RPC uses bounded ephemeral reservation retries.
  let parameters = decodeParameters(currentChainSettings().encodeParameters)
  for attempt in 0..<8:
    let selected = reservation()
    discard posix.close(selected.fd)
    if rpc.start(selected.port, "current-durable-path-test", parameters, view): return selected.port
  assert false, "current durable-path RPC startup failed"
  0
proc foreignContext(update: PreparedCurrentChainUpdate, publication: PreparedCurrentDiskPublication,
    generation: RepositoryGeneration) {.raises.} =
  ## Exact state identity and equal generation still cannot replace the prepared full application context.
  var disk = default(DiskStateStore)
  var path = "current-durable-foreign.db"
  let limits = currentDiskLimits()
  discard initializeDiskStateStore(disk, path, default(StorageChainId), update.currentUpdateState,
    limits, StorageSchema.FullStateV1, [1'u8]).value
  defer:
    if disk.opened: discard disk.close
    discard posix.unlink(path.toCString()) # All foreign context handles retire after native exclusion ends.
  while uint64(disk.generation.value) < uint64(generation):
    discard disk.commit(disk.snapshot.value, update.currentUpdateState, [2'u8]).value
  assert uint64(disk.generation.value) == uint64(generation)
  assert sameStateSnapshot(disk.snapshot.value, update.currentUpdateState)
  assert not disk.confirmsCurrentDiskPublication(publication, generation)
proc witness(context: CurrentChainFixture, managed: bool) {.raises.} =
  ## The host freezes every shared ARC alias between native submission and exact receipt collection.
  let original = initApplicationChain(context.currentChainSeeded).value
  var owner = original
  let bound = context.source.currentChainAdmission.reportBlockStage.value.value.admitted
  let child = bound.admittedBlock
  var policies = currentCandidateLimits()
  policies.completion.execution.initial.guests.provisions = provisionPolicy(items = 2, perBlob = 1, total = 2)
  policies.completion.execution.initial.provisions.values = PreimageLimits(items: ElementLimit(2),
    perBlob: ByteLimit(1), totalBlobBytes: ByteLimit(2))
  policies.completion.execution.initial.provisions.encodedBytes = ByteLimit(32)
  policies.completion.execution.execution.round = policies.completion.execution.initial
  let prefix = prepareCurrentCandidateReports(owner, child, policies)
  assert prefix.error == CurrentCandidateError.None
  let missing = completeCurrentCandidateReports(owner, prefix.value, [])
  assert missing.error == CurrentCandidateError.ReportFailure
  assert missing.reportFailure.error != ReportAdmissionError.None
  let prepared = completeCurrentCandidateReports(owner, prefix.value, context.older)
  assert prepared.error == CurrentCandidateError.None
  let update = prepared.value
  let expected = context.source.currentConsensusState.value
  assert array[32, byte](update.currentUpdateState.commitment.root) == array[32, byte](
      expected.commitment.root)
  let limits = currentDiskLimits()
  let physical = ManagedLimits(repository: limits.repository, roots: ElementLimit(9),
    snapshotBytes: ByteLimit(33554432), journalBytes: limits.bytes,
        contextBytes: limits.contextBytes)
  let identity = default(StorageChainId)
  var disk = default(DiskStateStore)
  var worker = default(DiskPublicationWorker)
  var rpc = default(Server)
  var path = if managed: "current-durable-managed" else: "current-durable.db"
  defer:
    discard worker.close # Join native borrowers before RPC, disk, prepared publications or retained source aliases retire.
    rpc.close()
    if disk.opened: discard disk.close
  let before = if managed: initializeManagedDiskChain(disk, path, identity, owner, physical).value
    else: initializeDiskChain(disk, path, identity, owner, limits).value
  let port = listener(rpc, owner.chainView)
  let peer = client(port)
  defer: discard posix.close(peer) # The host retains descriptor ownership through bounded frame polling.
  var pending = ""
  upgrade(rpc, peer, pending)
  sendText(peer, Subscribe)
  assert "\"result\":1" in readPacket(rpc, peer, pending)
  assert "\"slot\":1" in readPacket(rpc, peer, pending)
  let lease = rpc.pauseChain()
  assert lease != nil and owner.canInstallPrepared(rpc, update, lease)
  var publication = prepareDiskPublication(disk, owner, update, identity, limits.contextBytes).value
  assert not disk.confirmsCurrentDiskPublication(publication, before)
  let absent = default(PreparedCurrentDiskPublication)
  assert not disk.confirmsCurrentDiskPublication(absent, before)
  assert worker.start()
  let ticket = worker.submit(disk, publication).value
  worker.waitCurrentDiskDone() # Only scalar phase/ticket operations occur until collection ends every native graph activation.
  let completed = worker.collect(ticket)
  assert completed.kind == DiskCompletionKind.Completed
  let receipt = completed.value
  assert receipt.error == DiskChainError.None
  let generation = receipt.value
  assert uint64(generation) == uint64(before)+1
  assert sameStateSnapshot(owner.stateSnapshot.value, original.stateSnapshot.value)
  assert sameStateSnapshot(disk.snapshot.value, update.currentUpdateState)
  foreignContext(update, publication, generation)
  failHash(3)
  assert disk.confirmsCurrentDiskPublication(publication, generation)
  assert not disk.confirmsCurrentDiskPublication(publication, before)
  assert owner.canInstallPrepared(rpc, publication.chainUpdate, lease)
  owner.installPrepared(rpc, publication.chainUpdate, lease)
  assert owner.installedPrepared(update).error == ApplicationChainError.None
  assert sameStateSnapshot(owner.stateSnapshot.value, disk.snapshot.value)
  assert hashCalls() == 0, "receipt binding and canonical/RPC installation never hash or recapture"
  assert rpc.chainPaused and rpc.resumeChain(lease)
  failHash(0)
  let encoded = base64.encode(array[32, byte](update.currentUpdateChild.blockHash))
  let event = readPacket(rpc, peer, pending)
  assert "subscribeBestBlock" in event and encoded in event
  sendText(peer, Best)
  assert encoded in readPacket(rpc, peer, pending)
  assert worker.close.kind == DiskCompletionKind.Uninitialized
  assert disk.close == FileError.None
  assert not disk.confirmsCurrentDiskPublication(publication, generation)
  let reopened = if managed: openManagedDiskChain(disk, path, identity, currentChainSettings(),
      integrationStoreLimits(), physical)
    else: openDiskChain(disk, path, identity, currentChainSettings(), integrationStoreLimits(), limits)
  assert reopened.error == DiskChainError.None
  let restored = reopened.value
  assert array[32, byte](restored.stateSnapshot.value.commitment.root) == array[32, byte](
      expected.commitment.root)
  assert array[32, byte](restored.chainView.bestBlock.value.blockHash) == array[32, byte](
      update.currentUpdateChild.blockHash)
  assert sameStateSnapshot(restored.stateSnapshot.value, disk.snapshot.value)
  assert disk.close == FileError.None
  if managed:
    removeManagedSample(path, [ManagedEpoch(1)]) # No maintenance/compaction creates another physical epoch in this witness.
  else:
    assert posix.unlink(path.toCString()) == 0 # The next backend witness begins with absent physical storage.
proc main() {.raises.} =
  ## Real incoming guarantees need the original lookup headers; no ancestry or state certificate is synthesized.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index in 0..<raw.len: bytes[index] = byte(raw[index])
  let context = currentChainFixture(decodeOwnedReport(bytes, 2).value, uses = 2, available = true, blobs = true)
  assert context.older.len > 0
  for managed in [false, true]: witness(context, managed) # Each backend covers the complete signed-block/native/RPC/restart path.
try:
  main() # Source, native thread, socket, file and restart failures all fail the end-to-end witness.
except:
  quit(2)
echo "PVM current durable path passed"
