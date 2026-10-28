# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real signed current preparation crosses native durable publication, exact RPC exclusion and strict complete-map reopen.
import std/assertions
import std/syncio
import std/envvars
import std/monotimes
import std/times
import std/base64
import std/strutils
import std/posix/posix
import ../../../src/app/services as app_services
import ../../../src/app/options as app_options
import ../../../src/app/preparation_worker as app_preparation_worker
import ../../../src/app/current_block_input as app_current_block_input
import ../../../src/app/current_handoff as app_current_handoff
import ../../../src/app/candidate as app_candidate
import ../../../src/app/handoff as app_handoff
import ../../../src/app/chain as app_chain
import ../../../src/app/disk_worker as app_disk_worker
import ../../../src/app/disk_chain as app_disk_chain
import ../../../src/rpc/server as rpc_server
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/provider as chain_provider
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/block_codec as codec_block_codec
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/state/store as state_store
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/state/accumulation_current_consensus as state_accumulation_current_consensus
import ../../../src/state/block_admission as state_block_admission
import ../../../src/state/report_admission as state_report_admission
import ../../../src/state/accumulation_finalization as state_accumulation_finalization
import ../../../src/state/accumulation_completion as state_accumulation_completion
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../support/state_accumulation_current_chain_context
import ../../support/state_accumulation_current_candidate_context
import ../../support/state_current_application_context
import ../../support/state_current_services_disk_samples
import ../../support/app_managed_storage_samples
import ../../support/rpc_socket
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Enable failure only after synchronized Done, when the worker no longer calls hashing primitives.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe the post-collection host installation independently of status flags.
proc scenario(context: CurrentChainFixture, managed, network: bool) {.raises.} =
  ## Each layout/RPC combination publishes once, acknowledges once, and strictly reopens its actual durable child.
  var path = "pvm-current-services-disk-chain"
  var database = "pvm-current-services-disk-state"
  writeFile(path, context.currentApplicationText)
  defer:
    discard posix.unlink(path.toCString())
    if managed:
      removeManagedSample(database, [ManagedEpoch(1)])
    else:
      discard posix.unlink(database.toCString()) # Only exact test-owned storage names are retired after joined close.
  let wire = context.currentDiskChildBytes
  var input = default(CurrentBlockInput)
  var owner = default(Services)
  defer: owner.close() # The receiver remains stable until both native worker lifetimes have joined.
  var port = 0'u16
  if network:
    let reserved = reservation()
    port = reserved.port
    discard posix.close(reserved.fd)
  let options = currentDiskOptions(path, database, managed, port)
  assert owner.start(options, "current durable Services")
  let parent = owner.stateSnapshot.value
  let parentHash = owner.chainView.bestBlock.value.blockHash
  let update = prepareCurrentServicesUpdate(owner, input, wire)
  assert sameStateSnapshot(parent, owner.stateSnapshot.value)
  assert array[32, byte](parentHash) == array[32, byte](owner.chainView.bestBlock.value.blockHash)
  equalCurrentDiskMap(update.currentUpdateState, context.source.currentConsensusState.value)
  var peer = -1.cint
  var pending = ""
  if network:
    peer = client(port)
    upgrade(owner.rpc, peer, pending)
    sendText(peer, """{"jsonrpc":"2.0","method":"subscribeBestBlock","params":[],"id":2}""")
    assert "\"result\":1" in readPacket(owner.rpc, peer, pending)
    assert "\"slot\":1" in readPacket(owner.rpc, peer, pending)
  assert owner.currentDiskPreparationOutcome.error == DiskChainError.Uninitialized
  assert owner.diskPublicationOutcome.error == DiskChainError.Uninitialized
  assert owner.enqueueCurrentAccumulation(update) == CurrentHandoffAdmission.None
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Pending
  let legacy = default(PreparedFinalAccumulation)
  assert owner.enqueueAccumulation(legacy, default(AccumulationCompositionLimits)) ==
      AccumulationEnqueueError.Busy
  owner.tick(0)
  assert owner.currentDiskPublicationAdmissionError == DiskWorkerError.None
  assert owner.diskPublicationActive and owner.rpc.chainPaused
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Publishing
  assert not owner.preparationAvailable and not owner.stateProofAvailable
  assert not owner.cancelCurrentAccumulation() and not owner.beginDiskMaintenance()
  assert owner.enqueueCurrentAccumulation(update) == CurrentHandoffAdmission.Busy
  owner.waitCurrentDiskDone()
  assert owner.diskPublicationActive and owner.rpc.chainPaused
  assert not owner.preparationAvailable and not owner.stateProofAvailable
  failHash(1)
  owner.tick(0) # Collection, receipt confirmation and installation consume cached owners without hashing.
  assert hashCalls() == 0, "current durable host completion does no hashing"
  failHash(0)
  assert not owner.diskPublicationActive and not owner.rpc.chainPaused
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Finished
  assert owner.diskPublicationOutcome.error == DiskChainError.None
  assert owner.currentDiskPreparationOutcome.error == DiskChainError.Uninitialized
  assert not owner.preparationAvailable and not owner.stateProofAvailable
  assert owner.enqueueCurrentAccumulation(update) == CurrentHandoffAdmission.Busy
  let installed = owner.takeCurrentAccumulation()
  assert installed.error == CurrentHandoffError.None
  let childHash = installed.value.blockHash
  assert sameStateSnapshot(owner.stateSnapshot.value, update.currentUpdateState)
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Idle
  assert owner.preparationAvailable and owner.stateProofAvailable
  if network:
    let expected = base64.encode(array[32, byte](childHash))
    assert expected in readPacket(owner.rpc, peer, pending)
    sendText(peer, """{"jsonrpc":"2.0","method":"bestBlock","id":1}""")
    assert expected in readPacket(owner.rpc, peer, pending)
    discard posix.close(peer) # Listener shutdown follows retirement of the actual test-owned socket.
  owner.close()
  assert owner.diskPublicationOutcome.error == DiskChainError.None
  assert owner.start(options, "strict current durable restart")
  assert array[32, byte](owner.chainView.bestBlock.value.blockHash) == array[32, byte](childHash)
  equalCurrentDiskMap(owner.stateSnapshot.value, context.source.currentConsensusState.value)
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Idle
  owner.close() # Close joins before the deferred exact namespace cleanup runs.
proc main() {.raises.} =
  ## Signed fixture execution and all four durable combinations must complete without fixture/runtime exceptions.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index in 0..<raw.len: bytes[index] = byte(raw[index])
  let context = currentChainFixture(decodeOwnedReport(bytes, 2).value, available = true)
  scenario(context, false, false)
  scenario(context, false, true)
  scenario(context, true, false)
  scenario(context, true, true)
try:
  main()
except:
  quit(2) # Execution, disk, RPC or reopen failure cannot satisfy durable publication evidence.
echo "PVM current Services disk passed"
