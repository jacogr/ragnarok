# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real managed compaction preserves current Pending/Finished authority, publication receipts and exact RPC exclusion.
import std/assertions
import std/envvars
import std/syncio
import std/base64
import std/strutils
import std/posix/posix
import ../../../src/app/services as app_services
import ../../../src/app/options as app_options
import ../../../src/app/current_block_input as app_current_block_input
import ../../../src/app/current_handoff as app_current_handoff
import ../../../src/app/disk_chain as app_disk_chain
import ../../../src/app/disk_worker as app_disk_worker
import ../../../src/app/chain as app_chain
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/provider as chain_provider
import ../../../src/state/store as state_store
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/state/accumulation_current_consensus as state_accumulation_current_consensus
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/storage/file_errors as storage_file_errors
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/rpc/server as rpc_server
import ../../support/state_current_services_disk_samples
import ../../support/state_current_application_context
import ../../support/state_accumulation_current_chain_context
import ../../support/app_managed_storage_samples
import ../../support/rpc_socket
type MaintenanceOrder {.pure.} = enum ## Each explicit order owns one complete sequential Services lifetime.
  Pending, Finished, Automatic, Joined
const ChainPath = "pvm-current-services-maintenance-chain"
const DiskPath = "pvm-current-services-maintenance-state"
proc optionsFor(port: uint16, automatic: bool): Options =
  ## A one-byte automatic threshold is explicit local policy; ordinary cases disable background replacement.
  if not automatic: return currentDiskOptions(ChainPath, DiskPath, true, port)
  var args = @["server", "--with-state", "--chain", ChainPath, "--state-storage", "disk",
    "--state-db", DiskPath, "--state-layout", "managed", "--state-compact-bytes", "1"]
  if port != 0:
    args.add("--with-rpc")
    args.add("--rpc-port")
    args.add($port) # Reuse only a test-owned loopback reservation.
  result = default(Options)
  assert parseCanonicalOptions(args, result), "current maintenance: parseCanonicalOptions(args, result)"
proc excluded(owner: var Services, update: PreparedCurrentChainUpdate) =
  ## During any native operation only synchronized/scalar observations and immediate Busy gates are permitted.
  assert owner.diskPublicationActive and owner.rpc.chainPaused, "current maintenance: owner.diskPublicationActive and owner.rpc.chainPaused"
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Publishing, "current maintenance: owner.currentAccumulationPhase == CurrentHandoffPhase.Publishing"
  assert not owner.preparationAvailable and not owner.stateProofAvailable, "current maintenance: not owner.preparationAvailable and not owner.stateProofAvailable"
  assert not owner.cancelCurrentAccumulation() and not owner.beginDiskMaintenance(), "current maintenance: not owner.cancelCurrentAccumulation() and not owner.beginDiskMaintenance()"
  assert owner.enqueueCurrentAccumulation(update) == CurrentHandoffAdmission.Busy, "current maintenance: owner.enqueueCurrentAccumulation(update) == CurrentHandoffAdmission.Busy"
proc scenario(context: CurrentChainFixture, order: MaintenanceOrder, network: bool) {.raises.} =
  ## Actual current execution feeds each ordering; strict reopen must retain the same complete child after physical replacement.
  var path = DiskPath
  defer: removeManagedSample(path, [ManagedEpoch(1), ManagedEpoch(2), ManagedEpoch(3)])
  var input = default(CurrentBlockInput)
  var owner = default(Services)
  defer: owner.close() # Join both workers before any receiver or exact managed namespace retires.
  var port = 0'u16
  if network:
    let reserved = reservation()
    port = reserved.port
    discard posix.close(reserved.fd)
  let options = optionsFor(port, order == MaintenanceOrder.Automatic)
  assert owner.start(options, "current managed maintenance"), "current maintenance: owner.start(options, \"current managed maintenance\")"
  let startup = owner.startupDiskMaintenanceOutcome
  var beforeEpoch = 1'u64
  if startup.error == DiskChainError.None:
    beforeEpoch = uint64(startup.value.epoch) # Automatic startup replacement is an actual independent receipt.
  else:
    assert startup.error == DiskChainError.Uninitialized, "current maintenance: startup.error == DiskChainError.Uninitialized"
  assert beforeEpoch == 1'u64 or beforeEpoch == 2'u64,
      "current maintenance: beforeEpoch == 1'u64 or beforeEpoch == 2'u64" # Fresh test-owned namespaces bound the next epoch before addition.
  let update = prepareCurrentServicesUpdate(owner, input, context.currentDiskChildBytes)
  let childHash = update.currentUpdateView.bestBlock.value.blockHash
  var peer = -1.cint
  var pending = ""
  if network:
    peer = client(port)
    upgrade(owner.rpc, peer, pending)
    sendText(peer, """{"jsonrpc":"2.0","method":"subscribeBestBlock","params":[],"id":2}""")
    assert "\"result\":1" in readPacket(owner.rpc, peer, pending), "current maintenance: \"\\\"result\\\":1\" in readPacket(owner.rpc, peer, pending)"
    assert "\"slot\":1" in readPacket(owner.rpc, peer, pending), "current maintenance: \"\\\"slot\\\":1\" in readPacket(owner.rpc, peer, pending)"
  assert owner.enqueueCurrentAccumulation(update) == CurrentHandoffAdmission.None, "current maintenance: owner.enqueueCurrentAccumulation(update) == CurrentHandoffAdmission.None"
  if order == MaintenanceOrder.Pending:
    assert owner.beginDiskMaintenance(), "current maintenance: owner.beginDiskMaintenance()"
    owner.excluded(update)
    owner.waitCurrentDiskDone()
    owner.excluded(update) # Done does not permit taking a retained Pending update or its graph.
    owner.tick(0) # Collect maintenance, then stage/submit the still-pending current publication.
    owner.excluded(update)
    assert owner.currentDiskPublicationAdmissionError == DiskWorkerError.None, "current maintenance: owner.currentDiskPublicationAdmissionError == DiskWorkerError.None"
  else:
    owner.tick(0) # Admit current IO before any explicit or automatic maintenance can share the worker.
    owner.excluded(update)
  owner.waitCurrentDiskDone()
  owner.excluded(update)
  owner.tick(0)
  var publicationGeneration = 0'u64
  if order == MaintenanceOrder.Automatic:
    owner.excluded(update) # The same host turn collected current IO and admitted due maintenance.
    owner.waitCurrentDiskDone()
    owner.excluded(update)
    owner.tick(0) # A header-only replacement journal must not immediately schedule another no-op compaction.
  else:
    assert owner.currentAccumulationPhase == CurrentHandoffPhase.Finished, "current maintenance: owner.currentAccumulationPhase == CurrentHandoffPhase.Finished"
    assert owner.diskPublicationOutcome.error == DiskChainError.None, "current maintenance: owner.diskPublicationOutcome.error == DiskChainError.None"
    publicationGeneration = uint64(owner.diskPublicationOutcome.value)
    if order in {MaintenanceOrder.Finished, MaintenanceOrder.Joined}:
      assert owner.beginDiskMaintenance(), "current maintenance: owner.beginDiskMaintenance()"
      owner.excluded(update)
      if order == MaintenanceOrder.Joined:
        owner.stopDiskPublication() # An actual entered receipt or explicit NotExecuted must preserve current completion.
      else:
        owner.waitCurrentDiskDone()
        owner.excluded(update)
        owner.tick(0)
  assert not owner.diskPublicationActive and not owner.rpc.chainPaused, "current maintenance: not owner.diskPublicationActive and not owner.rpc.chainPaused"
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Finished, "current maintenance: owner.currentAccumulationPhase == CurrentHandoffPhase.Finished"
  assert not owner.preparationAvailable and not owner.stateProofAvailable, "current maintenance: not owner.preparationAvailable and not owner.stateProofAvailable"
  assert owner.diskPublicationOutcome.error == DiskChainError.None, "current maintenance: owner.diskPublicationOutcome.error == DiskChainError.None"
  if order != MaintenanceOrder.Automatic:
    assert uint64(owner.diskPublicationOutcome.value) == publicationGeneration, "current maintenance: uint64(owner.diskPublicationOutcome.value) == publicationGeneration"
  let maintained = owner.diskMaintenanceCompletion
  if order == MaintenanceOrder.Joined:
    assert maintained.kind in {DiskCompletionKind.Maintained, DiskCompletionKind.NotExecuted}, "current maintenance: maintained.kind in {DiskCompletionKind.Maintained, DiskCompletionKind.NotExecuted}"
  else:
    assert maintained.kind == DiskCompletionKind.Maintained, "current maintenance: maintained.kind == DiskCompletionKind.Maintained"
  if maintained.kind == DiskCompletionKind.Maintained:
    assert maintained.maintenanceValue.error == DiskChainError.None, "current maintenance: maintained.maintenanceValue.error == DiskChainError.None"
    assert maintained.maintenanceValue.value.cleanup == FileError.None, "current maintenance: maintained.maintenanceValue.value.cleanup == FileError.None"
    assert uint64(maintained.maintenanceValue.value.epoch) == beforeEpoch+1, "current maintenance: uint64(maintained.maintenanceValue.value.epoch) == beforeEpoch+1"
  assert not owner.diskMaintenanceFailed, "current maintenance: not owner.diskMaintenanceFailed"
  let installed = owner.takeCurrentAccumulation()
  assert installed.error == CurrentHandoffError.None, "current maintenance: installed.error == CurrentHandoffError.None"
  assert array[32, byte](installed.value.blockHash) == array[32, byte](childHash), "current maintenance: array[32, byte](installed.value.blockHash) == array[32, byte](childHash)"
  assert sameStateSnapshot(owner.stateSnapshot.value, update.currentUpdateState), "current maintenance: sameStateSnapshot(owner.stateSnapshot.value, update.currentUpdateState)"
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Idle, "current maintenance: owner.currentAccumulationPhase == CurrentHandoffPhase.Idle"
  if order == MaintenanceOrder.Joined:
    assert not owner.preparationAvailable and not owner.stateProofAvailable, "explicit disk shutdown requires restart"
    assert owner.enqueueCurrentAccumulation(update) == CurrentHandoffAdmission.Unavailable, "stopped backend refuses new current work"
  else:
    assert owner.preparationAvailable and owner.stateProofAvailable, "collected maintenance restores idle availability"
  if network:
    let expected = base64.encode(array[32, byte](childHash))
    assert expected in readPacket(owner.rpc, peer, pending), "current maintenance: expected in readPacket(owner.rpc, peer, pending)"
    sendText(peer, """{"jsonrpc":"2.0","method":"bestBlock","id":1}""")
    assert expected in readPacket(owner.rpc, peer, pending), "current maintenance: expected in readPacket(owner.rpc, peer, pending)"
    discard posix.close(peer) # Actual RPC head visibility follows release of the maintenance lease.
  owner.close()
  assert owner.diskPublicationOutcome.error == DiskChainError.None, "current maintenance: owner.diskPublicationOutcome.error == DiskChainError.None"
  assert owner.start(options, "strict compacted current restart"), "current maintenance: owner.start(options, \"strict compacted current restart\")"
  assert array[32, byte](owner.chainView.bestBlock.value.blockHash) == array[32, byte](childHash), "current maintenance: array[32, byte](owner.chainView.bestBlock.value.blockHash) == array[32, byte](childHash)"
  equalCurrentDiskMap(owner.stateSnapshot.value, context.source.currentConsensusState.value)
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Idle, "current maintenance: owner.currentAccumulationPhase == CurrentHandoffPhase.Idle"
  assert owner.preparationAvailable and owner.stateProofAvailable, "fresh startup restores backend availability"
  owner.close()
proc main() {.raises.} =
  ## Each current/maintenance ordering runs with both startup RPC policies and exact original complete state.
  var path = ChainPath
  defer: discard posix.unlink(path.toCString())
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index in 0..<raw.len: bytes[index] = byte(raw[index])
  let context = currentChainFixture(decodeOwnedReport(bytes, 2).value, available = true)
  writeFile(ChainPath, context.currentApplicationText)
  for order in [MaintenanceOrder.Pending, MaintenanceOrder.Finished,
      MaintenanceOrder.Automatic, MaintenanceOrder.Joined]:
    scenario(context, order, false)
    scenario(context, order, true) # Each listener lifetime joins before the next order starts.
try:
  main()
except:
  quit(2) # Compaction, current execution, actual RPC or strict reopen failure cannot satisfy completion evidence.
echo "PVM current Services maintenance passed"
